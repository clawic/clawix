package com.example.clawix.android.chatlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.clawix.android.core.WireSession
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

/**
 * Long-press / ellipsis menu for a chat. Mirrors the action set iOS
 * exposes on `ChatDetailView` (rename + archive) and on `ChatListView`
 * row context menus (pin + rename + archive). Delete is intentionally
 * excluded; iOS doesn't offer it either.
 */
@Composable
fun ChatActionsSheet(
    chat: WireSession,
    onDismiss: () -> Unit,
    onTogglePin: () -> Unit,
    onRename: () -> Unit,
    onToggleArchive: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
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
        ) {
            Text(
                text = chat.title.ifBlank { "Untitled chat" },
                style = AppTypography.title,
                color = Palette.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(16.dp))

            ActionRow(
                glyph = LucideGlyph.Pin,
                label = if (chat.isPinned) "Unpin" else "Pin",
                onClick = { onDismiss(); onTogglePin() },
            )
            ActionRow(
                glyph = LucideGlyph.Pencil,
                label = "Rename",
                onClick = { onDismiss(); onRename() },
            )
            ActionRow(
                glyph = LucideGlyph.Archive,
                label = if (chat.isArchived) "Unarchive" else "Archive",
                onClick = { onDismiss(); onToggleArchive() },
            )

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ActionRow(glyph: LucideGlyph, label: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Palette.cardFill),
            contentAlignment = Alignment.Center,
        ) {
            LucideIcon(glyph, size = 18.dp, tint = Palette.textPrimary)
        }
        Spacer(Modifier.width(12.dp))
        Text(label, style = AppTypography.body, color = Palette.textPrimary)
    }
}
