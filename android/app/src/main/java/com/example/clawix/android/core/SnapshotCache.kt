package com.example.clawix.android.core

import java.io.File
import kotlinx.serialization.Serializable

/**
 * Disk cache for the home chats list + recent messages of the
 * last-viewed chat. Mirrors `SnapshotCache.swift` in
 * `clawix/packages/ClawixCore/Sources/ClawixCore/SnapshotCache.swift`.
 *
 * Cap: 30 chats (sorted by recency) × 80 trailing messages per chat.
 * The first paint after cold-start hydrates from this file before the
 * WebSocket has time to land a fresh `sessionsSnapshot`.
 *
 * Atomic writes: serialize to `<file>.tmp` then `renameTo` so a crash
 * mid-write can never leave a partial file.
 */
@Serializable
data class SnapshotPayload(
    val schemaVersion: Int,
    val sessions: List<WireChat>,
    val messagesBySession: Map<String, List<WireMessage>>,
)

class SnapshotCache(filesDir: File) {
    private val dir = File(filesDir, "clawix").apply { mkdirs() }
    private val file = File(dir, "snapshot.json")
    private val tmp = File(dir, "snapshot.json.tmp")

    private val maxChats = 30
    private val maxMessages = 80
    private val ser = SnapshotPayload.serializer()

    fun load(): SnapshotPayload? {
        if (!file.exists()) return null
        return runCatching { BridgeJson.decodeFromString(ser, file.readText()) }.getOrNull()
    }

    fun save(chats: List<WireChat>, messagesBySession: Map<String, List<WireMessage>>) {
        val trimmedChats = chats
            .sortedByDescending { it.lastMessageAt ?: it.createdAt }
            .take(maxChats)
        val keepIds = trimmedChats.map { it.id }.toSet()
        val trimmedMessages = messagesBySession
            .filterKeys { it in keepIds }
            .mapValues { (_, list) -> list.takeLast(maxMessages) }

        val payload = SnapshotPayload(
            schemaVersion = BRIDGE_SCHEMA_VERSION,
            sessions = trimmedChats,
            messagesBySession = trimmedMessages,
        )
        runCatching {
            tmp.writeText(BridgeJson.encodeToString(ser, payload))
            if (file.exists()) file.delete()
            tmp.renameTo(file)
        }
    }

    fun clear() {
        runCatching { file.delete() }
        runCatching { tmp.delete() }
    }
}
