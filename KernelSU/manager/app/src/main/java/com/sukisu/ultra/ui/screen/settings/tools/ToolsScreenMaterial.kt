package com.sukisu.ultra.ui.screen.settings.tools

import android.content.Context
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.add
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.FolderDelete
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Security
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.KsuIsValid
import com.sukisu.ultra.ui.component.material.SegmentedColumn
import com.sukisu.ultra.ui.component.material.SegmentedListItem
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.navigation3.Route
import com.sukisu.ultra.ui.util.getSELinuxStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ToolsMaterial() {
    val navigator = LocalNavigator.current
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.tools)) },
                scrollBehavior = scrollBehavior,
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        contentWindowInsets = WindowInsets.systemBars.add(WindowInsets.displayCutout).only(WindowInsetsSides.Horizontal)
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxHeight()
                .nestedScroll(scrollBehavior.nestedScrollConnection)
                .padding(horizontal = 16.dp),
            contentPadding = innerPadding,
        ) {
            item {
                KsuIsValid {
                    SelinuxToggleSectionMaterial(scope = scope, context = context)

                    SegmentedColumn(
                        modifier = Modifier.padding(top = 12.dp),
                        content = listOf(
                            {
                                val umontManager = stringResource(id = R.string.umount_path_manager)
                                SegmentedListItem(
                                    onClick = { navigator.push(Route.UmountManager) },
                                    headlineContent = { Text(umontManager) },
                                    leadingContent = {
                                        Icon(
                                            Icons.Rounded.FolderDelete,
                                            umontManager,
                                            tint = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                )
                            }
                        )
                    )

                    AllowlistBackupSectionMaterial(scope = scope, context = context)
                }
            }
        }
    }
}

@Composable
fun SelinuxToggleSectionMaterial(
    scope: CoroutineScope,
    context: Context
) {
    var selinuxEnforcing by remember { mutableStateOf(true) }
    var selinuxLoading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        val current = withContext(Dispatchers.IO) { !isSelinuxPermissive() }
        selinuxEnforcing = current
        selinuxLoading = false
    }

    SegmentedColumn(
        modifier = Modifier.padding(top = 12.dp),
        content = listOf(
            {
                val statusLabel = getSELinuxStatus()
                SegmentedListItem(
                    headlineContent = { Text(stringResource(R.string.tools_selinux_toggle)) },
                    supportingContent = { Text(stringResource(R.string.tools_selinux_summary, statusLabel)) },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Rounded.Security,
                            contentDescription = stringResource(id = R.string.tools_selinux_toggle),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    },
                    trailingContent = {
                        Switch(
                            checked = selinuxEnforcing,
                            enabled = !selinuxLoading,
                            onCheckedChange = { target ->
                                selinuxLoading = true
                                scope.launch(Dispatchers.IO) {
                                    val success = if (target) {
                                        setSelinuxPermissive(false)
                                    } else {
                                        setSelinuxPermissive(true)
                                    }
                                    val actual = !isSelinuxPermissive()
                                    withContext(Dispatchers.Main) {
                                        selinuxEnforcing = actual
                                        selinuxLoading = false
                                        Toast.makeText(
                                            context,
                                            if (success && actual == target) {
                                                context.getString(
                                                    R.string.tools_selinux_apply_success,
                                                    context.getString(
                                                        if (actual) {
                                                            R.string.selinux_status_enforcing
                                                        } else {
                                                            R.string.selinux_status_permissive
                                                        }
                                                    )
                                                )
                                            } else {
                                                context.getString(R.string.tools_selinux_apply_failed)
                                            },
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    }
                                }
                            }
                        )
                    }
                )
            }
        )
    )
}

@Composable
private fun AllowlistBackupSectionMaterial(
    scope: CoroutineScope,
    context: Context
) {
    val contextRef = remember { context }

    val backupLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        if (uri == null) {
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            val success = backupAllowlistToUri(contextRef, uri)
            Toast.makeText(
                contextRef,
                contextRef.getString(
                    if (success) {
                        R.string.allowlist_backup_success
                    } else {
                        R.string.allowlist_backup_failed
                    }
                ),
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    val restoreLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) {
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            val success = restoreAllowlistFromUri(contextRef, uri)
            Toast.makeText(
                contextRef,
                contextRef.getString(
                    if (success) {
                        R.string.allowlist_restore_success
                    } else {
                        R.string.allowlist_restore_failed
                    }
                ),
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    SegmentedColumn(
        modifier = Modifier.padding(vertical = 12.dp),
        content = listOf(
            {
                SegmentedListItem(
                    headlineContent = { Text(stringResource(R.string.allowlist_backup_title)) },
                    supportingContent = { Text(stringResource(R.string.allowlist_backup_summary_picker)) },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Rounded.Backup,
                            contentDescription = stringResource(R.string.allowlist_backup_title),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    },
                    onClick = {
                        backupLauncher.launch("ksu_allowlist_backup.bin")
                    }
                )
            },
            {
                SegmentedListItem(
                    headlineContent = { Text(stringResource(R.string.allowlist_restore_title)) },
                    supportingContent = { Text(stringResource(R.string.allowlist_restore_summary_picker)) },
                    leadingContent = {
                        Icon(
                            imageVector = Icons.Rounded.Restore,
                            contentDescription = stringResource(R.string.allowlist_restore_title),
                            tint = MaterialTheme.colorScheme.onSurface
                        )
                    },
                    onClick = {
                        restoreLauncher.launch(arrayOf("*/*"))
                    }
                )
            }
        )
    )
}
