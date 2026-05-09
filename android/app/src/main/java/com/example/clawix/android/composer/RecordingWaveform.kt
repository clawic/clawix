package com.example.clawix.android.composer

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.example.clawix.android.theme.Palette

/**
 * Live waveform: each bar maps to a recent amplitude sample (0..1).
 * Mirrors iOS `RecordingWaveform`. New samples are pushed at the right
 * edge; the array slides leftwards.
 */
@Composable
fun RecordingWaveform(
    samples: List<Float>,
    modifier: Modifier = Modifier,
    height: Dp = 60.dp,
) {
    Canvas(modifier = modifier
        .fillMaxWidth()
        .height(height)
    ) {
        if (samples.isEmpty()) return@Canvas
        val barCount = samples.size
        val barSpacing = 4f
        val totalSpacing = barSpacing * (barCount - 1)
        val barWidth = (size.width - totalSpacing) / barCount.coerceAtLeast(1).toFloat()
        val midY = size.height / 2
        val maxBar = size.height * 0.92f
        for ((idx, amp) in samples.withIndex()) {
            val h = (amp.coerceIn(0f, 1f) * maxBar).coerceAtLeast(2f)
            val x = idx * (barWidth + barSpacing) + barWidth / 2f
            drawLine(
                color = Palette.userBubbleFill,
                start = Offset(x, midY - h / 2f),
                end = Offset(x, midY + h / 2f),
                strokeWidth = barWidth,
                cap = StrokeCap.Round,
            )
        }
    }
}
