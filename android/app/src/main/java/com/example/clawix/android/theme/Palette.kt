package com.example.clawix.android.theme

import androidx.compose.ui.graphics.Color

/**
 * Mirror of `clawix/ios/Sources/Clawix/Theme/DesignTokens.swift::Palette`.
 * Dark-only. The iPhone companion intentionally diverges from the dense
 * desktop grays because iOS 26 Liquid Glass reads better with refractive
 * capsules over a pure black canvas.
 */
object Palette {
    val background = Color(0xFF000000)
    val surface = Color(0xFF1A1A1A)            // Color(white: 0.10)
    val cardFill = Color(0x0FFFFFFF)            // white.opacity(0.06)
    val cardHover = Color(0x1AFFFFFF)           // white.opacity(0.10)
    val border = Color(0x1AFFFFFF)
    val borderSubtle = Color(0x0FFFFFFF)
    val popupStroke = Color(0x1AFFFFFF)
    const val popupStrokeWidth: Float = 0.5f
    val selFill = Color(0xFF474747)             // Color(white: 0.28)
    val textPrimary = Color.White
    val textSecondary = Color(0xA6FFFFFF)       // white.opacity(0.65) ≈ 0xA6
    val textTertiary = Color(0x73FFFFFF)        // white.opacity(0.45) ≈ 0x73

    // ChatGPT-style user message bubble: light, dark text. Contrast against
    // the assistant's bare-text response is what gives the rhythm.
    val userBubbleFill = Color(0xFFEBEBEB)      // white: 0.92
    val userBubbleText = Color(0xFF0D0D0D)      // white: 0.05

    // Soft pastel blue for unread cue. Same hue as the desktop's
    // `Palette.pastelBlue`.
    val unreadDot = Color(red = 0.45f, green = 0.65f, blue = 1.0f)

    // Launch-screen background.
    val launchBg = Color(0xFF0A0A0A)
}

object MenuStyle {
    const val cornerRadius: Float = 12f
    val fill = Color(red = 0.135f, green = 0.135f, blue = 0.135f, alpha = 0.92f)
    val shadowColor = Color(0x66000000)         // black.opacity(0.40)
    const val shadowRadius: Float = 18f
    const val shadowOffsetY: Float = 10f
    const val rowVerticalPadding: Float = 12f
    const val rowHorizontalPadding: Float = 16f
    val rowText = Color(0xFFF0F0F0)             // white: 0.94
    val rowIcon = Color(0xFFDBDBDB)             // white: 0.86
    val rowSubtle = Color(0xFF8C8C8C)           // white: 0.55
    val dividerColor = Color(0x0FFFFFFF)
}
