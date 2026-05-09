package com.example.clawix.android.composer

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import coil.compose.AsyncImage
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Horizontal grid of the user's most recent photos, mirroring iOS
 * `RecentPhotosLoader`. Reads `MediaStore.Images.Media` via
 * `ContentResolver`, ordered by `DATE_ADDED DESC`, capped at 30.
 *
 * Permissions: API 33+ uses `READ_MEDIA_IMAGES`; lower uses
 * `READ_EXTERNAL_STORAGE`. Permission gating renders an inline CTA
 * instead of the grid until granted.
 */
@Composable
fun RecentPhotosRow(
    onPick: (ComposerAttachment) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val perm = recentPhotosPermission()
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
        )
    }
    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasPermission = granted }

    var uris by remember { mutableStateOf<List<Uri>>(emptyList()) }

    LaunchedEffect(hasPermission) {
        if (hasPermission) {
            uris = withContext(Dispatchers.IO) { queryRecentImages(context) }
        }
    }

    if (!hasPermission) {
        Box(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 6.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Palette.cardFill)
                .clickable { launcher.launch(perm) }
                .padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            Text(
                "Tap to enable Recent Photos",
                style = AppTypography.body,
                color = Palette.textSecondary,
            )
        }
        return
    }
    if (uris.isEmpty()) return

    LazyRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
    ) {
        items(uris, key = { it.toString() }) { uri ->
            Box(
                Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(Palette.surface)
                    .clickable {
                        scope.launch {
                            val att = withContext(Dispatchers.IO) { loadAttachment(context, uri) }
                            if (att != null) onPick(att)
                        }
                    },
            ) {
                AsyncImage(
                    model = uri,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.size(96.dp),
                )
            }
        }
    }
}

private fun recentPhotosPermission(): String =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Manifest.permission.READ_MEDIA_IMAGES
    } else {
        Manifest.permission.READ_EXTERNAL_STORAGE
    }

private fun queryRecentImages(context: Context, limit: Int = 30): List<Uri> {
    val out = mutableListOf<Uri>()
    val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
    } else {
        @Suppress("DEPRECATION")
        MediaStore.Images.Media.EXTERNAL_CONTENT_URI
    }
    val projection = arrayOf(MediaStore.Images.Media._ID)
    val sortOrder = "${MediaStore.Images.Media.DATE_ADDED} DESC"
    runCatching {
        context.contentResolver.query(collection, projection, null, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
            while (cursor.moveToNext() && out.size < limit) {
                val id = cursor.getLong(idCol)
                out.add(ContentUris.withAppendedId(collection, id))
            }
        }
    }
    return out
}

private fun loadAttachment(context: Context, uri: Uri): ComposerAttachment? {
    return runCatching {
        val resolver = context.contentResolver
        val mime = resolver.getType(uri) ?: "image/jpeg"
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
        ComposerAttachment(
            kind = WireAttachmentKind.image,
            mimeType = mime,
            filename = uri.lastPathSegment ?: "photo",
            bytes = bytes,
        )
    }.getOrNull()
}
