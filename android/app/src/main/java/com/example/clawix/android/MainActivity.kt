package com.example.clawix.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import com.example.clawix.android.theme.ClawixTheme
import com.example.clawix.android.theme.Palette

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val container = (application as ClawixApplication).container

        setContent {
            ClawixTheme {
                ClawixRoot(container = container)
            }
        }
    }
}

@Composable
private fun ClawixRoot(container: AppContainer) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.background)
    ) {
        AppNav(container = container)
    }
}
