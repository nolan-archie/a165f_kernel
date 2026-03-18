package com.sukisu.ultra.ui.component.uninstalldialog

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.navigation3.Navigator

@Composable
fun UninstallDialog(
    showDialog: MutableState<Boolean>,
    navigator: Navigator
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> UninstallDialogMiuix(showDialog, navigator)
        UiMode.Material -> UninstallDialogMaterial(showDialog, navigator)
    }
}
