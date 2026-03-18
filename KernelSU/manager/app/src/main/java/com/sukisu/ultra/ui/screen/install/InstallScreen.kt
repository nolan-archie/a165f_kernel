package com.sukisu.ultra.ui.screen.install

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun InstallScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> InstallScreenMiuix()
        UiMode.Material -> InstallScreenMaterial()
    }
}
