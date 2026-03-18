package com.sukisu.ultra.ui.screen.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.navigation3.Navigator

@Composable
fun SettingPager(
    navigator: Navigator,
    bottomInnerPadding: Dp
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SettingPagerMiuix(navigator, bottomInnerPadding)
        UiMode.Material -> SettingPagerMaterial(navigator, bottomInnerPadding)
    }
}
