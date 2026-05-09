package com.example.clawix.android.bridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import java.net.InetAddress

/**
 * Discovered Mac on the LAN. `host` is an IPv4 string (the bridge daemon
 * binds 0.0.0.0:port without TLS so we can connect directly).
 */
data class DiscoveredMac(
    val name: String,
    val host: String,
    val port: Int,
)

/**
 * Wraps `NsdManager` to discover `_clawix-bridge._tcp` advertisements on
 * the LAN. Callers acquire a `WifiManager.MulticastLock` for the
 * lifetime of the discovery (Android filters multicast by default to
 * save battery). On API 34+ migrate to `registerServiceInfoCallback`;
 * fall back to legacy `discoverServices`+`resolveService` for
 * minSdk 29 devices.
 *
 * Mirrors iOS `BonjourBrowser` (NSNetServiceBrowser based) but exposes
 * a Flow so coroutines can collect discovered Macs and cancel naturally
 * when the consumer scope is cancelled.
 */
class BonjourDiscovery(context: Context) {
    private val appCtx = context.applicationContext
    private val nsd = appCtx.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifi = appCtx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val multicastLock: WifiManager.MulticastLock =
        wifi.createMulticastLock(MULTICAST_TAG).apply { setReferenceCounted(true) }

    private val _state = MutableStateFlow<List<DiscoveredMac>>(emptyList())
    val discovered: StateFlow<List<DiscoveredMac>> = _state.asStateFlow()

    /**
     * Cold flow: each subscriber arms its own discovery + multicast lock
     * lifecycle. Emits the cumulative list of resolved Macs.
     */
    fun start(): Flow<List<DiscoveredMac>> = callbackFlow {
        val seen = mutableMapOf<String, DiscoveredMac>()
        var locked = false
        try {
            multicastLock.acquire()
            locked = true
        } catch (t: Throwable) {
            Log.w(TAG, "multicast lock failed", t)
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.d(TAG, "discovery started for $serviceType")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.d(TAG, "discovery stopped for $serviceType")
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "discovery start failed: $errorCode")
                close()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "discovery stop failed: $errorCode")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                Log.d(TAG, "found: ${service.serviceName}")
                resolve(service) { resolved ->
                    if (resolved != null) {
                        seen[resolved.name] = resolved
                        _state.value = seen.values.toList()
                        trySend(seen.values.toList())
                    }
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                Log.d(TAG, "lost: ${service.serviceName}")
                seen.remove(service.serviceName)
                _state.value = seen.values.toList()
                trySend(seen.values.toList())
            }
        }

        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)

        awaitClose {
            runCatching { nsd.stopServiceDiscovery(listener) }
            if (locked) runCatching { multicastLock.release() }
        }
    }

    /**
     * Resolves the given service to host+port. Uses the new callback API
     * on API 34+, the legacy resolveService on older versions.
     */
    @Suppress("DEPRECATION")
    private fun resolve(service: NsdServiceInfo, onResolved: (DiscoveredMac?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val cb = object : NsdManager.ServiceInfoCallback {
                override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                    Log.w(TAG, "info callback register failed: $errorCode")
                    onResolved(null)
                }
                override fun onServiceUpdated(info: NsdServiceInfo) {
                    val host = info.hostAddresses.firstOrNull()?.hostAddress
                    if (host != null) {
                        onResolved(DiscoveredMac(info.serviceName ?: "Mac", host, info.port))
                    }
                    runCatching { nsd.unregisterServiceInfoCallback(this) }
                }
                override fun onServiceLost() {
                    onResolved(null)
                }
                override fun onServiceInfoCallbackUnregistered() {}
            }
            try {
                nsd.registerServiceInfoCallback(service, java.util.concurrent.Executors.newSingleThreadExecutor(), cb)
            } catch (t: Throwable) {
                Log.w(TAG, "register info callback threw, falling back", t)
                legacyResolve(service, onResolved)
            }
        } else {
            legacyResolve(service, onResolved)
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyResolve(service: NsdServiceInfo, onResolved: (DiscoveredMac?) -> Unit) {
        nsd.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "resolve failed: $errorCode")
                onResolved(null)
            }
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                val host = serviceInfo.host?.hostAddress ?: serviceInfo.host?.toString()?.removePrefix("/")
                if (host != null) {
                    onResolved(DiscoveredMac(serviceInfo.serviceName ?: "Mac", host, serviceInfo.port))
                } else {
                    onResolved(null)
                }
            }
        })
    }

    companion object {
        private const val TAG = "ClawixBonjour"
        private const val SERVICE_TYPE = "_clawix-bridge._tcp"
        private const val MULTICAST_TAG = "clawix-mdns"
    }
}

private fun NsdServiceInfo.hostAddressesCompat(): List<InetAddress> {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        @Suppress("NewApi")
        this.hostAddresses
    } else {
        @Suppress("DEPRECATION")
        host?.let { listOf(it) } ?: emptyList()
    }
}
