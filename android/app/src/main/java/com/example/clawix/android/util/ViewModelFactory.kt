package com.example.clawix.android.util

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

/**
 * Tiny factory builder so callsites can inline a `viewModel(factory = ...)`
 * without writing a class per VM. Usage:
 *
 * ```
 * val vm: MyVM = viewModel(factory = ViewModelFactory { MyVM(container) })
 * ```
 */
class ViewModelFactory<T : ViewModel>(
    private val builder: () -> T,
) : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <V : ViewModel> create(modelClass: Class<V>): V = builder() as V
}
