package com.example.clawix.android.pairing

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.clawix.android.AppContainer
import com.example.clawix.android.icons.QrIcon
import com.example.clawix.android.icons.SettingsIcon
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette

@Composable
fun PairingScreen(
    container: AppContainer,
    onPaired: () -> Unit,
    onScanQr: () -> Unit,
    onShortCode: () -> Unit,
) {
    val view = LocalView.current
    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
            .systemBarsPadding()
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = AppLayout.screenHorizontalPadding),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Hero glyph
            Box(
                Modifier
                    .size(120.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Palette.cardFill),
                contentAlignment = Alignment.Center,
            ) {
                QrIcon(size = 56.dp, tint = Palette.textPrimary)
            }
            Spacer(Modifier.height(28.dp))
            Text(
                "Pair with your Mac",
                style = AppTypography.headlineLarge,
                color = Palette.textPrimary,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "Open Clawix on your Mac. Click \"Pair iPhone\" in the menu bar — your Mac will show a QR code.",
                style = AppTypography.body,
                color = Palette.textSecondary,
            )
            Spacer(Modifier.height(36.dp))

            CtaPrimary(
                text = "Scan QR code",
                glyph = LucideGlyph.Scan,
                onClick = {
                    Haptics.tap(view)
                    onScanQr()
                },
            )
            Spacer(Modifier.height(12.dp))
            CtaSecondary(
                text = "Type a code instead",
                glyph = LucideGlyph.Hash,
                onClick = {
                    Haptics.tap(view)
                    onShortCode()
                },
            )
        }
    }
}

@Composable
private fun CtaPrimary(text: String, glyph: LucideGlyph, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(AppLayout.buttonCornerRadius))
            .background(Palette.userBubbleFill)
            .clickable { onClick() }
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        LucideIcon(glyph = glyph, size = 20.dp, tint = Palette.userBubbleText)
        Spacer(Modifier.width(10.dp))
        Text(text, style = AppTypography.bodyEmphasized.copy(fontWeight = FontWeight.SemiBold), color = Palette.userBubbleText)
    }
}

@Composable
private fun CtaSecondary(text: String, glyph: LucideGlyph, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(AppLayout.buttonCornerRadius))
            .background(Palette.cardFill)
            .clickable { onClick() }
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        LucideIcon(glyph = glyph, size = 20.dp, tint = Palette.textPrimary)
        Spacer(Modifier.width(10.dp))
        Text(text, style = AppTypography.bodyEmphasized, color = Palette.textPrimary)
    }
}
