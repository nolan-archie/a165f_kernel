package com.sukisu.ultra.ui.viewmodel

import com.sukisu.ultra.data.model.RepoModule
import com.sukisu.ultra.ui.component.SearchStatus

data class ModuleRepoUiState(
    val isRefreshing: Boolean = false,
    val modules: List<RepoModule> = emptyList(),
    val searchStatus: SearchStatus = SearchStatus(""),
    val searchResults: List<RepoModule> = emptyList(),
    val error: Throwable? = null
)
