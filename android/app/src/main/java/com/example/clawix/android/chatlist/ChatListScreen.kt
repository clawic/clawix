package com.example.clawix.android.chatlist

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.DerivedProject
import com.example.clawix.android.core.WireChat
import com.example.clawix.android.icons.ComposeIcon
import com.example.clawix.android.icons.SearchIcon
import com.example.clawix.android.icons.SettingsIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import com.example.clawix.android.theme.glassPill
import com.example.clawix.android.theme.glassCircle
import com.example.clawix.android.util.ViewModelFactory

@Composable
fun ChatListScreen(
    container: AppContainer,
    onOpenChat: (String) -> Unit,
    onOpenProject: (String) -> Unit,
    onUnpair: () -> Unit,
) {
    val vm: ChatListViewModel = viewModel(factory = ViewModelFactory { ChatListViewModel(container) })
    val ui by vm.ui.collectAsStateWithLifecycle()
    val query by vm.query.collectAsStateWithLifecycle()
    val view = LocalView.current

    var searchExpanded by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showAllProjects by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        // Refresh chats list once on entry
        container.bridgeClient.send(com.example.clawix.android.core.BridgeBody.ListChats)
        container.bridgeClient.send(com.example.clawix.android.core.BridgeBody.ListProjects)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
    ) {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize(),
            contentPadding = PaddingValues(
                top = 80.dp,
                bottom = 100.dp,
                start = AppLayout.screenHorizontalPadding,
                end = AppLayout.screenHorizontalPadding,
            ),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (ui.projects.isNotEmpty()) {
                item {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Projects", style = AppTypography.caption, color = Palette.textTertiary)
                        Spacer(Modifier.weight(1f))
                        if (ui.projects.size > 5) {
                            Text(
                                "See all",
                                style = AppTypography.caption,
                                color = Palette.textSecondary,
                                modifier = Modifier.clickable { showAllProjects = true },
                            )
                        }
                    }
                }
                items(ui.projects.take(5), key = { it.id }) { project ->
                    ProjectRow(project = project, onClick = { onOpenProject(project.id) })
                }
                item { Spacer(Modifier.height(12.dp)) }
            }

            if (ui.pinnedChats.isNotEmpty()) {
                item {
                    Text(
                        "Pinned",
                        style = AppTypography.caption,
                        color = Palette.textTertiary,
                        modifier = Modifier.padding(top = 4.dp, bottom = 4.dp)
                    )
                }
                items(ui.pinnedChats, key = { it.id }) { chat ->
                    ChatRow(
                        chat = chat,
                        isUnread = chat.id in ui.unread,
                        onClick = { onOpenChat(chat.id) },
                        onLongClick = { Haptics.longPress(view); /* TODO menu */ },
                    )
                }
                item { Spacer(Modifier.height(12.dp)) }
            }

            if (ui.recentChats.isNotEmpty()) {
                item {
                    Text(
                        "Recent",
                        style = AppTypography.caption,
                        color = Palette.textTertiary,
                        modifier = Modifier.padding(top = 4.dp, bottom = 4.dp)
                    )
                }
                items(ui.recentChats, key = { it.id }) { chat ->
                    ChatRow(
                        chat = chat,
                        isUnread = chat.id in ui.unread,
                        onClick = { onOpenChat(chat.id) },
                        onLongClick = { Haptics.longPress(view); /* TODO menu */ },
                    )
                }
            } else if (ui.pinnedChats.isEmpty() && ui.projects.isEmpty()) {
                item { EmptyState() }
            }
        }

        // Top bar pill
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                Modifier
                    .height(AppLayout.topBarPillHeight)
                    .weight(1f)
                    .glassPill()
                    .padding(horizontal = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(36.dp)
                        .clickable {
                            searchExpanded = !searchExpanded
                            Haptics.tap(view)
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    SearchIcon(size = 18.dp, tint = Palette.textPrimary)
                }
                AnimatedVisibility(
                    visible = searchExpanded,
                    enter = expandHorizontally(),
                    exit = shrinkHorizontally(),
                ) {
                    Spacer(Modifier.width(8.dp))
                    BasicTextField(
                        value = query,
                        onValueChange = vm::setQuery,
                        singleLine = true,
                        textStyle = LocalTextStyle.current.copy(color = Palette.textPrimary),
                        cursorBrush = SolidColor(Palette.textPrimary),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        modifier = Modifier.weight(1f),
                    )
                }
                if (!searchExpanded) {
                    Spacer(Modifier.weight(1f))
                    Text("Clawix", style = AppTypography.bodyEmphasized, color = Palette.textPrimary)
                    Spacer(Modifier.weight(1f))
                    // hidden symmetry placeholder
                    Box(Modifier.size(36.dp))
                }
            }

            Box(
                Modifier
                    .size(AppLayout.topBarPillHeight)
                    .glassCircle()
                    .clickable {
                        Haptics.tap(view)
                        showSettings = true
                    },
                contentAlignment = Alignment.Center,
            ) {
                SettingsIcon(size = 22.dp, tint = Palette.textPrimary)
            }
        }

        // FAB
        NewChatFAB(
            onClick = {
                Haptics.tap(view)
                val id = vm.newChat()
                onOpenChat(id)
            },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .systemBarsPadding()
                .padding(horizontal = 20.dp, vertical = 24.dp),
        )

        if (showSettings) {
            SettingsSheet(
                connection = ui.connection,
                onDismiss = { showSettings = false },
                onUnpair = { showSettings = false; onUnpair() },
                onReconnect = { showSettings = false; vm.refreshConnection() },
            )
        }
        if (showAllProjects) {
            AllProjectsSheet(
                projects = ui.projects,
                onDismiss = { showAllProjects = false },
                onProject = { onOpenProject(it.id) },
            )
        }
    }
}

@Composable
private fun EmptyState() {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(top = 80.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ComposeIcon(size = 40.dp, tint = Palette.textTertiary)
        Spacer(Modifier.height(12.dp))
        Text("No chats yet", style = AppTypography.bodyEmphasized, color = Palette.textSecondary)
        Spacer(Modifier.height(4.dp))
        Text("Tap the new chat button to start", style = AppTypography.secondary, color = Palette.textTertiary)
    }
}
