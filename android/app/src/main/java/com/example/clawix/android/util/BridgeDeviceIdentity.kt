package com.example.clawix.android.util

import android.content.Context
import android.provider.Settings
import java.util.UUID

object BridgeDeviceIdentity {
    const val clientId: String = "clawix.android.companion"

    fun installationId(context: Context): String =
        persistedId(context, "installation_id")

    fun deviceId(context: Context): String {
        val androidId = runCatching {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        }.getOrNull()
        if (!androidId.isNullOrBlank() && androidId != "9774d56d682e549c") {
            return androidId
        }
        return persistedId(context, "device_id")
    }

    private fun persistedId(context: Context, key: String): String {
        val prefs = context.getSharedPreferences("clawix_bridge_identity", Context.MODE_PRIVATE)
        val existing = prefs.getString(key, null)
        if (!existing.isNullOrBlank()) return existing
        val value = UUID.randomUUID().toString().lowercase()
        prefs.edit().putString(key, value).apply()
        return value
    }
}
