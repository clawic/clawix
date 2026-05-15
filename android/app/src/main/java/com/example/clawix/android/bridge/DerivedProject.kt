package com.example.clawix.android.bridge

import com.example.clawix.android.core.WireSession
import kotlinx.datetime.Instant

/**
 * Project derived from the chat list when the daemon doesn't ship an
 * explicit `projectsSnapshot`. Groups chats by `cwd` (or branch when
 * cwd is missing) and surfaces the most-recent label as the title.
 *
 * Mirrors the macOS `DerivedProject.from(chats:)` helper closely enough
 * that the same UI affordances apply (chip with project name, count of
 * chats, last-used timestamp).
 */
data class DerivedProject(
    val id: String,
    val title: String,
    val cwd: String?,
    val branch: String?,
    val chatIds: List<String>,
    val lastUsedAt: Instant?,
) {
    companion object {
        fun from(chats: List<WireSession>): List<DerivedProject> {
            // Group by cwd; chats without cwd are not projectised.
            val byCwd = chats.groupBy { it.cwd ?: "" }
            val derived = byCwd
                .filterKeys { it.isNotEmpty() }
                .map { (cwd, group) ->
                    val sorted = group.sortedByDescending { it.lastMessageAt ?: it.createdAt }
                    val title = projectTitle(cwd)
                    DerivedProject(
                        id = "cwd:${cwd.hashCode()}",
                        title = title,
                        cwd = cwd,
                        branch = sorted.firstOrNull()?.branch,
                        chatIds = sorted.map { it.id },
                        lastUsedAt = sorted.firstOrNull()?.lastMessageAt ?: sorted.firstOrNull()?.createdAt,
                    )
                }
                .sortedByDescending { it.lastUsedAt }
            return derived
        }

        /** Last path segment, with `~` collapsed for clarity. */
        private fun projectTitle(cwd: String): String {
            val cleaned = cwd.trimEnd('/')
            val last = cleaned.substringAfterLast('/')
            return if (last.isBlank()) cleaned else last
        }
    }
}
