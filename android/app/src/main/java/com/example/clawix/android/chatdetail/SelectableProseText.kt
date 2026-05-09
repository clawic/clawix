package com.example.clawix.android.chatdetail

import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * Wrapper enabling text selection / copy on long-press for assistant
 * messages. Mirrors iOS `SelectableProseTextView` (which uses
 * `UITextView` interop). Compose's `SelectionContainer` is enough.
 */
@Composable
fun SelectableProseText(content: @Composable () -> Unit, modifier: Modifier = Modifier) {
    SelectionContainer(modifier = modifier) {
        content()
    }
}
