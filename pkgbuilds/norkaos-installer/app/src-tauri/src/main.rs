// Установщик NorkaOS: окно на Tauri, вся работа с диском в скрипте norka-install.
// Отсюда только читаем диски, запускаем скрипт через sudo и пересылаем его ход в окно.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};
use tauri::{AppHandle, Emitter};

#[derive(Serialize)]
struct Partition {
    path: String,
    size: u64,
    fstype: String,
    label: String,
}

#[derive(Serialize)]
struct Disk {
    path: String,
    size: u64,
    model: String,
    transport: String,
    /// С этого диска запущена живая система: ставить на него нельзя
    live: bool,
    windows: bool,
    bitlocker: bool,
    gpt: bool,
    largest_free: u64,
    partitions: Vec<Partition>,
}

#[derive(Deserialize)]
struct InstallRequest {
    mode: String,
    disk: String,
    user: String,
    fullname: String,
    password: String,
    hostname: String,
    timezone: String,
    locale: String,
}

#[derive(Clone, Serialize)]
struct ProgressEvent {
    kind: String,
    text: String,
    value: u32,
}

fn run(cmd: &str, args: &[&str]) -> String {
    Command::new(cmd)
        .args(args)
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
        .unwrap_or_default()
}

fn text(v: &Value, key: &str) -> String {
    v[key].as_str().unwrap_or("").trim().to_string()
}

/// Самый большой кусок свободного места на диске в байтах, по выводу parted
fn largest_free(path: &str) -> u64 {
    run("sudo", &["parted", "-sm", path, "unit", "B", "print", "free"])
        .lines()
        .filter(|l| l.ends_with("free;"))
        .filter_map(|l| l.split(':').nth(3)?.trim_end_matches('B').parse::<u64>().ok())
        .max()
        .unwrap_or(0)
}

#[tauri::command]
fn list_disks() -> Vec<Disk> {
    let live_source = run("findmnt", &["-no", "SOURCE", "/run/archiso/bootmnt"]);
    let live_disk = run("lsblk", &["-no", "PKNAME", live_source.trim()]);
    let live_disk = live_disk.trim();
    let json: Value = serde_json::from_str(&run(
        "lsblk",
        &["-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,TRAN,MODEL,FSTYPE,LABEL,PTTYPE,RM"],
    ))
    .unwrap_or(Value::Null);
    let mut disks = Vec::new();
    for dev in json["blockdevices"].as_array().cloned().unwrap_or_default() {
        if text(&dev, "type") != "disk" || dev["size"].as_u64().unwrap_or(0) < 8 << 30 {
            continue;
        }
        let path = text(&dev, "path");
        let name = text(&dev, "name");
        let children = dev["children"].as_array().cloned().unwrap_or_default();
        let partitions: Vec<Partition> = children
            .iter()
            .map(|p| Partition {
                path: text(p, "path"),
                size: p["size"].as_u64().unwrap_or(0),
                fstype: text(p, "fstype"),
                label: text(p, "label"),
            })
            .collect();
        let live = !live_disk.is_empty() && name == live_disk;
        disks.push(Disk {
            windows: partitions.iter().any(|p| p.fstype == "ntfs" || p.fstype == "BitLocker"),
            bitlocker: partitions.iter().any(|p| p.fstype == "BitLocker"),
            gpt: text(&dev, "pttype") == "gpt",
            largest_free: if partitions.is_empty() { 0 } else { largest_free(&path) },
            size: dev["size"].as_u64().unwrap_or(0),
            model: text(&dev, "model"),
            transport: text(&dev, "tran"),
            live,
            path,
            partitions,
        });
    }
    disks
}

#[tauri::command]
fn list_timezones() -> Vec<String> {
    run("timedatectl", &["list-timezones"]).lines().map(String::from).collect()
}

#[tauri::command]
fn start_install(app: AppHandle, request: InstallRequest) -> Result<(), String> {
    // Пароль передаём файлом с правами 600, чтобы он не светился в списке процессов
    let pw_path = std::env::temp_dir().join(format!("norka-pw-{}", std::process::id()));
    let mut file = std::fs::File::create(&pw_path).map_err(|e| e.to_string())?;
    file.set_permissions(std::fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())?;
    writeln!(file, "{}", request.password).map_err(|e| e.to_string())?;
    drop(file);

    let mut child = Command::new("sudo")
        .args([
            "norka-install",
            "--mode", &request.mode,
            "--disk", &request.disk,
            "--user", &request.user,
            "--fullname", &request.fullname,
            "--password-file", pw_path.to_str().unwrap_or_default(),
            "--hostname", &request.hostname,
            "--timezone", &request.timezone,
            "--locale", &request.locale,
            "--yes",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| e.to_string())?;

    let stdout = child.stdout.take().ok_or("нет вывода")?;
    let stderr = child.stderr.take().ok_or("нет вывода ошибок")?;
    std::thread::spawn(move || {
        // Последние строки ошибок покажем, если установка упадёт
        let errors = std::thread::spawn(move || {
            let lines: Vec<String> = BufReader::new(stderr).lines().map_while(Result::ok).collect();
            lines.iter().rev().take(6).rev().cloned().collect::<Vec<_>>().join("\n")
        });
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            let event = if let Some(rest) = line.strip_prefix("STEP ") {
                let (counter, title) = rest.split_once(' ').unwrap_or((rest, ""));
                let number = counter.split('/').next().and_then(|n| n.parse().ok()).unwrap_or(0);
                ProgressEvent { kind: "step".into(), text: title.into(), value: number }
            } else if let Some(rest) = line.strip_prefix("PROGRESS ") {
                ProgressEvent { kind: "progress".into(), text: String::new(), value: rest.trim().parse().unwrap_or(0) }
            } else {
                continue;
            };
            let _ = app.emit("install", event);
        }
        let ok = child.wait().map(|s| s.success()).unwrap_or(false);
        let _ = std::fs::remove_file(&pw_path);
        let details = errors.join().unwrap_or_default();
        let _ = app.emit(
            "install",
            ProgressEvent { kind: if ok { "done" } else { "failed" }.into(), text: details, value: 100 },
        );
    });
    Ok(())
}

#[tauri::command]
fn reboot() {
    let _ = Command::new("systemctl").arg("reboot").spawn();
}

fn main() {
    // С драйвером NVIDIA WebKit иногда рисует пустое окно: отключаем ему dmabuf
    if std::path::Path::new("/proc/driver/nvidia").exists() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![list_disks, list_timezones, start_install, reboot])
        .run(tauri::generate_context!())
        .expect("не удалось запустить установщик");
}
