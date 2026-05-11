package com.example.clawix.android.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Modifiers that produce the iOS 26 "Liquid Glass" pills used across the
 * app (top bar pill, settings buttons, search bar). Android uses the same
 * translucent fallback on all supported API levels because Compose
 * RenderEffect blurs the foreground layer rather than a true backdrop.
 */

private val GlassFill = Color(0x14FFFFFF)        // white.opacity(0.08) — slightly more than cardFill so the pill reads
private val GlassBorder = Color(0x33FFFFFF)      // white.opacity(0.20)
private val Fallback29Dim = Color(0x33000000)    // adds depth when blur isn't available

@Composable
fun Modifier.glassCircle(
    blurRadius: Dp = 22.dp,
    fill: Color = GlassFill,
    border: Color = GlassBorder,
): Modifier = this
    .applyBlurIfAvailable(blurRadius)
    .clip(CircleShape)
    .background(fill)
    .background(if (canBlur()) Color.Transparent else Fallback29Dim)
    .border(0.6.dp, border, CircleShape)

@Composable
fun Modifier.glassRounded(
    cornerRadius: Dp,
    blurRadius: Dp = 22.dp,
    fill: Color = GlassFill,
    border: Color = GlassBorder,
): Modifier = this
    .applyBlurIfAvailable(blurRadius)
    .clip(RoundedCornerShape(cornerRadius))
    .background(fill)
    .background(if (canBlur()) Color.Transparent else Fallback29Dim)
    .border(BorderStroke(0.6.dp, border), RoundedCornerShape(cornerRadius))

@Composable
fun Modifier.glassPill(
    blurRadius: Dp = 22.dp,
    fill: Color = GlassFill,
    border: Color = GlassBorder,
): Modifier = glassRounded(
    cornerRadius = AppLayout.topBarPillHeight / 2,
    blurRadius = blurRadius,
    fill = fill,
    border = border,
)

private fun canBlur(): Boolean = false

/**
 * Keep the modifier hook so call sites can stay aligned with the shared glass
 * shape helpers. The fallback dim layer above provides the Android rendering.
 */
private fun Modifier.applyBlurIfAvailable(@Suppress("UNUSED_PARAMETER") blurRadius: Dp): Modifier = this
