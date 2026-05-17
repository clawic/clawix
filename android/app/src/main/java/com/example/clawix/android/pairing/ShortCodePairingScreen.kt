package com.example.clawix.android.pairing

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.Credentials
import com.example.clawix.android.bridge.DiscoveredMac
import com.example.clawix.android.icons.CloseIcon
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import kotlinx.coroutines.launch

@Composable
fun ShortCodePairingScreen(
    container: AppContainer,
    onPaired: () -> Unit,
    onCancel: () -> Unit,
) {
    val view = LocalView.current
    val flow = remember { ShortCodePairingFlow(container) }
    val discovered by flow.discovered.collectAsStateWithLifecycle()
    val status by flow.status.collectAsStateWithLifecycle()
    val busy by flow.busy.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    val codeComplete = code.length >= 9
    val canPair = codeComplete && discovered.isNotEmpty() && !busy

    LaunchedEffect(Unit) { flow.start() }

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
            .systemBarsPadding()
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = AppLayout.screenHorizontalPadding)
        ) {
            // Top bar
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Palette.cardFill)
                        .clickable { onCancel() },
                    contentAlignment = Alignment.Center,
                ) { CloseIcon(size = 18.dp, tint = Palette.textPrimary) }
                Spacer(Modifier.width(12.dp))
                Text("Pair with code", style = AppTypography.title, color = Palette.textPrimary)
            }

            Spacer(Modifier.height(16.dp))
            Text(
                "Make sure your phone and Mac are on the same Wi-Fi.",
                style = AppTypography.secondary,
                color = Palette.textSecondary,
            )
            Spacer(Modifier.height(16.dp))

            OutlinedTextField(
                value = code,
                onValueChange = { code = it.uppercase().filter { c -> c.isLetterOrDigit() || c == '-' }.take(11) },
                placeholder = { Text("ABC-DEF-GHI", style = AppTypography.body, color = Palette.textTertiary) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Characters,
                ),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Palette.cardFill,
                    unfocusedContainerColor = Palette.cardFill,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    cursorColor = Palette.textPrimary,
                ),
                shape = RoundedCornerShape(AppLayout.buttonCornerRadius),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(12.dp))

            Row(
                Modifier
                    .fillMaxWidth()
                    .height(52.dp)
                    .clip(RoundedCornerShape(AppLayout.buttonCornerRadius))
                    .background(if (code.length >= 9) Palette.userBubbleFill else Palette.cardFill)
                    .clickable(enabled = canPair) {
                        Haptics.send(view)
                        scope.launch {
                            val target = discovered.firstOrNull() ?: return@launch
                            val ok = flow.tryPair(target, code)
                            if (ok) onPaired()
                        }
                    }
                    .padding(horizontal = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                LucideIcon(LucideGlyph.Check, size = 18.dp, tint = if (code.length >= 9) Palette.userBubbleText else Palette.textTertiary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "Pair",
                    style = AppTypography.bodyEmphasized,
                    color = if (code.length >= 9) Palette.userBubbleText else Palette.textTertiary,
                )
            }

            status?.let {
                Spacer(Modifier.height(12.dp))
                Text(it, style = AppTypography.secondary, color = Palette.textSecondary)
            }

            Spacer(Modifier.height(24.dp))
            Text("Discovered Macs", style = AppTypography.caption, color = Palette.textTertiary)
            Spacer(Modifier.height(8.dp))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                items(discovered, key = { it.name }) { mac ->
                    MacRow(mac = mac, onClick = {
                        scope.launch {
                            if (codeComplete && !busy) {
                                val ok = flow.tryPair(mac, code)
                                if (ok) onPaired()
                            }
                        }
                    })
                }
            }
        }
    }
}

@Composable
private fun MacRow(mac: DiscoveredMac, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .background(Palette.cardFill)
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LucideIcon(LucideGlyph.Laptop, size = 20.dp, tint = Palette.textPrimary)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f, fill = true)) {
            Text(mac.name, style = AppTypography.bodyEmphasized, color = Palette.textPrimary)
            Text(
                "${mac.host}:${mac.port}",
                style = AppTypography.caption,
                color = Palette.textTertiary,
            )
        }
        LucideIcon(LucideGlyph.ChevronRight, size = 18.dp, tint = Palette.textTertiary)
    }
}
