package com.example.clawix.android.chatlist

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.clawix.android.core.WireSession
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

@Composable
fun ChatRow(
    chat: WireSession,
    isUnread: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 12.dp, vertical = AppLayout.listRowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (chat.isPinned) {
                    LucideIcon(LucideGlyph.Pin, size = 14.dp, tint = Palette.textTertiary)
                    Spacer(Modifier.width(6.dp))
                }
                Text(
                    text = chat.title.ifBlank { "Untitled" },
                    style = AppTypography.bodyEmphasized,
                    color = Palette.textPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            chat.lastMessagePreview?.takeIf { it.isNotBlank() }?.let {
                Spacer(Modifier.size(2.dp))
                Text(
                    text = it,
                    style = AppTypography.secondary,
                    color = Palette.textSecondary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (isUnread) {
            Spacer(Modifier.width(8.dp))
            Box(
                Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(Palette.unreadDot)
            )
        }
    }
}
