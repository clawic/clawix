package com.example.clawix.android.chatdetail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.clawix.android.AppContainer
import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.WireAttachment
import com.example.clawix.android.core.WireChat
import com.example.clawix.android.core.WireMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class ChatDetailUi(
    val chat: WireChat?,
    val messages: List<WireMessage>,
    val hasMore: Boolean,
    val isStreaming: Boolean,
)

class ChatDetailViewModel(
    private val container: AppContainer,
    private val chatId: String,
) : ViewModel() {

    val ui: StateFlow<ChatDetailUi> = container.bridgeStore.state
        .map { state ->
            val chat = state.chats.firstOrNull { it.id == chatId }
            val messages = state.messagesByChat[chatId] ?: emptyList()
            val hasMore = state.hasMoreByChat[chatId] ?: false
            val streaming = messages.any { !it.streamingFinished && it.role == com.example.clawix.android.core.WireRole.assistant }
            ChatDetailUi(chat, messages, hasMore, streaming)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ChatDetailUi(null, emptyList(), false, false))

    fun open() {
        container.bridgeStore.setOpenChat(chatId)
        container.bridgeClient.openChat(chatId)
    }

    fun close() {
        container.bridgeStore.setOpenChat(null)
        container.bridgeClient.closeChat()
    }

    fun loadOlder(beforeMessageId: String) {
        container.bridgeClient.loadOlderMessages(chatId, beforeMessageId)
    }

    fun sendPrompt(text: String, attachments: List<WireAttachment> = emptyList()) {
        if (chatId in (container.bridgeStore.state.value.pendingNewChats)) {
            container.bridgeClient.newChat(chatId, text, attachments)
            container.bridgeStore.unregisterPendingNewChat(chatId)
        } else {
            container.bridgeClient.sendPrompt(chatId, text, attachments)
        }
    }

    fun stop() {
        container.bridgeClient.interruptTurn(chatId)
    }
}
