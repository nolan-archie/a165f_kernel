package com.sukisu.ultra.ui.component.sendlogdialog

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode
import com.sukisu.ultra.ui.component.dialog.LoadingDialogHandle

@Composable
fun SendLogDialog(
    showDialog: MutableState<Boolean>,
    loadingDialog: LoadingDialogHandle
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> SendLogDialogMiuix(showDialog, loadingDialog)
        UiMode.Material -> SendLogDialogMaterial(showDialog, loadingDialog)
    }
}
