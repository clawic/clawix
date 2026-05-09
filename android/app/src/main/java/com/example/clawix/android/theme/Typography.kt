package com.example.clawix.android.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Mirror of iOS `Typography`. Letter spacing values use the same negative
 * `tracking` numbers iOS uses for chunky modern look (-0.4 on titles,
 * -0.2 on body). All numerical values are explicit, no derived defaults,
 * to keep parity easy to audit against `DesignTokens.swift`.
 */
object AppTypography {
    val title = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        letterSpacing = (-0.4).sp,
    )
    val headlineLarge = TextStyle(
        fontFamily = PlusJakartaFamily,
        fontWeight = FontWeight.Bold,
        fontSize = 28.sp,
        letterSpacing = (-0.6).sp,
    )
    val body = TextStyle(
        fontFamily = ManropeFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        letterSpacing = (-0.2).sp,
    )
    val bodyEmphasized = TextStyle(
        fontFamily = ManropeFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        letterSpacing = (-0.2).sp,
    )
    val chatBody = TextStyle(
        fontFamily = ManropeFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.5.sp,
        letterSpacing = (-0.2).sp,
        lineHeight = 24.sp,
    )
    val secondary = TextStyle(
        fontFamily = ManropeFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        letterSpacing = (-0.1).sp,
    )
    val caption = TextStyle(
        fontFamily = ManropeFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
    )
    val mono = TextStyle(
        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
        fontSize = 14.sp,
    )

    /** Material3 vehicle. We override almost every slot so MaterialTheme
     *  consumers downstream get the right defaults. */
    val materialTypography = Typography(
        displayLarge = headlineLarge,
        headlineLarge = headlineLarge,
        headlineMedium = title,
        headlineSmall = title,
        titleLarge = title,
        titleMedium = bodyEmphasized,
        titleSmall = secondary.copy(fontWeight = FontWeight.Medium),
        bodyLarge = body,
        bodyMedium = body,
        bodySmall = secondary,
        labelLarge = bodyEmphasized,
        labelMedium = secondary,
        labelSmall = caption,
    )
}
