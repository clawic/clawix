package com.example.clawix.android.chatlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.clawix.android.bridge.ConnectionRoute
import com.example.clawix.android.bridge.ConnectionState
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

@Composable
fun SettingsSheet(
    connection: ConnectionState,
    onDismiss: () -> Unit,
    onUnpair: () -> Unit,
    onReconnect: () -> Unit,
    onPairAnother: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
        contentColor = Palette.textPrimary,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 12.dp)
        ) {
            Text("Settings", style = AppTypography.title, color = Palette.textPrimary)
            Spacer(Modifier.height(20.dp))

            ConnectionStatusRow(connection = connection)
            Spacer(Modifier.height(16.dp))

            ActionRow(LucideGlyph.Refresh, "Reconnect", onClick = onReconnect)
            ActionRow(LucideGlyph.QrCode, "Pair another Mac", onClick = onPairAnother)
            ActionRow(LucideGlyph.Unlock, "Unpair Mac", danger = true, onClick = onUnpair)
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ConnectionStatusRow(connection: ConnectionState) {
    val (label, color, icon) = when (connection) {
        ConnectionState.Idle -> Triple("Not connected", Palette.textTertiary, LucideGlyph.WifiOff)
        ConnectionState.Connecting -> Triple("Connecting…", Palette.textSecondary, LucideGlyph.Wifi)
        is ConnectionState.Reconnecting -> Triple("Reconnecting (#${connection.attempt})", Palette.textSecondary, LucideGlyph.Wifi)
        is ConnectionState.Connected -> {
            val routeLabel = when (connection.route) {
                ConnectionRoute.Lan -> "LAN"
                ConnectionRoute.Tailscale -> "Tailscale"
                ConnectionRoute.Bonjour -> "Bonjour"
            }
            Triple("Connected via $routeLabel${connection.hostDisplayName?.let { " · $it" } ?: ""}", Palette.unreadDot, LucideGlyph.Wifi)
        }
        is ConnectionState.Failed -> Triple("Failed: ${connection.reason}", Palette.unreadDot, LucideGlyph.CircleAlert)
        is ConnectionState.VersionMismatch -> Triple("Update required (server v${connection.serverVersion})", Palette.unreadDot, LucideGlyph.CircleAlert)
    }
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .background(Palette.cardFill)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(color.copy(alpha = 0.20f)), contentAlignment = Alignment.Center) {
            LucideIcon(icon, size = 18.dp, tint = color)
        }
        Spacer(Modifier.width(12.dp))
        Text(label, style = AppTypography.body, color = Palette.textPrimary)
    }
}

@Composable
private fun ActionRow(glyph: LucideGlyph, label: String, danger: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LucideIcon(glyph, size = 20.dp, tint = if (danger) Palette.unreadDot else Palette.textPrimary)
        Spacer(Modifier.width(12.dp))
        Text(label, style = AppTypography.body, color = if (danger) Palette.unreadDot else Palette.textPrimary)
    }
}
