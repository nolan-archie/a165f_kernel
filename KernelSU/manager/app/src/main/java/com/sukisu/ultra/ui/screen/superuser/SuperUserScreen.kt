package com.sukisu.ultra.ui.screen.superuser

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.navigation3.Navigator

@Composable
fun SuperUserPager(
    navigator: Navigator,
    bottomInnerPadding: Dp
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SuperUserPagerMiuix(navigator, bottomInnerPadding)
        UiMode.Material -> SuperUserPagerMaterial(navigator, bottomInnerPadding)
    }
}
