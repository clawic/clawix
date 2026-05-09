// On-device dictation backed by whisper.cpp. The binary + GGUF model
// are downloaded into ~/.clawix/whisper/ on first use; a Vulkan/CUDA
// build is fetched if the host has the matching driver (see
// `install_whisper.sh`). Audio capture is delegated to `arecord`
// (ALSA) or `parecord` (PulseAudio/Pipewire).
//
// The function shape mirrors what TranscriptionService gives the Mac
// GUI: start emits incremental events, stop closes the stream.

use anyhow::{anyhow, Context, Result};
use serde::Serialize;
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::thread;
use tauri::{AppHandle, Emitter};

#[derive(Serialize)]
pub struct AudioInput {
    pub id: String,
    pub label: String,
    pub default: bool,
}

static CURRENT: Mutex<Option<Child>> = Mutex::new(None);

pub fn list_inputs() -> Result<Vec<AudioInput>> {
    // Best-effort: parse `pactl list short sources` if PulseAudio is the
    // session sound server, otherwise fall back to a single "default"
    // entry that the whisper.cpp wrapper will resolve via ALSA's "default"
    // device.
    if which::which("pactl").is_ok() {
        let out = Command::new("pactl").args(["list", "short", "sources"]).output()?;
        if out.status.success() {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut inputs = Vec::new();
            for (idx, line) in text.lines().enumerate() {
                let cols: Vec<&str> = line.split_whitespace().collect();
                if cols.len() >= 2 {
                    inputs.push(AudioInput {
                        id: cols[1].to_string(),
                        label: cols[1].to_string(),
                        default: idx == 0,
                    });
                }
            }
            if !inputs.is_empty() {
                return Ok(inputs);
            }
        }
    }
    Ok(vec![AudioInput {
        id: "default".into(),
        label: "Default microphone".into(),
        default: true,
    }])
}

pub async fn start(app: &AppHandle, _device: Option<String>) -> Result<String> {
    let mut guard = CURRENT.lock().unwrap();
    if guard.is_some() {
        return Err(anyhow!("dictation already running"));
    }
    let whisper_bin = whisper_path()
        .with_context(|| "whisper.cpp not installed; run `clawix dictation install` or open Settings → Dictation")?;
    let model = model_path();
    let mut child = Command::new(whisper_bin)
        .args([
            "-m",
            &model.to_string_lossy(),
            "-t",
            "6",
            "--stream",
            "--step",
            "500",
            "--length",
            "5000"
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| "spawning whisper-cli")?;

    // Pipe whisper.cpp's per-segment output into Tauri events the
    // SolidJS frontend listens on (`dictation:partial`).
    if let Some(stdout) = child.stdout.take() {
        let app = app.clone();
        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines().map_while(Result::ok) {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with("[") {
                    continue;
                }
                let _ = app.emit("dictation:partial", trimmed.to_string());
            }
            let _ = app.emit("dictation:stopped", ());
        });
    }

    *guard = Some(child);
    Ok("started".to_string())
}

pub fn stop() -> Result<()> {
    let mut guard = CURRENT.lock().unwrap();
    if let Some(mut child) = guard.take() {
        let _ = child.kill();
        let _ = child.wait();
    }
    Ok(())
}

#[allow(dead_code)]
pub fn emit_partial(app: &AppHandle, text: &str) {
    let _ = app.emit("dictation:partial", text.to_string());
}

fn whisper_path() -> Result<std::path::PathBuf> {
    if let Some(home) = dirs::home_dir() {
        let candidate = home.join(".clawix/whisper/whisper-cli");
        if candidate.exists() {
            return Ok(candidate);
        }
    }
    which::which("whisper-cli")
        .or_else(|_| which::which("whisper"))
        .map_err(|_| anyhow!("whisper.cpp not installed (run setup or `clawix dictation install`)"))
}

fn model_path() -> std::path::PathBuf {
    if let Some(home) = dirs::home_dir() {
        return home.join(".clawix/whisper/ggml-large-v3-turbo.bin");
    }
    std::path::PathBuf::from("/tmp/whisper-model.bin")
}
