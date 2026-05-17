package com.example.clawix.android.bridge

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.example.clawix.android.core.PairingPayload

/**
 * Pairing credentials persisted between app launches. Mirrors iOS
 * `Credentials.swift`. The pairing token authorises the WebSocket; the
 * host/port and Tailscale fallback are used by the multi-path racer.
 * Coordinator and Iroh fields are preserved from the v1 QR payload so
 * remote bridge routes can be enabled without re-pairing.
 */
data class Credentials(
    val host: String,
    val port: Int,
    val token: String,
    val hostDisplayName: String?,
    val tailscaleHost: String?,
    val coordinatorUrl: String? = null,
    val irohNodeId: String? = null,
) {
    companion object {
        fun fromPairingPayload(p: PairingPayload): Credentials = Credentials(
            host = p.host,
            port = p.port,
            token = p.token,
            hostDisplayName = p.hostDisplayName,
            tailscaleHost = p.tailscaleHost,
            coordinatorUrl = p.coordinatorUrl,
            irohNodeId = p.irohNodeId,
        )
    }
}

/**
 * EncryptedSharedPreferences-backed credential store. Equivalent to iOS
 * UserDefaults under key `ClawixBridge.Credentials.v1`. The master key
 * lives in Android Keystore (AES256-GCM); SharedPrefs blob is encrypted
 * before hitting disk.
 *
 * Defensive: if the keystore key was invalidated by the system (factory
 * reset of the secure enclave, user disabling biometrics, etc.) the
 * load() throws. We catch and clear so the user lands on the pairing
 * screen instead of an unrecoverable crash.
 */
class CredentialStore(context: Context) {
    private val appCtx = context.applicationContext

    private val prefs by lazy {
        try {
            val masterKey = MasterKey.Builder(appCtx)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                appCtx,
                "clawix_credentials_v1",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (t: Throwable) {
            // Reset on corrupt keystore: drop the file, retry once.
            appCtx.getSharedPreferences("clawix_credentials_v1", Context.MODE_PRIVATE)
                .edit().clear().apply()
            val masterKey = MasterKey.Builder(appCtx)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                appCtx,
                "clawix_credentials_v1",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }
    }

    fun load(): Credentials? {
        val token = prefs.getString(KEY_TOKEN, null) ?: return null
        val host = prefs.getString(KEY_HOST, null) ?: return null
        val port = prefs.getInt(KEY_PORT, 0).takeIf { it > 0 } ?: return null
        return Credentials(
            host = host,
            port = port,
            token = token,
            hostDisplayName = prefs.getString(KEY_MAC_NAME, null),
            tailscaleHost = prefs.getString(KEY_TAILSCALE_HOST, null),
            coordinatorUrl = prefs.getString(KEY_COORDINATOR_URL, null),
            irohNodeId = prefs.getString(KEY_IROH_NODE_ID, null),
        )
    }

    fun save(c: Credentials) {
        prefs.edit()
            .putString(KEY_HOST, c.host)
            .putInt(KEY_PORT, c.port)
            .putString(KEY_TOKEN, c.token)
            .putString(KEY_MAC_NAME, c.hostDisplayName)
            .putString(KEY_TAILSCALE_HOST, c.tailscaleHost)
            .putString(KEY_COORDINATOR_URL, c.coordinatorUrl)
            .putString(KEY_IROH_NODE_ID, c.irohNodeId)
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val KEY_HOST = "host"
        private const val KEY_PORT = "port"
        private const val KEY_TOKEN = "token"
        private const val KEY_MAC_NAME = "hostDisplayName"
        private const val KEY_TAILSCALE_HOST = "tailscaleHost"
        private const val KEY_COORDINATOR_URL = "coordinatorUrl"
        private const val KEY_IROH_NODE_ID = "irohNodeId"
    }
}
