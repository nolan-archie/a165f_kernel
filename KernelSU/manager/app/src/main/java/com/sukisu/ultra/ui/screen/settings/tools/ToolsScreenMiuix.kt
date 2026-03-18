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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Backup
import androidx.compose.material.icons.rounded.FolderDelete
import androidx.compose.material.icons.rounded.Restore
import androidx.compose.material.icons.rounded.Security
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.KsuIsValid
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.navigation3.Route
import com.sukisu.ultra.ui.util.getSELinuxStatus
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.HazeTint
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.basic.IconButton
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuix.kmp.basic.Scaffold
import top.yukonga.miuix.kmp.basic.TopAppBar
import top.yukonga.miuix.kmp.extra.SuperArrow
import top.yukonga.miuix.kmp.extra.SuperSwitch
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Back
import top.yukonga.miuix.kmp.theme.MiuixTheme.colorScheme
import top.yukonga.miuix.kmp.utils.overScrollVertical
import top.yukonga.miuix.kmp.utils.scrollEndHaptic

@Composable
fun ToolsMiuix() {
    val navigator = LocalNavigator.current
    val scrollBehavior = MiuixScrollBehavior()
    val hazeState = remember { HazeState() }
    val hazeStyle = HazeStyle(
        backgroundColor = colorScheme.surface,
        tint = HazeTint(colorScheme.surface.copy(0.8f))
    )
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                modifier = Modifier.hazeEffect(hazeState) {
                    style = hazeStyle
                    blurRadius = 30.dp
                    noiseFactor = 0f
                },
                color = Color.Transparent,
                title = stringResource(R.string.tools),
                scrollBehavior = scrollBehavior,
                navigationIcon = {
                    IconButton(onClick = { navigator.pop() }) {
                        val layoutDirection = LocalLayoutDirection.current
                        Icon(
                            modifier = Modifier.graphicsLayer {
                                if (layoutDirection == LayoutDirection.Rtl) scaleX = -1f
                            },
                            imageVector = MiuixIcons.Back,
                            contentDescription = null
                        )
                    }
                }
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
                KsuIsValid {
                    SelinuxToggleSection(scope = scope, context = context)

                    Card(
                        modifier = Modifier
                            .padding(top = 12.dp)
                            .fillMaxWidth(),
                    ) {
                        val umontManager = stringResource(id = R.string.umount_path_manager)
                        SuperArrow(
                            title = umontManager,
                            startAction = {
                                Icon(
                                    Icons.Rounded.FolderDelete,
                                    modifier = Modifier.padding(end = 6.dp),
                                    contentDescription = umontManager,
                                    tint = colorScheme.onBackground
                                )
                            },
                            onClick = {
                                navigator.push(Route.UmountManager)
                            }
                        )
                    }
                    
                    AllowlistBackupSection(scope = scope, context = context)
                }
            }
        }
    }
}

@Composable
fun SelinuxToggleSection(
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

    Card(
        modifier = Modifier
            .padding(top = 12.dp)
            .fillMaxWidth(),
    ) {
        val statusLabel = getSELinuxStatus()
        SuperSwitch(
            title = stringResource(R.string.tools_selinux_toggle),
            summary = stringResource(
                R.string.tools_selinux_summary,
                statusLabel
            ),
            startAction = {
                Icon(
                    imageVector = Icons.Rounded.Security,
                    modifier = Modifier.padding(end = 6.dp),
                    contentDescription = stringResource(id = R.string.tools_selinux_toggle),
                    tint = colorScheme.onBackground
                )
            },
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
}

@Composable
private fun AllowlistBackupSection(
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

    Card(
        modifier = Modifier
            .padding(vertical = 12.dp)
            .fillMaxWidth(),
    ) {
        SuperArrow(
            title = stringResource(R.string.allowlist_backup_title),
            summary = stringResource(R.string.allowlist_backup_summary_picker),
            startAction = {
                Icon(
                    imageVector = Icons.Rounded.Backup,
                    modifier = Modifier.padding(end = 6.dp),
                    contentDescription = stringResource(R.string.allowlist_backup_title),
                    tint = colorScheme.onBackground
                )
            },
            onClick = {
                backupLauncher.launch("ksu_allowlist_backup.bin")
            }
        )

        SuperArrow(
            title = stringResource(R.string.allowlist_restore_title),
            summary = stringResource(R.string.allowlist_restore_summary_picker),
            startAction = {
                Icon(
                    imageVector = Icons.Rounded.Restore,
                    modifier = Modifier.padding(end = 6.dp),
                    contentDescription = stringResource(R.string.allowlist_restore_title),
                    tint = colorScheme.onBackground
                )
            },
            onClick = {
                restoreLauncher.launch(arrayOf("*/*"))
            }
        )
    }
}
