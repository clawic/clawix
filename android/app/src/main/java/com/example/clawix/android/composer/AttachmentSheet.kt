package com.example.clawix.android.composer

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.clawix.android.AppContainer
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

@Composable
fun AttachmentSheet(
    container: AppContainer,
    onDismiss: () -> Unit,
    onPickResult: (ComposerAttachment) -> Unit,
    onOpenCamera: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    val context = LocalContext.current

    val photoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri != null) {
            val att = readImageAttachment(context, uri)
            if (att != null) onPickResult(att)
        }
    }

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
            Text("Attach", style = AppTypography.title, color = Palette.textPrimary)
            Spacer(Modifier.height(12.dp))

            // Recent photos grid (mirror iOS RecentPhotosLoader).
            RecentPhotosRow(onPick = { att ->
                onPickResult(att)
            })
            Spacer(Modifier.height(12.dp))

            ActionRow(LucideGlyph.Camera, "Camera") {
                onOpenCamera()
            }
            ActionRow(LucideGlyph.Images, "All photos") {
                photoPicker.launch(
                    androidx.activity.result.PickVisualMediaRequest(
                        ActivityResultContracts.PickVisualMedia.ImageOnly
                    )
                )
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ActionRow(glyph: LucideGlyph, label: String, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).background(Palette.cardFill), contentAlignment = Alignment.Center) {
            LucideIcon(glyph, size = 18.dp, tint = Palette.textPrimary)
        }
        Spacer(Modifier.width(12.dp))
        Text(label, style = AppTypography.body, color = Palette.textPrimary)
    }
}

private fun readImageAttachment(context: Context, uri: Uri): ComposerAttachment? {
    return runCatching {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: "image/jpeg"
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
        ComposerAttachment(
            kind = WireAttachmentKind.image,
            mimeType = mime,
            filename = uri.lastPathSegment ?: "image",
            bytes = bytes,
        )
    }.getOrNull()
}
