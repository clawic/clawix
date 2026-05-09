package com.example.clawix.android.pairing

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.Credentials
import com.example.clawix.android.core.PairingPayload
import com.example.clawix.android.icons.CloseIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette
import java.util.concurrent.Executors
import kotlinx.coroutines.launch

@Composable
fun QRScannerScreen(
    container: AppContainer,
    onScanned: () -> Unit,
    onCancel: () -> Unit,
) {
    val context = LocalContext.current
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
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

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
    ) {
        if (hasPermission) {
            CameraPreview(
                onScanned = { raw ->
                    val payload = PairingPayload.parse(raw) ?: return@CameraPreview
                    container.credentialStore.save(Credentials.fromPairingPayload(payload))
                    container.bridgeClient.connect(container.credentialStore.load() ?: return@CameraPreview)
                    onScanned()
                }
            )
        }

        // Overlay reticle
        Box(
            Modifier
                .fillMaxSize()
                .padding(48.dp),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                Modifier
                    .size(260.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Color.Transparent)
            )
        }

        // Top bar (back + title)
        Box(
            Modifier
                .fillMaxWidth()
                .systemBarsPadding()
                .padding(horizontal = AppLayout.screenHorizontalPadding, vertical = 12.dp)
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(Palette.cardFill)
                    .clickable { onCancel() },
                contentAlignment = Alignment.Center,
            ) {
                CloseIcon(size = 18.dp, tint = Palette.textPrimary)
            }
            Text(
                "Scan QR",
                style = AppTypography.title,
                color = Palette.textPrimary,
                modifier = Modifier.align(Alignment.Center)
            )
        }
    }
}

@Composable
private fun CameraPreview(onScanned: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }

    AndroidView(
        factory = { ctx ->
            val previewView = PreviewView(ctx).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val providerFuture = ProcessCameraProvider.getInstance(ctx)
            providerFuture.addListener({
                val provider = providerFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build().also {
                        it.setAnalyzer(executor, QRBarcodeAnalyzer(onScanned))
                    }
                runCatching {
                    provider.unbindAll()
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis,
                    )
                }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
        modifier = Modifier.fillMaxSize(),
    )
}
