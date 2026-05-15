package com.example.clawix.android.core

import kotlinx.serialization.Serializable

/**
 * JSON payload encoded inside the QR code that the daemon emits on
 * `pairingStart`. Mirrors `PairingPayload` in
 * `clawix/ios/Sources/Clawix/Bridge/Credentials.swift`.
 */
@Serializable
data class PairingPayload(
    val v: Int = 1,
    val host: String,
    val port: Int = 24080,
    val token: String,
    val hostDisplayName: String? = null,
    val tailscaleHost: String? = null,
    val shortCode: String? = null,
) {
    companion object {
        /** Tolerant parser. Returns null if the QR isn't ours. */
        fun parse(raw: String): PairingPayload? = runCatching {
            BridgeJson.json.decodeFromString(serializer(), raw)
        }.getOrNull()
    }
}
