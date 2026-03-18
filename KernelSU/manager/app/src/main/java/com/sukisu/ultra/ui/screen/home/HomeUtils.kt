package com.sukisu.ultra.ui.screen.home

import android.content.Context
import android.os.Build
import android.system.Os
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.pm.PackageInfoCompat
import com.sukisu.ultra.Natives
import com.sukisu.ultra.ui.util.getSELinuxStatus
import com.sukisu.ultra.ui.util.getSuSFSStatus
import com.sukisu.ultra.ui.util.getSuSFSVersion

data class ManagerVersion(
    val versionName: String,
    val versionCode: Long
)

data class SystemInfo(
    val kernelVersion: String,
    val managerVersion: String,
    val fingerprint: String,
    val selinuxStatus: String
)

@Composable
fun rememberSystemInfo(): SystemInfo {
    val context = LocalContext.current
    val uname = Os.uname()
    val managerVersion = getManagerVersion(context)

    return SystemInfo(
        kernelVersion = uname.release,
        managerVersion = "${managerVersion.versionName} (${managerVersion.versionCode})",
        fingerprint = Build.FINGERPRINT,
        selinuxStatus = getSELinuxStatus()
    )
}

fun getManagerVersion(context: Context): ManagerVersion {
    val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)!!
    val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo)
    return ManagerVersion(
        versionName = packageInfo.versionName!!,
        versionCode = versionCode
    )
}

enum class SusfsStatus {
    Idle, Supported, Unsupported, Error
}

data class SusfsInfoState(
    val status: SusfsStatus = SusfsStatus.Idle,
    val detail: String = "",
)

@Composable
fun rememberSusfsInfo(
    manualHookLabel: String,
    inlineHookLabel: String,
): SusfsInfoState {
    return remember(manualHookLabel, inlineHookLabel) {
        runCatching {
            val supported = getSuSFSStatus().equals("true", ignoreCase = true)
            if (supported) {
                val version = getSuSFSVersion().trim()
                val hookLabel = when (val type = Natives.getHookType()) {
                    "Manual" -> manualHookLabel
                    "Inline" -> inlineHookLabel
                    else -> type
                }.takeIf { it.isNotBlank() }?.let { "($it)" }.orEmpty()
                SusfsInfoState(
                    status = SusfsStatus.Supported,
                    detail = listOf(version, hookLabel)
                        .filter { it.isNotBlank() }
                        .joinToString(" ")
                )
            } else {
                SusfsInfoState(
                    status = SusfsStatus.Unsupported,
                    detail = ""
                )
            }
        }.getOrElse {
            SusfsInfoState(status = SusfsStatus.Error)
        }
    }
}
