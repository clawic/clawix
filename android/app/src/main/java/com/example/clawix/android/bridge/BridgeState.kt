package com.example.clawix.android.bridge

import com.example.clawix.android.core.BridgeRuntimeState
import com.example.clawix.android.core.WireChat
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireProject
import kotlinx.datetime.Instant

/**
 * Connection life-cycle of the WebSocket. Mirrors the iOS
 * `BridgeStore.ConnectionState`. Surfaced through `BridgeStore.state`
 * so the UI can render the right banner / pill.
 */
sealed class ConnectionState {
    data object Idle : ConnectionState()
    data object Connecting : ConnectionState()
    data class Connected(val macName: String?, val route: ConnectionRoute) : ConnectionState()
    data class Reconnecting(val attempt: Int) : ConnectionState()
    data class Failed(val reason: String) : ConnectionState()
    data class VersionMismatch(val serverVersion: Int) : ConnectionState()
}

enum class ConnectionRoute { Lan, Tailscale, Bonjour }

/**
 * Cached file or generated-image fetched from the daemon. Lives in
 * memory only; not persisted (the bytes can always be re-fetched).
 */
data class FileSnapshotState(
    val path: String,
    val content: String?,
    val isMarkdown: Boolean,
    val error: String?,
)

data class GeneratedImageState(
    val path: String,
    val dataBase64: String?,
    val mimeType: String?,
    val errorMessage: String?,
)

data class BridgeState(
    val connection: ConnectionState = ConnectionState.Idle,
    val runtime: BridgeRuntimeState? = null,
    val chats: List<WireChat> = emptyList(),
    val messagesByChat: Map<String, List<WireMessage>> = emptyMap(),
    val hasMoreByChat: Map<String, Boolean> = emptyMap(),
    val openChatId: String? = null,
    val pendingNewChats: Set<String> = emptySet(),
    val projects: List<WireProject> = emptyList(),
    val fileSnapshots: Map<String, FileSnapshotState> = emptyMap(),
    val generatedImages: Map<String, GeneratedImageState> = emptyMap(),
    val pendingTranscriptions: Map<String, String> = emptyMap(), // requestId -> chatId
    val transcriptionResults: Map<String, String> = emptyMap(),  // requestId -> text
)
