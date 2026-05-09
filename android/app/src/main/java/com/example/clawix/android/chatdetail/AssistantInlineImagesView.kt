package com.example.clawix.android.chatdetail

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import android.graphics.BitmapFactory
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.GeneratedImageState
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import com.example.clawix.android.util.Base64Util

/**
 * Inline images extracted from the assistant message text. Mirrors iOS
 * `AssistantInlineImagesView`. Paths come from
 * `WireWorkItem.generatedImagePath` or markdown-detected `![](...)`.
 * The first time a path is rendered we ask the daemon for the bytes
 * via `requestGeneratedImage`.
 */
@Composable
fun AssistantInlineImagesView(
    container: AppContainer,
    paths: List<String>,
    modifier: Modifier = Modifier,
) {
    if (paths.isEmpty()) return
    Row(
        modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
    ) {
        for ((idx, path) in paths.withIndex()) {
            if (idx > 0) Spacer(Modifier.width(8.dp))
            InlineImage(container = container, path = path)
        }
    }
}

@Composable
private fun InlineImage(container: AppContainer, path: String) {
    var bitmap by remember(path) { mutableStateOf<ImageBitmap?>(null) }
    var error by remember(path) { mutableStateOf<String?>(null) }
    val state by container.bridgeStore.state.collectAsState()

    LaunchedEffect(path) {
        if (state.generatedImages[path] == null) {
            container.bridgeClient.requestGeneratedImage(path)
        }
    }

    val cached: GeneratedImageState? = state.generatedImages[path]
    LaunchedEffect(cached) {
        val data = cached?.dataBase64 ?: return@LaunchedEffect
        runCatching {
            val bytes = Base64Util.decode(data)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size).asImageBitmap()
        }.onSuccess { bitmap = it }
            .onFailure { error = it.message }
    }
    if (cached?.errorMessage != null) error = cached.errorMessage

    Box(
        Modifier
            .size(160.dp)
            .clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            .background(Palette.cardFill),
        contentAlignment = Alignment.Center,
    ) {
        when {
            bitmap != null -> Image(
                bitmap = bitmap!!,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(160.dp).clip(RoundedCornerShape(AppLayout.cardCornerRadius))
            )
            error != null -> Text(error!!, style = AppTypography.caption, color = Palette.textTertiary, modifier = Modifier.padding(8.dp))
            else -> Text("Loading…", style = AppTypography.caption, color = Palette.textTertiary)
        }
    }
}

