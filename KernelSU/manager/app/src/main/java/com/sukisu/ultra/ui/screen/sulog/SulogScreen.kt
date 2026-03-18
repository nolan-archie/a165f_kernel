package com.sukisu.ultra.ui.screen.sulog

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun SulogScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SulogMiuix()
        UiMode.Material -> SulogMaterial()
    }
}
