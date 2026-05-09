package com.example.clawix.android.bridge

import android.content.Context
import android.content.SharedPreferences

/**
 * Maps project id (cwd hash) to a user-friendly display label. Mirrors
 * iOS `ProjectLabelsCache`. Useful for cold-start so the user sees the
 * same project names before the daemon's `projectsSnapshot` arrives.
 */
class ProjectLabelsCache(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("clawix_project_labels_v1", Context.MODE_PRIVATE)

    fun get(id: String): String? = prefs.getString(id, null)

    fun put(id: String, label: String) {
        prefs.edit().putString(id, label).apply()
    }

    fun all(): Map<String, String> {
        @Suppress("UNCHECKED_CAST")
        return prefs.all.filterValues { it is String } as Map<String, String>
    }

    fun clear() {
        prefs.edit().clear().apply()
    }
}
