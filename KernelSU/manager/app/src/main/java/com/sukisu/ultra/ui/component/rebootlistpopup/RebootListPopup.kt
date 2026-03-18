package com.sukisu.ultra.ui.component.rebootlistpopup

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun RebootListPopup() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> RebootListPopupMiuix()
        UiMode.Material -> RebootListPopupMaterial()
    }
}
