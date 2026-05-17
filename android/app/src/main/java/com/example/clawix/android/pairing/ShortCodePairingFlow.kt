package com.example.clawix.android.pairing

import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.Credentials
import com.example.clawix.android.bridge.DiscoveredMac
import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.BridgeCoder
import com.example.clawix.android.core.BridgeFrame
import com.example.clawix.android.core.ClientKind
import com.example.clawix.android.util.BridgeDeviceIdentity
import com.example.clawix.android.util.DeviceName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * Drives the short-code pairing flow: keep a Bonjour browser running so
 * the user sees Macs on the LAN; when they enter a 9-char code and tap
 * pair, open a one-shot WebSocket against the chosen Mac, send `auth`
 * with the code as token, wait for `authOk`, persist credentials, hand
 * back to the caller.
 *
 * Mirrors `ShortCodePairingFlow.swift` on iOS.
 */
class ShortCodePairingFlow(private val container: AppContainer) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _status = MutableStateFlow<String?>(null)
    private val _busy = MutableStateFlow(false)
    val status: StateFlow<String?> = _status.asStateFlow()
    val busy: StateFlow<Boolean> = _busy.asStateFlow()
    val discovered: StateFlow<List<DiscoveredMac>> = container.bonjour.discovered

    private var browseJob: Job? = null

    fun start() {
        if (browseJob != null) return
        browseJob = scope.launch {
            container.bonjour.start().collect { /* container.bonjour.discovered already reflects */ }
        }
    }

    fun stop() {
        browseJob?.cancel()
        browseJob = null
    }

    /**
     * Attempts to authenticate against `mac` using the typed `code`. On
     * success, persists Credentials and returns true. On failure logs the
     * reason in `status` and returns false.
     */
    suspend fun tryPair(mac: DiscoveredMac, code: String): Boolean {
        if (_busy.value) return false
        _busy.value = true
        try {
            _status.value = "Connecting to ${mac.name}..."
            val client = OkHttpClient.Builder()
                .connectTimeout(5, TimeUnit.SECONDS)
                .readTimeout(8, TimeUnit.SECONDS)
                .build()
            val request = Request.Builder()
                .url("ws://${mac.host}:${mac.port}/")
                .build()

            val ok = withTimeoutOrNull(8_000) {
                suspendCancellableCoroutine<Boolean> { cont ->
                    var resumed = false
                    val listener = object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            val auth = BridgeFrame(
                                body = BridgeBody.Auth(
                                    token = code,
                                    deviceName = DeviceName.resolve(container.context),
                                    clientKind = ClientKind.COMPANION,
                                    clientId = BridgeDeviceIdentity.clientId,
                                    installationId = BridgeDeviceIdentity.installationId(container.context),
                                    deviceId = BridgeDeviceIdentity.deviceId(container.context),
                                )
                            )
                            webSocket.send(BridgeCoder.encode(auth))
                        }

                        override fun onMessage(webSocket: WebSocket, text: String) {
                            val frame = runCatching { BridgeCoder.decode(text) }.getOrNull() ?: return
                            when (val body = frame.body) {
                                is BridgeBody.AuthOk -> {
                                    if (!resumed) {
                                        resumed = true
                                        val creds = Credentials(
                                            host = mac.host,
                                            port = mac.port,
                                            token = code,
                                            hostDisplayName = body.hostDisplayName ?: mac.name,
                                            tailscaleHost = null,
                                        )
                                        container.credentialStore.save(creds)
                                        container.bridgeClient.connect(creds)
                                        cont.resume(true)
                                    }
                                    webSocket.close(1000, null)
                                }
                                is BridgeBody.AuthFailed -> {
                                    _status.value = "Pairing failed: ${body.reason}"
                                    if (!resumed) { resumed = true; cont.resume(false) }
                                    webSocket.close(1000, null)
                                }
                                is BridgeBody.VersionMismatch -> {
                                    _status.value = "Update Clawix on your Mac (server v${body.serverVersion})"
                                    if (!resumed) { resumed = true; cont.resume(false) }
                                    webSocket.close(1000, null)
                                }
                                else -> { /* ignore other inbound frames */ }
                            }
                        }

                        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                            _status.value = "Network error: ${t.message ?: t.javaClass.simpleName}"
                            if (!resumed) { resumed = true; cont.resume(false) }
                        }
                    }
                    val ws = client.newWebSocket(request, listener)
                    cont.invokeOnCancellation { ws.cancel() }
                }
            } ?: false
            if (!ok && _status.value == "Connecting to ${mac.name}...") {
                _status.value = "Couldn't reach ${mac.name}. Try again?"
            }
            return ok
        } finally {
            _busy.value = false
        }
    }
}
