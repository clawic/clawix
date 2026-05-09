package com.example.clawix.android.composer

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import com.example.clawix.android.AppContainer
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.icons.MicIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import kotlinx.coroutines.delay

private enum class PrimaryGlyph { Arrow, Waveform, Stop }

@Composable
fun ComposerView(
    container: AppContainer,
    isStreaming: Boolean,
    onSend: (String, List<com.example.clawix.android.core.WireAttachment>) -> Unit,
    onStop: () -> Unit,
) {
    var text by remember { mutableStateOf("") }
    val attachments = remember { mutableStateListOf<ComposerAttachment>() }
    val focusRequester = remember { FocusRequester() }
    val view = LocalView.current
    var showAttachmentSheet by remember { mutableStateOf(false) }
    var showCamera by remember { mutableStateOf(false) }
    var voiceRecording by remember { mutableStateOf(false) }
    val recorderHook = remember { VoiceRecorder(container) }

    // 350ms autofocus delay matches iOS animation completion timing.
    LaunchedEffect(Unit) {
        delay(350)
        runCatching { focusRequester.requestFocus() }
    }

    val primaryGlyph: PrimaryGlyph = when {
        isStreaming -> PrimaryGlyph.Stop
        text.isBlank() && attachments.isEmpty() -> PrimaryGlyph.Waveform
        else -> PrimaryGlyph.Arrow
    }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.composerCornerRadius))
            .background(Palette.cardFill)
    ) {
        // Attachment chips row
        if (attachments.isNotEmpty()) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                attachments.forEach { att ->
                    AttachmentChip(att = att, onRemove = { attachments.remove(att) })
                }
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            // Attach button
            Box(
                Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .clickable {
                        Haptics.tap(view)
                        showAttachmentSheet = true
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.Plus, size = 22.dp, tint = Palette.textPrimary)
            }

            Spacer(Modifier.width(6.dp))

            BasicTextField(
                value = text,
                onValueChange = { text = it },
                textStyle = LocalTextStyle.current.copy(color = Palette.textPrimary),
                cursorBrush = SolidColor(Palette.textPrimary),
                modifier = Modifier
                    .weight(1f)
                    .focusRequester(focusRequester)
                    .padding(vertical = 10.dp)
                    .heightIn(min = 24.dp, max = 198.dp),
                decorationBox = { inner ->
                    if (text.isEmpty()) {
                        Text("Message Codex…", style = AppTypography.body, color = Palette.textTertiary)
                    }
                    inner()
                },
            )

            Spacer(Modifier.width(6.dp))

            // Primary action button morphs across 3 states
            Box(
                Modifier
                    .size(42.dp)
                    .clip(CircleShape)
                    .background(
                        if (primaryGlyph == PrimaryGlyph.Waveform) Palette.cardFill
                        else Palette.userBubbleFill
                    )
                    .clickable {
                        when (primaryGlyph) {
                            PrimaryGlyph.Arrow -> {
                                Haptics.send(view)
                                onSend(text, attachments.map { it.toWire() })
                                text = ""
                                attachments.clear()
                            }
                            PrimaryGlyph.Waveform -> {
                                Haptics.tap(view)
                                voiceRecording = true
                            }
                            PrimaryGlyph.Stop -> {
                                Haptics.tap(view)
                                onStop()
                            }
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                AnimatedContent(
                    targetState = primaryGlyph,
                    transitionSpec = {
                        (scaleIn(initialScale = 0.6f) + fadeIn()) togetherWith
                            (scaleOut(targetScale = 0.6f) + fadeOut())
                    },
                    label = "primary-glyph",
                ) { glyph ->
                    when (glyph) {
                        PrimaryGlyph.Arrow -> LucideIcon(LucideGlyph.ArrowUp, size = 20.dp, tint = Palette.userBubbleText)
                        PrimaryGlyph.Waveform -> MicIcon(size = 20.dp, tint = Palette.textPrimary)
                        PrimaryGlyph.Stop -> LucideIcon(LucideGlyph.StopCircle, size = 20.dp, tint = Palette.userBubbleText)
                    }
                }
            }
        }
    }

    if (showAttachmentSheet) {
        AttachmentSheet(
            container = container,
            onDismiss = { showAttachmentSheet = false },
            onPickResult = { att ->
                attachments.add(att)
                showAttachmentSheet = false
            },
            onOpenCamera = {
                showAttachmentSheet = false
                showCamera = true
            },
        )
    }
    if (showCamera) {
        CameraCaptureScreen(
            onCancel = { showCamera = false },
            onCapture = { att ->
                attachments.add(att)
                showCamera = false
            },
            onOpenLibrary = {
                showCamera = false
                showAttachmentSheet = true
            },
        )
    }
    if (voiceRecording) {
        RecordingOverlay(
            container = container,
            onComplete = { result ->
                voiceRecording = false
                if (result != null) {
                    when (result) {
                        is VoiceRecordingResult.Transcribed -> {
                            text = if (text.isBlank()) result.text else text + " " + result.text
                        }
                        is VoiceRecordingResult.Audio -> {
                            attachments.add(result.attachment)
                        }
                    }
                }
            }
        )
    }
}

@Composable
private fun AttachmentChip(att: ComposerAttachment, onRemove: () -> Unit) {
    Row(
        Modifier
            .clip(RoundedCornerShape(AppLayout.chipCornerRadius))
            .background(Palette.cardHover)
            .padding(start = 8.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (att.kind) {
            com.example.clawix.android.core.WireAttachmentKind.image -> LucideIcon(LucideGlyph.Image, size = 14.dp, tint = Palette.textPrimary)
            com.example.clawix.android.core.WireAttachmentKind.audio -> LucideIcon(LucideGlyph.AudioWaveform, size = 14.dp, tint = Palette.textPrimary)
        }
        Spacer(Modifier.width(6.dp))
        Text(
            att.filename?.take(18) ?: when (att.kind) {
                com.example.clawix.android.core.WireAttachmentKind.image -> "Image"
                com.example.clawix.android.core.WireAttachmentKind.audio -> "Audio"
            },
            style = AppTypography.caption,
            color = Palette.textPrimary,
        )
        Spacer(Modifier.width(6.dp))
        Box(
            Modifier
                .size(16.dp)
                .clip(CircleShape)
                .clickable { onRemove() },
            contentAlignment = Alignment.Center,
        ) {
            LucideIcon(LucideGlyph.X, size = 12.dp, tint = Palette.textSecondary)
        }
    }
}
