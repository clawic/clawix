package com.example.clawix.android.chatdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.clawix.android.AppContainer
import com.example.clawix.android.composer.ComposerView
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireRole
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import com.example.clawix.android.theme.glassCircle
import com.example.clawix.android.util.ViewModelFactory
import kotlinx.coroutines.launch

@Composable
fun ChatDetailScreen(
    container: AppContainer,
    chatId: String,
    onBack: () -> Unit,
    onOpenProject: (String) -> Unit,
) {
    val vm: ChatDetailViewModel = viewModel(
        key = "chat_$chatId",
        factory = ViewModelFactory { ChatDetailViewModel(container, chatId) }
    )
    val ui by vm.ui.collectAsStateWithLifecycle()
    val view = LocalView.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    DisposableEffect(chatId) {
        vm.open()
        onDispose { vm.close() }
    }

    var fileViewerPath by remember { mutableStateOf<String?>(null) }
    var imageViewerPath by remember { mutableStateOf<String?>(null) }
    var showActions by remember { mutableStateOf(false) }
    var showRename by remember { mutableStateOf(false) }

    // Auto-scroll to bottom when streaming
    LaunchedEffect(ui.messages.size, ui.isStreaming) {
        if (ui.messages.isNotEmpty()) {
            listState.animateScrollToItem(0)
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .consumeWindowInsets(WindowInsets.ime),
            contentPadding = PaddingValues(
                top = AppLayout.composerReservedHeight + 8.dp,
                bottom = AppLayout.topBarReservedHeight + 24.dp,
                start = AppLayout.screenHorizontalPadding,
                end = AppLayout.screenHorizontalPadding,
            ),
            reverseLayout = true,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(ui.messages.reversed(), key = { it.id }) { msg ->
                MessageRow(
                    message = msg,
                    container = container,
                    onImageTap = { imageViewerPath = it },
                )
            }
            if (ui.hasMore) {
                item {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Load older messages",
                            style = AppTypography.secondary,
                            color = Palette.textSecondary,
                            modifier = Modifier.clickable {
                                val first = ui.messages.firstOrNull() ?: return@clickable
                                vm.loadOlder(first.id)
                            },
                        )
                    }
                }
            }
        }

        // Top bar
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                Modifier
                    .size(AppLayout.topBarPillHeight)
                    .glassCircle()
                    .clickable {
                        Haptics.tap(view)
                        onBack()
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.ChevronLeft, size = 22.dp, tint = Palette.textPrimary)
            }
            Box(
                Modifier
                    .height(AppLayout.topBarPillHeight)
                    .weight(1f)
                    .clip(RoundedCornerShape(AppLayout.topBarPillHeight / 2)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = ui.chat?.title?.ifBlank { "New chat" } ?: "New chat",
                    style = AppTypography.bodyEmphasized,
                    color = Palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Box(
                Modifier
                    .size(AppLayout.topBarPillHeight)
                    .glassCircle()
                    .clickable {
                        Haptics.tap(view)
                        if (ui.chat != null) showActions = true
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.Edit2, size = 20.dp, tint = Palette.textPrimary)
            }
        }

        // Composer pinned to bottom, IME-aware
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .imePadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 10.dp)
        ) {
            ComposerView(
                container = container,
                isStreaming = ui.isStreaming,
                onSend = { text, attachments ->
                    Haptics.send(view)
                    vm.sendPrompt(text, attachments)
                },
                onStop = {
                    Haptics.tap(view)
                    vm.stop()
                },
            )
        }

        fileViewerPath?.let { path ->
            FileViewerSheet(container = container, path = path, onDismiss = { fileViewerPath = null })
        }
        imageViewerPath?.let { path ->
            ImageViewerDialog(container = container, path = path, onDismiss = { imageViewerPath = null })
        }
        if (showActions) {
            ui.chat?.let { chat ->
                com.example.clawix.android.chatlist.ChatActionsSheet(
                    chat = chat,
                    onDismiss = { showActions = false },
                    onTogglePin = { vm.togglePin() },
                    onRename = { showRename = true },
                    onToggleArchive = {
                        val wasArchived = chat.isArchived
                        vm.toggleArchive()
                        if (!wasArchived) onBack()
                    },
                )
            }
        }
        if (showRename) {
            ui.chat?.let { chat ->
                com.example.clawix.android.chatlist.RenameChatDialog(
                    initialTitle = chat.title,
                    onDismiss = { showRename = false },
                    onSave = { vm.rename(it) },
                )
            }
        }
    }
}

@Composable
private fun MessageRow(
    message: WireMessage,
    container: AppContainer,
    onImageTap: (String) -> Unit,
) {
    when (message.role) {
        WireRole.user -> UserBubble(message = message)
        WireRole.assistant -> AssistantMessage(
            message = message,
            container = container,
            onImageTap = onImageTap,
        )
    }
}

@Composable
private fun UserBubble(message: WireMessage) {
    val ref = message.audioRef
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
        if (ref != null) {
            // Audio bubble
            UserAudioBubble(
                container = (rememberAppContainer()),
                audioRef = ref,
            )
        } else {
            Box(
                Modifier
                    .clip(RoundedCornerShape(AppLayout.userBubbleRadius))
                    .background(Palette.userBubbleFill)
                    .padding(horizontal = 14.dp, vertical = 10.dp)
            ) {
                Text(message.content, style = AppTypography.chatBody, color = Palette.userBubbleText)
            }
        }
    }
}

@Composable
private fun rememberAppContainer(): AppContainer {
    val ctx = androidx.compose.ui.platform.LocalContext.current.applicationContext
    return (ctx as com.example.clawix.android.ClawixApplication).container
}

@Composable
private fun AssistantMessage(
    message: WireMessage,
    container: AppContainer,
    onImageTap: (String) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        if (message.timeline.isNotEmpty()) {
            AssistantTimeline(message.timeline)
            Spacer(Modifier.height(4.dp))
        }
        if (!message.streamingFinished && message.content.isBlank() && message.timeline.isEmpty()) {
            ThinkingShimmer()
        } else {
            SelectableProseText({
                AssistantMarkdownView(message.content)
            })
        }
        // Inline images
        val imagePaths = message.timeline
            .filterIsInstance<com.example.clawix.android.core.WireTimelineEntry.Tools>()
            .flatMap { it.items }
            .mapNotNull { it.generatedImagePath }
        if (imagePaths.isNotEmpty()) {
            AssistantInlineImagesView(container = container, paths = imagePaths)
        }
    }
}
