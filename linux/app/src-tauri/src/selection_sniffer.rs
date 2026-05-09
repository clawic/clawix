// Read whatever the user has selected (highlighted) in *another* app.
// Linux exposes the "primary selection" buffer for this, fed by
// every text widget that participates in the X selection / Wayland
// data-control protocol.
//
// AT-SPI2 was rejected: terminals, Electron, and JetBrains apps don't
// export AT-SPI consistently, so the sniffer would silently fail in the
// most common dev surfaces.

use anyhow::{anyhow, Result};
use std::process::Command;

pub fn read_primary() -> Result<String> {
    let session = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    let output = if session == "wayland" {
        if which::which("wl-paste").is_err() {
            return Err(anyhow!("wl-paste not installed; needed for selection sniffing on Wayland"));
        }
        Command::new("wl-paste").args(["--primary", "--no-newline"]).output()?
    } else {
        if which::which("xclip").is_ok() {
            Command::new("xclip")
                .args(["-selection", "primary", "-o"])
                .output()?
        } else if which::which("xsel").is_ok() {
            Command::new("xsel").args(["--primary", "--output"]).output()?
        } else {
            return Err(anyhow!(
                "neither xclip nor xsel installed; needed for selection sniffing on X11"
            ));
        }
    };
    if !output.status.success() {
        return Err(anyhow!(
            "selection read failed: {}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}
