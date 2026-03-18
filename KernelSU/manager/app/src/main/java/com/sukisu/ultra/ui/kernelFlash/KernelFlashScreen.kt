package com.sukisu.ultra.ui.kernelFlash

import android.net.Uri
import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun KernelFlashScreen(
    kernelUri: Uri,
    selectedSlot: String? = null,
    kpmPatchEnabled: Boolean = false,
    kpmUndoPatch: Boolean = false
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> KernelFlashMiuix(
            kernelUri = kernelUri,
            selectedSlot = selectedSlot,
            kpmPatchEnabled = kpmPatchEnabled,
            kpmUndoPatch = kpmUndoPatch
        )
        UiMode.Material -> KernelFlashMaterial(
            kernelUri = kernelUri,
            selectedSlot = selectedSlot,
            kpmPatchEnabled = kpmPatchEnabled,
            kpmUndoPatch = kpmUndoPatch
        )
    }
}
