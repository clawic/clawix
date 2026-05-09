package com.example.clawix.android.core

import kotlinx.serialization.json.put

internal fun encodePayload(body: BridgeBody, b: kotlinx.serialization.json.JsonObjectBuilder) {
    when (body) {
        is BridgeBody.Auth -> {
            b.put("token", body.token)
            body.deviceName?.let { b.put("deviceName", it) }
            body.clientKind?.let { b.put("clientKind", it.name) }
        }
        BridgeBody.ListChats -> {}
        is BridgeBody.OpenChat -> {
            b.put("chatId", body.chatId)
            body.limit?.let { b.put("limit", it) }
        }
        is BridgeBody.LoadOlderMessages -> {
            b.put("chatId", body.chatId)
            b.put("beforeMessageId", body.beforeMessageId)
            b.put("limit", body.limit)
        }
        is BridgeBody.SendPrompt -> {
            b.put("chatId", body.chatId)
            b.put("text", body.text)
            if (body.attachments.isNotEmpty()) {
                b.put("attachments", BridgeJson.encodeToJsonElement(WireAttachment.listSerializer, body.attachments))
            }
        }
        is BridgeBody.NewChat -> {
            b.put("chatId", body.chatId)
            b.put("text", body.text)
            if (body.attachments.isNotEmpty()) {
                b.put("attachments", BridgeJson.encodeToJsonElement(WireAttachment.listSerializer, body.attachments))
            }
        }
        is BridgeBody.InterruptTurn -> b.put("chatId", body.chatId)
        is BridgeBody.AuthOk -> body.macName?.let { b.put("macName", it) }
        is BridgeBody.AuthFailed -> b.put("reason", body.reason)
        is BridgeBody.VersionMismatch -> b.put("serverVersion", body.serverVersion)
        is BridgeBody.ChatsSnapshot -> b.put("chats", BridgeJson.encodeToJsonElement(WireChat.listSerializer, body.chats))
        is BridgeBody.ChatUpdated -> b.put("chat", BridgeJson.encodeToJsonElement(WireChat.serializer(), body.chat))
        is BridgeBody.MessagesSnapshot -> {
            b.put("chatId", body.chatId)
            b.put("messages", BridgeJson.encodeToJsonElement(WireMessage.listSerializer, body.messages))
            body.hasMore?.let { b.put("hasMore", it) }
        }
        is BridgeBody.MessagesPage -> {
            b.put("chatId", body.chatId)
            b.put("messages", BridgeJson.encodeToJsonElement(WireMessage.listSerializer, body.messages))
            b.put("hasMore", body.hasMore)
        }
        is BridgeBody.MessageAppended -> {
            b.put("chatId", body.chatId)
            b.put("message", BridgeJson.encodeToJsonElement(WireMessage.serializer(), body.message))
        }
        is BridgeBody.MessageStreaming -> {
            b.put("chatId", body.chatId)
            b.put("messageId", body.messageId)
            b.put("content", body.content)
            b.put("reasoningText", body.reasoningText)
            b.put("finished", body.finished)
        }
        is BridgeBody.ErrorEvent -> {
            b.put("code", body.code)
            b.put("message", body.message)
        }
        is BridgeBody.EditPrompt -> {
            b.put("chatId", body.chatId)
            b.put("messageId", body.messageId)
            b.put("text", body.text)
        }
        is BridgeBody.ArchiveChat -> b.put("chatId", body.chatId)
        is BridgeBody.UnarchiveChat -> b.put("chatId", body.chatId)
        is BridgeBody.PinChat -> b.put("chatId", body.chatId)
        is BridgeBody.UnpinChat -> b.put("chatId", body.chatId)
        is BridgeBody.RenameChat -> {
            b.put("chatId", body.chatId)
            b.put("title", body.title)
        }
        BridgeBody.PairingStart, BridgeBody.ListProjects, BridgeBody.RequestRateLimits -> {}
        is BridgeBody.PairingPayload -> {
            b.put("qrJson", body.qrJson)
            b.put("bearer", body.bearer)
        }
        is BridgeBody.ProjectsSnapshot -> b.put("projects", BridgeJson.encodeToJsonElement(WireProject.listSerializer, body.projects))
        is BridgeBody.ReadFile -> b.put("path", body.path)
        is BridgeBody.FileSnapshot -> {
            b.put("path", body.path)
            body.content?.let { b.put("content", it) }
            b.put("isMarkdown", body.isMarkdown)
            body.error?.let { b.put("error", it) }
        }
        is BridgeBody.TranscribeAudio -> {
            b.put("requestId", body.requestId)
            b.put("audioBase64", body.audioBase64)
            b.put("mimeType", body.mimeType)
            body.language?.let { b.put("language", it) }
        }
        is BridgeBody.TranscriptionResult -> {
            b.put("requestId", body.requestId)
            b.put("text", body.text)
            body.errorMessage?.let { b.put("errorMessage", it) }
        }
        is BridgeBody.RequestAudio -> b.put("audioId", body.audioId)
        is BridgeBody.AudioSnapshot -> {
            b.put("audioId", body.audioId)
            body.audioBase64?.let { b.put("audioBase64", it) }
            body.mimeType?.let { b.put("mimeType", it) }
            body.errorMessage?.let { b.put("errorMessage", it) }
        }
        is BridgeBody.RequestGeneratedImage -> b.put("path", body.path)
        is BridgeBody.GeneratedImageSnapshot -> {
            b.put("path", body.path)
            body.dataBase64?.let { b.put("dataBase64", it) }
            body.mimeType?.let { b.put("mimeType", it) }
            body.errorMessage?.let { b.put("errorMessage", it) }
        }
        is BridgeBody.BridgeStateFrame -> {
            b.put("state", body.state)
            b.put("chatCount", body.chatCount)
            body.message?.let { b.put("message", it) }
        }
        is BridgeBody.RateLimitsSnapshot -> {
            body.snapshot?.let { b.put("rateLimits", BridgeJson.encodeToJsonElement(WireRateLimitSnapshot.serializer(), it)) }
            b.put(
                "rateLimitsByLimitId",
                BridgeJson.encodeToJsonElement(WireRateLimitSnapshot.mapSerializer, body.byLimitId)
            )
        }
        is BridgeBody.RateLimitsUpdated -> {
            body.snapshot?.let { b.put("rateLimits", BridgeJson.encodeToJsonElement(WireRateLimitSnapshot.serializer(), it)) }
            b.put(
                "rateLimitsByLimitId",
                BridgeJson.encodeToJsonElement(WireRateLimitSnapshot.mapSerializer, body.byLimitId)
            )
        }
        is BridgeBody.Unknown -> {
            // Re-emit raw fields preserving keys.
            body.raw.forEach { (k, v) ->
                if (k != "schemaVersion" && k != "type") b.put(k, v)
            }
        }
    }
}
