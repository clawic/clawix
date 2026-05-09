package com.example.clawix.android

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.example.clawix.android.bridge.BridgeClient
import com.example.clawix.android.bridge.BridgeStore
import com.example.clawix.android.bridge.BonjourDiscovery
import com.example.clawix.android.bridge.CredentialStore
import com.example.clawix.android.bridge.ProjectLabelsCache
import com.example.clawix.android.bridge.UnreadChatsCache
import com.example.clawix.android.core.SnapshotCache
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Process-wide DI container + lifecycle observer. Hooks into
 * `ProcessLifecycleOwner` (one level above Activity) so rotations don't
 * churn the WebSocket. Mirrors iOS `scenePhase` semantics.
 *
 * Naming: `AppContainer` not Hilt module because the dep graph is small,
 * stable, and explicit-by-hand reads cleaner than annotated bindings.
 */
class ClawixApplication : Application() {

    val container: AppContainer by lazy { AppContainer(this) }

    private var hasBootstrapped = false

    override fun onCreate() {
        super.onCreate()
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                val creds = container.credentialStore.load()
                if (creds != null) {
                    container.bridgeClient.connect(creds)
                }
                hasBootstrapped = true
            }

            override fun onStop(owner: LifecycleOwner) {
                if (hasBootstrapped) {
                    container.bridgeClient.suspendConnection()
                }
            }
        })
    }
}

class AppContainer(private val app: Application) {
    val context: android.content.Context get() = app

    val appScope: CoroutineScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val credentialStore: CredentialStore by lazy { CredentialStore(app) }
    val snapshotCache: SnapshotCache by lazy { SnapshotCache(app.filesDir) }
    val unreadCache: UnreadChatsCache by lazy { UnreadChatsCache(app) }
    val projectLabelsCache: ProjectLabelsCache by lazy { ProjectLabelsCache(app) }

    val bonjour: BonjourDiscovery by lazy { BonjourDiscovery(app) }

    val bridgeStore: BridgeStore by lazy {
        BridgeStore(
            scope = appScope,
            snapshotCache = snapshotCache,
            unreadCache = unreadCache,
            projectLabelsCache = projectLabelsCache,
        )
    }

    val bridgeClient: BridgeClient by lazy {
        BridgeClient(
            scope = appScope,
            store = bridgeStore,
            bonjour = bonjour,
            credentialStore = credentialStore,
            appContext = app,
        )
    }
}
