package com.example.clawix.android.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

/**
 * Wire-format version. Mirrors `bridgeSchemaVersion` in
 * `clawix/packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift`.
 */
const val BRIDGE_SCHEMA_VERSION: Int = 1

const val BRIDGE_INITIAL_PAGE_LIMIT: Int = 60
const val BRIDGE_OLDER_PAGE_LIMIT: Int = 40

@Serializable
enum class ClientKind(val wireValue: String) {
    COMPANION("companion"),
    DESKTOP("desktop");

    companion object {
        fun fromWire(value: String): ClientKind =
            entries.firstOrNull { it.wireValue == value } ?: error("unknown clientKind $value")
    }
}

/**
 * Top-level frame. Wire format is flat: `{ "schemaVersion": N, "type": "...", ...payload-fields }`,
 * no nested envelope. Implemented with a custom serializer because
 * kotlinx-serialization's polymorphic discriminator support assumes the
 * payload sits inside a sub-object.
 */
@Serializable(with = BridgeFrameSerializer::class)
data class BridgeFrame(
    val schemaVersion: Int = BRIDGE_SCHEMA_VERSION,
    val body: BridgeBody,
)

/**
 * All discriminated frame bodies. One sealed-class branch per `type` tag
 * the Swift `BridgeBody` enum carries. Whenever a new frame is added on
 * the daemon side, a new branch goes here AND in `BridgeFrameSerializer`
 * (the encode + decode `when` arms).
 */
sealed class BridgeBody {
    abstract val typeTag: String

    // MARK: - Outbound (mobile -> daemon)
    data class Auth(
        val token: String,
        val deviceName: String?,
        val clientKind: ClientKind?,
        val clientId: String? = null,
        val installationId: String? = null,
        val deviceId: String? = null,
    ) : BridgeBody() {
        override val typeTag = "auth"
    }
    data object ListSessions : BridgeBody() { override val typeTag = "listSessions" }
    data class OpenSession(val sessionId: String, val limit: Int?) : BridgeBody() {
        override val typeTag = "openSession"
    }
    data class LoadOlderMessages(val sessionId: String, val beforeMessageId: String, val limit: Int) : BridgeBody() {
        override val typeTag = "loadOlderMessages"
    }
    data class SendMessage(val sessionId: String, val text: String, val attachments: List<WireAttachment>) : BridgeBody() {
        override val typeTag = "sendMessage"
    }
    data class NewSession(val sessionId: String, val text: String, val attachments: List<WireAttachment>) : BridgeBody() {
        override val typeTag = "newSession"
    }
    data class InterruptTurn(val sessionId: String) : BridgeBody() {
        override val typeTag = "interruptTurn"
    }

    // MARK: - Inbound (daemon -> mobile)
    data class AuthOk(val hostDisplayName: String?) : BridgeBody() { override val typeTag = "authOk" }
    data class AuthFailed(val reason: String) : BridgeBody() { override val typeTag = "authFailed" }
    data class VersionMismatch(val serverVersion: Int) : BridgeBody() { override val typeTag = "versionMismatch" }
    data class SessionsSnapshot(val sessions: List<WireSession>) : BridgeBody() { override val typeTag = "sessionsSnapshot" }
    data class SessionUpdated(val session: WireSession) : BridgeBody() { override val typeTag = "sessionUpdated" }
    data class MessagesSnapshot(val sessionId: String, val messages: List<WireMessage>, val hasMore: Boolean?) : BridgeBody() {
        override val typeTag = "messagesSnapshot"
    }
    data class MessagesPage(val sessionId: String, val messages: List<WireMessage>, val hasMore: Boolean) : BridgeBody() {
        override val typeTag = "messagesPage"
    }
    data class MessageAppended(val sessionId: String, val message: WireMessage) : BridgeBody() {
        override val typeTag = "messageAppended"
    }
    data class MessageStreaming(
        val sessionId: String,
        val messageId: String,
        val content: String,
        val reasoningText: String,
        val finished: Boolean,
    ) : BridgeBody() {
        override val typeTag = "messageStreaming"
    }
    data class ErrorEvent(val code: String, val message: String) : BridgeBody() { override val typeTag = "errorEvent" }

    // MARK: - v2 desktop-only outbound (kept for completeness; mobile won't emit)
    data class EditPrompt(val sessionId: String, val messageId: String, val text: String) : BridgeBody() { override val typeTag = "editPrompt" }
    data class ArchiveSession(val sessionId: String) : BridgeBody() { override val typeTag = "archiveSession" }
    data class UnarchiveSession(val sessionId: String) : BridgeBody() { override val typeTag = "unarchiveSession" }
    data class PinSession(val sessionId: String) : BridgeBody() { override val typeTag = "pinSession" }
    data class UnpinSession(val sessionId: String) : BridgeBody() { override val typeTag = "unpinSession" }
    data class RenameSession(val sessionId: String, val title: String) : BridgeBody() { override val typeTag = "renameSession" }
    data object PairingStart : BridgeBody() { override val typeTag = "pairingStart" }
    data object ListProjects : BridgeBody() { override val typeTag = "listProjects" }
    data class ReadFile(val path: String) : BridgeBody() { override val typeTag = "readFile" }

    // MARK: - v2 inbound
    data class PairingPayload(val qrJson: String, val bearer: String) : BridgeBody() { override val typeTag = "pairingPayload" }
    data class ProjectsSnapshot(val projects: List<WireProject>) : BridgeBody() { override val typeTag = "projectsSnapshot" }
    data class FileSnapshot(val path: String, val content: String?, val isMarkdown: Boolean, val error: String?) : BridgeBody() {
        override val typeTag = "fileSnapshot"
    }

    // MARK: - v3 voice notes
    data class TranscribeAudio(val requestId: String, val audioBase64: String, val mimeType: String, val language: String?) : BridgeBody() {
        override val typeTag = "transcribeAudio"
    }
    data class TranscriptionResult(val requestId: String, val text: String, val errorMessage: String?) : BridgeBody() {
        override val typeTag = "transcriptionResult"
    }
    data class RequestAudio(val audioId: String) : BridgeBody() { override val typeTag = "requestAudio" }
    data class AudioSnapshot(val audioId: String, val audioBase64: String?, val mimeType: String?, val errorMessage: String?) : BridgeBody() {
        override val typeTag = "audioSnapshot"
    }

    // MARK: - v4 inline images
    data class RequestGeneratedImage(val path: String) : BridgeBody() { override val typeTag = "requestGeneratedImage" }
    data class GeneratedImageSnapshot(val path: String, val dataBase64: String?, val mimeType: String?, val errorMessage: String?) : BridgeBody() {
        override val typeTag = "generatedImageSnapshot"
    }

    // MARK: - bridge bootstrap state
    data class BridgeStateFrame(val state: String, val chatCount: Int, val message: String?) : BridgeBody() {
        override val typeTag = "bridgeState"
    }

    // MARK: - v5 rate limits
    data object RequestRateLimits : BridgeBody() { override val typeTag = "requestRateLimits" }
    data class RateLimitsSnapshot(val snapshot: WireRateLimitSnapshot?, val byLimitId: Map<String, WireRateLimitSnapshot>) : BridgeBody() {
        override val typeTag = "rateLimitsSnapshot"
    }
    data class RateLimitsUpdated(val snapshot: WireRateLimitSnapshot?, val byLimitId: Map<String, WireRateLimitSnapshot>) : BridgeBody() {
        override val typeTag = "rateLimitsUpdated"
    }

    // MARK: - unknown future type (forward-compat)
    data class Unknown(val type: String, val raw: JsonObject) : BridgeBody() { override val typeTag = type }
}
