package com.sukisu.ultra.ui.viewmodel

import androidx.compose.runtime.Immutable
import com.sukisu.ultra.data.model.AppInfo
import com.sukisu.ultra.ui.component.SearchStatus

@Immutable
data class GroupedApps(
    val uid: Int,
    val apps: List<AppInfo>,
    val primary: AppInfo,
    val anyAllowSu: Boolean,
    val anyCustom: Boolean,
    val shouldUmount: Boolean,
    val ownerName: String? = null,
)

data class SuperUserUiState(
    val isRefreshing: Boolean = false,
    val appList: List<AppInfo> = emptyList(),
    val groupedApps: List<GroupedApps> = emptyList(),
    val userIds: List<Int> = emptyList(),
    val searchStatus: SearchStatus = SearchStatus(""),
    val searchResults: List<AppInfo> = emptyList(),
    val showSystemApps: Boolean = false,
    val showOnlyPrimaryUserApps: Boolean = false,
    val error: Throwable? = null
)
