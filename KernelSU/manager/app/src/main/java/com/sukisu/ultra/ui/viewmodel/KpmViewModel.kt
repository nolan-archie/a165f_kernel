package com.sukisu.ultra.ui.viewmodel

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sukisu.ultra.data.repository.KpmRepository
import com.sukisu.ultra.data.repository.KpmRepositoryImpl
import com.sukisu.ultra.ui.component.SearchStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class KpmViewModel(
    private val repo: KpmRepository = KpmRepositoryImpl()
) : ViewModel() {

    companion object {
        private const val TAG = "KpmViewModel"
    }

    private val _uiState = MutableStateFlow(KpmUiState())
    val uiState: StateFlow<KpmUiState> = _uiState.asStateFlow()

    private var _showInputDialog = false
    private var _selectedModuleId: String? = null
    private var _inputArgs = ""
    var currentModuleDetail by mutableStateOf("")
        private set

    val showInputDialog: Boolean get() = _showInputDialog
    val selectedModuleId: String? get() = _selectedModuleId
    val inputArgs: String get() = _inputArgs

    fun fetchModuleList() {
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true, error = null) }

            repo.getModuleList()
                .onSuccess { modules ->
                    _uiState.update {
                        it.copy(
                            moduleList = modules,
                            isRefreshing = false
                        )
                    }
                }
                .onFailure { e ->
                    Log.e(TAG, "fetchModuleList failed", e)
                    _uiState.update {
                        it.copy(
                            isRefreshing = false,
                            error = e
                        )
                    }
                }
        }
    }

    fun loadModuleDetail(moduleId: String) {
        viewModelScope.launch {
            repo.getModuleInfo(moduleId)
                .onSuccess { detail ->
                    currentModuleDetail = detail
                    Log.d(TAG, "Module detail loaded: $currentModuleDetail")
                }
                .onFailure { e ->
                    Log.e(TAG, "Failed to load module detail", e)
                    currentModuleDetail = "Error: ${e.message}"
                }
        }
    }

    fun showInputDialog(moduleId: String) {
        _selectedModuleId = moduleId
        _showInputDialog = true
    }

    fun hideInputDialog() {
        _showInputDialog = false
        _selectedModuleId = null
        _inputArgs = ""
    }

    fun updateInputArgs(args: String) {
        _inputArgs = args
    }

    suspend fun executeControl(): Int {
        val moduleId = _selectedModuleId ?: return -1

        return repo.controlModule(moduleId, _inputArgs)
            .onSuccess { _ ->
                hideInputDialog()
            }
            .onFailure { e ->
                Log.e(TAG, "Failed to control module", e)
                hideInputDialog()
                1
            }
            .getOrElse { -1 }
    }

    fun updateSearchStatus(status: SearchStatus) {
        _uiState.update { it.copy(searchStatus = status) }
    }

    suspend fun updateSearchText(text: String) {
        _uiState.update {
            it.copy(
                searchStatus = it.searchStatus.copy(searchText = text)
            )
        }

        if (text.isEmpty()) {
            _uiState.update {
                it.copy(
                    searchStatus = it.searchStatus.copy(resultStatus = SearchStatus.ResultStatus.DEFAULT),
                    searchResults = emptyList()
                )
            }
            return
        }

        _uiState.update {
            it.copy(searchStatus = it.searchStatus.copy(resultStatus = SearchStatus.ResultStatus.LOAD))
        }

        val result = withContext(Dispatchers.Default) {
            _uiState.value.moduleList.filter {
                it.id.contains(text, true) ||
                it.name.contains(text, true) ||
                it.description.contains(text, true) ||
                it.author.contains(text, true) ||
                it.version.contains(text, true)
            }
        }

        _uiState.update {
            it.copy(
                searchResults = result,
                searchStatus = it.searchStatus.copy(
                    resultStatus = if (result.isEmpty()) SearchStatus.ResultStatus.EMPTY else SearchStatus.ResultStatus.SHOW
                )
            )
        }
    }

    data class ModuleInfo(
        val id: String,
        val name: String,
        val version: String,
        val author: String,
        val description: String,
        val args: String,
        val enabled: Boolean,
        val hasAction: Boolean
    )
}
