package com.sukisu.ultra.ui.screen.module

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.navigation3.Navigator

@Composable
fun ModulePager(
    navigator: Navigator,
    bottomInnerPadding: Dp
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ModulePagerMiuix(navigator, bottomInnerPadding)
        UiMode.Material -> ModulePagerMaterial(navigator, bottomInnerPadding)
    }
}
