package com.example.clawix.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.clawix.android.chatdetail.ChatDetailScreen
import com.example.clawix.android.chatlist.ChatListScreen
import com.example.clawix.android.pairing.PairingScreen
import com.example.clawix.android.pairing.QRScannerScreen
import com.example.clawix.android.pairing.ShortCodePairingScreen
import com.example.clawix.android.projectdetail.ProjectDetailScreen

object Routes {
    const val Pairing = "pairing"
    const val PairingQr = "pairing/qr"
    const val PairingShortCode = "pairing/short_code"
    const val ChatList = "chats"
    const val ChatDetail = "chats/{chatId}"
    const val ProjectDetail = "projects/{projectId}"

    fun chatDetail(chatId: String) = "chats/$chatId"
    fun projectDetail(projectId: String) = "projects/$projectId"
}

@Composable
fun AppNav(container: AppContainer) {
    val nav = rememberNavController()

    var hasCreds by remember { mutableStateOf(container.credentialStore.load() != null) }
    val start = if (hasCreds) Routes.ChatList else Routes.Pairing

    LaunchedEffect(Unit) {
        // Recompute once on cold start in case Lifecycle observer hasn't
        // fired yet. Subsequent state changes flow via the Pairing screen
        // navigating with popUpTo(0).
    }

    NavHost(navController = nav, startDestination = start) {
        composable(Routes.Pairing) {
            PairingScreen(
                container = container,
                onPaired = {
                    hasCreds = true
                    nav.navigate(Routes.ChatList) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onScanQr = { nav.navigate(Routes.PairingQr) },
                onShortCode = { nav.navigate(Routes.PairingShortCode) },
            )
        }
        composable(Routes.PairingQr) {
            QRScannerScreen(
                container = container,
                onScanned = {
                    hasCreds = true
                    nav.navigate(Routes.ChatList) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onCancel = { nav.popBackStack() },
            )
        }
        composable(Routes.PairingShortCode) {
            ShortCodePairingScreen(
                container = container,
                onPaired = {
                    hasCreds = true
                    nav.navigate(Routes.ChatList) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onCancel = { nav.popBackStack() },
            )
        }
        composable(Routes.ChatList) {
            ChatListScreen(
                container = container,
                onOpenChat = { chatId -> nav.navigate(Routes.chatDetail(chatId)) },
                onOpenProject = { id -> nav.navigate(Routes.projectDetail(id)) },
                onUnpair = {
                    container.credentialStore.clear()
                    container.bridgeClient.disconnect()
                    hasCreds = false
                    nav.navigate(Routes.Pairing) {
                        popUpTo(0) { inclusive = true }
                    }
                },
            )
        }
        composable(
            route = Routes.ChatDetail,
            arguments = listOf(navArgument("chatId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val chatId = backStackEntry.arguments?.getString("chatId") ?: return@composable
            ChatDetailScreen(
                container = container,
                chatId = chatId,
                onBack = { nav.popBackStack() },
                onOpenProject = { pid -> nav.navigate(Routes.projectDetail(pid)) },
            )
        }
        composable(
            route = Routes.ProjectDetail,
            arguments = listOf(navArgument("projectId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val projectId = backStackEntry.arguments?.getString("projectId") ?: return@composable
            ProjectDetailScreen(
                container = container,
                projectId = projectId,
                onBack = { nav.popBackStack() },
                onOpenChat = { chatId -> nav.navigate(Routes.chatDetail(chatId)) },
            )
        }
    }
}
