package com.example.clawix.android.icons

import androidx.compose.foundation.Canvas
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Hand-rolled Path-based icons mirroring the SVG-derived
 * the iOS custom icon files. Stroke widths and corner
 * curves match the SwiftUI `Path` originals.
 *
 * Intentionally NOT using Material Icons or `Icons.*` because user
 * preference forbids generic material glyphs.
 */

internal const val ICON_VIEWPORT = 24f
internal const val ICON_STROKE_BASE = 1.7f

@Composable
internal fun StrokeIcon(
    modifier: Modifier,
    size: Dp,
    tint: Color,
    block: (Path, Float) -> Unit,
) {
    val color = if (tint == Color.Unspecified) LocalContentColor.current else tint
    Canvas(modifier = modifier.then(androidx.compose.foundation.layout.size(size))) {
        val scale = this.size.minDimension / ICON_VIEWPORT
        val sw = ICON_STROKE_BASE * scale
        val path = Path()
        block(path, scale)
        drawPath(path = path, color = color, style = Stroke(width = sw, cap = StrokeCap.Round))
    }
}

@Composable
internal fun FillIcon(
    modifier: Modifier,
    size: Dp,
    tint: Color,
    block: (Path, Float) -> Unit,
) {
    val color = if (tint == Color.Unspecified) LocalContentColor.current else tint
    Canvas(modifier = modifier.then(androidx.compose.foundation.layout.size(size))) {
        val scale = this.size.minDimension / ICON_VIEWPORT
        val path = Path().apply { fillType = PathFillType.EvenOdd }
        block(path, scale)
        drawPath(path = path, color = color)
    }
}

@Composable
fun ComposeIcon(modifier: Modifier = Modifier, size: Dp = 22.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        // pencil-on-square: a pencil pointing into a tile (new chat metaphor)
        p.moveTo(4 * s, 20 * s)
        p.lineTo(20 * s, 20 * s)
        p.moveTo(4 * s, 4 * s)
        p.lineTo(13 * s, 4 * s)
        p.moveTo(4 * s, 4 * s)
        p.lineTo(4 * s, 13 * s)
        p.moveTo(15 * s, 4 * s)
        p.lineTo(20 * s, 9 * s)
        p.lineTo(11 * s, 18 * s)
        p.lineTo(7 * s, 19 * s)
        p.lineTo(8 * s, 15 * s)
        p.close()
    }
}

@Composable
fun SearchIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.addOval(
            androidx.compose.ui.geometry.Rect(
                Offset(4f * s, 4f * s),
                Size(11f * s, 11f * s),
            )
        )
        p.moveTo(14 * s, 14 * s)
        p.lineTo(20 * s, 20 * s)
    }
}

@Composable
fun CloseIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(6 * s, 6 * s)
        p.lineTo(18 * s, 18 * s)
        p.moveTo(18 * s, 6 * s)
        p.lineTo(6 * s, 18 * s)
    }
}

@Composable
fun SettingsIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.addOval(
            androidx.compose.ui.geometry.Rect(
                Offset(9 * s, 9 * s),
                Size(6 * s, 6 * s),
            )
        )
        // Spokes
        for (i in 0..7) {
            val angle = i * Math.PI / 4
            val cx = 12 * s
            val cy = 12 * s
            val r1 = 7 * s
            val r2 = 9 * s
            p.moveTo((cx + r1 * Math.cos(angle)).toFloat(), (cy + r1 * Math.sin(angle)).toFloat())
            p.lineTo((cx + r2 * Math.cos(angle)).toFloat(), (cy + r2 * Math.sin(angle)).toFloat())
        }
    }
}

@Composable
fun CopyIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(8 * s, 8 * s)
        p.lineTo(8 * s, 4 * s)
        p.lineTo(20 * s, 4 * s)
        p.lineTo(20 * s, 16 * s)
        p.lineTo(16 * s, 16 * s)
        p.moveTo(4 * s, 8 * s)
        p.lineTo(16 * s, 8 * s)
        p.lineTo(16 * s, 20 * s)
        p.lineTo(4 * s, 20 * s)
        p.close()
    }
}

@Composable
fun ArchiveIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(3 * s, 5 * s)
        p.lineTo(21 * s, 5 * s)
        p.lineTo(21 * s, 9 * s)
        p.lineTo(3 * s, 9 * s)
        p.close()
        p.moveTo(5 * s, 9 * s)
        p.lineTo(5 * s, 20 * s)
        p.lineTo(19 * s, 20 * s)
        p.lineTo(19 * s, 9 * s)
        p.moveTo(10 * s, 13 * s)
        p.lineTo(14 * s, 13 * s)
    }
}

@Composable
fun PencilIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(15 * s, 4 * s)
        p.lineTo(20 * s, 9 * s)
        p.lineTo(8 * s, 21 * s)
        p.lineTo(3 * s, 21 * s)
        p.lineTo(3 * s, 16 * s)
        p.close()
    }
}

@Composable
fun GlobeIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.addOval(
            androidx.compose.ui.geometry.Rect(
                Offset(3 * s, 3 * s),
                Size(18 * s, 18 * s),
            )
        )
        p.moveTo(3 * s, 12 * s)
        p.lineTo(21 * s, 12 * s)
        p.moveTo(12 * s, 3 * s)
        // wavy meridian
        p.cubicTo(8 * s, 9 * s, 8 * s, 15 * s, 12 * s, 21 * s)
        p.moveTo(12 * s, 3 * s)
        p.cubicTo(16 * s, 9 * s, 16 * s, 15 * s, 12 * s, 21 * s)
    }
}

@Composable
fun McpIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    // Three connected dots forming a flow
    StrokeIcon(modifier, size, tint) { p, s ->
        p.addOval(
            androidx.compose.ui.geometry.Rect(Offset(3 * s, 9 * s), Size(6 * s, 6 * s))
        )
        p.addOval(
            androidx.compose.ui.geometry.Rect(Offset(15 * s, 3 * s), Size(6 * s, 6 * s))
        )
        p.addOval(
            androidx.compose.ui.geometry.Rect(Offset(15 * s, 15 * s), Size(6 * s, 6 * s))
        )
        p.moveTo(9 * s, 12 * s)
        p.lineTo(15 * s, 6 * s)
        p.moveTo(9 * s, 12 * s)
        p.lineTo(15 * s, 18 * s)
    }
}
