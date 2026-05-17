// WebSocket client to the local `clawix-bridge` daemon. Mirrors what
// the Mac GUI's DaemonBridgeClient does: connects to ws://127.0.0.1:24080,
// sends the auth frame with the bridge token from
// `~/.clawix/state/bridge-token`, and dispatches inbound frames as Tauri
// events the SolidJS frontend subscribes to.

use anyhow::{anyhow, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, info, warn};

const DEFAULT_PORT: u16 = 24080;
const BRIDGE_SCHEMA_VERSION: u8 = 1;
const RECONNECT_BACKOFF_MS: u64 = 1500;
const FRAME_BATCH_WINDOW_MS: u64 = 16;

#[derive(Default)]
pub struct DaemonClient {
    write_tx: Option<tokio::sync::mpsc::Sender<Message>>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairingPayload {
    pub token: String,
    pub short_code: String,
    pub qr_json: String,
}

#[derive(Serialize)]
pub struct ChatBrief {
    pub id: String,
    pub title: String,
    pub last_message: Option<String>,
    pub has_active_turn: bool,
}

impl DaemonClient {
    pub fn new() -> Self {
        Self { write_tx: None }
    }

    pub async fn get_chats(&self) -> Result<Vec<crate::commands::WireSessionBrief>> {
        self.send_intent(serde_json::json!({ "type": "listSessions" }))
            .await?;
        Ok(Vec::new())
    }

    pub async fn open_session(&self, session_id: &str) -> Result<serde_json::Value> {
        self.send_intent(serde_json::json!({
            "type": "openSession",
            "sessionId": session_id,
        }))
        .await
    }

    pub async fn send_message(
        &self,
        session_id: Option<&str>,
        text: &str,
    ) -> Result<serde_json::Value> {
        let body = if let Some(id) = session_id {
            serde_json::json!({ "type": "sendMessage", "sessionId": id, "text": text })
        } else {
            serde_json::json!({
                "type": "newSession",
                "sessionId": uuid_v4(),
                "text": text
            })
        };
        self.send_intent(body).await
    }

    pub async fn interrupt_turn(&self, session_id: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "interruptTurn",
            "sessionId": session_id
        }))
        .await?;
        Ok(())
    }

    pub async fn start_pairing(&self) -> Result<PairingPayload> {
        // The daemon mints a fresh pairing payload via `pairingStart`.
        // The frame round-trips back as `pairingPayload`; the WS reader
        // task forwards that to a oneshot channel keyed by request id.
        // For the v1 scaffold we read straight from `~/.clawix/state/`
        // where the daemon already persists the bridge token + short code.
        let state_dir = state_dir();
        let token = std::fs::read_to_string(state_dir.join("bridge-token"))
            .with_context(|| "reading bridge token from ~/.clawix/state/bridge-token")?
            .trim()
            .to_string();
        let short_code = std::fs::read_to_string(state_dir.join("bridge-shortcode"))
            .unwrap_or_default()
            .trim()
            .to_string();
        let qr_json = serde_json::json!({
            "v": BRIDGE_SCHEMA_VERSION,
            "host": pairing_host(),
            "port": DEFAULT_PORT,
            "token": &token,
            "shortCode": &short_code,
        })
        .to_string();
        Ok(PairingPayload {
            token,
            short_code,
            qr_json,
        })
    }

    async fn send_intent(&self, body: serde_json::Value) -> Result<serde_json::Value> {
        let tx = self
            .write_tx
            .as_ref()
            .ok_or_else(|| anyhow!("daemon not connected"))?;
        let frame = bridge_frame(body)?;
        tx.send(Message::Text(frame.to_string()))
            .await
            .map_err(|e| anyhow!("send: {e}"))?;
        Ok(serde_json::Value::Null)
    }
}

pub async fn connect_and_run(client: Arc<Mutex<DaemonClient>>, app: AppHandle) -> Result<()> {
    loop {
        let url = url::Url::parse(&format!("ws://127.0.0.1:{}/", DEFAULT_PORT))?;
        match tokio_tungstenite::connect_async(url.as_str()).await {
            Ok((ws, _)) => {
                info!("daemon connected at {DEFAULT_PORT}");
                let (mut write, mut read) = ws.split();
                let (tx, mut rx) = tokio::sync::mpsc::channel::<Message>(64);
                {
                    let mut guard = client.lock().await;
                    guard.write_tx = Some(tx.clone());
                }
                // Auth frame
                if let Ok(bearer) = read_bearer() {
                    let auth = serde_json::json!({
                        "schemaVersion": BRIDGE_SCHEMA_VERSION,
                        "type": "auth",
                        "token": bearer,
                        "deviceName": hostname(),
                        "clientKind": "desktop",
                        "clientId": "clawix.linux.desktop",
                        "installationId": persisted_id("bridge-installation-id"),
                        "deviceId": persisted_id("bridge-device-id")
                    });
                    let _ = write.send(Message::Text(auth.to_string())).await;
                }
                // Spawn the writer pump
                let writer_task = tokio::spawn(async move {
                    while let Some(msg) = rx.recv().await {
                        if write.send(msg).await.is_err() {
                            break;
                        }
                    }
                });
                // Reader: batch incoming frames into 16ms windows so we
                // don't spam the webview IPC during heavy token streaming.
                let mut batch: Vec<serde_json::Value> = Vec::with_capacity(64);
                let mut flush = tokio::time::interval(Duration::from_millis(FRAME_BATCH_WINDOW_MS));
                flush.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                loop {
                    tokio::select! {
                        msg = read.next() => {
                            match msg {
                                Some(Ok(Message::Text(text))) => {
                                    if let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) {
                                        batch.push(value);
                                    }
                                }
                                Some(Ok(Message::Binary(bin))) => {
                                    if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bin) {
                                        batch.push(value);
                                    }
                                }
                                Some(Ok(Message::Close(_))) | None => {
                                    debug!("daemon ws closed");
                                    break;
                                }
                                Some(Ok(_)) => {}
                                Some(Err(e)) => {
                                    warn!(?e, "ws read error");
                                    break;
                                }
                            }
                        }
                        _ = flush.tick(), if !batch.is_empty() => {
                            let drained: Vec<_> = batch.drain(..).collect();
                            let _ = app.emit("bridge:frames", drained);
                        }
                    }
                }
                writer_task.abort();
                {
                    let mut guard = client.lock().await;
                    guard.write_tx = None;
                }
            }
            Err(e) => {
                debug!(?e, "daemon connect failed, retrying");
            }
        }
        tokio::time::sleep(Duration::from_millis(RECONNECT_BACKOFF_MS)).await;
    }
}

fn read_bearer() -> Result<String> {
    let path = state_dir().join("bridge-token");
    Ok(std::fs::read_to_string(path)?.trim().to_string())
}

fn state_dir() -> PathBuf {
    dirs::home_dir()
        .map(|h| h.join(".clawix").join("state"))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn bridge_frame(body: Value) -> Result<Value> {
    let mut object = body
        .as_object()
        .cloned()
        .ok_or_else(|| anyhow!("bridge frame body must be a JSON object"))?;
    object.insert(
        "schemaVersion".to_string(),
        Value::from(BRIDGE_SCHEMA_VERSION),
    );
    Ok(Value::Object(object))
}

fn persisted_id(name: &str) -> String {
    let dir = state_dir();
    let path = dir.join(name);
    if let Ok(existing) = std::fs::read_to_string(&path) {
        let trimmed = existing.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    let value = uuid_v4();
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(path, format!("{value}\n"));
    value
}

fn hostname() -> String {
    nix::unistd::gethostname()
        .ok()
        .and_then(|s| s.into_string().ok())
        .unwrap_or_else(|| "linux".to_string())
}

fn pairing_host() -> String {
    std::net::UdpSocket::bind("0.0.0.0:0")
        .and_then(|socket| {
            let _ = socket.connect("8.8.8.8:80");
            socket.local_addr()
        })
        .map(|addr| addr.ip().to_string())
        .unwrap_or_else(|_| "127.0.0.1".to_string())
}

fn uuid_v4() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:032x}", nanos)
}
