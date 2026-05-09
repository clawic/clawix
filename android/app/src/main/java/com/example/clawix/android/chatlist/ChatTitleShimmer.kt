package com.example.clawix.android.chatlist

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import kotlin.math.cos

/**
 * Per-character opacity shimmer matching iOS `ChatTitleShimmer`. A
 * 3-second sinusoidal phase walks across the string so each glyph
 * pulses in turn. Used while a chat title is "Untitled" because the
 * daemon hasn't streamed it yet.
 */
@Composable
fun ChatTitleShimmer(
    text: String,
    style: TextStyle = AppTypography.bodyEmphasized,
    modifier: Modifier = Modifier,
) {
    val transition = rememberInfiniteTransition(label = "title-shimmer")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(durationMillis = 3000, easing = LinearEasing)),
        label = "phase",
    )

    Row(modifier) {
        text.forEachIndexed { idx, ch ->
            val charPhase = (phase - idx.toFloat() / text.length.coerceAtLeast(1)).mod(1f)
            // Smoothstep cubic: 0..1
            val s = (1f - cos(2f * Math.PI.toFloat() * charPhase)) / 2f
            val alpha = 0.40f + 0.55f * s
            Text(
                text = ch.toString(),
                style = style,
                color = Palette.textPrimary.copy(alpha = alpha),
            )
        }
    }
}
