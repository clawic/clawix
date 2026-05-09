package com.example.clawix.android.chatdetail

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.clawix.android.AppContainer
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import com.example.clawix.android.util.Base64Util

/**
 * Full-screen pinch-zoomable viewer. Mirrors iOS `ImageViewerView`.
 * Tap outside to dismiss. The image bytes are pulled from the daemon
 * (same path as inline images) and decoded once.
 */
@Composable
fun ImageViewerDialog(
    container: AppContainer,
    path: String,
    onDismiss: () -> Unit,
) {
    val state by container.bridgeStore.state.collectAsState()
    val cached = state.generatedImages[path]

    LaunchedEffect(path) {
        if (cached == null) container.bridgeClient.requestGeneratedImage(path)
    }

    var bitmap by remember(cached?.dataBase64) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(cached?.dataBase64) {
        val data = cached?.dataBase64 ?: return@LaunchedEffect
        runCatching {
            val bytes = Base64Util.decode(data)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size).asImageBitmap()
        }.onSuccess { bitmap = it }
    }

    var scale by remember { mutableStateOf(1f) }
    var offsetX by remember { mutableStateOf(0f) }
    var offsetY by remember { mutableStateOf(0f) }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = true),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black)
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        scale = (scale * zoom).coerceIn(1f, 6f)
                        offsetX += pan.x
                        offsetY += pan.y
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            when {
                bitmap != null -> Image(
                    bitmap = bitmap!!,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer(
                            scaleX = scale,
                            scaleY = scale,
                            translationX = offsetX,
                            translationY = offsetY,
                        ),
                )
                cached?.errorMessage != null -> Text(cached.errorMessage, style = AppTypography.body, color = Palette.unreadDot)
                else -> Text("Loading…", style = AppTypography.body, color = Palette.textTertiary)
            }
        }
    }
}
