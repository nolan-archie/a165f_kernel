package com.sukisu.ultra.ui.screen.template

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun AppProfileTemplateScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> AppProfileTemplateScreenMiuix()
        UiMode.Material -> AppProfileTemplateScreenMaterial()
    }
}
