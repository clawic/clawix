package com.example.clawix.android.icons

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun CursorIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    FillIcon(modifier, size, tint) { p, s ->
        p.moveTo(5 * s, 3 * s)
        p.lineTo(19 * s, 12 * s)
        p.lineTo(13 * s, 13 * s)
        p.lineTo(11 * s, 19 * s)
        p.close()
    }
}

@Composable
fun TerminalIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(4 * s, 6 * s)
        p.lineTo(20 * s, 6 * s)
        p.lineTo(20 * s, 18 * s)
        p.lineTo(4 * s, 18 * s)
        p.close()
        p.moveTo(7 * s, 10 * s)
        p.lineTo(10 * s, 12 * s)
        p.lineTo(7 * s, 14 * s)
        p.moveTo(11 * s, 14 * s)
        p.lineTo(15 * s, 14 * s)
    }
}

@Composable
fun MicIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(12 * s, 3 * s)
        p.lineTo(12 * s, 3 * s)
        // Mic body: rounded rect 9..15 x 3..14
        val rect = androidx.compose.ui.geometry.Rect(Offset(9 * s, 3 * s), Size(6 * s, 11 * s))
        p.addRoundRect(
            androidx.compose.ui.geometry.RoundRect(
                rect,
                androidx.compose.ui.geometry.CornerRadius(3 * s),
            )
        )
        // Cradle arc
        p.moveTo(5 * s, 11 * s)
        p.cubicTo(5 * s, 16 * s, 9 * s, 19 * s, 12 * s, 19 * s)
        p.cubicTo(15 * s, 19 * s, 19 * s, 16 * s, 19 * s, 11 * s)
        // Stand
        p.moveTo(12 * s, 19 * s)
        p.lineTo(12 * s, 22 * s)
    }
}

@Composable
fun VoiceWaveformIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(4 * s, 12 * s); p.lineTo(4 * s, 12 * s)
        p.moveTo(7 * s, 10 * s); p.lineTo(7 * s, 14 * s)
        p.moveTo(10 * s, 6 * s); p.lineTo(10 * s, 18 * s)
        p.moveTo(13 * s, 8 * s); p.lineTo(13 * s, 16 * s)
        p.moveTo(16 * s, 4 * s); p.lineTo(16 * s, 20 * s)
        p.moveTo(19 * s, 9 * s); p.lineTo(19 * s, 15 * s)
    }
}

@Composable
fun QrIcon(modifier: Modifier = Modifier, size: Dp = 22.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        // Three corner finder squares (top-left, top-right, bottom-left)
        for ((cx, cy) in listOf(3 to 3, 14 to 3, 3 to 14)) {
            p.moveTo(cx * s, cy * s)
            p.lineTo((cx + 7) * s, cy * s)
            p.lineTo((cx + 7) * s, (cy + 7) * s)
            p.lineTo(cx * s, (cy + 7) * s)
            p.close()
            p.moveTo((cx + 2) * s, (cy + 2) * s)
            p.lineTo((cx + 5) * s, (cy + 2) * s)
            p.lineTo((cx + 5) * s, (cy + 5) * s)
            p.lineTo((cx + 2) * s, (cy + 5) * s)
            p.close()
        }
        // Data dots in bottom-right quadrant
        p.moveTo(14 * s, 14 * s); p.lineTo(15 * s, 14 * s)
        p.moveTo(17 * s, 14 * s); p.lineTo(18 * s, 14 * s)
        p.moveTo(14 * s, 17 * s); p.lineTo(15 * s, 17 * s)
        p.moveTo(17 * s, 17 * s); p.lineTo(20 * s, 17 * s)
        p.moveTo(14 * s, 20 * s); p.lineTo(20 * s, 20 * s)
    }
}
