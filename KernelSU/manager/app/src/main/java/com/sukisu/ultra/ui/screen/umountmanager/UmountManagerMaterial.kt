package com.sukisu.ultra.ui.screen.umountmanager

import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.dialog.ConfirmResult
import com.sukisu.ultra.ui.component.dialog.rememberConfirmDialog
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.util.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UmountManagerMaterial() {
    val navigator = LocalNavigator.current
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val confirmDialog = rememberConfirmDialog()

    var pathList by remember { mutableStateOf<List<UmountPathEntry>>(emptyList()) }
    var isLoading by remember { mutableStateOf(false) }
    var showAddDialog by remember { mutableStateOf(false) }

    val confirmActionText = stringResource(R.string.confirm_action)
    val umountPathRemovedText = stringResource(R.string.umount_path_removed)
    val confirmClearCustomPathsText = stringResource(R.string.confirm_clear_custom_paths)
    val customPathsClearedText = stringResource(R.string.custom_paths_cleared)
    val operationFailedText = stringResource(R.string.operation_failed)
    val configAppliedText = stringResource(R.string.config_applied)
    val umountPathAddedText = stringResource(R.string.umount_path_added)

    fun loadPaths() {
        scope.launch(Dispatchers.IO) {
            isLoading = true
            val result = listUmountPaths()
            val entries = parseUmountPaths(result)
            withContext(Dispatchers.Main) {
                pathList = entries
                isLoading = false
            }
        }
    }

    LaunchedEffect(Unit) {
        loadPaths()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.umount_path_manager)) },
                navigationIcon = {
                    IconButton(onClick = { navigator.pop() }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = null
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { loadPaths() }) {
                        Icon(
                            imageVector = Icons.Filled.Refresh,
                            contentDescription = null
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                ),
                scrollBehavior = scrollBehavior
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showAddDialog = true }
            ) {
                Icon(
                    imageVector = Icons.Rounded.Add,
                    contentDescription = null,
                    tint = Color.White
                )
            }
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .padding(paddingValues)
                .fillMaxHeight()
        ) {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(SPACING_LARGE)
            ) {
                Row(
                    modifier = Modifier.padding(SPACING_LARGE),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Info,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(SPACING_MEDIUM))
                    Text(
                        text = stringResource(R.string.umount_path_restart_notice)
                    )
                }
            }

            if (isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = SPACING_LARGE, vertical = SPACING_MEDIUM),
                    verticalArrangement = Arrangement.spacedBy(SPACING_MEDIUM)
                ) {
                    items(pathList, key = { it.path }) { entry ->
                        UmountPathCardMaterial(
                            entry = entry,
                            onDelete = {
                                scope.launch(Dispatchers.IO) {
                                    val success = removeUmountPath(entry.path)
                                    withContext(Dispatchers.Main) {
                                        if (success) {
                                            Toast.makeText(
                                                context,
                                                umountPathRemovedText,
                                                Toast.LENGTH_SHORT
                                            ).show()
                                            loadPaths()
                                        } else {
                                            Toast.makeText(
                                                context,
                                                operationFailedText,
                                                Toast.LENGTH_SHORT
                                            ).show()
                                        }
                                    }
                                }
                            }
                        )
                    }

                    item {
                        Spacer(modifier = Modifier.height(SPACING_LARGE))
                    }

                    item {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = SPACING_LARGE),
                            horizontalArrangement = Arrangement.spacedBy(SPACING_MEDIUM)
                        ) {
                            Button(
                                onClick = {
                                    scope.launch {
                                        if (confirmDialog.awaitConfirm(
                                                title = confirmActionText,
                                                content = confirmClearCustomPathsText
                                            ) == ConfirmResult.Confirmed) {
                                            withContext(Dispatchers.IO) {
                                                val success = clearCustomUmountPaths()
                                                withContext(Dispatchers.Main) {
                                                    if (success) {
                                                        Toast.makeText(
                                                            context,
                                                            customPathsClearedText,
                                                            Toast.LENGTH_SHORT
                                                        ).show()
                                                        loadPaths()
                                                    } else {
                                                        Toast.makeText(
                                                            context,
                                                            operationFailedText,
                                                            Toast.LENGTH_SHORT
                                                        ).show()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(text = stringResource(R.string.clear_custom_paths))
                            }

                            Button(
                                onClick = {
                                    scope.launch(Dispatchers.IO) {
                                        val success = applyUmountConfigToKernel()
                                        withContext(Dispatchers.Main) {
                                            if (success) {
                                                Toast.makeText(
                                                    context,
                                                    configAppliedText,
                                                    Toast.LENGTH_SHORT
                                                ).show()
                                            } else {
                                                Toast.makeText(
                                                    context,
                                                    operationFailedText,
                                                    Toast.LENGTH_SHORT
                                                ).show()
                                            }
                                        }
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            ) {
                                Text(text = stringResource(R.string.apply_config))
                            }
                        }
                    }
                }
            }
        }

        if (showAddDialog) {
            AddUmountPathDialogMaterial(
                onDismiss = { showAddDialog = false },
                onConfirm = { path, flags ->
                    showAddDialog = false

                    scope.launch(Dispatchers.IO) {
                        val success = addUmountPath(path, flags)
                        withContext(Dispatchers.Main) {
                            if (success) {
                                saveUmountConfig()
                                Toast.makeText(
                                    context,
                                    umountPathAddedText,
                                    Toast.LENGTH_SHORT
                                ).show()
                                loadPaths()
                            } else {
                                Toast.makeText(
                                    context,
                                    operationFailedText,
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                        }
                    }
                }
            )
        }
    }
}

@Composable
fun UmountPathCardMaterial(
    entry: UmountPathEntry,
    onDelete: () -> Unit
) {
    val confirmDialog = rememberConfirmDialog()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    val confirmDeleteText = stringResource(R.string.confirm_delete)
    val confirmDeleteUmountPathText = stringResource(R.string.confirm_delete_umount_path, entry.path)

    Card(
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(SPACING_LARGE),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Outlined.Folder,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )

            Spacer(modifier = Modifier.width(SPACING_LARGE))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = entry.path
                )
                Spacer(modifier = Modifier.height(SPACING_SMALL))
                Text(
                    text = buildString {
                        append(stringResource(R.string.flags))
                        append(": ")
                        append(entry.flags.toUmountFlagName(context))
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            IconButton(
                onClick = {
                    scope.launch {
                        if (confirmDialog.awaitConfirm(
                                title = confirmDeleteText,
                                content = confirmDeleteUmountPathText
                            ) == ConfirmResult.Confirmed) {
                            onDelete()
                        }
                    }
                }
            ) {
                Icon(
                    imageVector = Icons.Filled.Delete,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}

@Composable
fun AddUmountPathDialogMaterial(
    onDismiss: () -> Unit,
    onConfirm: (String, Int) -> Unit
) {
    var path by rememberSaveable { mutableStateOf("") }
    var flags by rememberSaveable { mutableStateOf("0") }
    val showDialog = remember { mutableStateOf(true) }

    AlertDialog(
        onDismissRequest = {
            showDialog.value = false
            onDismiss()
        },
        title = { Text(stringResource(R.string.add_umount_path)) },
        text = {
            Column {
                OutlinedTextField(
                    value = path,
                    onValueChange = { path = it },
                    label = { Text(stringResource(R.string.mount_path)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                Spacer(modifier = Modifier.height(SPACING_MEDIUM))

                OutlinedTextField(
                    value = flags,
                    onValueChange = { flags = it },
                    label = { Text(stringResource(R.string.umount_flags)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )

                Spacer(modifier = Modifier.height(SPACING_SMALL))

                Text(
                    text = stringResource(R.string.umount_flags_hint),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = SPACING_MEDIUM)
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val flagsInt = flags.toIntOrNull() ?: 0
                    showDialog.value = false
                    onConfirm(path, flagsInt)
                },
                enabled = path.isNotBlank()
            ) {
                Text(stringResource(android.R.string.ok))
            }
        },
        dismissButton = {
            TextButton(
                onClick = {
                    showDialog.value = false
                    onDismiss()
                }
            ) {
                Text(stringResource(android.R.string.cancel))
            }
        }
    )
}
