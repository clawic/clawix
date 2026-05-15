package com.example.clawix.android.chatlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.ConnectionState
import com.example.clawix.android.bridge.DerivedProject
import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.WireSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.launch
import java.util.UUID

data class ChatListUi(
    val pinnedChats: List<WireSession>,
    val recentChats: List<WireSession>,
    val projects: List<DerivedProject>,
    val unread: Set<String>,
    val connection: ConnectionState,
)

class ChatListViewModel(private val container: AppContainer) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    val ui: StateFlow<ChatListUi> = combine(
        container.bridgeStore.state,
        _query,
    ) { state, q ->
        val unread = container.unreadCache.load()
        val visible = state.chats.filter { !it.isArchived }
        val filtered = if (q.isBlank()) visible else visible.filter {
            it.title.contains(q, ignoreCase = true) ||
                (it.lastMessagePreview ?: "").contains(q, ignoreCase = true)
        }
        val sorted = filtered.sortedWith(
            compareByDescending<WireSession> { it.isPinned }
                .thenByDescending { it.lastMessageAt ?: it.createdAt }
        )
        ChatListUi(
            pinnedChats = sorted.filter { it.isPinned },
            recentChats = sorted.filter { !it.isPinned },
            projects = DerivedProject.from(state.chats),
            unread = unread,
            connection = state.connection,
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        ChatListUi(emptyList(), emptyList(), emptyList(), emptySet(), ConnectionState.Idle)
    )

    fun setQuery(q: String) { _query.value = q }

    fun newSession(initialText: String? = null): String {
        val id = UUID.randomUUID().toString()
        if (initialText != null && initialText.isNotBlank()) {
            container.bridgeClient.newSession(id, initialText, emptyList())
        } else {
            container.bridgeStore.registerPendingNewSession(id)
        }
        return id
    }

    fun togglePin(chat: WireSession) {
        if (chat.isPinned) container.bridgeClient.unpinSession(chat.id)
        else container.bridgeClient.pinSession(chat.id)
    }

    fun toggleArchive(chat: WireSession) {
        if (chat.isArchived) container.bridgeClient.unarchiveSession(chat.id)
        else container.bridgeClient.archiveSession(chat.id)
    }

    fun rename(chat: WireSession, newTitle: String) {
        val trimmed = newTitle.trim()
        if (trimmed.isEmpty()) return
        container.bridgeClient.renameSession(chat.id, trimmed)
    }

    fun refreshConnection() {
        val creds = container.credentialStore.load() ?: return
        container.bridgeClient.connect(creds)
    }
}
