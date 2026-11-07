// Норка-помощник: всё через локальный Ollama на 127.0.0.1:11434, в сеть ходит только он сам при скачивании моделей.
// Каждая модель из библиотеки копируется под именем norka-<id> с системным промптом Норки
use serde::Serialize;
use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::process::Command;
use std::time::Duration;
use tauri::{AppHandle, Emitter};

const OLLAMA: &str = "http://127.0.0.1:11434";

fn agent(timeout: u64) -> ureq::Agent {
    ureq::AgentBuilder::new().timeout_connect(Duration::from_secs(3)).timeout_read(Duration::from_secs(timeout)).build()
}

#[derive(Serialize)]
pub struct Status {
    installed: bool,
    running: bool,
    models: Vec<String>,
}

#[derive(Serialize)]
pub struct Hardware {
    ram_gb: f64,
    vram_gb: f64,
}

#[tauri::command]
pub fn ai_status() -> Status {
    let installed = std::path::Path::new("/usr/bin/ollama").exists();
    let tags = agent(5).get(&format!("{OLLAMA}/api/tags")).call().ok().and_then(|r| r.into_json::<Value>().ok());
    let models = tags
        .as_ref()
        .and_then(|v| v["models"].as_array().cloned())
        .unwrap_or_default()
        .iter()
        .filter_map(|m| m["name"].as_str().map(String::from))
        .collect();
    Status { installed, running: tags.is_some(), models }
}

/// Память и видеопамять, чтобы подсказать модель по силам
#[tauri::command]
pub fn ai_hardware() -> Hardware {
    let ram_kb: f64 = std::fs::read_to_string("/proc/meminfo")
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("MemTotal:").and_then(|v| v.trim().split_whitespace().next()?.parse().ok()))
        .unwrap_or(0.0);
    let mut vram_mb: f64 = Command::new("nvidia-smi")
        .args(["--query-gpu=memory.total", "--format=csv,noheader,nounits"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8_lossy(&o.stdout).lines().next()?.trim().parse().ok())
        .unwrap_or(0.0);
    if vram_mb == 0.0 {
        // AMD и Intel: размер видеопамяти отдаёт драйвер amdgpu
        if let Ok(entries) = std::fs::read_dir("/sys/class/drm") {
            for e in entries.flatten() {
                if let Ok(v) = std::fs::read_to_string(e.path().join("device/mem_info_vram_total")) {
                    vram_mb = vram_mb.max(v.trim().parse::<f64>().unwrap_or(0.0) / 1048576.0);
                }
            }
        }
    }
    Hardware { ram_gb: ram_kb / 1048576.0, vram_gb: vram_mb / 1024.0 }
}

#[derive(Clone, Serialize)]
struct PullEvent {
    id: String,
    kind: String,
    completed: u64,
    total: u64,
    text: String,
}

/// Скачать модель и сделать из неё Норку. Ход скачивания идёт событиями ai-pull
#[tauri::command]
pub fn ai_pull(app: AppHandle, id: String, base: String, system: String) -> Result<(), String> {
    std::thread::spawn(move || {
        let emit = |kind: &str, completed: u64, total: u64, text: String| {
            let _ = app.emit("ai-pull", PullEvent { id: id.clone(), kind: kind.into(), completed, total, text });
        };
        let result = (|| -> Result<(), String> {
            let response = agent(3600)
                .post(&format!("{OLLAMA}/api/pull"))
                .send_json(json!({ "model": base, "stream": true }))
                .map_err(|e| e.to_string())?;
            for line in BufReader::new(response.into_reader()).lines().map_while(Result::ok) {
                let v: Value = serde_json::from_str(&line).unwrap_or(Value::Null);
                if let Some(err) = v["error"].as_str() {
                    return Err(err.to_string());
                }
                emit("progress", v["completed"].as_u64().unwrap_or(0), v["total"].as_u64().unwrap_or(0), v["status"].as_str().unwrap_or("").into());
            }
            agent(600)
                .post(&format!("{OLLAMA}/api/create"))
                .send_json(json!({ "model": format!("norka-{id}"), "from": base, "system": system, "stream": false }))
                .map_err(|e| e.to_string())?;
            Ok(())
        })();
        match result {
            Ok(()) => emit("done", 0, 0, String::new()),
            Err(e) => emit("failed", 0, 0, e),
        }
    });
    Ok(())
}

/// Промпт Норки у уже скачанной модели: если он устарел (обновили NorkaOS), пересоздаём копию без скачивания
#[tauri::command]
pub fn ai_refresh_prompt(id: String, base: String, system: String) -> Result<bool, String> {
    let model = format!("norka-{id}");
    let shown: Value = agent(30)
        .post(&format!("{OLLAMA}/api/show"))
        .send_json(json!({ "model": model }))
        .map_err(|e| e.to_string())?
        .into_json()
        .map_err(|e| e.to_string())?;
    if shown["system"].as_str() == Some(system.as_str()) {
        return Ok(false);
    }
    agent(600)
        .post(&format!("{OLLAMA}/api/create"))
        .send_json(json!({ "model": model, "from": base, "system": system, "stream": false }))
        .map_err(|e| e.to_string())?;
    Ok(true)
}

#[tauri::command]
pub fn ai_delete(id: String, base: String) -> Result<(), String> {
    for model in [format!("norka-{id}"), base] {
        let _ = agent(30).delete(&format!("{OLLAMA}/api/delete")).send_json(json!({ "model": model }));
    }
    Ok(())
}

#[derive(Clone, Serialize)]
struct ChatEvent {
    kind: String,
    text: String,
}

/// Ответ Норки по кусочкам: события ai-chat с kind token, done или error
#[tauri::command]
pub fn ai_chat(app: AppHandle, model: String, messages: Vec<Value>, think: Option<bool>) -> Result<(), String> {
    std::thread::spawn(move || {
        let emit = |kind: &str, text: String| {
            let _ = app.emit("ai-chat", ChatEvent { kind: kind.into(), text });
        };
        let response = agent(600)
            .post(&format!("{OLLAMA}/api/chat"))
            .send_json({
                // Отключать раздумья можно только у моделей, которые их умеют, иначе Ollama ругается
                let mut body = json!({ "model": model, "messages": messages, "stream": true });
                if let Some(think) = think {
                    body["think"] = json!(think);
                }
                body
            });
        let response = match response {
            Ok(r) => r,
            Err(e) => return emit("error", e.to_string()),
        };
        for line in BufReader::new(response.into_reader()).lines().map_while(Result::ok) {
            let v: Value = serde_json::from_str(&line).unwrap_or(Value::Null);
            if let Some(err) = v["error"].as_str() {
                return emit("error", err.to_string());
            }
            if let Some(token) = v["message"]["content"].as_str() {
                if !token.is_empty() {
                    emit("token", token.to_string());
                }
            }
        }
        emit("done", String::new());
    });
    Ok(())
}

fn model_file() -> std::path::PathBuf {
    crate::config_dir().join("model")
}

#[tauri::command]
pub fn ai_default_model() -> String {
    std::fs::read_to_string(model_file()).unwrap_or_default().trim().to_string()
}

#[tauri::command]
pub fn ai_set_default_model(model: String) -> Result<(), String> {
    std::fs::create_dir_all(crate::config_dir()).map_err(|e| e.to_string())?;
    std::fs::write(model_file(), model).map_err(|e| e.to_string())
}
