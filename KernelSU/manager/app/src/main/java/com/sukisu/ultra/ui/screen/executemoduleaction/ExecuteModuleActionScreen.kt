package com.sukisu.ultra.ui.screen.executemoduleaction

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun ExecuteModuleActionScreen(moduleId: String) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ExecuteModuleActionScreenMiuix(moduleId)
        UiMode.Material -> ExecuteModuleActionScreenMaterial(moduleId)
    }
}
