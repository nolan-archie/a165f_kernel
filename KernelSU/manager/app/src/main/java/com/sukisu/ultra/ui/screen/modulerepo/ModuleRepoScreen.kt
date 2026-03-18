package com.sukisu.ultra.ui.screen.modulerepo

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun ModuleRepoScreen() {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ModuleRepoScreenMiuix()
        UiMode.Material -> ModuleRepoScreenMaterial()
    }
}

@Composable
fun ModuleRepoDetailScreen(module: RepoModuleArg) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> ModuleRepoDetailScreenMiuix(module)
        UiMode.Material -> ModuleRepoDetailScreenMaterial(module)
    }
}
