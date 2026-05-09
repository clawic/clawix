package com.example.clawix.android.theme

import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Modifiers that produce the iOS 26 "Liquid Glass" pills used across the
 * app (top bar pill, settings buttons, search bar). On API 31+ uses
 * `RenderEffect.createBlurEffect`; on API 29-30 falls back to a
 * translucent layer with a subtle dim. Documented as a known visual
 * delta vs iOS in the README.
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

private fun canBlur(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

/**
 * Applies a blur RenderEffect on API 31+. On older versions returns the
 * receiver untouched (fallback handled by extra dim layer).
 */
private fun Modifier.applyBlurIfAvailable(blurRadius: Dp): Modifier {
    if (!canBlur()) return this
    val px = blurRadius.value
    return this.graphicsLayer {
        renderEffect = RenderEffect
            .createBlurEffect(px, px, Shader.TileMode.CLAMP)
            .asComposeRenderEffect()
    }
}
