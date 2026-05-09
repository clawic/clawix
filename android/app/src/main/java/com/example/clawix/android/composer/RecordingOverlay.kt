package com.example.clawix.android.composer

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.example.clawix.android.AppContainer
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette

sealed class VoiceRecordingResult {
    data class Transcribed(val text: String) : VoiceRecordingResult()
    data class Audio(val attachment: ComposerAttachment) : VoiceRecordingResult()
}

@Composable
fun RecordingOverlay(
    container: AppContainer,
    onComplete: (VoiceRecordingResult?) -> Unit,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val recorder = remember { VoiceRecorder(container) }
    val samples = remember { mutableStateListOf<Float>() }
    var elapsed by remember { mutableStateOf(0L) }
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (!granted) onComplete(null)
    }

    LaunchedEffect(Unit) {
        if (!hasPermission) {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
            return@LaunchedEffect
        }
        runCatching { recorder.start(context) }
            .onFailure { onComplete(null); return@LaunchedEffect }
        Haptics.tap(view)
        val started = System.currentTimeMillis()
        while (true) {
            kotlinx.coroutines.delay(100)
            elapsed = System.currentTimeMillis() - started
            samples.add(recorder.currentAmplitudeNormalized())
            if (samples.size > 60) samples.removeFirst()
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            runCatching { recorder.stopAndDiscard() }
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.78f))
            .clickable { /* swallow */ }
    ) {
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 32.dp)
                .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
                .background(Palette.surface)
                .padding(20.dp),
        ) {
            Text(
                "Recording…  ${formatElapsed(elapsed)}",
                style = AppTypography.bodyEmphasized,
                color = Palette.textPrimary,
            )
            Spacer(Modifier.height(12.dp))
            RecordingWaveform(samples = samples)
            Spacer(Modifier.height(16.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ActionPill(
                    icon = LucideGlyph.X,
                    label = "Cancel",
                    onClick = {
                        Haptics.tap(view)
                        runCatching { recorder.stopAndDiscard() }
                        onComplete(null)
                    },
                    weight = 1f,
                )
                ActionPill(
                    icon = LucideGlyph.AudioWaveform,
                    label = "Send audio",
                    onClick = {
                        Haptics.send(view)
                        val (bytes, mime) = recorder.stopAndCollect() ?: return@ActionPill onComplete(null)
                        onComplete(
                            VoiceRecordingResult.Audio(
                                ComposerAttachment(
                                    kind = WireAttachmentKind.audio,
                                    mimeType = mime,
                                    filename = "voice.m4a",
                                    bytes = bytes,
                                )
                            )
                        )
                    },
                    weight = 1f,
                )
                ActionPill(
                    icon = LucideGlyph.Check,
                    label = "Transcribe",
                    primary = true,
                    onClick = {
                        Haptics.send(view)
                        val (bytes, mime) = recorder.stopAndCollect() ?: return@ActionPill onComplete(null)
                        recorder.transcribe(bytes, mime) { text ->
                            onComplete(text?.let { VoiceRecordingResult.Transcribed(it) })
                        }
                    },
                    weight = 1f,
                )
            }
        }
    }
}

private fun formatElapsed(ms: Long): String {
    val totalSec = ms / 1000
    val m = totalSec / 60
    val s = totalSec % 60
    return "%d:%02d".format(m, s)
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ActionPill(
    icon: LucideGlyph,
    label: String,
    onClick: () -> Unit,
    primary: Boolean = false,
    weight: Float,
) {
    Row(
        Modifier
            .weight(weight)
            .clip(RoundedCornerShape(AppLayout.buttonCornerRadius))
            .background(if (primary) Palette.userBubbleFill else Palette.cardFill)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        LucideIcon(icon, size = 16.dp, tint = if (primary) Palette.userBubbleText else Palette.textPrimary)
        Spacer(Modifier.width(6.dp))
        Text(
            label,
            style = AppTypography.secondary,
            color = if (primary) Palette.userBubbleText else Palette.textPrimary,
        )
    }
}
