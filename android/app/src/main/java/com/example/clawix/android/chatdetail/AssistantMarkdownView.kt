package com.example.clawix.android.chatdetail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.clawix.android.theme.AppLayout
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

/**
 * Bare-bones markdown renderer mirroring iOS `AssistantMarkdownView`.
 * Supports: headings (#, ##, ###), bold (**), italic (*), code spans
 * (`...`), code blocks (```), unordered lists (-, *), links
 * `[text](url)`. Images `![](path)` are rendered separately via
 * AssistantInlineImagesView (here we just render a placeholder string).
 *
 * Single-file, ~200 LoC, intentionally minimal: paritarchitectural with
 * iOS where a 3rd-party markdown lib would be overkill.
 */
@Composable
fun AssistantMarkdownView(text: String, modifier: Modifier = Modifier) {
    val blocks = remember(text) { parseBlocks(text) }
    Column(modifier.fillMaxWidth()) {
        for ((idx, b) in blocks.withIndex()) {
            if (idx > 0) Spacer(Modifier.height(6.dp))
            when (b) {
                is Block.Heading -> Text(
                    renderInline(b.text),
                    style = AppTypography.title.copy(
                        fontSize = (24 - 2 * (b.level - 1)).sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = Palette.textPrimary,
                )
                is Block.Paragraph -> Text(
                    renderInline(b.text),
                    style = AppTypography.chatBody,
                    color = Palette.textPrimary,
                )
                is Block.ListItem -> Text(
                    renderInline("• ${b.text}"),
                    style = AppTypography.chatBody,
                    color = Palette.textPrimary,
                    modifier = Modifier.padding(start = 8.dp),
                )
                is Block.Code -> Text(
                    text = b.text,
                    style = AppTypography.mono,
                    color = Palette.textPrimary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(AppLayout.chipCornerRadius))
                        .background(Palette.cardFill)
                        .padding(12.dp),
                )
            }
        }
    }
}

private sealed class Block {
    data class Heading(val level: Int, val text: String) : Block()
    data class Paragraph(val text: String) : Block()
    data class ListItem(val text: String) : Block()
    data class Code(val text: String) : Block()
}

private fun parseBlocks(raw: String): List<Block> {
    val blocks = mutableListOf<Block>()
    val lines = raw.split('\n')
    var i = 0
    val paragraph = StringBuilder()

    fun flushParagraph() {
        if (paragraph.isNotBlank()) {
            blocks.add(Block.Paragraph(paragraph.toString().trim()))
        }
        paragraph.clear()
    }

    while (i < lines.size) {
        val line = lines[i]
        when {
            line.startsWith("```") -> {
                flushParagraph()
                val code = StringBuilder()
                i++
                while (i < lines.size && !lines[i].startsWith("```")) {
                    code.append(lines[i]).append('\n')
                    i++
                }
                blocks.add(Block.Code(code.toString().trimEnd()))
                if (i < lines.size) i++
            }
            line.startsWith("# ") -> { flushParagraph(); blocks.add(Block.Heading(1, line.removePrefix("# "))); i++ }
            line.startsWith("## ") -> { flushParagraph(); blocks.add(Block.Heading(2, line.removePrefix("## "))); i++ }
            line.startsWith("### ") -> { flushParagraph(); blocks.add(Block.Heading(3, line.removePrefix("### "))); i++ }
            line.startsWith("- ") -> { flushParagraph(); blocks.add(Block.ListItem(line.removePrefix("- "))); i++ }
            line.startsWith("* ") -> { flushParagraph(); blocks.add(Block.ListItem(line.removePrefix("* "))); i++ }
            line.isBlank() -> { flushParagraph(); i++ }
            else -> {
                if (paragraph.isNotEmpty()) paragraph.append(' ')
                paragraph.append(line)
                i++
            }
        }
    }
    flushParagraph()
    return blocks
}

/** Inline span renderer: bold, italic, code, links, image placeholder. */
private fun renderInline(raw: String): AnnotatedString = buildAnnotatedString {
    var i = 0
    while (i < raw.length) {
        when {
            raw.startsWith("**", i) -> {
                val end = raw.indexOf("**", i + 2)
                if (end < 0) { append(raw.substring(i)); i = raw.length }
                else {
                    pushStyle(SpanStyle(fontWeight = FontWeight.Bold))
                    append(raw.substring(i + 2, end))
                    pop()
                    i = end + 2
                }
            }
            raw[i] == '*' -> {
                val end = raw.indexOf('*', i + 1)
                if (end < 0) { append('*'); i++ }
                else {
                    pushStyle(SpanStyle(fontStyle = FontStyle.Italic))
                    append(raw.substring(i + 1, end))
                    pop()
                    i = end + 1
                }
            }
            raw[i] == '`' -> {
                val end = raw.indexOf('`', i + 1)
                if (end < 0) { append('`'); i++ }
                else {
                    pushStyle(SpanStyle(background = Palette.cardFill, color = Palette.textPrimary))
                    append(raw.substring(i + 1, end))
                    pop()
                    i = end + 1
                }
            }
            raw.startsWith("![", i) -> {
                // Image placeholder; AssistantInlineImagesView shows actual bytes
                val close = raw.indexOf(')', i)
                append("[image]")
                i = if (close < 0) raw.length else close + 1
            }
            raw[i] == '[' -> {
                val labelClose = raw.indexOf(']', i)
                val urlOpen = if (labelClose >= 0) raw.indexOf('(', labelClose) else -1
                val urlClose = if (urlOpen >= 0) raw.indexOf(')', urlOpen) else -1
                if (labelClose < 0 || urlOpen != labelClose + 1 || urlClose < 0) { append('['); i++ }
                else {
                    pushStyle(SpanStyle(color = Palette.unreadDot))
                    append(raw.substring(i + 1, labelClose))
                    pop()
                    i = urlClose + 1
                }
            }
            else -> { append(raw[i]); i++ }
        }
    }
}
