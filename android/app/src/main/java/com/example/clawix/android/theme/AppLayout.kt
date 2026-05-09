package com.example.clawix.android.theme

import androidx.compose.ui.unit.dp

/**
 * Mirror of iOS `AppLayout`. Tuned for iOS 26 Liquid Glass: pill heights
 * are ~50dp so refraction has room to read; composer reaches ~64dp for a
 * chunky tappable surface. dp ≡ pt at 1x for our purposes.
 */
object AppLayout {
    val screenHorizontalPadding = 16.dp
    val screenTopPadding = 8.dp
    val cardCornerRadius = 20.dp
    val chipCornerRadius = 12.dp
    val buttonCornerRadius = 16.dp
    val cardSpacing = 12.dp
    val listRowVerticalPadding = 14.dp
    val composerCornerRadius = 32.dp
    val userBubbleRadius = 24.dp
    val topBarPillHeight = 50.dp
    val topBarReservedHeight = 64.dp
    val composerReservedHeight = 110.dp
}
