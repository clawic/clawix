package com.example.clawix.android.projectdetail

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.example.clawix.android.AppContainer
import com.example.clawix.android.chatlist.ChatRow
import com.example.clawix.android.icons.FolderOpenIcon
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import com.example.clawix.android.theme.glassCircle
import com.example.clawix.android.util.ViewModelFactory

@Composable
fun ProjectDetailScreen(
    container: AppContainer,
    projectId: String,
    onBack: () -> Unit,
    onOpenChat: (String) -> Unit,
) {
    val vm: ProjectDetailViewModel = viewModel(
        key = "project_$projectId",
        factory = ViewModelFactory { ProjectDetailViewModel(container, projectId) }
    )
    val ui by vm.ui.collectAsStateWithLifecycle()
    val view = LocalView.current

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
    ) {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = AppLayout.topBarReservedHeight + 64.dp,
                bottom = 32.dp,
                start = AppLayout.screenHorizontalPadding,
                end = AppLayout.screenHorizontalPadding,
            ),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item { ProjectHeader(ui) }
            items(ui.chats, key = { it.id }) { chat ->
                ChatRow(
                    chat = chat,
                    isUnread = false,
                    onClick = { onOpenChat(chat.id) },
                    onLongClick = { Haptics.longPress(view) },
                )
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 10.dp),
        ) {
            Box(
                Modifier
                    .size(AppLayout.topBarPillHeight)
                    .glassCircle()
                    .clickable { Haptics.tap(view); onBack() },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.ChevronLeft, size = 22.dp, tint = Palette.textPrimary)
            }
        }
    }
}

@Composable
private fun ProjectHeader(ui: ProjectDetailUi) {
    val project = ui.project ?: return
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .background(Palette.cardFill)
            .padding(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FolderOpenIcon(size = 22.dp, tint = Palette.textPrimary)
            Spacer(Modifier.size(10.dp))
            Text(project.title, style = AppTypography.title, color = Palette.textPrimary)
        }
        if (project.cwd != null) {
            Spacer(Modifier.height(6.dp))
            Text(project.cwd, style = AppTypography.caption, color = Palette.textTertiary)
        }
        if (project.branch != null) {
            Spacer(Modifier.height(2.dp))
            Text("on ${project.branch}", style = AppTypography.caption, color = Palette.textTertiary)
        }
    }
}
