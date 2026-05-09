// Inject typed characters into whatever window has focus. Strategy
// depends on session type:
//   - Wayland: spawn `wtype "<text>"` (requires the wtype tool, which
//     also requires the compositor to expose virtual-keyboard-v1; KDE
//     and wlroots-based DEs do, GNOME currently does not).
//   - X11: spawn `xdotool type --delay 1 -- "<text>"`.
// We never inject Cmd+V (Apple-only). The Linux paste convention is
// Ctrl+V, but we type characters directly so we don't depend on the
// clipboard at all.

use anyhow::{anyhow, Result};
use std::process::Command;

pub fn inject(text: &str) -> Result<()> {
    let session = session_type();
    match session {
        SessionType::Wayland => spawn(&["wtype", "--", text]),
        SessionType::X11 => spawn(&["xdotool", "type", "--delay", "1", "--", text]),
    }
}

fn spawn(args: &[&str]) -> Result<()> {
    if which::which(args[0]).is_err() {
        return Err(anyhow!(
            "{} not installed; required for text injection on this session",
            args[0]
        ));
    }
    let status = Command::new(args[0]).args(&args[1..]).status()?;
    if !status.success() {
        return Err(anyhow!("{} exited with status {status}", args[0]));
    }
    Ok(())
}

enum SessionType {
    Wayland,
    X11,
}

fn session_type() -> SessionType {
    match std::env::var("XDG_SESSION_TYPE")
        .unwrap_or_default()
        .as_str()
    {
        "wayland" => SessionType::Wayland,
        _ => SessionType::X11,
    }
}
