package com.example.clawix.android.pairing

import android.annotation.SuppressLint
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.atomic.AtomicBoolean

/**
 * CameraX `ImageAnalysis.Analyzer` that hands frames to ML Kit's QR
 * scanner. The first successful decode triggers `onScanned` and the
 * analyzer disables itself (subsequent frames are dropped) so the
 * navigation transition has no chance of receiving a duplicate.
 */
class QRBarcodeAnalyzer(
    private val onScanned: (String) -> Unit,
) : ImageAnalysis.Analyzer {

    private val didReport = AtomicBoolean(false)
    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build()
    )

    @SuppressLint("UnsafeOptInUsageError")
    override fun analyze(imageProxy: ImageProxy) {
        if (didReport.get()) {
            imageProxy.close(); return
        }
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close(); return
        }
        val img = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        scanner.process(img)
            .addOnSuccessListener { barcodes ->
                val raw = barcodes.firstOrNull { it.rawValue != null }?.rawValue
                if (raw != null && didReport.compareAndSet(false, true)) {
                    onScanned(raw)
                }
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }
}
