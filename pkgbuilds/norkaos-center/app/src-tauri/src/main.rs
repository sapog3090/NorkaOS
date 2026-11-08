// Норка Центр и Норка Привет: одно окно на Tauri, режим выбирается флагом --hello.
// Настройки рабочего стола меняются скриптами Plasma через D-Bus, всё от root идёт через pkexec
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::{AppHandle, Emitter};

mod ai;

const APPS_HELPER: &str = "/usr/lib/norka/norka-apps";
const SNAPSHOTS_HELPER: &str = "/usr/lib/norka/norka-snapshots-admin";

#[derive(Clone, Serialize)]
struct ProgressEvent {
    kind: String,
    text: String,
    value: u32,
}

#[derive(Serialize)]
struct Snapshot {
    number: u32,
    date: String,
    description: String,
}

#[derive(Serialize)]
struct Snapshots {
    snapshots: Vec<Snapshot>,
    broken: Vec<String>,
}

pub fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config"))
        .join("norka")
}

fn output(cmd: &str, args: &[&str]) -> Result<String, String> {
    let out = Command::new(cmd).args(args).output().map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

#[tauri::command]
fn mode() -> String {
    let args: Vec<String> = std::env::args().collect();
    for (flag, name) in [("--hello", "hello"), ("--helper", "helper"), ("--chat", "chat")] {
        if args.iter().any(|a| a == flag) {
            return name.into();
        }
    }
    "center".into()
}

#[tauri::command]
fn finish_hello() -> Result<(), String> {
    let dir = config_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("hello-done"), "").map_err(|e| e.to_string())
}

/// Ставит программы через pkexec и пересылает в окно строки STEP и PROGRESS
#[tauri::command]
fn install_apps(app: AppHandle, ids: Vec<String>) -> Result<(), String> {
    let mut child = Command::new("pkexec")
        .arg(APPS_HELPER)
        .args(&ids)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;
    let stdout = child.stdout.take().ok_or("нет вывода")?;
    let stderr = child.stderr.take().ok_or("нет вывода ошибок")?;
    std::thread::spawn(move || {
        let errors = std::thread::spawn(move || {
            let lines: Vec<String> = BufReader::new(stderr).lines().map_while(Result::ok).collect();
            lines.iter().rev().take(8).rev().cloned().collect::<Vec<_>>().join("\n")
        });
        let mut failed = String::new();
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            let event = if let Some(rest) = line.strip_prefix("STEP ") {
                let (counter, id) = rest.split_once(' ').unwrap_or((rest, ""));
                let number = counter.split('/').next().and_then(|n| n.parse().ok()).unwrap_or(0);
                ProgressEvent { kind: "step".into(), text: id.into(), value: number }
            } else if let Some(rest) = line.strip_prefix("PROGRESS ") {
                ProgressEvent { kind: "progress".into(), text: String::new(), value: rest.trim().parse().unwrap_or(0) }
            } else if let Some(rest) = line.strip_prefix("FAILED ") {
                failed = rest.to_string();
                continue;
            } else {
                continue;
            };
            let _ = app.emit("apps", event);
        }
        let ok = child.wait().map(|s| s.success()).unwrap_or(false);
        let details = errors.join().unwrap_or_default();
        let _ = app.emit(
            "apps",
            ProgressEvent {
                kind: if ok { "done" } else { "failed" }.into(),
                text: if ok { String::new() } else { format!("{failed}\n{details}") },
                value: 100,
            },
        );
    });
    Ok(())
}

/// Снимки «до обновления» читаем через snapper без root (группа wheel разрешена в его конфиге),
/// старые корни после отката берём из журнала norka-rollback
#[tauri::command]
fn snapshots() -> Snapshots {
    let list = output("snapper", &["-c", "root", "--csvout", "list", "--columns", "number,type,date,description"])
        .unwrap_or_default();
    let mut snapshots: Vec<Snapshot> = list
        .lines()
        .skip(1)
        .filter_map(|line| {
            let mut parts = line.splitn(4, ',');
            let number = parts.next()?.parse().ok()?;
            if parts.next()? != "pre" {
                return None;
            }
            Some(Snapshot { number, date: parts.next()?.into(), description: parts.next().unwrap_or("").into() })
        })
        .collect();
    snapshots.reverse();
    let mut broken: Vec<String> = std::fs::read_to_string("/var/log/norka-broken-roots")
        .unwrap_or_default()
        .lines()
        .map(|l| l.trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();
    broken.dedup();
    Snapshots { snapshots, broken }
}

#[tauri::command]
fn rollback(number: u32) -> Result<String, String> {
    output("pkexec", &[SNAPSHOTS_HELPER, "rollback", &number.to_string()])
}

#[tauri::command]
fn clean_broken() -> Result<String, String> {
    output("pkexec", &[SNAPSHOTS_HELPER, "clean-broken"])
}

/// Скрипт Plasma: так меняются панель и Норка на рабочем столе без перезапуска
#[tauri::command]
fn plasma(script: String) -> Result<String, String> {
    let out = output(
        "busctl",
        &["--user", "call", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", "evaluateScript", "s", &script],
    )?;
    // busctl печатает «s "строка"»: снимаем обёртку и экранирование
    let text = out.trim().strip_prefix("s ").unwrap_or(out.trim());
    let text = text.trim_matches('"').replace("\\\"", "\"").replace("\\\\", "\\");
    Ok(text)
}

#[tauri::command]
fn terminal_hello() -> bool {
    !config_dir().join("no-terminal-hello").exists()
}

#[tauri::command]
fn set_terminal_hello(on: bool) -> Result<(), String> {
    let flag = config_dir().join("no-terminal-hello");
    if on {
        let _ = std::fs::remove_file(flag);
        Ok(())
    } else {
        std::fs::create_dir_all(config_dir()).map_err(|e| e.to_string())?;
        std::fs::write(flag, "").map_err(|e| e.to_string())
    }
}

/// Есть ли видеокарта NVIDIA без её драйвера: тогда Привет первым предложит драйвер
#[tauri::command]
fn needs_nvidia() -> bool {
    let gpu = output("lspci", &["-d", "10de:"]).unwrap_or_default().to_lowercase();
    let has_card = gpu.lines().any(|l| l.contains("vga") || l.contains("3d") || l.contains("display"));
    has_card && Command::new("pacman").args(["-Q", "nvidia-utils"]).output().map(|o| !o.status.success()).unwrap_or(true)
}

#[tauri::command]
fn open_chat() {
    let _ = Command::new("norka-chat").spawn();
}

#[tauri::command]
fn jokes() -> bool {
    !config_dir().join("no-jokes").exists()
}

#[tauri::command]
fn set_jokes(on: bool) -> Result<(), String> {
    let flag = config_dir().join("no-jokes");
    if on {
        let _ = std::fs::remove_file(flag);
        Ok(())
    } else {
        std::fs::create_dir_all(config_dir()).map_err(|e| e.to_string())?;
        std::fs::write(flag, "").map_err(|e| e.to_string())
    }
}

#[tauri::command]
fn reboot() {
    let _ = Command::new("systemctl").arg("reboot").spawn();
}

#[tauri::command]
fn version() -> String {
    std::fs::read_to_string("/etc/os-release")
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("BUILD_ID=").map(|v| v.trim_matches('"').to_string()))
        .unwrap_or_default()
}

fn main() {
    // С драйвером NVIDIA WebKit иногда рисует пустое окно: отключаем ему dmabuf
    if std::path::Path::new("/proc/driver/nvidia").exists() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    tauri::Builder::default()
        .setup(|app| {
            use tauri::Manager;
            if mode() == "chat" {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.set_title("Norka");
                    let _ = window.set_size(tauri::LogicalSize::new(440.0, 620.0));
                    let _ = window.set_min_size(Some(tauri::LogicalSize::new(360.0, 420.0)));
                }
            } else if mode() == "helper" {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.set_title("Norka Helper");
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            mode,
            finish_hello,
            install_apps,
            snapshots,
            rollback,
            clean_broken,
            plasma,
            terminal_hello,
            set_terminal_hello,
            needs_nvidia,
            open_chat,
            ai::ai_status,
            ai::ai_hardware,
            ai::ai_pull,
            ai::ai_delete,
            ai::ai_refresh_prompt,
            ai::ai_chat,
            ai::ai_run,
            ai::ai_default_model,
            ai::ai_set_default_model,
            jokes,
            set_jokes,
            reboot,
            version
        ])
        .run(tauri::generate_context!())
        .expect("не удалось запустить Норка Центр");
}
