package com.sukisu.ultra.ui.susfs.repository

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.sukisu.ultra.ui.susfs.util.SuSFSManager

class SuSFSRepositoryImpl : SuSFSRepository {

    override suspend fun loadInitialConfig(context: Context): Result<SuSFSManager.ModuleConfig> =
        withContext(Dispatchers.IO) {
            runCatching { SuSFSManager.getCurrentModuleConfig(context) }
        }

    override suspend fun getEnabledFeatures(context: Context): Result<List<SuSFSManager.EnabledFeature>> =
        withContext(Dispatchers.IO) {
            runCatching { SuSFSManager.getEnabledFeatures(context) }
        }

    override suspend fun getInstalledApps(): Result<List<SuSFSManager.AppInfo>> =
        withContext(Dispatchers.IO) {
            runCatching { SuSFSManager.getInstalledApps() }
        }

    override suspend fun getSlotInfo(
        context: Context
    ): Result<Pair<List<SuSFSManager.SlotInfo>, String>> = withContext(Dispatchers.IO) {
        runCatching {
            val slotInfo = SuSFSManager.getCurrentSlotInfo()
            val currentActive = SuSFSManager.getCurrentActiveSlot()
            slotInfo to currentActive
        }
    }
}

