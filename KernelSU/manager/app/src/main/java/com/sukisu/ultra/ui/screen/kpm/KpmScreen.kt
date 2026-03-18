package com.sukisu.ultra.ui.screen.kpm

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun KpmScreen(
    bottomInnerPadding: Dp = 0.dp
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> KpmMiuix(bottomInnerPadding = bottomInnerPadding)
        UiMode.Material -> KpmMaterial(bottomInnerPadding = bottomInnerPadding)
    }
}
