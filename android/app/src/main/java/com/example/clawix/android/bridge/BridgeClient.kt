package com.example.clawix.android.bridge

import android.util.Log
import com.example.clawix.android.core.BRIDGE_INITIAL_PAGE_LIMIT
import com.example.clawix.android.core.BRIDGE_OLDER_PAGE_LIMIT
import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.BridgeCoder
import com.example.clawix.android.core.BridgeFrame
import com.example.clawix.android.core.BridgeRuntimeState
import com.example.clawix.android.core.ClientKind
import com.example.clawix.android.core.WireAttachment
import com.example.clawix.android.util.DeviceName
import com.example.clawix.android.util.TailscaleHostCheck
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.consumeEach
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.math.min

private const val TAG = "ClawixBridgeClient"

private data class Candidate(val host: String, val port: Int, val route: ConnectionRoute)

private sealed class RaceResult {
    data class Win(
        val socket: WebSocket,
        val route: ConnectionRoute,
        val macName: String?,
        val candidate: Candidate,
        val listener: WinnerListener,
    ) : RaceResult()
    data class Lost(val reason: String) : RaceResult()
}

/**
 * The crown jewel: connects to the daemon via the fastest path, keeps
 * the connection alive with pings, reconnects with exponential backoff.
 *
 * Mirrors iOS `BridgeClient.swift`. Concurrency is built on coroutines:
 *   - `connect` lazily kicks off `connectionLoop` (one job for the
 *     life of the credentials)
 *   - inside the loop, a single iteration: race candidates -> promote
 *     winner -> read frames + ping -> on disconnect, backoff and loop
 *   - `suspendConnection` cancels the loop without clearing creds
 *   - `disconnect` clears creds and cancels everything
 */
class BridgeClient(
    private val scope: CoroutineScope,
    private val store: BridgeStore,
    private val bonjour: BonjourDiscovery,
    private val credentialStore: CredentialStore,
    private val appContext: android.content.Context,
) {
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS) // we ping ourselves
        .pingInterval(0, TimeUnit.MILLISECONDS)
        .build()

    private val mutex = Mutex()
    private var loopJob: Job? = null
    private var winner: WebSocket? = null
    private var coalescer: StreamCoalescer? = null

    init { store.hydrateFromCache() }

    fun connect(creds: Credentials) {
        scope.launch {
            mutex.withLock {
                if (loopJob?.isActive == true) return@withLock
                loopJob = scope.launch { connectionLoop(creds) }
            }
        }
    }

    fun suspendConnection() {
        scope.launch {
            mutex.withLock {
                loopJob?.cancel()
                loopJob = null
                winner?.close(1000, "background")
                winner = null
                store.setConnection(ConnectionState.Idle)
            }
        }
    }

    fun disconnect() {
        scope.launch {
            mutex.withLock {
                loopJob?.cancel()
                loopJob = null
                winner?.close(1000, "disconnect")
                winner = null
                store.setConnection(ConnectionState.Idle)
            }
        }
    }

    // --- Public command surface -----------------------------------------------

    fun send(body: BridgeBody) {
        val ws = winner ?: return
        ws.send(BridgeCoder.encode(BridgeFrame(body = body)))
    }

    fun openChat(chatId: String) {
        store.setOpenChat(chatId)
        send(BridgeBody.OpenSession(chatId, BRIDGE_INITIAL_PAGE_LIMIT))
    }

    fun closeChat() {
        store.setOpenChat(null)
    }

    fun loadOlderMessages(chatId: String, beforeMessageId: String) {
        send(BridgeBody.LoadOlderMessages(chatId, beforeMessageId, BRIDGE_OLDER_PAGE_LIMIT))
    }

    fun sendPrompt(chatId: String, text: String, attachments: List<WireAttachment> = emptyList()) {
        send(BridgeBody.SendPrompt(chatId, text, attachments))
    }

    fun newChat(chatId: String, text: String, attachments: List<WireAttachment> = emptyList()) {
        store.registerPendingNewChat(chatId)
        send(BridgeBody.NewSession(chatId, text, attachments))
    }

    fun interruptTurn(chatId: String) {
        send(BridgeBody.InterruptTurn(chatId))
    }

    fun archiveChat(chatId: String) {
        store.applyOptimisticArchive(chatId, archived = true)
        send(BridgeBody.ArchiveSession(chatId))
    }

    fun unarchiveChat(chatId: String) {
        store.applyOptimisticArchive(chatId, archived = false)
        send(BridgeBody.UnarchiveSession(chatId))
    }

    fun pinChat(chatId: String) {
        store.applyOptimisticPin(chatId, pinned = true)
        send(BridgeBody.PinSession(chatId))
    }

    fun unpinChat(chatId: String) {
        store.applyOptimisticPin(chatId, pinned = false)
        send(BridgeBody.UnpinSession(chatId))
    }

    fun renameChat(chatId: String, title: String) {
        store.applyOptimisticRename(chatId, title)
        send(BridgeBody.RenameSession(chatId, title))
    }

    fun listProjects() {
        send(BridgeBody.ListProjects)
    }

    fun readFile(path: String) {
        send(BridgeBody.ReadFile(path))
    }

    fun requestGeneratedImage(path: String) {
        send(BridgeBody.RequestGeneratedImage(path))
    }

    fun requestAudio(audioId: String) {
        send(BridgeBody.RequestAudio(audioId))
    }

    fun transcribeAudio(requestId: String, chatId: String, audioBase64: String, mimeType: String, language: String?) {
        store.registerPendingTranscription(requestId, chatId)
        send(BridgeBody.TranscribeAudio(requestId, audioBase64, mimeType, language))
    }

    // --- Connection lifecycle -------------------------------------------------

    private suspend fun connectionLoop(creds: Credentials) {
        var attempt = 0
        while (scope.isActive) {
            store.setConnection(if (attempt == 0) ConnectionState.Connecting else ConnectionState.Reconnecting(attempt))

            val winnerResult = raceCandidates(creds)
            if (winnerResult == null) {
                attempt += 1
                val backoff = backoffFor(attempt)
                Log.d(TAG, "race failed, retry in ${backoff}ms (attempt $attempt)")
                delay(backoff)
                continue
            }
            attempt = 0
            mutex.withLock {
                winner = winnerResult.socket
            }
            store.setConnection(ConnectionState.Connected(winnerResult.macName, winnerResult.route))
            replayPendingNewChats()

            // Bind a stream coalescer for this session
            val coa = StreamCoalescer(scope) { batch -> store.applyStreamingBatch(batch) }
            coalescer = coa
            winnerResult.listener.coalescer = coa
            winnerResult.listener.store = store

            // Keepalive + idle watchdog
            val keepaliveJob = scope.launch {
                while (scope.isActive) {
                    delay(15_000)
                    val ws = winner ?: break
                    val sent = ws.send("{\"schemaVersion\":5,\"type\":\"_ping\"}")
                    if (!sent) break
                    val sinceLast = System.currentTimeMillis() - winnerResult.listener.lastInboundAt.get()
                    if (sinceLast > 30_000) {
                        Log.d(TAG, "keepalive: 30s without traffic, closing")
                        ws.close(1011, "idle")
                        break
                    }
                }
            }

            // Wait for socket close
            winnerResult.listener.closed.await()
            keepaliveJob.cancelAndJoin()
            mutex.withLock { winner = null }
            attempt += 1
            store.setConnection(ConnectionState.Reconnecting(attempt))
            delay(backoffFor(attempt))
        }
    }

    private fun backoffFor(attempt: Int): Long {
        if (attempt <= 2) return 500
        val pow = 1L shl (attempt - 2).coerceAtMost(4)
        return min(16_000L, pow * 1_000L)
    }

    /**
     * Multi-path racing. Spins one Job per candidate in parallel; the
     * first to receive `authOk` becomes the winner. Bonjour browsing
     * runs alongside (cold flow) so newly discovered Macs feed late
     * candidates if the static ones are unreachable.
     */
    private suspend fun raceCandidates(creds: Credentials): RaceResult.Win? {
        val winnerChannel = Channel<RaceResult.Win>(Channel.RENDEZVOUS)
        val candidateJobs = mutableListOf<Job>()
        val seenHostKeys = mutableSetOf<String>()

        fun launchCandidate(c: Candidate) {
            val key = "${c.host}:${c.port}:${c.route}"
            if (!seenHostKeys.add(key)) return
            candidateJobs += scope.launch {
                val win = withTimeoutOrNull(5_000) { tryHandshake(creds, c) }
                if (win != null) winnerChannel.trySend(win)
            }
        }

        // Static candidates: LAN host from QR, Tailscale fallback
        launchCandidate(Candidate(creds.host, creds.port, ConnectionRoute.Lan))
        creds.tailscaleHost?.let {
            if (it != creds.host) launchCandidate(Candidate(it, creds.port, ConnectionRoute.Tailscale))
        }
        if (TailscaleHostCheck.isTailscale(creds.host)) {
            // pure-tailscale credentials: nothing extra
        }

        // Bonjour candidates: feed in as they appear
        val bonjourJob = scope.launch {
            bonjour.start().collect { macs ->
                for (mac in macs) launchCandidate(Candidate(mac.host, mac.port, ConnectionRoute.Bonjour))
            }
        }

        val winner = withTimeoutOrNull(15_000) { winnerChannel.receive() }
        // Cancel losers
        candidateJobs.forEach { it.cancel() }
        bonjourJob.cancel()
        winnerChannel.close()
        return winner
    }

    /**
     * Open a WebSocket against `c.host:c.port`, send `auth`, wait for
     * `authOk`. Returns the win on success, null on timeout/failure.
     */
    private suspend fun tryHandshake(creds: Credentials, c: Candidate): RaceResult.Win? =
        suspendCancellableCoroutine { cont ->
            val request = Request.Builder().url("ws://${c.host}:${c.port}/").build()
            val listener = WinnerListener()
            val ws = http.newWebSocket(request, listener)
            listener.attach(ws) { macName ->
                if (cont.isActive) {
                    cont.resume(RaceResult.Win(ws, c.route, macName, c, listener))
                }
            }
            listener.onAuthFailed = {
                ws.close(1000, "auth failed")
                if (cont.isActive) cont.resume(null)
            }
            listener.onTransportFailure = {
                if (cont.isActive) cont.resume(null)
            }
            // Auth as soon as the socket opens
            listener.onOpen = {
                val auth = BridgeFrame(
                    body = BridgeBody.Auth(
                        token = creds.token,
                        deviceName = DeviceName.resolve(appContext),
                        clientKind = ClientKind.ios,
                    )
                )
                ws.send(BridgeCoder.encode(auth))
            }
            cont.invokeOnCancellation {
                runCatching { ws.cancel() }
            }
        }

    private fun replayPendingNewChats() {
        // The store keeps the original NewChat frames? In our minimal
        // implementation we mark the chat ids; the daemon replays the
        // turn for any chat id we have in `pendingNewChats` because the
        // NewChat frame was already sent before the disconnect. Nothing
        // extra to do here for now.
    }
}

/**
 * Long-lived per-connection listener. Bridges OkHttp callbacks into our
 * suspend functions and routes inbound frames to BridgeStore.
 */
class WinnerListener : WebSocketListener() {

    private val streamScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val closed = CompletableDeferred<Unit>()
    val lastInboundAt = AtomicLong(System.currentTimeMillis())

    var onOpen: () -> Unit = {}
    var onAuthFailed: () -> Unit = {}
    var onTransportFailure: () -> Unit = {}

    var coalescer: StreamCoalescer? = null
    var store: BridgeStore? = null

    private var promotedAuthOk: ((macName: String?) -> Unit)? = null
    private var attachedSocket: WebSocket? = null

    fun attach(ws: WebSocket, onAuthOk: (String?) -> Unit) {
        this.attachedSocket = ws
        this.promotedAuthOk = onAuthOk
    }

    override fun onOpen(webSocket: WebSocket, response: Response) {
        onOpen.invoke()
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
        lastInboundAt.set(System.currentTimeMillis())
        val frame = runCatching { BridgeCoder.decode(text) }.getOrNull() ?: return
        when (val body = frame.body) {
            is BridgeBody.AuthOk -> {
                promotedAuthOk?.invoke(body.macName)
                promotedAuthOk = null
            }
            is BridgeBody.AuthFailed -> {
                onAuthFailed.invoke()
            }
            is BridgeBody.VersionMismatch -> {
                store?.setConnection(ConnectionState.VersionMismatch(body.serverVersion))
                webSocket.close(1000, "version mismatch")
            }
            is BridgeBody.SessionsSnapshot -> store?.applyChatsSnapshot(body.chats)
            is BridgeBody.ChatUpdated -> store?.applyChatUpdated(body.chat)
            is BridgeBody.MessagesSnapshot -> store?.applyMessagesSnapshot(body.chatId, body.messages, body.hasMore)
            is BridgeBody.MessagesPage -> store?.applyMessagesPage(body.chatId, body.messages, body.hasMore)
            is BridgeBody.MessageAppended -> store?.applyMessageAppended(body.chatId, body.message)
            is BridgeBody.MessageStreaming -> {
                val coa = coalescer ?: return
                streamScope.launch {
                    coa.enqueue(
                        PendingStreamUpdate(
                            chatId = body.chatId,
                            messageId = body.messageId,
                            content = body.content,
                            reasoningText = body.reasoningText,
                            finished = body.finished,
                        )
                    )
                }
            }
            is BridgeBody.ProjectsSnapshot -> store?.applyProjects(body.projects)
            is BridgeBody.FileSnapshot -> store?.applyFileSnapshot(
                FileSnapshotState(body.path, body.content, body.isMarkdown, body.error)
            )
            is BridgeBody.GeneratedImageSnapshot -> store?.applyGeneratedImage(
                GeneratedImageState(body.path, body.dataBase64, body.mimeType, body.errorMessage)
            )
            is BridgeBody.TranscriptionResult -> {
                store?.applyTranscriptionResult(body.requestId, body.text)
            }
            is BridgeBody.AudioSnapshot -> {
                // UserAudioBubble polls store for cached audio; for now just log.
            }
            is BridgeBody.BridgeStateFrame -> {
                store?.setRuntime(BridgeRuntimeState.fromWire(body.state, body.message))
            }
            else -> Unit
        }
    }

    override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
        webSocket.close(1000, null)
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        if (!closed.isCompleted) closed.complete(Unit)
    }

    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        Log.d(TAG, "ws failure: ${t.message}")
        onTransportFailure.invoke()
        if (!closed.isCompleted) closed.complete(Unit)
        streamScope.cancel()
    }
}
