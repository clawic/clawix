package com.example.clawix.android.chatlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.clawix.android.bridge.DerivedProject
import com.example.clawix.android.icons.FolderClosedIcon
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

@Composable
fun ProjectRow(project: DerivedProject, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .background(Palette.cardFill)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = AppLayout.listRowVerticalPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        FolderClosedIcon(size = 22.dp, tint = Palette.textPrimary)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                project.title,
                style = AppTypography.bodyEmphasized,
                color = Palette.textPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val subtitle = buildString {
                if (project.branch != null) append(project.branch)
                if (project.chatIds.isNotEmpty()) {
                    if (isNotEmpty()) append(" · ")
                    append("${project.chatIds.size} chats")
                }
            }
            if (subtitle.isNotEmpty()) {
                Spacer(Modifier.size(2.dp))
                Text(subtitle, style = AppTypography.caption, color = Palette.textTertiary)
            }
        }
        LucideIcon(LucideGlyph.ChevronRight, size = 16.dp, tint = Palette.textTertiary)
    }
}
