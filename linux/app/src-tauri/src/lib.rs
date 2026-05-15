// Clawix Linux runtime entry. Wires Tauri plugins, mounts the system
// tray, brings up the WebSocket bridge to the local `clawix-bridge`
// daemon, and exposes Rust commands to the SolidJS frontend.

mod chat_db;
mod daemon_client;
mod dictation;
mod selection_sniffer;
mod service_manager;
mod shortcuts;
mod text_injector;
mod tray;

use std::sync::Arc;
use tauri::Manager;
use tokio::sync::Mutex;
use tracing_subscriber::EnvFilter;

pub struct AppState {
    pub daemon: Arc<Mutex<daemon_client::DaemonClient>>,
    pub db: Arc<chat_db::ChatDb>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let db = Arc::new(chat_db::ChatDb::open_default().expect("chat db open"));
    let daemon = Arc::new(Mutex::new(daemon_client::DaemonClient::new()));

    tauri::Builder::default()
        .plugin(tauri_plugin_window_state::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(AppState {
            daemon: daemon.clone(),
            db: db.clone(),
        })
        .setup(move |app| {
            let handle = app.handle().clone();
            tray::install(&handle)?;
            shortcuts::install(&handle)?;
            service_manager::ensure_daemon_running()?;
            let daemon_handle = handle.clone();
            let daemon_arc = daemon.clone();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = daemon_client::connect_and_run(daemon_arc, daemon_handle).await {
                    tracing::error!(?e, "daemon connection terminated");
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_chats,
            commands::open_chat,
            commands::send_prompt,
            commands::interrupt_turn,
            commands::start_pairing,
            commands::list_audio_inputs,
            commands::start_dictation,
            commands::stop_dictation,
            commands::inject_text,
            commands::read_primary_selection,
            commands::open_quickask,
            commands::daemon_status,
            commands::set_setting,
            commands::get_setting,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

mod commands {
    use super::AppState;
    use crate::{daemon_client, dictation, selection_sniffer, service_manager, text_injector};
    use serde::{Deserialize, Serialize};
    use tauri::{Manager, State};

    #[derive(Serialize)]
    pub struct WireSessionBrief {
        pub id: String,
        pub title: String,
        pub last_message: Option<String>,
        pub has_active_turn: bool,
    }

    #[tauri::command]
    pub async fn get_chats(state: State<'_, AppState>) -> Result<Vec<WireSessionBrief>, String> {
        let client = state.daemon.lock().await;
        client.get_chats().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn open_chat(
        chat_id: String,
        state: State<'_, AppState>,
    ) -> Result<serde_json::Value, String> {
        let client = state.daemon.lock().await;
        client.open_chat(&chat_id).await.map_err(|e| e.to_string())
    }

    #[derive(Deserialize)]
    pub struct SendMessageArgs {
        pub chat_id: Option<String>,
        pub text: String,
    }

    #[tauri::command]
    pub async fn send_prompt(
        args: SendMessageArgs,
        state: State<'_, AppState>,
    ) -> Result<serde_json::Value, String> {
        let client = state.daemon.lock().await;
        client
            .send_prompt(args.chat_id.as_deref(), &args.text)
            .await
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn interrupt_turn(
        chat_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.interrupt_turn(&chat_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn start_pairing(state: State<'_, AppState>) -> Result<daemon_client::PairingPayload, String> {
        let client = state.daemon.lock().await;
        client.start_pairing().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn list_audio_inputs() -> Result<Vec<dictation::AudioInput>, String> {
        dictation::list_inputs().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn start_dictation(
        device: Option<String>,
        app_handle: tauri::AppHandle,
    ) -> Result<String, String> {
        dictation::start(&app_handle, device).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn stop_dictation() -> Result<(), String> {
        dictation::stop().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn inject_text(text: String) -> Result<(), String> {
        text_injector::inject(&text).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn read_primary_selection() -> Result<String, String> {
        selection_sniffer::read_primary().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn open_quickask(app_handle: tauri::AppHandle) -> Result<(), String> {
        crate::shortcuts::open_quickask(&app_handle).map_err(|e| e.to_string())
    }

    #[derive(Serialize)]
    pub struct DaemonStatus {
        pub installed: bool,
        pub running: bool,
        pub version: Option<String>,
    }

    #[tauri::command]
    pub async fn daemon_status() -> Result<DaemonStatus, String> {
        let installed = service_manager::is_installed();
        let running = service_manager::is_active();
        let version = service_manager::daemon_version();
        Ok(DaemonStatus { installed, running, version })
    }

    #[tauri::command]
    pub async fn set_setting(
        key: String,
        value: serde_json::Value,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        state.db.set_setting(&key, &value.to_string()).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn get_setting(
        key: String,
        state: State<'_, AppState>,
    ) -> Result<Option<String>, String> {
        state.db.get_setting(&key).map_err(|e| e.to_string())
    }
}
