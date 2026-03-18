package com.sukisu.ultra.ui.susfs

import android.annotation.SuppressLint
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.add
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.systemBars
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.susfs.component.*
import com.sukisu.ultra.ui.susfs.content.BasicSettingsContent
import com.sukisu.ultra.ui.susfs.content.EnabledFeaturesContent
import com.sukisu.ultra.ui.susfs.content.KstatConfigContent
import com.sukisu.ultra.ui.susfs.content.SusLoopPathsContent
import com.sukisu.ultra.ui.susfs.content.SusMapsContent
import com.sukisu.ultra.ui.susfs.content.SusPathsContent
import com.sukisu.ultra.ui.susfs.util.SuSFSManager
import com.sukisu.ultra.ui.util.isAbDevice
import com.sukisu.ultra.ui.susfs.viewmodel.SuSFSViewModel
import com.sukisu.ultra.ui.susfs.viewmodel.SuSFSUiState
import kotlinx.coroutines.launch
import androidx.lifecycle.viewmodel.compose.viewModel
import top.yukonga.miuix.kmp.basic.*
import top.yukonga.miuix.kmp.extra.SuperDialog
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Back
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme
import top.yukonga.miuix.kmp.utils.overScrollVertical
import top.yukonga.miuix.kmp.utils.scrollEndHaptic

enum class SuSFSTab(val displayNameRes: Int) {
    BASIC_SETTINGS(R.string.susfs_tab_basic_settings),
    SUS_PATHS(R.string.susfs_tab_sus_paths),
    SUS_LOOP_PATHS(R.string.susfs_tab_sus_loop_paths),
    SUS_MAPS(R.string.susfs_tab_sus_maps),
    KSTAT_CONFIG(R.string.susfs_tab_kstat_config),
    ENABLED_FEATURES(R.string.susfs_tab_enabled_features);

    companion object {
        fun getAllTabs(): List<SuSFSTab> {
            return entries.toList()
        }
    }
}

@SuppressLint("SdCardPath", "AutoboxingStateCreation")
@Composable
fun SuSFSConfigScreen() {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scrollBehavior = MiuixScrollBehavior()
    val hazeState = remember { HazeState() }
    val hazeStyle = HazeStyle(
        backgroundColor = colorScheme.surface,
        tint = HazeTint(colorScheme.surface.copy(0.8f))
    )

    val viewModel: SuSFSViewModel = viewModel()
    val uiState: SuSFSUiState by viewModel.uiState.collectAsState()
    val coroutineScope = rememberCoroutineScope()

    var isNavigating by remember { mutableStateOf(false) }

    val allTabs = SuSFSTab.getAllTabs()

    // 加载当前配置
    LaunchedEffect(Unit) {
        viewModel.loadInitial(context)
    }

    // 当切换到启用功能状态标签页时加载数据
    LaunchedEffect(uiState.selectedTab) {
        if (uiState.selectedTab == SuSFSTab.ENABLED_FEATURES) {
            viewModel.loadEnabledFeatures(context)
        }
    }

    // 当配置变化时，自动调整开机自启动状态
    LaunchedEffect(uiState.canEnableAutoStart, uiState.autoStartEnabled) {
        if (!uiState.canEnableAutoStart && uiState.autoStartEnabled) {
            viewModel.configureAutoStart(context, false)
        }
    }


    // 槽位信息对话框
    SlotInfoDialog(
        showDialog = uiState.showSlotInfoDialog,
        onDismiss = { viewModel.showSlotInfoDialog(false) },
        slotInfoList = uiState.slotInfoList,
        currentActiveSlot = uiState.currentActiveSlot,
        isLoadingSlotInfo = uiState.isLoadingSlotInfo,
        onRefresh = { viewModel.loadSlotInfo(context) },
        onUseUname = { uname: String ->
            viewModel.updateUname(uname)
            viewModel.showSlotInfoDialog(false)
        },
        onUseBuildTime = { buildTime: String ->
            viewModel.updateBuildTime(buildTime)
            viewModel.showSlotInfoDialog(false)
        }
    )

    // 各种对话框
    AddPathDialog(
        showDialog = uiState.showAddPathDialog,
        onDismiss = { viewModel.closeAddPathDialog() },
        onConfirm = { path ->
            val oldPath = uiState.editingPath
            coroutineScope.launch {
                val success = if (oldPath != null) {
                    SuSFSManager.editSusPath(context, oldPath, path)
                } else {
                    SuSFSManager.addSusPath(context, path)
                }
                if (success) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddPathDialog()
            }
        },
        isLoading = uiState.isLoading,
        titleRes = if (uiState.editingPath != null) R.string.susfs_edit_sus_path else R.string.susfs_add_sus_path,
        labelRes = R.string.susfs_path_label,
        initialValue = uiState.editingPath ?: ""
    )

    AddPathDialog(
        showDialog = uiState.showAddLoopPathDialog,
        onDismiss = { viewModel.closeAddLoopPathDialog() },
        onConfirm = { path ->
            val oldPath = uiState.editingLoopPath
            coroutineScope.launch {
                val success = if (oldPath != null) {
                    SuSFSManager.editSusLoopPath(context, oldPath, path)
                } else {
                    SuSFSManager.addSusLoopPath(context, path)
                }
                if (success) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddLoopPathDialog()
            }
        },
        isLoading = uiState.isLoading,
        titleRes = if (uiState.editingLoopPath != null) R.string.susfs_edit_sus_loop_path else R.string.susfs_add_sus_loop_path,
        labelRes = R.string.susfs_loop_path_label,
        initialValue = uiState.editingLoopPath ?: ""
    )

    AddPathDialog(
        showDialog = uiState.showAddSusMapDialog,
        onDismiss = { viewModel.closeAddSusMapDialog() },
        onConfirm = { path ->
            val oldPath = uiState.editingSusMap
            coroutineScope.launch {
                val success = if (oldPath != null) {
                    SuSFSManager.editSusMap(context, oldPath, path)
                } else {
                    SuSFSManager.addSusMap(context, path)
                }
                if (success) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddSusMapDialog()
            }
        },
        isLoading = uiState.isLoading,
        titleRes = if (uiState.editingSusMap != null) R.string.susfs_edit_sus_map else R.string.susfs_add_sus_map,
        labelRes = R.string.susfs_sus_map_label,
        initialValue = uiState.editingSusMap ?: ""
    )

    AddAppPathDialog(
        showDialog = uiState.showAddAppPathDialog,
        onDismiss = { viewModel.closeAddAppPathDialog() },
        onConfirm = { packageNames ->
            coroutineScope.launch {
                var successCount = 0
                packageNames.forEach { packageName ->
                    if (SuSFSManager.addAppPaths(context, packageName)) {
                        successCount++
                    }
                }
                if (successCount > 0) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddAppPathDialog()
            }
        },
        isLoading = uiState.isLoading,
        apps = uiState.installedApps,
        onLoadApps = { viewModel.loadInstalledApps() },
        existingSusPaths = uiState.susPaths
    )


    AddKstatStaticallyDialog(
        showDialog = uiState.showAddKstatStaticallyDialog,
        onDismiss = { viewModel.closeAddKstatStaticallyDialog() },
        onConfirm = { path, ino, dev, nlink, size, atime, atimeNsec, mtime, mtimeNsec, ctime, ctimeNsec, blocks, blksize ->
            val oldConfig = uiState.editingKstatConfig
            coroutineScope.launch {
                val success = if (oldConfig != null) {
                    SuSFSManager.editKstatConfig(
                        context,
                        oldConfig,
                        path,
                        ino,
                        dev,
                        nlink,
                        size,
                        atime,
                        atimeNsec,
                        mtime,
                        mtimeNsec,
                        ctime,
                        ctimeNsec,
                        blocks,
                        blksize
                    )
                } else {
                    SuSFSManager.addKstatStatically(
                        context, path, ino, dev, nlink, size, atime, atimeNsec,
                        mtime, mtimeNsec, ctime, ctimeNsec, blocks, blksize
                    )
                }
                if (success) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddKstatStaticallyDialog()
            }
        },
        isLoading = uiState.isLoading,
        initialConfig = uiState.editingKstatConfig ?: ""
    )

    AddPathDialog(
        showDialog = uiState.showAddKstatDialog,
        onDismiss = { viewModel.closeAddKstatDialog() },
        onConfirm = { path ->
            val oldPath = uiState.editingKstatPath
            coroutineScope.launch {
                val success = if (oldPath != null) {
                    SuSFSManager.editAddKstat(context, oldPath, path)
                } else {
                    SuSFSManager.addKstat(context, path)
                }
                if (success) {
                    viewModel.reloadConfig(context)
                }
                viewModel.closeAddKstatDialog()
            }
        },
        isLoading = uiState.isLoading,
        titleRes = if (uiState.editingKstatPath != null) R.string.edit_kstat_path_title else R.string.add_kstat_path_title,
        labelRes = R.string.file_or_directory_path_label,
        initialValue = uiState.editingKstatPath ?: ""
    )

    // 确认对话框
    ConfirmDialog(
        showDialog = uiState.showConfirmReset,
        onDismiss = { viewModel.toggleConfirmReset(false) },
        onConfirm = {
            viewModel.resetAll(context)
        },
        titleRes = R.string.susfs_reset_confirm_title,
        messageRes = R.string.susfs_reset_confirm_title,
        isLoading = uiState.isLoading
    )

    // 重置对话框
    ConfirmDialog(
        showDialog = uiState.showResetPathsDialog,
        onDismiss = { viewModel.toggleResetPathsDialog(false) },
        onConfirm = {
            coroutineScope.launch {
                SuSFSManager.saveSusPaths(context, emptySet())
                if (SuSFSManager.isAutoStartEnabled(context)) {
                    SuSFSManager.configureAutoStart(context, true)
                }
                viewModel.reloadConfig(context)
                viewModel.toggleResetPathsDialog(false)
            }
        },
        titleRes = R.string.susfs_reset_paths_title,
        messageRes = R.string.susfs_reset_paths_message,
        isLoading = uiState.isLoading
    )

    ConfirmDialog(
        showDialog = uiState.showResetLoopPathsDialog,
        onDismiss = { viewModel.toggleResetLoopPathsDialog(false) },
        onConfirm = {
            coroutineScope.launch {
                SuSFSManager.saveSusLoopPaths(context, emptySet())
                if (SuSFSManager.isAutoStartEnabled(context)) {
                    SuSFSManager.configureAutoStart(context, true)
                }
                viewModel.reloadConfig(context)
                viewModel.toggleResetLoopPathsDialog(false)
            }
        },
        titleRes = R.string.susfs_reset_loop_paths_title,
        messageRes = R.string.susfs_reset_loop_paths_message,
        isLoading = uiState.isLoading
    )

    ConfirmDialog(
        showDialog = uiState.showResetSusMapsDialog,
        onDismiss = { viewModel.toggleResetSusMapsDialog(false) },
        onConfirm = {
            coroutineScope.launch {
                SuSFSManager.saveSusMaps(context, emptySet())
                if (SuSFSManager.isAutoStartEnabled(context)) {
                    SuSFSManager.configureAutoStart(context, true)
                }
                viewModel.reloadConfig(context)
                viewModel.toggleResetSusMapsDialog(false)
            }
        },
        titleRes = R.string.susfs_reset_sus_maps_title,
        messageRes = R.string.susfs_reset_sus_maps_message,
        isLoading = uiState.isLoading
    )


    ConfirmDialog(
        showDialog = uiState.showResetKstatDialog,
        onDismiss = { viewModel.toggleResetKstatDialog(false) },
        onConfirm = {
            coroutineScope.launch {
                SuSFSManager.saveKstatConfigs(context, emptySet())
                SuSFSManager.saveAddKstatPaths(context, emptySet())
                if (SuSFSManager.isAutoStartEnabled(context)) {
                    SuSFSManager.configureAutoStart(context, true)
                }
                viewModel.reloadConfig(context)
                viewModel.toggleResetKstatDialog(false)
            }
        },
        titleRes = R.string.reset_kstat_config_title,
        messageRes = R.string.reset_kstat_config_message,
        isLoading = uiState.isLoading
    )

    // 主界面布局
    Scaffold(
        topBar = {
            TopAppBar(
                modifier = Modifier.hazeEffect(hazeState) {
                    style = hazeStyle
                    blurRadius = 30.dp
                    noiseFactor = 0f
                },
                color = Color.Transparent,
                title = stringResource(R.string.susfs_config_title),
                navigationIcon = {
                    IconButton(onClick = {
                        if (!isNavigating) {
                            isNavigating = true
                            navigator.pop()
                        }
                    }) {
                        val layoutDirection = LocalLayoutDirection.current
                        Icon(
                            modifier = Modifier.graphicsLayer {
                                if (layoutDirection == LayoutDirection.Rtl) scaleX = -1f
                            },
                            imageVector = MiuixIcons.Back,
                            contentDescription = stringResource(R.string.log_viewer_back),
                            tint = colorScheme.onBackground
                        )
                    }
                },
                scrollBehavior = scrollBehavior
            )
        },
        popupHost = { },
        contentWindowInsets = WindowInsets.systemBars.add(WindowInsets.displayCutout).only(WindowInsetsSides.Horizontal)
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxHeight()
                .scrollEndHaptic()
                .overScrollVertical()
                .nestedScroll(scrollBehavior.nestedScrollConnection)
                .hazeSource(state = hazeState)
                .padding(horizontal = 12.dp),
            contentPadding = innerPadding,
            overscrollEffect = null,
        ) {
            item {
                // 标签页
                LazyRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    contentPadding = PaddingValues(vertical = 8.dp)
                ) {
                    items(allTabs.size) { index ->
                        val tab = allTabs[index]
                        val isSelected = uiState.selectedTab == tab
                        Card(
                            modifier = Modifier
                                .clickable { viewModel.setSelectedTab(tab) },
                            colors = CardDefaults.defaultColors(
                                if (isSelected) {
                                    colorScheme.primaryContainer
                                } else {
                                    colorScheme.surfaceVariant.copy(alpha = 0.3f)
                                }
                            ),
                            cornerRadius = 8.dp
                        ) {
                            Text(
                                text = stringResource(tab.displayNameRes),
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                                style = MiuixTheme.textStyles.body1,
                                fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal,
                                color = if (isSelected) {
                                    colorScheme.onPrimaryContainer
                                } else {
                                    colorScheme.onSurfaceVariantSummary
                                }
                            )
                        }
                    }
                }

            }

            item {
                Spacer(modifier = Modifier.height(12.dp))

                // 标签页内容
                when (uiState.selectedTab) {
                    SuSFSTab.BASIC_SETTINGS -> {
                        BasicSettingsContent(
                            unameValue = uiState.unameValue,
                            onUnameValueChange = { value -> viewModel.updateUname(value) },
                            buildTimeValue = uiState.buildTimeValue,
                            onBuildTimeValueChange = { value -> viewModel.updateBuildTime(value) },
                            executeInPostFsData = uiState.executeInPostFsData,
                            onExecuteInPostFsDataChange = { value -> viewModel.setExecuteInPostFsData(value) },
                            autoStartEnabled = uiState.autoStartEnabled,
                            canEnableAutoStart = uiState.canEnableAutoStart,
                            isLoading = uiState.isLoading,
                            onAutoStartToggle = { enabled: Boolean ->
                                viewModel.configureAutoStart(context, enabled)
                            },
                            onShowSlotInfo = {
                                viewModel.showSlotInfoDialog(true)
                                viewModel.loadSlotInfo(context)
                            },
                            context = context,
                            enableHideBl = uiState.enableHideBl,
                            onEnableHideBlChange = { enabled: Boolean ->
                                viewModel.setEnableHideBl(context, enabled)
                            },
                            enableCleanupResidue = uiState.enableCleanupResidue,
                            onEnableCleanupResidueChange = { enabled: Boolean ->
                                viewModel.setEnableCleanupResidue(context, enabled)
                            },
                            enableAvcLogSpoofing = uiState.enableAvcLogSpoofing,
                            onEnableAvcLogSpoofingChange = { enabled: Boolean ->
                                viewModel.setEnableAvcLogSpoofing(context, enabled)
                            },
                            hideSusMountsForAllProcs = uiState.hideSusMountsForAllProcs,
                            onHideSusMountsForAllProcsChange = { hideForAll: Boolean ->
                                viewModel.setHideSusMountsForAllProcs(context, hideForAll)
                            },
                            onReset = { viewModel.toggleConfirmReset(true) },
                            onApply = { viewModel.applyBasicSettings(context) },
                            onConfigReload = {
                                viewModel.reloadConfig(context)
                            }
                        )
                    }
                    SuSFSTab.SUS_PATHS -> {
                        SusPathsContent(
                            susPaths = uiState.susPaths,
                            isLoading = uiState.isLoading,
                            onAddPath = { viewModel.openAddPathDialog() },
                            onAddAppPath = {
                                viewModel.openAddAppPathDialog()
                                viewModel.loadInstalledApps()
                            },
                            onRemovePath = { path ->
                                coroutineScope.launch {
                                    if (SuSFSManager.removeSusPath(context, path)) {
                                        viewModel.reloadConfig(context)
                                    }
                                }
                            },
                            onEditPath = { path ->
                                viewModel.openAddPathDialog(path)
                            },
                            forceRefreshApps = uiState.selectedTab == SuSFSTab.SUS_PATHS,
                            onReset = { viewModel.toggleResetPathsDialog(true) }
                        )
                    }
                    SuSFSTab.SUS_LOOP_PATHS -> {
                        SusLoopPathsContent(
                            susLoopPaths = uiState.susLoopPaths,
                            isLoading = uiState.isLoading,
                            onAddLoopPath = { viewModel.openAddLoopPathDialog() },
                            onRemoveLoopPath = { path ->
                                coroutineScope.launch {
                                    if (SuSFSManager.removeSusLoopPath(context, path)) {
                                        viewModel.reloadConfig(context)
                                    }
                                }
                            },
                            onEditLoopPath = { path ->
                                viewModel.openAddLoopPathDialog(path)
                            },
                            onReset = { viewModel.toggleResetLoopPathsDialog(true) }
                        )
                    }
                    SuSFSTab.SUS_MAPS -> {
                        SusMapsContent(
                            susMaps = uiState.susMaps,
                            isLoading = uiState.isLoading,
                            onAddSusMap = { viewModel.openAddSusMapDialog() },
                            onRemoveSusMap = { map ->
                                coroutineScope.launch {
                                    if (SuSFSManager.removeSusMap(context, map)) {
                                        viewModel.reloadConfig(context)
                                    }
                                }
                            },
                            onEditSusMap = { map ->
                                viewModel.openAddSusMapDialog(map)
                            },
                            onReset = { viewModel.toggleResetSusMapsDialog(true) }
                        )
                    }
                    SuSFSTab.KSTAT_CONFIG -> {
                        KstatConfigContent(
                            kstatConfigs = uiState.kstatConfigs,
                            addKstatPaths = uiState.addKstatPaths,
                            isLoading = uiState.isLoading,
                            onAddKstatStatically = { viewModel.openAddKstatStaticallyDialog() },
                            onAddKstat = { viewModel.openAddKstatDialog() },
                            onRemoveKstatConfig = { config ->
                                coroutineScope.launch {
                                    if (SuSFSManager.removeKstatConfig(context, config)) {
                                        viewModel.reloadConfig(context)
                                    }
                                }
                            },
                            onEditKstatConfig = { config ->
                                viewModel.openAddKstatStaticallyDialog(config)
                            },
                            onRemoveAddKstat = { path ->
                                coroutineScope.launch {
                                    if (SuSFSManager.removeAddKstat(context, path)) {
                                        viewModel.reloadConfig(context)
                                    }
                                }
                            },
                            onEditAddKstat = { path ->
                                viewModel.openAddKstatDialog(path)
                            },
                            onUpdateKstat = { path ->
                                coroutineScope.launch {
                                    SuSFSManager.updateKstat(context, path)
                                }
                            },
                            onUpdateKstatFullClone = { path ->
                                coroutineScope.launch {
                                    SuSFSManager.updateKstatFullClone(context, path)
                                }
                            }
                        )
                    }
                    SuSFSTab.ENABLED_FEATURES -> {
                        EnabledFeaturesContent(
                            enabledFeatures = uiState.enabledFeatures,
                            onRefresh = { viewModel.loadEnabledFeatures(context) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun SlotInfoDialog(
    showDialog: Boolean,
    onDismiss: () -> Unit,
    slotInfoList: List<SuSFSManager.SlotInfo>,
    currentActiveSlot: String,
    isLoadingSlotInfo: Boolean,
    onRefresh: () -> Unit,
    onUseUname: (String) -> Unit,
    onUseBuildTime: (String) -> Unit
) {
    val isAbDevice = produceState(initialValue = false) {
        value = isAbDevice()
    }.value

    val showDialogState = remember { mutableStateOf(showDialog && isAbDevice) }
    
    LaunchedEffect(showDialog, isAbDevice) {
        showDialogState.value = showDialog && isAbDevice
    }

    if (showDialogState.value) {
        SuperDialog(
            show = showDialogState,
            title = stringResource(R.string.susfs_slot_info_title),
            onDismissRequest = onDismiss,
            content = {
                Column(
                    modifier = Modifier.padding(horizontal = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = stringResource(R.string.susfs_current_active_slot, currentActiveSlot),
                        style = MiuixTheme.textStyles.body2,
                        fontWeight = FontWeight.Medium,
                        color = colorScheme.primary
                    )

                    if (slotInfoList.isNotEmpty()) {
                        slotInfoList.forEach { slotInfo ->
                            Card(
                                modifier = Modifier.fillMaxWidth(),
                                colors = CardDefaults.defaultColors(
                                    if (slotInfo.slotName == currentActiveSlot) {
                                        colorScheme.primary.copy(alpha = 0.1f)
                                    } else {
                                        colorScheme.surface.copy(alpha = 0.5f)
                                    }
                                ),
                                cornerRadius = 8.dp
                            ) {
                                Column(
                                    modifier = Modifier.padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp)
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Storage,
                                            contentDescription = null,
                                            tint = if (slotInfo.slotName == currentActiveSlot) {
                                                colorScheme.primary
                                            } else {
                                                colorScheme.onSurface
                                            },
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(
                                            text = slotInfo.slotName,
                                            style = MiuixTheme.textStyles.body1,
                                            fontWeight = FontWeight.Bold,
                                            color = if (slotInfo.slotName == currentActiveSlot) {
                                                colorScheme.primary
                                            } else {
                                                colorScheme.onSurface
                                            }
                                        )
                                        if (slotInfo.slotName == currentActiveSlot) {
                                            Spacer(modifier = Modifier.width(6.dp))
                                            Box(
                                                modifier = Modifier
                                                    .background(
                                                        color = colorScheme.primary,
                                                        shape = RoundedCornerShape(4.dp)
                                                    )
                                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                                            ) {
                                                Text(
                                                    text = stringResource(R.string.susfs_slot_current_badge),
                                                    style = MiuixTheme.textStyles.body2,
                                                    color = colorScheme.onPrimary
                                                )
                                            }
                                        }
                                    }
                                    Text(
                                        text = stringResource(R.string.susfs_slot_uname, slotInfo.uname),
                                        style = MiuixTheme.textStyles.body2.copy(fontSize = 13.sp),
                                        color = colorScheme.onSurface
                                    )
                                    Text(
                                        text = stringResource(R.string.susfs_slot_build_time, slotInfo.buildTime),
                                        style = MiuixTheme.textStyles.body2.copy(fontSize = 13.sp),
                                        color = colorScheme.onSurface
                                    )

                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                                    ) {
                                        Button(
                                            onClick = { onUseUname(slotInfo.uname) },
                                            modifier = Modifier
                                                .weight(1f)
                                                .heightIn(min = 48.dp)
                                                .padding(vertical = 8.dp),
                                            cornerRadius = 8.dp
                                        ) {
                                            Text(
                                                text = stringResource(R.string.susfs_slot_use_uname),
                                                style = MiuixTheme.textStyles.body2,
                                                maxLines = 2
                                            )
                                        }
                                        Button(
                                            onClick = { onUseBuildTime(slotInfo.buildTime) },
                                            modifier = Modifier
                                                .weight(1f)
                                                .heightIn(min = 48.dp)
                                                .padding(vertical = 8.dp),
                                            cornerRadius = 8.dp
                                        ) {
                                            Text(
                                                text = stringResource(R.string.susfs_slot_use_build_time),
                                                style = MiuixTheme.textStyles.body2,
                                                maxLines = 2
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Text(
                            text = stringResource(R.string.susfs_slot_info_unavailable),
                            style = MiuixTheme.textStyles.body2,
                            color = colorScheme.error
                        )
                    }
                    
                    Spacer(modifier = Modifier.height(12.dp))
                    
                    Button(
                        onClick = onRefresh,
                        enabled = !isLoadingSlotInfo,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .padding(vertical = 8.dp),
                        cornerRadius = 8.dp
                    ) {
                        Text(
                            text = stringResource(R.string.refresh)
                        )
                    }

                    Button(
                        onClick = onDismiss,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .padding(vertical = 8.dp),
                        cornerRadius = 8.dp
                    ) {
                        Text(
                            text = stringResource(android.R.string.cancel)
                        )
                    }
                }
            }
        )
    }
}