package com.example.clawix.android.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Subtle top fade that replaces the bottom edge of an elevated top bar
 * with a gradient back to the background color. Mirrors iOS
 * `TopBarBlurFade`: enough to disambiguate the floating glass pill from
 * scrolling content without requiring an actual blur on legacy APIs.
 */
@Composable
fun TopBarBlurFade(
    bgColor: Color,
    height: Dp = 24.dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .background(
                Brush.verticalGradient(
                    0f to bgColor,
                    1f to bgColor.copy(alpha = 0f),
                )
            )
    )
}
