package com.example.clawix.android.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Vertical fade-out edges over a scrollable list. Matches iOS
 * `FadeEdge`: lays a gradient from `bgColor` → transparent over the top
 * `topHeight` and bottom `bottomHeight` so the content visually
 * disappears into the background instead of clipping at a hard line.
 */
@Composable
fun FadeEdges(
    bgColor: Color,
    topHeight: Dp = 60.dp,
    bottomHeight: Dp = 80.dp,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxWidth()) {
        if (topHeight > 0.dp) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(topHeight)
                    .align(Alignment.TopCenter)
                    .background(
                        Brush.verticalGradient(
                            0f to bgColor,
                            1f to bgColor.copy(alpha = 0f),
                        )
                    )
            )
        }
        if (bottomHeight > 0.dp) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(bottomHeight)
                    .align(Alignment.BottomCenter)
                    .background(
                        Brush.verticalGradient(
                            0f to bgColor.copy(alpha = 0f),
                            1f to bgColor,
                        )
                    )
            )
        }
    }
}
