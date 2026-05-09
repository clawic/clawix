package com.example.clawix.android.icons

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.clawix.android.theme.LucideFamily

/**
 * Renders a Lucide glyph as text using the bundled `lucide.ttf` icon
 * font. The font maps each named icon to a private-use codepoint; we
 * expose the most common ones via the `LucideGlyph` enum so callsites
 * stay typo-proof.
 */
@Composable
fun LucideIcon(
    glyph: LucideGlyph,
    modifier: Modifier = Modifier,
    size: Dp = 20.dp,
    tint: Color = LocalContentColor.current,
) {
    val sizeSp: TextUnit = (size.value * 0.92f).sp  // visually balance vs SVG icons
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = String(Character.toChars(glyph.codepoint)),
            style = TextStyle(
                fontFamily = LucideFamily,
                fontSize = sizeSp,
                color = tint,
            )
        )
    }
}
