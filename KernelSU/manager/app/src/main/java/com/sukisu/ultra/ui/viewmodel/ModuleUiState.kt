package com.sukisu.ultra.ui.viewmodel

import com.sukisu.ultra.data.model.Module
import com.sukisu.ultra.data.model.ModuleUpdateInfo
import com.sukisu.ultra.ui.component.SearchStatus

data class ModuleUiState(
    val isRefreshing: Boolean = false,
    val modules: List<Module> = emptyList(),
    val moduleList: List<Module> = emptyList(),
    val updateInfo: Map<String, ModuleUpdateInfo> = emptyMap(),
    val searchStatus: SearchStatus = SearchStatus(""),
    val searchResults: List<Module> = emptyList(),
    val sortEnabledFirst: Boolean = false,
    val sortActionFirst: Boolean = false,
    val checkModuleUpdate: Boolean = true
)
