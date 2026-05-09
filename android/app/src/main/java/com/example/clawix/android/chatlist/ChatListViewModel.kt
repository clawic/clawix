package com.example.clawix.android.chatlist

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.ConnectionState
import com.example.clawix.android.bridge.DerivedProject
import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.WireChat
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
    val pinnedChats: List<WireChat>,
    val recentChats: List<WireChat>,
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
            compareByDescending<WireChat> { it.isPinned }
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

    fun newChat(initialText: String? = null): String {
        val id = UUID.randomUUID().toString()
        if (initialText != null && initialText.isNotBlank()) {
            container.bridgeClient.newChat(id, initialText, emptyList())
        } else {
            container.bridgeStore.registerPendingNewChat(id)
        }
        return id
    }

    fun togglePin(chat: WireChat) {
        if (chat.isPinned) container.bridgeClient.send(BridgeBody.UnpinChat(chat.id))
        else container.bridgeClient.send(BridgeBody.PinChat(chat.id))
    }

    fun toggleArchive(chat: WireChat) {
        if (chat.isArchived) container.bridgeClient.send(BridgeBody.UnarchiveChat(chat.id))
        else container.bridgeClient.send(BridgeBody.ArchiveChat(chat.id))
    }

    fun rename(chat: WireChat, newTitle: String) {
        container.bridgeClient.send(BridgeBody.RenameChat(chat.id, newTitle))
    }

    fun refreshConnection() {
        val creds = container.credentialStore.load() ?: return
        container.bridgeClient.connect(creds)
    }
}
