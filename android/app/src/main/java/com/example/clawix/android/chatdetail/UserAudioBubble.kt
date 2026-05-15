package com.example.clawix.android.chatdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.example.clawix.android.AppContainer
import com.example.clawix.android.core.WireAudioRef
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

/**
 * Playable bubble for user voice notes. Mirrors iOS `UserAudioBubble`.
 * Tap to fetch + play. We use `MediaPlayer` for simplicity since the
 * file is short (a few seconds).
 */
@Composable
fun UserAudioBubble(
    container: AppContainer,
    audioRef: WireAudioRef,
    modifier: Modifier = Modifier,
) {
    var loading by remember { mutableStateOf(false) }
    Row(
        modifier
            .clip(RoundedCornerShape(AppLayout.userBubbleRadius))
            .background(Palette.userBubbleFill)
            .clickable {
                loading = true
                container.bridgeClient.requestAudio(audioRef.id)
                // Real playback starts when the AudioSnapshot arrives.
            }
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(Palette.userBubbleText.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
            LucideIcon(if (loading) LucideGlyph.Pause else LucideGlyph.Play, size = 14.dp, tint = Palette.userBubbleText)
        }
        Spacer(Modifier.width(10.dp))
        Text(
            text = formatDuration(audioRef.durationMs),
            style = AppTypography.bodyEmphasized,
            color = Palette.userBubbleText,
        )
    }
}

private fun formatDuration(ms: Int): String {
    val totalSec = ms / 1000
    val m = totalSec / 60
    val s = totalSec % 60
    return "%d:%02d".format(m, s)
}
