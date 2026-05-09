package com.example.clawix.android.chatlist

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import com.example.clawix.android.theme.AppTypography
import com.example.clawix.android.theme.Palette

/**
 * Compose mirror of iOS rename alert (title + TextField + Save / Cancel).
 * Pre-fills the current title, selects-all on open so the user can type
 * over it, trims and validates non-empty before invoking `onSave`.
 */
@Composable
fun RenameChatDialog(
    initialTitle: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var value by remember {
        mutableStateOf(TextFieldValue(initialTitle, TextRange(0, initialTitle.length)))
    }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    val trimmed = value.text.trim()
    val canSave = trimmed.isNotEmpty() && trimmed != initialTitle.trim()

    AlertDialog(
        containerColor = Palette.surface,
        textContentColor = Palette.textPrimary,
        titleContentColor = Palette.textPrimary,
        onDismissRequest = onDismiss,
        title = { Text("Rename chat", color = Palette.textPrimary) },
        text = {
            Column(Modifier.fillMaxWidth()) {
                Spacer(Modifier.height(4.dp))
                BasicTextField(
                    value = value,
                    onValueChange = { value = it },
                    textStyle = AppTypography.body.copy(color = Palette.textPrimary),
                    cursorBrush = SolidColor(Palette.textPrimary),
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = {
                        if (canSave) {
                            onSave(trimmed)
                            onDismiss()
                        }
                    }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focus),
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = canSave,
                onClick = {
                    onSave(trimmed)
                    onDismiss()
                },
            ) { Text("Save", color = if (canSave) Palette.unreadDot else Palette.textTertiary) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = Palette.textSecondary)
            }
        },
    )
}
