package com.sukisu.ultra.ui.screen.templateeditor

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun TemplateEditorScreen(template: com.sukisu.ultra.ui.viewmodel.TemplateViewModel.TemplateInfo, readOnly: Boolean) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> TemplateEditorScreenMiuix(template, readOnly)
        UiMode.Material -> TemplateEditorScreenMaterial(template, readOnly)
    }
}
