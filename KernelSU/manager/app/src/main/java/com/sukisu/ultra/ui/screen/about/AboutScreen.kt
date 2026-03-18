package com.sukisu.ultra.ui.screen.about

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun AboutScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> AboutScreenMiuix()
        UiMode.Material -> AboutScreenMaterial()
    }
}
