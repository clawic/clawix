package com.example.clawix.android.composer

import android.content.Context
import android.content.Intent
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import com.example.clawix.android.AppContainer
import com.example.clawix.android.util.Base64Util
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlin.math.log10
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Wraps `MediaRecorder` to capture m4a/AAC voice clips that the daemon
 * can transcribe via Whisper. Mirrors iOS `VoiceRecorder` (which uses
 * AVAudioRecorder + Speech.framework).
 *
 * Also runs a parallel `SpeechRecognizer` for on-device live
 * transcription, mirroring iOS `SFSpeechRecognizer` fallback. The
 * partial-results flow drives a live caption in `RecordingOverlay` and
 * acts as a fast path when the daemon's Whisper round-trip is slow or
 * unavailable. If Android's mic-source contention prevents both from
 * running at once, the recognizer silently no-ops and the daemon path
 * is the source of truth.
 */
class VoiceRecorder(private val container: AppContainer) {

    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null
    private var recognizer: SpeechRecognizer? = null

    private val _partial = MutableStateFlow("")
    val partialTranscript: StateFlow<String> = _partial.asStateFlow()
    private var finalTranscript: String = ""
    private var recognizerAvailable: Boolean = false

    fun start(context: Context) {
        // 1. MediaRecorder for the audio file (used by "send as audio" and
        //    by the daemon-side Whisper fallback).
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

        // 2. Parallel on-device SpeechRecognizer for live captioning.
        //    Best-effort: if mic contention or unavailable on this device,
        //    we silently drop to daemon-only path.
        runCatching {
            if (!SpeechRecognizer.isRecognitionAvailable(context)) return@runCatching
            val sr = SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = sr
            recognizerAvailable = true
            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) {
                    Log.d(TAG, "speech recognizer error=$error")
                    recognizerAvailable = false
                }

                override fun onResults(results: Bundle?) {
                    val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = list?.firstOrNull().orEmpty()
                    if (text.isNotBlank()) {
                        finalTranscript = text
                        _partial.value = text
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val list = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = list?.firstOrNull().orEmpty()
                    if (text.isNotBlank()) _partial.value = text
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                }
            }
            sr.startListening(intent)
        }.onFailure {
            Log.d(TAG, "speech recognizer init failed: ${it.message}")
            recognizerAvailable = false
        }
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
        stopRecognizer()
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
        stopRecognizer()
        val rec = recorder ?: return
        runCatching { rec.stop() }
        runCatching { rec.release() }
        recorder = null
        outputFile?.delete()
        outputFile = null
    }

    private fun stopRecognizer() {
        runCatching { recognizer?.stopListening() }
        runCatching { recognizer?.destroy() }
        recognizer = null
    }

    /**
     * Snapshot of the on-device transcript at this moment. Used as a
     * fast-path when the user taps "Transcribe" so the composer sees
     * text immediately without waiting for the daemon round-trip.
     */
    fun snapshotOnDeviceTranscript(): String =
        finalTranscript.ifBlank { _partial.value }

    /**
     * Sends the bytes to the daemon for Whisper transcription. If the
     * on-device recognizer already produced text, prefer it but still
     * fire the daemon request as a quality upgrade (Whisper is usually
     * better) — the latest result wins as long as it lands within the
     * 30s deadline. If the daemon never replies, the on-device text is
     * the final answer.
     */
    fun transcribe(bytes: ByteArray, mimeType: String, onResult: (String?) -> Unit) {
        val onDevice = snapshotOnDeviceTranscript().trim()
        val requestId = UUID.randomUUID().toString()
        val base64 = Base64Util.encode(bytes)
        val language = Locale.getDefault().language.takeIf { it.isNotBlank() }
        container.bridgeClient.transcribeAudio(requestId, "", base64, mimeType, language)

        // Watch for the result on a coroutine; bail out after 30s.
        // If the daemon never lands, fall back to on-device text.
        container.appScope.launch {
            val deadline = System.currentTimeMillis() + 30_000
            while (System.currentTimeMillis() < deadline) {
                kotlinx.coroutines.delay(150)
                val text = container.bridgeStore.consumeTranscriptionResult(requestId)
                if (text != null && text.isNotBlank()) {
                    onResult(text); return@launch
                }
            }
            onResult(onDevice.ifBlank { null })
        }
    }

    companion object {
        private const val TAG = "ClawixVoice"
    }
}
