package com.sukisu.ultra.ui.screen.appprofile

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun AppProfileScreen(uid: Int, packageName: String) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> AppProfileScreenMiuix(uid, packageName)
        UiMode.Material -> AppProfileScreenMaterial(uid, packageName)
    }
}
