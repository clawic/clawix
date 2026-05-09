package com.example.clawix.android.util

import android.content.Context
import android.os.Build
import android.provider.Settings

/**
 * User-readable device identifier sent in the `auth` frame so the daemon
 * can surface "iPhone of Iván" in its connected-clients UI. Falls back
 * to `Build.MODEL` if the user hasn't named their device.
 */
object DeviceName {
    fun resolve(context: Context): String {
        val global = runCatching {
            Settings.Global.getString(context.contentResolver, "device_name")
        }.getOrNull()
        if (!global.isNullOrBlank()) return global
        val secure = runCatching {
            Settings.Secure.getString(context.contentResolver, "bluetooth_name")
        }.getOrNull()
        if (!secure.isNullOrBlank()) return secure
        return "${Build.MANUFACTURER.replaceFirstChar { it.titlecase() }} ${Build.MODEL}"
    }
}
