package com.sukisu.ultra.ui.viewmodel

import androidx.compose.runtime.Immutable
import com.sukisu.ultra.ui.component.SearchStatus

@Immutable
data class KpmUiState(
    val isRefreshing: Boolean = false,
    val moduleList: List<KpmViewModel.ModuleInfo> = emptyList(),
    val searchStatus: SearchStatus = SearchStatus(""),
    val searchResults: List<KpmViewModel.ModuleInfo> = emptyList(),
    val error: Throwable? = null
)
