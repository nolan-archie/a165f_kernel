package com.sukisu.ultra.ui.kernelFlash

import android.content.Intent
import android.net.Uri
import android.os.Environment
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.key
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.component.KeyEventBlocker
import com.sukisu.ultra.ui.kernelFlash.state.*
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.util.reboot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KernelFlashMaterial(
    kernelUri: Uri,
    selectedSlot: String? = null,
    kpmPatchEnabled: Boolean = false,
    kpmUndoPatch: Boolean = false
) {
    val navigator = LocalNavigator.current
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()
    var logText by rememberSaveable { mutableStateOf("") }
    var showFloatAction by rememberSaveable { mutableStateOf(false) }
    val logContent = rememberSaveable { StringBuilder() }
    val horizonKernelState = remember {
        if (KernelFlashStateHolder.currentState != null &&
            KernelFlashStateHolder.currentUri == kernelUri &&
            KernelFlashStateHolder.currentSlot == selectedSlot &&
            KernelFlashStateHolder.currentKpmPatchEnabled == kpmPatchEnabled &&
            KernelFlashStateHolder.currentKpmUndoPatch == kpmUndoPatch) {
            KernelFlashStateHolder.currentState!!
        } else {
            HorizonKernelState().also {
                KernelFlashStateHolder.currentState = it
                KernelFlashStateHolder.currentUri = kernelUri
                KernelFlashStateHolder.currentSlot = selectedSlot
                KernelFlashStateHolder.currentKpmPatchEnabled = kpmPatchEnabled
                KernelFlashStateHolder.currentKpmUndoPatch = kpmUndoPatch
                KernelFlashStateHolder.isFlashing = false
            }
        }
    }

    val flashState by horizonKernelState.state.collectAsState()
    val activity = LocalActivity.current

    val onFlashComplete = {
        showFloatAction = true
        KernelFlashStateHolder.isFlashing = false
    }

    val flashComplete = stringResource(R.string.horizon_flash_complete)

    LaunchedEffect(flashState.isCompleted, flashState.error) {
        if (flashState.isCompleted && flashState.error.isEmpty()) {
            val intent = activity?.intent
            val isFromExternalIntent = intent?.action?.let { action ->
                action == Intent.ACTION_VIEW ||
                action == Intent.ACTION_SEND ||
                action == Intent.ACTION_SEND_MULTIPLE
            } ?: false

            if (isFromExternalIntent) {
                delay(1500)
                KernelFlashStateHolder.clear()
                activity.finish()
            }
        }
    }

    LaunchedEffect(Unit) {
        if (!KernelFlashStateHolder.isFlashing && !flashState.isCompleted && flashState.error.isEmpty()) {
            withContext(Dispatchers.IO) {
                KernelFlashStateHolder.isFlashing = true
                val worker = HorizonKernelWorker(
                    context = context,
                    state = horizonKernelState,
                    slot = selectedSlot,
                    kpmPatchEnabled = kpmPatchEnabled,
                    kpmUndoPatch = kpmUndoPatch
                )
                worker.uri = kernelUri
                worker.setOnFlashCompleteListener(onFlashComplete)
                worker.start()

                while (flashState.error.isEmpty() && !flashState.isCompleted) {
                    if (flashState.logs.isNotEmpty()) {
                        logText = flashState.logs.joinToString("\n")
                        logContent.clear()
                        logContent.append(logText)
                    }
                    delay(100)
                }

                if (flashState.error.isNotEmpty()) {
                    logText += "\n${flashState.error}\n"
                    logContent.append("\n${flashState.error}\n")
                    KernelFlashStateHolder.isFlashing = false
                }
            }
        } else {
            logText = flashState.logs.joinToString("\n")
            if (flashState.error.isNotEmpty()) {
                logText += "\n${flashState.error}\n"
            } else if (flashState.isCompleted) {
                logText += "\n$flashComplete\n\n\n"
                showFloatAction = true
            }
        }
    }

    val onBack: () -> Unit = {
        if (!flashState.isFlashing || flashState.isCompleted || flashState.error.isNotEmpty()) {
            if (flashState.isCompleted || flashState.error.isNotEmpty()) {
                KernelFlashStateHolder.clear()
            }
            navigator.pop()
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            if (flashState.isCompleted || flashState.error.isNotEmpty()) {
                KernelFlashStateHolder.clear()
            }
        }
    }

    BackHandler {
        onBack()
    }

    KeyEventBlocker {
        it.key == Key.VolumeDown || it.key == Key.VolumeUp
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(
                            when {
                                flashState.error.isNotEmpty() -> R.string.flash_failed
                                flashState.isCompleted -> R.string.flash_success
                                else -> R.string.kernel_flashing
                            }
                        )
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = null
                        )
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            scope.launch {
                                val format = SimpleDateFormat("yyyy-MM-dd-HH-mm-ss", Locale.getDefault())
                                val date = format.format(Date())
                                val file = File(
                                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                                    "KernelSU_kernel_flash_log_${date}.log"
                                )
                                file.writeText(logContent.toString())
                            }
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = stringResource(id = R.string.save_log)
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        },
        floatingActionButton = {
            if (showFloatAction) {
                FloatingActionButton(
                    onClick = {
                        scope.launch {
                            withContext(Dispatchers.IO) {
                                reboot()
                            }
                        }
                    },
                    containerColor = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.padding(bottom = 20.dp, end = 20.dp)
                ) {
                    Icon(
                        Icons.Default.Refresh,
                        contentDescription = stringResource(id = R.string.reboot),
                        tint = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            FlashProgressIndicatorMaterial(flashState, kpmPatchEnabled, kpmUndoPatch)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(scrollState)
            ) {
                LaunchedEffect(logText) {
                    scrollState.animateScrollTo(scrollState.maxValue)
                }
                Text(
                    modifier = Modifier.padding(16.dp),
                    text = logText,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface
                )
            }
        }
    }
}

@Composable
private fun FlashProgressIndicatorMaterial(
    flashState: FlashState,
    kpmPatchEnabled: Boolean = false,
    kpmUndoPatch: Boolean = false
) {
    val statusColor = when {
        flashState.error.isNotEmpty() -> MaterialTheme.colorScheme.error
        flashState.isCompleted -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.primary
    }

    val progress = animateFloatAsState(
        targetValue = flashState.progress.coerceIn(0f, 1f),
        label = "FlashProgress"
    )

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = when {
                        flashState.error.isNotEmpty() -> stringResource(R.string.flash_failed)
                        flashState.isCompleted -> stringResource(R.string.flash_success)
                        else -> stringResource(R.string.flashing)
                    },
                    fontSize = MaterialTheme.typography.titleMedium.fontSize,
                    fontWeight = FontWeight.Medium,
                    color = statusColor
                )

                when {
                    flashState.error.isNotEmpty() -> {
                        Icon(
                            imageVector = Icons.Default.Error,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error
                        )
                    }
                    flashState.isCompleted -> {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }

            if (kpmPatchEnabled || kpmUndoPatch) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = if (kpmUndoPatch) stringResource(R.string.kpm_undo_patch_mode)
                    else stringResource(R.string.kpm_patch_mode),
                    fontSize = MaterialTheme.typography.bodyMedium.fontSize,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            if (flashState.currentStep.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = flashState.currentStep,
                    fontSize = MaterialTheme.typography.bodyMedium.fontSize,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            LinearProgressIndicator(
                progress = { progress.value },
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )

            if (flashState.error.isNotEmpty()) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = flashState.error,
                    fontSize = MaterialTheme.typography.bodyMedium.fontSize,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            MaterialTheme.colorScheme.errorContainer,
                            MaterialTheme.shapes.small
                        )
                        .padding(12.dp)
                )
            }
        }
    }
}
