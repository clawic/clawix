package com.example.clawix.android.bridge

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * One pending update. Daemon sends `messageStreaming` frames carrying
 * **cumulative** content (not deltas), so storing the latest one per
 * messageId is enough.
 */
data class PendingStreamUpdate(
    val chatId: String,
    val messageId: String,
    val content: String,
    val reasoningText: String,
    val finished: Boolean,
)

/**
 * Coalesces high-frequency `messageStreaming` frames into batches that
 * fire at most every `coalesceMs`. Last-wins per messageId. A frame
 * with `finished = true` triggers an immediate flush so the user sees
 * the last token without a 80ms tail.
 *
 * Mirrors the iOS `StreamCoalescer` 80ms window. The result of a flush
 * is one call to `flush(map)`, where `map[messageId] = update` holds
 * the latest state of every message that received a chunk during the
 * window.
 */
class StreamCoalescer(
    private val scope: CoroutineScope,
    private val coalesceMs: Long = 80L,
    private val flush: (Map<String, PendingStreamUpdate>) -> Unit,
) {
    private val pending = mutableMapOf<String, PendingStreamUpdate>()
    private val mutex = Mutex()
    private var flushJob: Job? = null

    suspend fun enqueue(update: PendingStreamUpdate) {
        var doFlushNow = false
        mutex.withLock {
            pending[update.messageId] = update
            if (update.finished) {
                doFlushNow = true
            }
        }
        if (doFlushNow) {
            flushNow()
        } else {
            armFlush()
        }
    }

    suspend fun flushNow() {
        val snapshot: Map<String, PendingStreamUpdate>
        mutex.withLock {
            snapshot = pending.toMap()
            pending.clear()
            flushJob?.cancel()
            flushJob = null
        }
        if (snapshot.isNotEmpty()) flush(snapshot)
    }

    private fun armFlush() {
        if (flushJob?.isActive == true) return
        flushJob = scope.launch {
            delay(coalesceMs)
            flushNow()
        }
    }
}
