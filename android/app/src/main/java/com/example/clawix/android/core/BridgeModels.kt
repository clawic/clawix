package com.example.clawix.android.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

@Serializable
enum class WireRole {
    @SerialName("user") user,
    @SerialName("assistant") assistant,
}

@Serializable
enum class WireAttachmentKind {
    @SerialName("image") image,
    @SerialName("audio") audio,
}

/** Inline attachment piggy-backing on `sendMessage` / `newSession`. Bytes
 *  travel base64-encoded inline; daemon writes to a turn-scoped temp
 *  file and forwards the path to Codex (image) or runs Whisper on it
 *  (audio). */
@Serializable
data class WireAttachment(
    val id: String,
    val kind: WireAttachmentKind = WireAttachmentKind.image,
    val mimeType: String,
    val filename: String? = null,
    val dataBase64: String,
) {
    companion object {
        val listSerializer: KSerializer<List<WireAttachment>> = ListSerializer(serializer())
    }
}

/** Project descriptor (daemon -> desktop). iPhone consumes for header chips. */
@Serializable
data class WireProject(
    val id: String,
    val title: String,
    val cwd: String,
    val hasGitRepo: Boolean = false,
    val branch: String? = null,
    @Serializable(with = OptionalIsoDateSerializer::class)
    val lastUsedAt: Instant? = null,
) {
    companion object {
        val listSerializer: KSerializer<List<WireProject>> = ListSerializer(serializer())
    }
}

@Serializable
data class WireSession(
    val id: String,
    val title: String,
    @Serializable(with = IsoDateSerializer::class)
    val createdAt: Instant,
    val isPinned: Boolean = false,
    val isArchived: Boolean = false,
    val hasActiveTurn: Boolean = false,
    @Serializable(with = OptionalIsoDateSerializer::class)
    val lastMessageAt: Instant? = null,
    val lastMessagePreview: String? = null,
    val branch: String? = null,
    val cwd: String? = null,
    val lastTurnInterrupted: Boolean = false,
    val threadId: String? = null,
) {
    companion object {
        val listSerializer: KSerializer<List<WireSession>> = ListSerializer(serializer())
    }
}

@Serializable
enum class WireWorkItemStatus {
    @SerialName("inProgress") inProgress,
    @SerialName("completed") completed,
    @SerialName("failed") failed,
}

@Serializable
data class WireWorkItem(
    val id: String,
    val kind: String,
    val status: WireWorkItemStatus,
    val commandText: String? = null,
    val commandActions: List<String>? = null,
    val paths: List<String>? = null,
    val mcpServer: String? = null,
    val mcpTool: String? = null,
    val dynamicToolName: String? = null,
    val generatedImagePath: String? = null,
)

/** Sealed-class-with-discriminator: encodes as
 *  `{ "type": "reasoning" | "message" | "tools", "id": "...", ... }`
 *  exactly matching iOS. We hand-roll the serializer because the
 *  discriminator key is `type` (not `kind` or `_t`) and Compose already
 *  uses `kind` elsewhere. */
@Serializable(with = WireTimelineEntrySerializer::class)
sealed class WireTimelineEntry {
    abstract val id: String
    data class Reasoning(override val id: String, val text: String) : WireTimelineEntry()
    data class Message(override val id: String, val text: String) : WireTimelineEntry()
    data class Tools(override val id: String, val items: List<WireWorkItem>) : WireTimelineEntry()
}

object WireTimelineEntrySerializer : KSerializer<WireTimelineEntry> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("WireTimelineEntry")
    private val itemsSerializer = ListSerializer(WireWorkItem.serializer())

    override fun serialize(encoder: Encoder, value: WireTimelineEntry) {
        require(encoder is JsonEncoder)
        val obj = buildJsonObject {
            when (value) {
                is WireTimelineEntry.Reasoning -> {
                    put("type", "reasoning")
                    put("id", value.id)
                    put("text", value.text)
                }
                is WireTimelineEntry.Message -> {
                    put("type", "message")
                    put("id", value.id)
                    put("text", value.text)
                }
                is WireTimelineEntry.Tools -> {
                    put("type", "tools")
                    put("id", value.id)
                    put("items", BridgeJson.encodeToJsonElement(itemsSerializer, value.items))
                }
            }
        }
        encoder.encodeJsonElement(obj)
    }

    override fun deserialize(decoder: Decoder): WireTimelineEntry {
        require(decoder is JsonDecoder)
        val obj: JsonObject = decoder.decodeJsonElement().jsonObject
        val type = obj["type"]?.jsonPrimitive?.content ?: error("missing timeline type")
        val id = obj["id"]?.jsonPrimitive?.content ?: error("missing timeline id")
        return when (type) {
            "reasoning" -> WireTimelineEntry.Reasoning(id, obj["text"]?.jsonPrimitive?.content ?: "")
            "message" -> WireTimelineEntry.Message(id, obj["text"]?.jsonPrimitive?.content ?: "")
            "tools" -> {
                val items = obj["items"]?.let { BridgeJson.decodeFromJsonElement(itemsSerializer, it) } ?: emptyList()
                WireTimelineEntry.Tools(id, items)
            }
            else -> error("unknown timeline type: $type")
        }
    }
}

@Serializable
data class WireWorkSummary(
    @Serializable(with = IsoDateSerializer::class)
    val startedAt: Instant,
    @Serializable(with = OptionalIsoDateSerializer::class)
    val endedAt: Instant? = null,
    val items: List<WireWorkItem> = emptyList(),
)

/** Lightweight pointer for voice-clip user messages. */
@Serializable
data class WireAudioRef(
    val id: String,
    val mimeType: String,
    val durationMs: Int,
)

@Serializable
enum class WireAudioKind {
    @SerialName("user_message") user_message,
    @SerialName("dictation") dictation,
    @SerialName("agent_tts") agent_tts,
}

@Serializable
enum class WireAudioOriginActor {
    @SerialName("user") user,
    @SerialName("agent") agent,
}

@Serializable
enum class WireAudioTranscriptRole {
    @SerialName("transcription") transcription,
    @SerialName("synthesis_source") synthesis_source,
}

@Serializable
data class WireAudioTranscript(
    val id: String,
    val audioId: String,
    val role: WireAudioTranscriptRole,
    val text: String,
    val provider: String? = null,
    val language: String? = null,
    val createdAt: Long,
    val isPrimary: Boolean,
)

@Serializable
data class WireAudioAsset(
    val id: String,
    val kind: WireAudioKind,
    val appId: String,
    val originActor: WireAudioOriginActor,
    val mimeType: String,
    val bytesRelPath: String,
    val durationMs: Int,
    val createdAt: Long,
    val deviceId: String? = null,
    val sessionId: String? = null,
    val threadId: String? = null,
    val linkedMessageId: String? = null,
    val metadataJson: String? = null,
)

@Serializable
data class WireAudioAssetWithTranscripts(
    val asset: WireAudioAsset,
    val transcripts: List<WireAudioTranscript> = emptyList(),
)

@Serializable
data class WireAudioRegisterTranscript(
    val text: String,
    val role: WireAudioTranscriptRole? = null,
    val provider: String? = null,
    val language: String? = null,
)

@Serializable
data class WireAudioRegisterRequest(
    val id: String? = null,
    val kind: WireAudioKind,
    val appId: String,
    val originActor: WireAudioOriginActor,
    val mimeType: String,
    val bytesBase64: String,
    val durationMs: Int,
    val deviceId: String? = null,
    val sessionId: String? = null,
    val threadId: String? = null,
    val linkedMessageId: String? = null,
    val metadataJson: String? = null,
    val transcript: WireAudioRegisterTranscript? = null,
)

@Serializable
data class WireAudioAttachTranscriptInput(
    val text: String,
    val role: WireAudioTranscriptRole = WireAudioTranscriptRole.transcription,
    val provider: String? = null,
    val language: String? = null,
    val markAsPrimary: Boolean? = null,
)

@Serializable
data class WireAudioListFilter(
    val appId: String,
    val kind: WireAudioKind? = null,
    val originActor: WireAudioOriginActor? = null,
    val deviceId: String? = null,
    val sessionId: String? = null,
    val threadId: String? = null,
    val linkedMessageId: String? = null,
    val fromCreatedAt: Long? = null,
    val toCreatedAt: Long? = null,
    val limit: Int? = null,
    val offset: Int? = null,
)

@Serializable
data class WireAudioListResult(
    val items: List<WireAudioAssetWithTranscripts> = emptyList(),
    val total: Int,
)

@Serializable
data class WireMessage(
    val id: String,
    val role: WireRole,
    val content: String,
    val reasoningText: String = "",
    val streamingFinished: Boolean = true,
    val isError: Boolean = false,
    @Serializable(with = IsoDateSerializer::class)
    val timestamp: Instant,
    val timeline: List<WireTimelineEntry> = emptyList(),
    val workSummary: WireWorkSummary? = null,
    val audioRef: WireAudioRef? = null,
    val attachments: List<WireAttachment> = emptyList(),
) {
    companion object {
        val listSerializer: KSerializer<List<WireMessage>> = ListSerializer(serializer())
    }
}

// MARK: - Rate limits

@Serializable
data class WireRateLimitWindow(
    val usedPercent: Int,
    val resetsAt: Long? = null,
    val windowDurationMins: Long? = null,
)

@Serializable
data class WireCreditsSnapshot(
    val hasCredits: Boolean,
    val unlimited: Boolean,
    val balance: String? = null,
)

@Serializable
data class WireRateLimitSnapshot(
    val primary: WireRateLimitWindow? = null,
    val secondary: WireRateLimitWindow? = null,
    val credits: WireCreditsSnapshot? = null,
    val limitId: String? = null,
    val limitName: String? = null,
) {
    companion object {
        val mapSerializer: KSerializer<Map<String, WireRateLimitSnapshot>> =
            MapSerializer(String.serializer(), serializer())
    }
}
