package com.sukisu.ultra.ui.screen.flash

import androidx.compose.runtime.Composable
import com.sukisu.ultra.ui.LocalUiMode
import com.sukisu.ultra.ui.UiMode

@Composable
fun FlashScreen(flashIt: FlashIt) {
    when (LocalUiMode.current) {
        UiMode.Miuix -> FlashScreenMiuix(flashIt)
        UiMode.Material -> FlashScreenMaterial(flashIt)
    }
}
