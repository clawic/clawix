package com.example.clawix.android.chatdetail

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
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import kotlin.math.cos

/**
 * "Thinking…" indicator: same per-character opacity wave used by
 * `ChatTitleShimmer` but tuned for body text. Mirrors iOS
 * `ThinkingShimmer`.
 */
@Composable
fun ThinkingShimmer(text: String = "Thinking…", modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "thinking")
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(durationMillis = 3000, easing = LinearEasing)),
        label = "thinking-phase",
    )
    Row(modifier) {
        text.forEachIndexed { idx, ch ->
            val charPhase = (phase - idx.toFloat() / text.length.coerceAtLeast(1)).mod(1f)
            val s = (1f - cos(2f * Math.PI.toFloat() * charPhase)) / 2f
            val alpha = 0.30f + 0.55f * s
            Text(
                text = ch.toString(),
                style = AppTypography.bodyEmphasized,
                color = Palette.textPrimary.copy(alpha = alpha),
            )
        }
    }
}
