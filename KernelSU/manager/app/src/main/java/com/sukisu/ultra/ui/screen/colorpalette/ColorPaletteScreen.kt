package com.sukisu.ultra.ui.screen.colorpalette

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun ColorPaletteScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ColorPaletteScreenMiuix()
        UiMode.Material -> ColorPaletteScreenMaterial()
    }
}
