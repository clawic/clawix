package com.example.clawix.android.composer

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.Haptics
import com.example.clawix.android.theme.Palette
import java.util.UUID

@Composable
fun CameraCaptureScreen(
    onCancel: () -> Unit,
    onCapture: (ComposerAttachment) -> Unit,
    onOpenLibrary: () -> Unit,
) {
    val context = LocalContext.current
    val view = LocalView.current
    var hasPermission by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (!granted) onCancel()
    }
    LaunchedEffect(Unit) {
        if (!hasPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    var lensFacing by remember { mutableStateOf(CameraSelector.LENS_FACING_BACK) }
    var torchOn by remember { mutableStateOf(false) }
    val imageCapture = remember { ImageCapture.Builder().build() }
    var camera by remember { mutableStateOf<Camera?>(null) }
    val executor = remember { ContextCompat.getMainExecutor(context) }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (hasPermission) {
            CapturePreview(
                lensFacing = lensFacing,
                imageCapture = imageCapture,
                onCameraReady = { camera = it },
                torchOn = torchOn,
            )
        }

        Row(
            Modifier
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable {
                        Haptics.tap(view)
                        onCancel()
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.X, size = 18.dp, tint = Color.White)
            }
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(if (torchOn) Color.White else Color.Black.copy(alpha = 0.45f))
                    .clickable {
                        Haptics.tap(view)
                        torchOn = !torchOn
                        runCatching { camera?.cameraControl?.enableTorch(torchOn) }
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(
                    LucideGlyph.Eye,
                    size = 18.dp,
                    tint = if (torchOn) Color.Black else Color.White,
                )
            }
        }

        Row(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(horizontal = 32.dp, vertical = 32.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable {
                        Haptics.tap(view)
                        onOpenLibrary()
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.Image, size = 18.dp, tint = Color.White)
            }

            Box(
                Modifier
                    .size(78.dp)
                    .clip(CircleShape)
                    .background(Color.White)
                    .border(width = 4.dp, color = Color.Black.copy(alpha = 0.18f), shape = CircleShape)
                    .clickable {
                        Haptics.send(view)
                        imageCapture.takePicture(
                            executor,
                            object : ImageCapture.OnImageCapturedCallback() {
                                override fun onCaptureSuccess(image: ImageProxy) {
                                    val bytes = image.toJpegBytes()
                                    image.close()
                                    onCapture(
                                        ComposerAttachment(
                                            kind = WireAttachmentKind.image,
                                            mimeType = "image/jpeg",
                                                filename = "photo-${UUID.randomUUID().toString().take(8)}.jpg",
                                                bytes = bytes,
                                            )
                                    )
                                }

                                override fun onError(exception: ImageCaptureException) {}
                            }
                        )
                    },
            )

            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.45f))
                    .clickable {
                        Haptics.tap(view)
                        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
                            CameraSelector.LENS_FACING_FRONT
                        } else {
                            CameraSelector.LENS_FACING_BACK
                        }
                    },
                contentAlignment = Alignment.Center,
            ) {
                LucideIcon(LucideGlyph.Refresh, size = 18.dp, tint = Color.White)
            }
        }
    }
}

@Composable
private fun CapturePreview(
    lensFacing: Int,
    imageCapture: ImageCapture,
    onCameraReady: (Camera) -> Unit,
    torchOn: Boolean,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    AndroidView(
        factory = { ctx ->
            PreviewView(ctx).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
        },
        update = { previewView ->
            val providerFuture = ProcessCameraProvider.getInstance(context)
            providerFuture.addListener({
                runCatching {
                    val provider = providerFuture.get()
                    val preview = Preview.Builder().build().also {
                        it.setSurfaceProvider(previewView.surfaceProvider)
                    }
                    val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
                    provider.unbindAll()
                    val cam = provider.bindToLifecycle(
                        lifecycleOwner,
                        selector,
                        preview,
                        imageCapture,
                    )
                    onCameraReady(cam)
                    cam.cameraControl.enableTorch(torchOn)
                }
            }, ContextCompat.getMainExecutor(context))
        },
        modifier = Modifier.fillMaxSize(),
    )
}

private fun ImageProxy.toJpegBytes(): ByteArray {
    val buffer = planes[0].buffer
    val bytes = ByteArray(buffer.remaining())
    buffer.get(bytes)
    return bytes
}
