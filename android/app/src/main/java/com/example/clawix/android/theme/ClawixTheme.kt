package com.example.clawix.android.theme

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/**
 * Wraps Material3's `MaterialTheme` so library widgets (TextField,
 * BottomSheet, Dialog) inherit our dark palette. Every consumer of
 * MaterialTheme.colorScheme.* gets our overrides; consumer of
 * `LocalContentColor` / `LocalTextStyle` gets our defaults.
 */
@Composable
fun ClawixTheme(content: @Composable () -> Unit) {
    val colorScheme = darkColorScheme(
        primary = Palette.userBubbleFill,
        onPrimary = Palette.userBubbleText,
        primaryContainer = Palette.cardHover,
        onPrimaryContainer = Palette.textPrimary,
        secondary = Palette.unreadDot,
        onSecondary = Palette.background,
        background = Palette.background,
        onBackground = Palette.textPrimary,
        surface = Palette.background,
        onSurface = Palette.textPrimary,
        surfaceVariant = Palette.surface,
        onSurfaceVariant = Palette.textSecondary,
        surfaceContainer = Palette.surface,
        surfaceContainerHigh = Palette.surface,
        surfaceContainerHighest = Palette.surface,
        outline = Palette.border,
        outlineVariant = Palette.borderSubtle,
        error = Palette.unreadDot,
        onError = Palette.background,
    )

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography.materialTypography,
    ) {
        CompositionLocalProvider(
            LocalContentColor provides Palette.textPrimary,
            LocalTextStyle provides AppTypography.body,
            content = content,
        )
    }
}
