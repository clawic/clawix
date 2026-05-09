// Manages the systemd user unit that hosts `clawix-bridged`. Same unit
// is shared between the npm CLI install, the AppImage, and the .deb so
// only one daemon runs even if all three are installed. The path to the
// binary is overridable via the `CLAWIX_BRIDGE_BIN` env var.

use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command;

const UNIT_NAME: &str = "clawix-bridge.service";

pub fn ensure_daemon_running() -> Result<()> {
    write_unit_if_missing()?;
    if !is_active() {
        Command::new("systemctl")
            .args(["--user", "daemon-reload"])
            .status()?;
        Command::new("systemctl")
            .args(["--user", "enable", "--now", UNIT_NAME])
            .status()?;
    }
    Ok(())
}

pub fn restart() -> Result<()> {
    Command::new("systemctl")
        .args(["--user", "restart", UNIT_NAME])
        .status()?;
    Ok(())
}

pub fn toggle() -> Result<()> {
    if is_active() {
        Command::new("systemctl")
            .args(["--user", "stop", UNIT_NAME])
            .status()?;
    } else {
        Command::new("systemctl")
            .args(["--user", "start", UNIT_NAME])
            .status()?;
    }
    Ok(())
}

pub fn is_active() -> bool {
    Command::new("systemctl")
        .args(["--user", "is-active", "--quiet", UNIT_NAME])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn is_installed() -> bool {
    unit_path().exists()
}

pub fn daemon_version() -> Option<String> {
    let bin = daemon_bin()?;
    let out = Command::new(bin).arg("--version").output().ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn write_unit_if_missing() -> Result<()> {
    let path = unit_path();
    if path.exists() {
        return Ok(());
    }
    let bin = daemon_bin()
        .ok_or_else(|| anyhow::anyhow!("clawix-bridged binary not found"))?;
    let unit = format!(
        r#"[Unit]
Description=Clawix Bridge Daemon
After=network.target

[Service]
ExecStart={bin}
Environment=CLAWIX_BRIDGED_PORT=7778
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"#,
        bin = bin.display()
    );
    std::fs::create_dir_all(path.parent().unwrap()).with_context(|| "mkdir systemd user dir")?;
    std::fs::write(&path, unit).with_context(|| format!("write {path:?}"))?;
    Ok(())
}

fn unit_path() -> PathBuf {
    dirs::config_dir()
        .map(|d| d.join("systemd/user").join(UNIT_NAME))
        .unwrap_or_else(|| PathBuf::from("/tmp").join(UNIT_NAME))
}

fn daemon_bin() -> Option<PathBuf> {
    if let Ok(env_path) = std::env::var("CLAWIX_BRIDGE_BIN") {
        let p = PathBuf::from(env_path);
        if p.exists() {
            return Some(p);
        }
    }
    let candidates = [
        dirs::home_dir().map(|h| h.join(".clawix/bin/clawix-bridged")),
        Some(PathBuf::from("/usr/lib/clawix/clawix-bridged")),
        Some(PathBuf::from("/opt/clawix/clawix-bridged")),
        Some(PathBuf::from("/usr/local/bin/clawix-bridged")),
    ];
    for c in candidates.into_iter().flatten() {
        if c.exists() {
            return Some(c);
        }
    }
    which::which("clawix-bridged").ok()
}
