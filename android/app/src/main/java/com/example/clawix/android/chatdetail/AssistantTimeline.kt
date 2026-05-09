package com.example.clawix.android.chatdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.example.clawix.android.core.WireTimelineEntry
import com.example.clawix.android.core.WireWorkItem
import com.example.clawix.android.icons.GlobeIcon
import com.example.clawix.android.icons.LucideGlyph
import com.example.clawix.android.icons.LucideIcon
import com.example.clawix.android.icons.McpIcon
import com.example.clawix.android.icons.PencilIcon
import com.example.clawix.android.icons.TerminalIcon
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

/**
 * Renders the chronological timeline of assistant work (reasoning,
 * tool calls, message blocks) as a vertical stack. Mirrors iOS
 * `AssistantTimeline`.
 */
@Composable
fun AssistantTimeline(entries: List<WireTimelineEntry>, modifier: Modifier = Modifier) {
    if (entries.isEmpty()) return
    Column(modifier.fillMaxWidth()) {
        for ((idx, e) in entries.withIndex()) {
            if (idx > 0) Spacer(Modifier.height(8.dp))
            when (e) {
                is WireTimelineEntry.Reasoning -> ReasoningBlock(e.text)
                is WireTimelineEntry.Tools -> ToolsBlock(e.items)
                is WireTimelineEntry.Message -> AssistantMarkdownView(e.text)
            }
        }
    }
}

@Composable
private fun ReasoningBlock(text: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.chipCornerRadius))
            .background(Palette.cardFill)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        LucideIcon(LucideGlyph.Drama, size = 16.dp, tint = Palette.textTertiary)
        Spacer(Modifier.width(8.dp))
        Text(text, style = AppTypography.secondary, color = Palette.textSecondary)
    }
}

@Composable
private fun ToolsBlock(items: List<WireWorkItem>) {
    Column(verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp)) {
        for (item in items) {
            ToolItemRow(item)
        }
    }
}

@Composable
private fun ToolItemRow(item: WireWorkItem) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AppLayout.chipCornerRadius))
            .background(Palette.cardFill)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (item.kind) {
            "command" -> TerminalIcon(size = 16.dp, tint = Palette.textPrimary)
            "fileChange" -> PencilIcon(size = 16.dp, tint = Palette.textPrimary)
            "webSearch" -> GlobeIcon(size = 16.dp, tint = Palette.textPrimary)
            "mcpTool" -> McpIcon(size = 16.dp, tint = Palette.textPrimary)
            "imageGeneration" -> LucideIcon(LucideGlyph.Image, size = 16.dp, tint = Palette.textPrimary)
            else -> LucideIcon(LucideGlyph.CircleAlert, size = 16.dp, tint = Palette.textPrimary)
        }
        Spacer(Modifier.width(8.dp))
        val label = labelFor(item)
        Text(label, style = AppTypography.secondary, color = Palette.textPrimary)
    }
}

private fun labelFor(item: WireWorkItem): String = when (item.kind) {
    "command" -> item.commandText?.take(80) ?: "Ran command"
    "fileChange" -> "Edited ${item.paths?.size ?: 1} file" + if ((item.paths?.size ?: 0) > 1) "s" else ""
    "webSearch" -> "Searched the web"
    "mcpTool" -> "${item.mcpServer ?: "MCP"} · ${item.mcpTool ?: "tool"}"
    "dynamicTool" -> "Tool: ${item.dynamicToolName ?: "?"}"
    "imageGeneration" -> "Generated image"
    "imageView" -> "Viewed image"
    else -> item.kind
}
