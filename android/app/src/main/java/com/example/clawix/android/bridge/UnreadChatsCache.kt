package com.example.clawix.android.bridge

import android.content.Context
import android.content.SharedPreferences

/**
 * Persists the set of chat ids the user has NOT yet seen since their
 * last assistant turn finished. Mirrors iOS `UnreadChatsCache`. Lives
 * in plain SharedPreferences (no secrets) so cold-start can paint the
 * dot before the WebSocket lands.
 */
class UnreadChatsCache(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("clawix_unread_v1", Context.MODE_PRIVATE)

    fun load(): Set<String> = prefs.getStringSet(KEY, emptySet()) ?: emptySet()

    fun save(ids: Set<String>) {
        prefs.edit().putStringSet(KEY, ids).apply()
    }

    fun mark(id: String) {
        save(load() + id)
    }

    fun clear(id: String) {
        save(load() - id)
    }

    fun clearAll() {
        prefs.edit().remove(KEY).apply()
    }

    companion object {
        private const val KEY = "ids"
    }
}
