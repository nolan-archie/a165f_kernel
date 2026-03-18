package com.sukisu.ultra.ui.screen.sulog

import android.annotation.SuppressLint

@SuppressLint("DefaultLocale")
fun formatDuration(sec: Int): String {
    if (sec <= 0) return "0s"
    val h = sec / 3600
    val m = (sec % 3600) / 60
    val s = sec % 60
    return if (h > 0) String.format("%dh%02dm%02ds", h, m, s) else if (m > 0) String.format("%dm%02ds", m, s) else String.format("%ds", s)
}