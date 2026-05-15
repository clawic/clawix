package com.example.clawix.android.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

internal fun decodePayload(type: String, obj: JsonObject): BridgeBody = when (type) {
    "auth" -> BridgeBody.Auth(
        token = obj.requireString("token"),
        deviceName = obj.optString("deviceName"),
        clientKind = ClientKind.fromWire(obj.requireString("clientKind")),
        clientId = obj.requireString("clientId"),
        installationId = obj.requireString("installationId"),
        deviceId = obj.requireString("deviceId"),
    )
    "listSessions" -> BridgeBody.ListSessions
    "openSession" -> BridgeBody.OpenSession(obj.requireString("sessionId"), obj.optInt("limit"))
    "loadOlderMessages" -> BridgeBody.LoadOlderMessages(
        obj.requireString("sessionId"),
        obj.requireString("beforeMessageId"),
        obj.requireInt("limit"),
    )
    "sendMessage" -> BridgeBody.SendMessage(
        obj.requireString("sessionId"),
        obj.requireString("text"),
        obj.optList("attachments", WireAttachment.listSerializer) ?: emptyList(),
    )
    "newSession" -> BridgeBody.NewSession(
        obj.requireString("sessionId"),
        obj.requireString("text"),
        obj.optList("attachments", WireAttachment.listSerializer) ?: emptyList(),
    )
    "interruptTurn" -> BridgeBody.InterruptTurn(obj.requireString("sessionId"))
    "authOk" -> BridgeBody.AuthOk(obj.optString("hostDisplayName"))
    "authFailed" -> BridgeBody.AuthFailed(obj.requireString("reason"))
    "versionMismatch" -> BridgeBody.VersionMismatch(obj.requireInt("serverVersion"))
    "sessionsSnapshot" -> BridgeBody.SessionsSnapshot(obj.requireList("sessions", WireSession.listSerializer))
    "sessionUpdated" -> BridgeBody.SessionUpdated(obj.requireObj("session", WireSession.serializer()))
    "messagesSnapshot" -> BridgeBody.MessagesSnapshot(
        obj.requireString("sessionId"),
        obj.requireList("messages", WireMessage.listSerializer),
        obj.optBool("hasMore"),
    )
    "messagesPage" -> BridgeBody.MessagesPage(
        obj.requireString("sessionId"),
        obj.requireList("messages", WireMessage.listSerializer),
        obj.requireBool("hasMore"),
    )
    "messageAppended" -> BridgeBody.MessageAppended(
        obj.requireString("sessionId"),
        obj.requireObj("message", WireMessage.serializer()),
    )
    "messageStreaming" -> BridgeBody.MessageStreaming(
        obj.requireString("sessionId"),
        obj.requireString("messageId"),
        obj.optString("content") ?: "",
        obj.optString("reasoningText") ?: "",
        obj.requireBool("finished"),
    )
    "errorEvent" -> BridgeBody.ErrorEvent(obj.requireString("code"), obj.requireString("message"))
    "editPrompt" -> BridgeBody.EditPrompt(obj.requireString("sessionId"), obj.requireString("messageId"), obj.requireString("text"))
    "archiveSession" -> BridgeBody.ArchiveSession(obj.requireString("sessionId"))
    "unarchiveSession" -> BridgeBody.UnarchiveSession(obj.requireString("sessionId"))
    "pinSession" -> BridgeBody.PinSession(obj.requireString("sessionId"))
    "unpinSession" -> BridgeBody.UnpinSession(obj.requireString("sessionId"))
    "renameSession" -> BridgeBody.RenameSession(obj.requireString("sessionId"), obj.requireString("title"))
    "pairingStart" -> BridgeBody.PairingStart
    "listProjects" -> BridgeBody.ListProjects
    "readFile" -> BridgeBody.ReadFile(obj.requireString("path"))
    "pairingPayload" -> BridgeBody.PairingPayload(obj.requireString("qrJson"), obj.requireString("bearer"))
    "projectsSnapshot" -> BridgeBody.ProjectsSnapshot(obj.requireList("projects", WireProject.listSerializer))
    "fileSnapshot" -> BridgeBody.FileSnapshot(
        path = obj.requireString("path"),
        content = obj.optString("content"),
        isMarkdown = obj.requireBool("isMarkdown"),
        error = obj.optString("error"),
    )
    "transcribeAudio" -> BridgeBody.TranscribeAudio(
        obj.requireString("requestId"),
        obj.requireString("audioBase64"),
        obj.requireString("mimeType"),
        obj.optString("language"),
    )
    "transcriptionResult" -> BridgeBody.TranscriptionResult(
        obj.requireString("requestId"),
        obj.requireString("text"),
        obj.optString("errorMessage"),
    )
    "requestAudio" -> BridgeBody.RequestAudio(obj.requireString("audioId"))
    "audioSnapshot" -> BridgeBody.AudioSnapshot(
        obj.requireString("audioId"),
        obj.optString("audioBase64"),
        obj.optString("mimeType"),
        obj.optString("errorMessage"),
    )
    "requestGeneratedImage" -> BridgeBody.RequestGeneratedImage(obj.requireString("path"))
    "generatedImageSnapshot" -> BridgeBody.GeneratedImageSnapshot(
        obj.requireString("path"),
        obj.optString("dataBase64"),
        obj.optString("mimeType"),
        obj.optString("errorMessage"),
    )
    "bridgeState" -> BridgeBody.BridgeStateFrame(
        obj.requireString("state"),
        obj.requireInt("chatCount"),
        obj.optString("message"),
    )
    "requestRateLimits" -> BridgeBody.RequestRateLimits
    "rateLimitsSnapshot" -> BridgeBody.RateLimitsSnapshot(
        snapshot = obj.optObj("rateLimits", WireRateLimitSnapshot.serializer()),
        byLimitId = obj.optMap("rateLimitsByLimitId", WireRateLimitSnapshot.mapSerializer) ?: emptyMap(),
    )
    "rateLimitsUpdated" -> BridgeBody.RateLimitsUpdated(
        snapshot = obj.optObj("rateLimits", WireRateLimitSnapshot.serializer()),
        byLimitId = obj.optMap("rateLimitsByLimitId", WireRateLimitSnapshot.mapSerializer) ?: emptyMap(),
    )
    else -> BridgeBody.Unknown(type, obj)
}

internal fun JsonObject.requireString(key: String): String =
    this[key]?.jsonPrimitive?.content ?: error("missing $key")

internal fun JsonObject.optString(key: String): String? =
    this[key]?.jsonPrimitive?.contentOrNull

internal fun JsonObject.requireInt(key: String): Int =
    this[key]?.jsonPrimitive?.content?.toInt() ?: error("missing int $key")

internal fun JsonObject.optInt(key: String): Int? =
    this[key]?.jsonPrimitive?.contentOrNull?.toIntOrNull()

internal fun JsonObject.requireBool(key: String): Boolean =
    this[key]?.jsonPrimitive?.content?.toBooleanStrict() ?: error("missing bool $key")

internal fun JsonObject.optBool(key: String): Boolean? =
    this[key]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull()

private fun <T> JsonObject.requireList(key: String, ser: KSerializer<List<T>>): List<T> {
    val el = this[key] ?: error("missing list $key")
    return BridgeJson.decodeFromJsonElement(ser, el)
}

private fun <T> JsonObject.optList(key: String, ser: KSerializer<List<T>>): List<T>? {
    val el = this[key] ?: return null
    return BridgeJson.decodeFromJsonElement(ser, el)
}

private fun <T> JsonObject.requireObj(key: String, ser: KSerializer<T>): T {
    val el = this[key] ?: error("missing obj $key")
    return BridgeJson.decodeFromJsonElement(ser, el)
}

private fun <T> JsonObject.optObj(key: String, ser: KSerializer<T>): T? {
    val el = this[key] ?: return null
    return BridgeJson.decodeFromJsonElement(ser, el)
}

private fun <K, V> JsonObject.optMap(key: String, ser: KSerializer<Map<K, V>>): Map<K, V>? {
    val el = this[key] ?: return null
    return BridgeJson.decodeFromJsonElement(ser, el)
}
