package com.example.clawix.android.util

/**
 * Tailscale CGNAT range: 100.64.0.0/10. Used as a heuristic when the
 * pairing payload didn't include `tailscaleHost` separately but the
 * `host` field happened to be a CGNAT IP. Mirrors iOS behaviour.
 */
object TailscaleHostCheck {
    fun isTailscale(host: String): Boolean {
        val parts = host.split('.').takeIf { it.size == 4 } ?: return false
        val a = parts[0].toIntOrNull() ?: return false
        val b = parts[1].toIntOrNull() ?: return false
        return a == 100 && b in 64..127
    }
}
