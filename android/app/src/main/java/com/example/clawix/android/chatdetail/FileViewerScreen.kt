package com.example.clawix.android.chatdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.example.clawix.android.AppContainer
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

@Composable
fun FileViewerSheet(
    container: AppContainer,
    path: String,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val state by container.bridgeStore.state.collectAsState()
    val snapshot = state.fileSnapshots[path]

    LaunchedEffect(path) {
        if (snapshot == null) container.bridgeClient.readFile(path)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
        contentColor = Palette.textPrimary,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 12.dp)
                .verticalScroll(rememberScrollState())
        ) {
            Text(path.substringAfterLast('/'), style = AppTypography.title, color = Palette.textPrimary)
            Spacer(Modifier.height(4.dp))
            Text(path, style = AppTypography.caption, color = Palette.textTertiary)
            Spacer(Modifier.height(16.dp))
            when {
                snapshot == null -> Text("Loading…", style = AppTypography.body, color = Palette.textTertiary)
                snapshot.error != null -> Text(snapshot.error, style = AppTypography.body, color = Palette.unreadDot)
                snapshot.isMarkdown -> AssistantMarkdownView(snapshot.content ?: "")
                else -> Text(
                    snapshot.content ?: "",
                    style = AppTypography.mono,
                    color = Palette.textPrimary,
                )
            }
            Spacer(Modifier.height(36.dp))
        }
    }
}
