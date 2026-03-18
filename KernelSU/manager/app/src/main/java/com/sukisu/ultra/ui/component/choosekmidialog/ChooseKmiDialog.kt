package com.sukisu.ultra.ui.component.choosekmidialog

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun ChooseKmiDialog(
    showDialog: MutableState<Boolean>,
    onSelected: (String?) -> Unit
) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ChooseKmiDialogMiuix(showDialog, onSelected)
        UiMode.Material -> ChooseKmiDialogMaterial(showDialog, onSelected)
    }
}