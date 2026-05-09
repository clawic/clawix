package com.example.clawix.android.theme

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.example.clawix.android.R

/**
 * Custom font families. Matches iOS `BodyFont`/`AppFont` setup:
 * Plus Jakarta Sans for headlines, Manrope (variable) for body text,
 * Lucide for icons.
 *
 * Font assets live in `res/font/` with lowercase_underscore filenames so
 * they are addressable through `R.font.*`.
 */
val PlusJakartaFamily = FontFamily(
    Font(R.font.plus_jakarta_sans_regular, FontWeight.Normal),
    Font(R.font.plus_jakarta_sans_medium, FontWeight.Medium),
    Font(R.font.plus_jakarta_sans_semibold, FontWeight.SemiBold),
    Font(R.font.plus_jakarta_sans_bold, FontWeight.Bold),
)

/**
 * Manrope is shipped as a single variable font; we map the four cuts the
 * iOS app uses to the same file. Compose picks the closest weight at
 * render time. Intermediate weights (e.g. 450) won't render identically
 * to iOS, but the iPhone code rarely uses them.
 */
val ManropeFamily = FontFamily(
    Font(R.font.manrope_variable, FontWeight.Normal),
    Font(R.font.manrope_variable, FontWeight.Medium),
    Font(R.font.manrope_variable, FontWeight.SemiBold),
    Font(R.font.manrope_variable, FontWeight.Bold),
)

val LucideFamily = FontFamily(Font(R.font.lucide, FontWeight.Normal))
