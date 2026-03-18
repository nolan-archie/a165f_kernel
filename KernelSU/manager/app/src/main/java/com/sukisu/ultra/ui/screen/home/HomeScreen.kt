package com.sukisu.ultra.ui.screen.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.navigation3.Navigator

@Composable
fun HomePager(
    navigator: Navigator,
    bottomInnerPadding: Dp
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> HomePagerMiuix(navigator, bottomInnerPadding)
        UiMode.Material -> HomePagerMaterial(navigator, bottomInnerPadding)
    }
}
