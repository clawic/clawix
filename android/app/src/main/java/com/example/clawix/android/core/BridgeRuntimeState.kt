package com.example.clawix.android.core

/**
 * Bootstrap state of the daemon driving the BridgeServer. Mirrors
 * Swift `BridgeRuntimeState`. Sent immediately after `authOk` and on
 * every subsequent transition.
 */
sealed class BridgeRuntimeState {
    data object Booting : BridgeRuntimeState()
    data class Syncing(val message: String? = null) : BridgeRuntimeState()
    data object Ready : BridgeRuntimeState()
    data class Error(val message: String) : BridgeRuntimeState()

    val wireTag: String
        get() = when (this) {
            Booting -> "booting"
            is Syncing -> "syncing"
            Ready -> "ready"
            is Error -> "error"
        }

    companion object {
        fun fromWire(state: String, message: String?): BridgeRuntimeState = when (state) {
            "booting" -> Booting
            "syncing" -> Syncing(message)
            "ready" -> Ready
            "error" -> Error(message ?: "Unknown error")
            else -> Error("Unknown state: $state")
        }
    }
}
