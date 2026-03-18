package com.sukisu.ultra.ui.screen.settings.tools

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun ToolsScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ToolsMiuix()
        UiMode.Material -> ToolsMaterial()
    }
}
