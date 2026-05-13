package com.example.clawix.android.bridge

import com.example.clawix.android.core.BridgeRuntimeState
import com.example.clawix.android.core.SnapshotCache
import com.example.clawix.android.core.WireChat
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireProject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Single source of truth for chat / message / connection state on the
 * client. Mirrors iOS `BridgeStore`.
 *
 * Public API is read-only via `state: StateFlow<BridgeState>`. Mutations
 * happen through dedicated `apply*` methods that the BridgeClient invokes
 * when frames arrive. The store also persists to `SnapshotCache` on
 * every chat-list / messages mutation so cold-start can hydrate.
 */
class BridgeStore(
    private val scope: CoroutineScope,
    private val snapshotCache: SnapshotCache,
    private val unreadCache: UnreadChatsCache,
    private val projectLabelsCache: ProjectLabelsCache,
) {
    private val _state = MutableStateFlow(BridgeState())
    val state: StateFlow<BridgeState> = _state.asStateFlow()

    private val cacheMutex = Mutex()

    /** Hydrate from disk before the WebSocket connects. Idempotent. */
    fun hydrateFromCache() {
        val payload = snapshotCache.load() ?: return
        _state.update {
            it.copy(
                chats = payload.sessions,
                messagesBySession = payload.messagesBySession,
            )
        }
    }

    fun setConnection(state: ConnectionState) {
        _state.update { it.copy(connection = state) }
    }

    fun setRuntime(state: BridgeRuntimeState) {
        _state.update { it.copy(runtime = state) }
    }

    fun applySessionsSnapshot(chats: List<WireChat>) {
        _state.update { it.copy(chats = chats) }
        persistAsync()
    }

    fun applyChatUpdated(chat: WireChat) {
        _state.update { current ->
            val existing = current.chats.toMutableList()
            val idx = existing.indexOfFirst { it.id == chat.id }
            if (idx >= 0) existing[idx] = chat else existing.add(0, chat)
            current.copy(chats = existing)
        }
        persistAsync()
    }

    /**
     * Optimistic mutation. The UI updates immediately while the daemon
     * confirms with a `chatUpdated` frame that overwrites the entire chat
     * record. Mirrors how iOS `BridgeStore` patches `WireChat.isPinned`
     * locally before the round-trip resolves.
     */
    private inline fun mutateChat(chatId: String, transform: (WireChat) -> WireChat) {
        _state.update { current ->
            val list = current.chats.toMutableList()
            val idx = list.indexOfFirst { it.id == chatId }
            if (idx < 0) return@update current
            list[idx] = transform(list[idx])
            current.copy(chats = list)
        }
        persistAsync()
    }

    fun applyOptimisticPin(chatId: String, pinned: Boolean) {
        mutateChat(chatId) { it.copy(isPinned = pinned) }
    }

    fun applyOptimisticArchive(chatId: String, archived: Boolean) {
        mutateChat(chatId) { it.copy(isArchived = archived) }
    }

    fun applyOptimisticRename(chatId: String, title: String) {
        mutateChat(chatId) { it.copy(title = title) }
    }

    fun applyMessagesSnapshot(sessionId: String, messages: List<WireMessage>, hasMore: Boolean?) {
        _state.update { current ->
            val map = current.messagesBySession.toMutableMap()
            map[sessionId] = messages
            val more = current.hasMoreBySession.toMutableMap()
            if (hasMore != null) more[sessionId] = hasMore else more.remove(sessionId)
            current.copy(messagesBySession = map, hasMoreBySession = more)
        }
        persistAsync()
    }

    fun applyMessagesPage(sessionId: String, older: List<WireMessage>, hasMore: Boolean) {
        _state.update { current ->
            val existing = current.messagesBySession[sessionId] ?: emptyList()
            val merged = (older + existing).distinctBy { it.id }
            val map = current.messagesBySession.toMutableMap().apply { put(sessionId, merged) }
            val more = current.hasMoreBySession.toMutableMap().apply { put(sessionId, hasMore) }
            current.copy(messagesBySession = map, hasMoreBySession = more)
        }
        persistAsync()
    }

    fun applyMessageAppended(sessionId: String, message: WireMessage) {
        _state.update { current ->
            val existing = current.messagesBySession[sessionId] ?: emptyList()
            val map = current.messagesBySession.toMutableMap().apply {
                put(sessionId, existing + message)
            }
            current.copy(messagesBySession = map)
        }
        if (message.role == com.example.clawix.android.core.WireRole.assistant && _state.value.openSessionId != sessionId) {
            unreadCache.mark(sessionId)
        }
        persistAsync()
    }

    /**
     * Apply a batch of pending stream updates from StreamCoalescer.
     * Each entry replaces the cumulative content of the matching message.
     * If the message doesn't exist yet (rare race) we ignore the update;
     * a subsequent `messageAppended` will land it.
     */
    fun applyStreamingBatch(batch: Map<String, PendingStreamUpdate>) {
        if (batch.isEmpty()) return
        _state.update { current ->
            val updatedChats = current.messagesBySession.toMutableMap()
            for ((messageId, upd) in batch) {
                val list = updatedChats[upd.sessionId] ?: continue
                val idx = list.indexOfFirst { it.id == messageId }
                if (idx < 0) continue
                val newList = list.toMutableList()
                val existing = newList[idx]
                newList[idx] = existing.copy(
                    content = upd.content,
                    reasoningText = upd.reasoningText,
                    streamingFinished = upd.finished,
                )
                updatedChats[upd.sessionId] = newList
            }
            current.copy(messagesBySession = updatedChats)
        }
    }

    fun applyProjects(projects: List<WireProject>) {
        _state.update { it.copy(projects = projects) }
        for (p in projects) {
            projectLabelsCache.put(p.id, p.title)
        }
    }

    fun applyFileSnapshot(snapshot: FileSnapshotState) {
        _state.update {
            val map = it.fileSnapshots.toMutableMap().apply { put(snapshot.path, snapshot) }
            it.copy(fileSnapshots = map)
        }
    }

    fun applyGeneratedImage(image: GeneratedImageState) {
        _state.update {
            val map = it.generatedImages.toMutableMap().apply { put(image.path, image) }
            it.copy(generatedImages = map)
        }
    }

    fun setOpenSession(id: String?) {
        _state.update { it.copy(openSessionId = id) }
        if (id != null) unreadCache.clear(id)
    }

    fun registerPendingNewSession(sessionId: String) {
        _state.update {
            it.copy(pendingNewSessions = it.pendingNewSessions + sessionId)
        }
    }

    fun unregisterPendingNewSession(sessionId: String) {
        _state.update {
            it.copy(pendingNewSessions = it.pendingNewSessions - sessionId)
        }
    }

    fun registerPendingTranscription(requestId: String, chatId: String) {
        _state.update {
            it.copy(pendingTranscriptions = it.pendingTranscriptions + (requestId to chatId))
        }
    }

    fun applyTranscriptionResult(requestId: String, text: String) {
        _state.update {
            val pending = it.pendingTranscriptions - requestId
            val results = it.transcriptionResults + (requestId to text)
            it.copy(pendingTranscriptions = pending, transcriptionResults = results)
        }
    }

    fun consumeTranscriptionResult(requestId: String): String? {
        val text = _state.value.transcriptionResults[requestId] ?: return null
        _state.update {
            it.copy(transcriptionResults = it.transcriptionResults - requestId)
        }
        return text
    }

    private fun persistAsync() {
        scope.launch(Dispatchers.IO) {
            cacheMutex.withLock {
                val s = _state.value
                snapshotCache.save(s.chats, s.messagesBySession)
            }
        }
    }
}
