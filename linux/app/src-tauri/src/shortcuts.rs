// Global hotkey wiring. Uses `tauri-plugin-global-shortcut`, which
// transparently dispatches to:
//   - XDG GlobalShortcuts portal on Wayland (GNOME 46+, KDE 5.27+),
//   - XGrabKey on X11 sessions.
//
// QuickAsk window placement note: on GNOME Wayland, surfaces cannot be
// positioned at absolute coordinates from a regular client. We open
// QuickAsk as a centered floating window. On KDE/wlroots and X11 the
// window is positioned under the cursor (left for the frontend to do
// via `WebviewWindow::set_position` when the platform allows).

use anyhow::{Context, Result};
use tauri::{AppHandle, LogicalSize, Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

const QUICKASK_LABEL: &str = "quickask";
const QUICKASK_DEFAULT: &str = "Super+Space";

pub fn install(app: &AppHandle) -> Result<()> {
    let handle = app.clone();
    let plugin = app.global_shortcut();
    let shortcut = parse_or_default(QUICKASK_DEFAULT);
    plugin
        .on_shortcut(shortcut, move |_app, _shortcut, event| {
            if matches!(event.state, ShortcutState::Pressed) {
                let _ = open_quickask(&handle);
            }
        })
        .with_context(|| "register quickask shortcut")?;
    Ok(())
}

pub fn open_quickask(app: &AppHandle) -> Result<()> {
    if let Some(existing) = app.get_webview_window(QUICKASK_LABEL) {
        existing.show()?;
        existing.set_focus()?;
        return Ok(());
    }
    let window = WebviewWindowBuilder::new(app, QUICKASK_LABEL, WebviewUrl::App("index.html#/quickask".into()))
        .title("Quick Ask")
        .inner_size(620.0, 80.0)
        .min_inner_size(420.0, 64.0)
        .resizable(false)
        .decorations(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(true)
        .center()
        .build()?;
    let _ = window.set_size(LogicalSize::new(620.0, 80.0));
    Ok(())
}

fn parse_or_default(_raw: &str) -> Shortcut {
    Shortcut::new(Some(Modifiers::SUPER), Code::Space)
}
