package com.sukisu.ultra.ui.viewmodel

import com.sukisu.ultra.data.model.TemplateInfo

data class TemplateUiState(
    val isRefreshing: Boolean = false,
    val templates: List<TemplateInfo> = emptyList(),
    val templateList: List<TemplateInfo> = emptyList(),
    val error: Throwable? = null
)
