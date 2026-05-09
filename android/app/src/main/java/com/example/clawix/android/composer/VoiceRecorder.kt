package com.example.clawix.android.composer

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.util.Log
import com.example.clawix.android.AppContainer
import com.example.clawix.android.util.Base64Util
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.log10
import kotlinx.coroutines.launch

/**
 * Wraps `MediaRecorder` to capture m4a/AAC voice clips that the daemon
 * can transcribe. Mirrors iOS `VoiceRecorder` (which uses
 * AVAudioRecorder + Speech.framework). On Android we rely on the
 * daemon for STT — there is no on-device fallback that's free of
 * Google Play Services.
 */
class VoiceRecorder(private val container: AppContainer) {

    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    fun start(context: Context) {
        val out = File(context.cacheDir, "clawix_voice_${UUID.randomUUID()}.m4a")
        outputFile = out
        val rec = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        rec.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(44_100)
            setAudioChannels(1)
            setAudioEncodingBitRate(64_000)
            setOutputFile(out.absolutePath)
            prepare()
            start()
        }
        recorder = rec
    }

    /** 0..1 normalized amplitude. */
    fun currentAmplitudeNormalized(): Float {
        val rec = recorder ?: return 0f
        return runCatching {
            val raw = rec.maxAmplitude.coerceAtLeast(1)
            // log10 0..32767 -> 0..~4.51; scale to 0..1
            val db = 20 * log10(raw.toDouble())
            ((db - 30).coerceAtLeast(0.0) / 60.0).toFloat().coerceIn(0f, 1f)
        }.getOrDefault(0f)
    }

    /** Stops and returns (bytes, mimeType). Cleans up the file. */
    fun stopAndCollect(): Pair<ByteArray, String>? {
        val rec = recorder ?: return null
        runCatching { rec.stop() }
        runCatching { rec.release() }
        recorder = null
        val out = outputFile ?: return null
        outputFile = null
        return runCatching {
            val bytes = out.readBytes()
            out.delete()
            bytes to "audio/m4a"
        }.getOrNull()
    }

    fun stopAndDiscard() {
        val rec = recorder ?: return
        runCatching { rec.stop() }
        runCatching { rec.release() }
        recorder = null
        outputFile?.delete()
        outputFile = null
    }

    /** Sends the bytes to the daemon for Whisper transcription. */
    fun transcribe(bytes: ByteArray, mimeType: String, onResult: (String?) -> Unit) {
        val requestId = UUID.randomUUID().toString()
        val base64 = Base64Util.encode(bytes)
        val language = Locale.getDefault().language.takeIf { it.isNotBlank() }
        container.bridgeClient.transcribeAudio(requestId, "", base64, mimeType, language)

        // Watch for the result on a coroutine; bail out after 30s.
        container.appScope.launch {
            val deadline = System.currentTimeMillis() + 30_000
            while (System.currentTimeMillis() < deadline) {
                kotlinx.coroutines.delay(150)
                val text = container.bridgeStore.consumeTranscriptionResult(requestId)
                if (text != null) {
                    onResult(text); return@launch
                }
            }
            onResult(null)
        }
    }

    companion object {
        private const val TAG = "ClawixVoice"
    }
}
