package com.example.clawix.android.projectdetail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.clawix.android.AppContainer
import com.example.clawix.android.bridge.DerivedProject
import com.example.clawix.android.core.WireChat
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

data class ProjectDetailUi(
    val project: DerivedProject?,
    val chats: List<WireChat>,
)

class ProjectDetailViewModel(
    private val container: AppContainer,
    private val projectId: String,
) : ViewModel() {

    val ui: StateFlow<ProjectDetailUi> = container.bridgeStore.state
        .map { state ->
            val derived = DerivedProject.from(state.chats).firstOrNull { it.id == projectId }
            val chats = derived?.chatIds.orEmpty()
                .mapNotNull { id -> state.chats.firstOrNull { it.id == id } }
            ProjectDetailUi(derived, chats)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ProjectDetailUi(null, emptyList()))
}
