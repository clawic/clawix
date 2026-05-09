package com.example.clawix.android.icons

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun FileChipIcon(modifier: Modifier = Modifier, size: Dp = 16.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(6 * s, 3 * s)
        p.lineTo(14 * s, 3 * s)
        p.lineTo(20 * s, 9 * s)
        p.lineTo(20 * s, 21 * s)
        p.lineTo(6 * s, 21 * s)
        p.close()
        p.moveTo(14 * s, 3 * s)
        p.lineTo(14 * s, 9 * s)
        p.lineTo(20 * s, 9 * s)
    }
}

@Composable
fun FolderClosedIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(3 * s, 7 * s)
        p.lineTo(9 * s, 7 * s)
        p.lineTo(11 * s, 5 * s)
        p.lineTo(21 * s, 5 * s)
        p.lineTo(21 * s, 19 * s)
        p.lineTo(3 * s, 19 * s)
        p.close()
    }
}

@Composable
fun FolderOpenIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(3 * s, 7 * s)
        p.lineTo(9 * s, 7 * s)
        p.lineTo(11 * s, 5 * s)
        p.lineTo(21 * s, 5 * s)
        p.lineTo(21 * s, 9 * s)
        p.lineTo(3 * s, 9 * s)
        p.close()
        p.moveTo(3 * s, 9 * s)
        p.lineTo(5 * s, 19 * s)
        p.lineTo(19 * s, 19 * s)
        p.lineTo(21 * s, 9 * s)
    }
}

@Composable
fun FolderStackIcon(modifier: Modifier = Modifier, size: Dp = 20.dp, tint: Color = Color.Unspecified) {
    StrokeIcon(modifier, size, tint) { p, s ->
        p.moveTo(3 * s, 5 * s)
        p.lineTo(9 * s, 5 * s)
        p.lineTo(11 * s, 7 * s)
        p.lineTo(21 * s, 7 * s)
        p.lineTo(21 * s, 17 * s)
        p.lineTo(3 * s, 17 * s)
        p.close()
        p.moveTo(5 * s, 5 * s)
        p.lineTo(5 * s, 3 * s)
        p.lineTo(11 * s, 3 * s)
    }
}

