package com.sukisu.ultra.ui.screen.kpm

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.dialog.ConfirmDialogHandle
import com.sukisu.ultra.ui.component.dialog.ConfirmResult
import com.sukisu.ultra.ui.component.dialog.rememberConfirmDialog
import com.sukisu.ultra.ui.util.*
import com.sukisu.ultra.ui.viewmodel.KpmViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import top.yukonga.miuix.kmp.basic.TextButton
import java.io.File
import java.net.URLEncoder

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun KpmMaterial(
    viewModel: KpmViewModel = viewModel(),
    bottomInnerPadding: Dp = 0.dp
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val confirmDialog = rememberConfirmDialog()

    val uiState by viewModel.uiState.collectAsState()
    val searchStatus = uiState.searchStatus

    val listState = rememberLazyListState()

    val showEmptyState by remember {
        derivedStateOf {
            uiState.moduleList.isEmpty() && searchStatus.searchText.isEmpty() && !uiState.isRefreshing
        }
    }

    val moduleConfirmContentMap = uiState.moduleList.associate { module ->
        module.id to stringResource(R.string.confirm_uninstall_content, module.id)
    }

    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())

    LaunchedEffect(searchStatus.searchText) {
        viewModel.updateSearchText(searchStatus.searchText)
    }

    val kpmInstallSuccess = stringResource(R.string.kpm_install_success)
    val kpmInstallFailed = stringResource(R.string.kpm_install_failed)
    val cancel = stringResource(R.string.cancel)
    val uninstall = stringResource(R.string.uninstall)
    val failedToCheckModuleFile = stringResource(R.string.snackbar_failed_to_check_module_file)
    val kpmUninstallSuccess = stringResource(R.string.kpm_uninstall_success)
    val kpmUninstallFailed = stringResource(R.string.kpm_uninstall_failed)
    val kpmInstallMode = stringResource(R.string.kpm_install_mode)
    val kpmInstallModeLoad = stringResource(R.string.kpm_install_mode_load)
    val kpmInstallModeEmbed = stringResource(R.string.kpm_install_mode_embed)
    val invalidFileTypeMessage = stringResource(R.string.invalid_file_type)
    val confirmTitle = stringResource(R.string.confirm_uninstall_title_with_filename)

    val showToast: suspend (String) -> Unit = { msg ->
        scope.launch(Dispatchers.Main) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
        }
    }

    var tempFileForInstall by remember { mutableStateOf<File?>(null) }
    var showInstallModeDialog by remember { mutableStateOf(false) }
    val showInstallDialogState = remember { mutableStateOf(false) }
    var moduleName by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(tempFileForInstall) {
        moduleName = tempFileForInstall?.let { extractModuleName(it) }
    }

    LaunchedEffect(showInstallModeDialog) {
        showInstallDialogState.value = showInstallModeDialog
    }

    fun clearInstallState() {
        runCatching {
            showInstallDialogState.value = false
            showInstallModeDialog = false
            runCatching { tempFileForInstall?.delete() }
            tempFileForInstall = null
            moduleName = null
        }.onFailure {
            Log.e("KsuCli", "clearInstallState: ${it.message}", it)
        }
    }

    if (showInstallModeDialog) {
        AlertDialog(
            onDismissRequest = { clearInstallState() },
            title = { Text(kpmInstallMode) },
            text = {
                Column {
                    moduleName?.let {
                        Text(text = stringResource(R.string.kpm_install_mode_description, it))
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Button(
                            onClick = {
                                scope.launch {
                                    val tempFile = tempFileForInstall
                                    tempFile?.let {
                                        handleModuleInstall(
                                            tempFile = it,
                                            isEmbed = false,
                                            viewModel = viewModel,
                                            showToast = showToast,
                                            kpmInstallSuccess = kpmInstallSuccess,
                                            kpmInstallFailed = kpmInstallFailed
                                        )
                                    }
                                    clearInstallState()
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Download,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(kpmInstallModeLoad)
                        }

                        Button(
                            onClick = {
                                scope.launch {
                                    val tempFile = tempFileForInstall
                                    tempFile?.let {
                                        handleModuleInstall(
                                            tempFile = it,
                                            isEmbed = true,
                                            viewModel = viewModel,
                                            showToast = showToast,
                                            kpmInstallSuccess = kpmInstallSuccess,
                                            kpmInstallFailed = kpmInstallFailed
                                        )
                                    }
                                    clearInstallState()
                                }
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Icon(
                                imageVector = Icons.Filled.Inventory,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(kpmInstallModeEmbed)
                        }
                    }
                    Spacer(modifier = Modifier.height(16.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        TextButton(
                            text = cancel,
                            onClick = {
                                clearInstallState()
                            },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = {}
        )
    }

    val selectPatchLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult

        val uri = result.data?.data ?: return@rememberLauncherForActivityResult

        scope.launch {
            val fileName = uri.lastPathSegment ?: "unknown.kpm"
            val encodedFileName = URLEncoder.encode(fileName, "UTF-8")
            val tempFile = File(context.cacheDir, encodedFileName)

            context.contentResolver.openInputStream(uri)?.use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }

            if (!isValidKpmFile(tempFile, context.contentResolver.getType(uri))) {
                showToast(invalidFileTypeMessage)
                tempFile.delete()
                return@launch
            }

            tempFileForInstall = tempFile
            showInstallModeDialog = true
        }
    }

    LaunchedEffect(Unit) {
        while(true) {
            viewModel.fetchModuleList()
            delay(5000)
        }
    }

    val scrollDistance = remember { mutableFloatStateOf(0f) }
    var fabVisible by remember { mutableStateOf(true) }

    val nestedScrollConnection = remember(listState) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (isScrolledToEnd(listState)) return Offset.Zero

                scrollDistance.floatValue += available.y

                if (scrollDistance.floatValue <= -50f && fabVisible) {
                    fabVisible = false
                    scrollDistance.floatValue = 0f
                    return Offset(0f, available.y)
                }

                if (scrollDistance.floatValue >= 50f && !fabVisible) {
                    fabVisible = true
                    scrollDistance.floatValue = 0f
                    return Offset(0f, available.y)
                }

                return Offset.Zero
            }
        }
    }
    val offsetHeight by animateDpAsState(
        targetValue = if (fabVisible) 0.dp else 180.dp + WindowInsets.systemBars.asPaddingValues().calculateBottomPadding(),
        animationSpec = tween(durationMillis = 350)
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.kpm_title)) },
                actions = {
                    IconButton(
                        onClick = { viewModel.fetchModuleList() }
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Refresh,
                            contentDescription = stringResource(R.string.refresh),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        floatingActionButton = {
            AnimatedVisibility(visible = fabVisible) {
                FloatingActionButton(
                    modifier = Modifier
                        .offset(y = offsetHeight)
                        .padding(bottom = bottomInnerPadding + 20.dp, end = 20.dp),
                    onClick = {
                        selectPatchLauncher.launch(
                            Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "application/octet-stream"
                            }
                        )
                    },
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    contentColor = MaterialTheme.colorScheme.onPrimaryContainer
                ) {
                    Icon(
                        painter = painterResource(id = R.drawable.package_import),
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(40.dp)
                    )
                }
            }
        },
        contentWindowInsets = WindowInsets.systemBars.only(WindowInsetsSides.Horizontal)
    ) { innerPadding ->
        val layoutDirection = LocalLayoutDirection.current

        if (showEmptyState) {
            EmptyStateViewMaterial(
                innerPadding = innerPadding,
                bottomInnerPadding = bottomInnerPadding,
                layoutDirection = layoutDirection
            )
        } else {
            KpmListMaterial(
                viewModel = viewModel,
                scope = scope,
                moduleConfirmContentMap = moduleConfirmContentMap,
                showToast = showToast,
                kpmUninstallSuccess = kpmUninstallSuccess,
                kpmUninstallFailed = kpmUninstallFailed,
                failedToCheckModuleFile = failedToCheckModuleFile,
                uninstall = uninstall,
                cancel = cancel,
                confirmDialog = confirmDialog,
                confirmTitle = confirmTitle,
                scrollBehavior = scrollBehavior,
                nestedScrollConnection = nestedScrollConnection,
                innerPadding = innerPadding,
                bottomInnerPadding = bottomInnerPadding,
                layoutDirection = layoutDirection
            )
        }
    }
}

private suspend fun handleModuleInstall(
    tempFile: File,
    isEmbed: Boolean,
    viewModel: KpmViewModel,
    showToast: suspend (String) -> Unit,
    kpmInstallSuccess: String,
    kpmInstallFailed: String
) {
    val moduleId = extractModuleName(tempFile)
    if (moduleId.isNullOrEmpty()) {
        Log.e("KsuCli", "Failed to extract module ID from file: ${tempFile.name}")
        showToast(kpmInstallFailed)
        tempFile.delete()
        return
    }

    val targetPath = "/data/adb/kpm/$moduleId.kpm"

    try {
        if (isEmbed) {
            val shell = getRootShell()
            shell.newJob().add("mkdir -p /data/adb/kpm").exec()
            shell.newJob().add("cp ${tempFile.absolutePath} $targetPath").exec()
        }

        val loadResult = loadKpmModule(tempFile.absolutePath)
        if (!loadResult) {
            Log.e("KsuCli", "Failed to load KPM module")
            showToast(kpmInstallFailed)
        } else {
            viewModel.fetchModuleList()
            showToast(kpmInstallSuccess)
        }
    } catch (e: Exception) {
        Log.e("KsuCli", "Failed to load KPM module: ${e.message}", e)
        showToast(kpmInstallFailed)
    }
    tempFile.delete()
}

private suspend fun handleModuleUninstall(
    module: KpmViewModel.ModuleInfo,
    viewModel: KpmViewModel,
    showToast: suspend (String) -> Unit,
    kpmUninstallSuccess: String,
    kpmUninstallFailed: String,
    failedToCheckModuleFile: String,
    uninstall: String,
    cancel: String,
    confirmTitle : String,
    confirmContent : String,
    confirmDialog: ConfirmDialogHandle
) {
    val moduleFileName = "${module.id}.kpm"
    val moduleFilePath = "/data/adb/kpm/$moduleFileName"

    val fileExists = try {
        val shell = getRootShell()
        val result = shell.newJob().add("ls /data/adb/kpm/$moduleFileName").exec()
        result.isSuccess
    } catch (e: Exception) {
        Log.e("KsuCli", "Failed to check module file existence: ${e.message}", e)
        showToast(failedToCheckModuleFile)
        false
    }

    val confirmResult = confirmDialog.awaitConfirm(
        title = confirmTitle,
        content = confirmContent,
        confirm = uninstall,
        dismiss = cancel
    )

    if (confirmResult == ConfirmResult.Confirmed) {
        try {
            val unloadResult = unloadKpmModule(module.id)
            if (!unloadResult) {
                Log.e("KsuCli", "Failed to unload KPM module")
                showToast(kpmUninstallFailed)
                return
            }

            if (fileExists) {
                val shell = getRootShell()
                shell.newJob().add("rm $moduleFilePath").exec()
            }

            viewModel.fetchModuleList()
            showToast(kpmUninstallSuccess)
        } catch (e: Exception) {
            Log.e("KsuCli", "Failed to unload KPM module: ${e.message}", e)
            showToast(kpmUninstallFailed)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun KpmListMaterial(
    viewModel: KpmViewModel,
    scope: CoroutineScope,
    moduleConfirmContentMap: Map<String, String>,
    showToast: suspend (String) -> Unit,
    kpmUninstallSuccess: String,
    kpmUninstallFailed: String,
    failedToCheckModuleFile: String,
    uninstall: String,
    cancel: String,
    confirmDialog: ConfirmDialogHandle,
    confirmTitle: String,
    scrollBehavior: TopAppBarScrollBehavior,
    nestedScrollConnection: NestedScrollConnection,
    innerPadding: PaddingValues,
    bottomInnerPadding: Dp,
    layoutDirection: LayoutDirection
) {
    val context = LocalContext.current
    val sharedPreferences = context.getSharedPreferences("app_preferences", Context.MODE_PRIVATE)
    var isNoticeClosed by remember { mutableStateOf(sharedPreferences.getBoolean("is_notice_closed", false)) }

    val uiState by viewModel.uiState.collectAsState()

    var isRefreshing by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(isRefreshing) {
        if (isRefreshing) {
            delay(350)
            viewModel.fetchModuleList()
            isRefreshing = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(innerPadding)
    ) {
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = { if (!isRefreshing) isRefreshing = true },
            modifier = Modifier.fillMaxSize()
        ) {
            LazyColumn(
                modifier = Modifier
                    .fillMaxHeight()
                    .nestedScroll(scrollBehavior.nestedScrollConnection)
                    .nestedScroll(nestedScrollConnection),
                contentPadding = PaddingValues(
                    start = innerPadding.calculateStartPadding(layoutDirection),
                    end = innerPadding.calculateEndPadding(layoutDirection),
                ),
            ) {
                if (!isNoticeClosed) {
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 12.dp)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Info,
                                    contentDescription = null,
                                    modifier = Modifier
                                        .padding(end = 16.dp)
                                        .size(24.dp),
                                    tint = MaterialTheme.colorScheme.onSurface
                                )

                                Text(
                                    text = stringResource(R.string.kernel_module_notice),
                                    modifier = Modifier.weight(1f),
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                IconButton(
                                    onClick = {
                                        isNoticeClosed = true
                                        sharedPreferences.edit { putBoolean("is_notice_closed", true) }
                                    },
                                    modifier = Modifier.size(24.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.Close,
                                        contentDescription = stringResource(R.string.close_notice),
                                        tint = MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                        }
                    }
                }

                items(uiState.moduleList) { module ->
                    KpmModuleItemMaterial(
                        module = module,
                        viewModel = viewModel,
                        onUninstall = {
                            scope.launch {
                                val confirmContent = moduleConfirmContentMap[module.id] ?: ""
                                handleModuleUninstall(
                                    module = module,
                                    viewModel = viewModel,
                                    showToast = showToast,
                                    kpmUninstallSuccess = kpmUninstallSuccess,
                                    kpmUninstallFailed = kpmUninstallFailed,
                                    failedToCheckModuleFile = failedToCheckModuleFile,
                                    uninstall = uninstall,
                                    cancel = cancel,
                                    confirmDialog = confirmDialog,
                                    confirmTitle = confirmTitle,
                                    confirmContent = confirmContent
                                )
                            }
                        }
                    )
                }
                item {
                    Spacer(Modifier.height(bottomInnerPadding))
                }
            }
        }
    }
}

@Composable
private fun KpmModuleItemMaterial(
    module: KpmViewModel.ModuleInfo,
    viewModel: KpmViewModel,
    onUninstall: () -> Unit
) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val successMessage = stringResource(R.string.kpm_control_success)
    val failureMessage = stringResource(R.string.kpm_control_failed)

    val showToast: suspend (String) -> Unit = { msg ->
        scope.launch(Dispatchers.Main) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
        }
    }

    val showInputDialog = viewModel.showInputDialog && viewModel.selectedModuleId == module.id
    val showDialogState = remember { mutableStateOf(false) }

    LaunchedEffect(viewModel.showInputDialog, viewModel.selectedModuleId) {
        showDialogState.value = viewModel.showInputDialog && viewModel.selectedModuleId == module.id
    }

    if (showInputDialog) {
        AlertDialog(
            onDismissRequest = {
                showDialogState.value = false
                viewModel.hideInputDialog()
            },
            title = { Text(stringResource(R.string.kpm_control)) },
            text = {
                Column {
                    OutlinedTextField(
                        value = viewModel.inputArgs,
                        onValueChange = { viewModel.updateInputArgs(it) },
                        label = { Text(stringResource(R.string.kpm_args)) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    if (viewModel.inputArgs.isEmpty() && module.args.isNotEmpty()) {
                        Text(
                            text = module.args,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            fontSize = MaterialTheme.typography.bodySmall.fontSize,
                            modifier = Modifier.padding(start = 16.dp, top = 4.dp)
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        TextButton(
                            onClick = {
                                showDialogState.value = false
                                viewModel.hideInputDialog()
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.cancel))
                        }
                        Spacer(modifier = Modifier.width(20.dp))
                        Button(
                            onClick = {
                                scope.launch {
                                    val result = viewModel.executeControl()
                                    val message = when (result) {
                                        0 -> successMessage
                                        else -> failureMessage
                                    }
                                    showToast(message)
                                    showDialogState.value = false
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) {
                            Text(stringResource(R.string.confirm))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {}
        )
    }

    Card(
        modifier = Modifier
            .padding(horizontal = 12.dp)
            .padding(bottom = 12.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(
                    modifier = Modifier.weight(1f)
                ) {
                    Text(
                        text = module.name,
                        fontSize = 17.sp,
                        fontWeight = FontWeight(550),
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = "${stringResource(R.string.kpm_version)}: ${module.version}",
                        fontSize = 12.sp,
                        modifier = Modifier.padding(top = 2.dp),
                        fontWeight = FontWeight(550),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = "${stringResource(R.string.kpm_author)}: ${module.author}",
                        fontSize = 12.sp,
                        modifier = Modifier.padding(bottom = 1.dp),
                        fontWeight = FontWeight(550),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (module.args.isNotEmpty()) {
                        Text(
                            text = "${stringResource(R.string.kpm_args)}: ${module.args}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight(550),
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            if (module.description.isNotBlank()) {
                Text(
                    text = module.description,
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp),
                    overflow = TextOverflow.Ellipsis,
                    maxLines = 4
                )
            }

            HorizontalDivider(
                modifier = Modifier.padding(vertical = 8.dp),
                thickness = 0.5.dp,
            )

            Row {
                AnimatedVisibility(
                    visible = module.hasAction,
                    enter = fadeIn(),
                    exit = fadeOut()
                ) {
                    IconButton(
                        onClick = {
                            viewModel.showInputDialog(module.id)
                        },
                    ) {
                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = stringResource(R.string.kpm_control),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    }
                }

                Spacer(Modifier.weight(1f))

                Button(
                    onClick = onUninstall,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Delete,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(stringResource(R.string.kpm_uninstall))
                }
            }
        }
    }
}

@Composable
private fun EmptyStateViewMaterial(
    innerPadding: PaddingValues,
    bottomInnerPadding: Dp,
    layoutDirection: LayoutDirection
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(
                top = innerPadding.calculateTopPadding(),
                start = innerPadding.calculateStartPadding(layoutDirection),
                end = innerPadding.calculateEndPadding(layoutDirection),
                bottom = bottomInnerPadding
            ),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Code,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f),
                modifier = Modifier
                    .size(96.dp)
                    .padding(bottom = 16.dp)
            )
            Text(
                stringResource(R.string.kpm_empty),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurface
            )
        }
    }
}
