package com.example.clawix.android.chatlist

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.example.clawix.android.icons.ComposeIcon
import com.example.clawix.android.theme.Palette

@Composable
fun NewChatFAB(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(58.dp)
            .clip(CircleShape)
            .background(Palette.userBubbleFill)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        ComposeIcon(size = 26.dp, tint = Palette.userBubbleText)
    }
}
