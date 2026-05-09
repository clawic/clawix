// Tray icon backed by StatusNotifierItem (KDE native, GNOME via the
// AppIndicator extension). Mirrors what `MenuBarExtra` exposes on Mac:
// open chat, toggle bridge, restart daemon, settings, quit.

use anyhow::Result;
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager};

pub fn install(app: &AppHandle) -> Result<()> {
    let open = MenuItem::with_id(app, "open", "Open Clawix", true, None::<&str>)?;
    let quickask = MenuItem::with_id(app, "quickask", "Quick Ask…", true, Some("Super+Space"))?;
    let toggle_bridge = MenuItem::with_id(app, "toggle-bridge", "Pause iPhone bridge", true, None::<&str>)?;
    let restart_daemon = MenuItem::with_id(app, "restart-daemon", "Restart bridge daemon", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
    let about = MenuItem::with_id(app, "about", "About Clawix", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;

    let advanced = Submenu::with_items(
        app,
        "Advanced",
        true,
        &[&restart_daemon, &toggle_bridge],
    )?;

    let menu = Menu::with_items(
        app,
        &[
            &open,
            &quickask,
            &separator,
            &settings,
            &advanced,
            &about,
            &separator,
            &quit,
        ],
    )?;

    let _tray = TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .icon(app.default_window_icon().cloned().unwrap_or_else(|| {
            tauri::image::Image::new(&[], 0, 0)
        }))
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "quickask" => {
                let _ = crate::shortcuts::open_quickask(app);
            }
            "settings" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                    let _ = window.eval("window.location.hash = '#/settings';");
                }
            }
            "restart-daemon" => {
                let _ = crate::service_manager::restart();
            }
            "toggle-bridge" => {
                let _ = crate::service_manager::toggle();
            }
            "about" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.eval("window.location.hash = '#/about';");
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
        })
        .build(app)?;

    Ok(())
}
