package com.sukisu.ultra.ui.screen.umountmanager

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun UmountManagerScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> UmountManagerMiuix()
        UiMode.Material -> UmountManagerMaterial()
    }
}
