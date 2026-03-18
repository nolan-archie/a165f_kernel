package com.sukisu.ultra.ui.screen.sulog

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.add
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberTopAppBarState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sukisu.ultra.R
import com.sukisu.ultra.ui.navigation3.LocalNavigator
import com.sukisu.ultra.ui.util.retrieveSulogLogs
import com.sukisu.ultra.ui.util.streamFile
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SulogMaterial() {
    val navigator = LocalNavigator.current
    val scrollBehavior = TopAppBarDefaults.pinnedScrollBehavior(rememberTopAppBarState())
    data class SulogEntry(val uptime: Int, val uid: Int, val sym: Char, val raw: String)
    var entries by remember { mutableStateOf(listOf<SulogEntry>()) }

    LaunchedEffect(true) {
        val regex = Regex("""uptime_s=(\d+)\s+uid=(\d+)\s+sym=(.)""")
        while (isActive) {
            retrieveSulogLogs()
            delay(1000)

            val streamed = streamFile("/data/adb/ksu/log/sulog.log")
            val allLines = if (streamed.isEmpty()) emptyList() else streamed.takeLast(2000)

            val parsed = mutableListOf<SulogEntry>()
            val seen = LinkedHashSet<String>()
            for (ln in allLines) {
                val lineTrim = ln.trim()
                if (lineTrim.isEmpty()) continue
                val m = regex.find(lineTrim)
                val entry = if (m != null) {
                    val uptime = m.groupValues[1].toIntOrNull() ?: 0
                    val uid = m.groupValues[2].toIntOrNull() ?: 0
                    val sym = m.groupValues[3].firstOrNull() ?: '?'
                    if (uptime == 0 && uid == 0 && sym == '?') null else SulogEntry(uptime, uid, sym, lineTrim)
                } else {
                    SulogEntry(0, 0, '?', lineTrim)
                }
                if (entry != null) {
                    val key = "${entry.uptime}|${entry.uid}|${entry.sym}|${entry.raw}"
                    if (seen.add(key)) parsed.add(entry)
                }
            }

            val map = linkedMapOf<String, SulogEntry>()
            parsed.forEach { map["${it.uptime}|${it.uid}|${it.sym}|${it.raw}"] = it }
            entries.forEach { key ->
                val k = "${key.uptime}|${key.uid}|${key.sym}|${key.raw}"
                if (!map.containsKey(k)) map[k] = key
            }
            val combined = map.values.toList()
            entries = combined

            delay(4000)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.log_viewer_title)) },
                navigationIcon = {
                    IconButton(onClick = { navigator.pop() }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = null,
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                ),
                scrollBehavior = scrollBehavior
            )
        },
        contentWindowInsets = WindowInsets.systemBars.add(WindowInsets.displayCutout).only(WindowInsetsSides.Horizontal)
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxHeight()
                .padding(horizontal = 12.dp)
                .padding(innerPadding),
        ) {
            val priority = { c: Char ->
                when (c) {
                    'i' -> 0
                    'x' -> 1
                    '$' -> 2
                    else -> 3
                }
            }
            val displayed = entries.sortedWith(compareBy({ priority(it.sym) }, { -it.uptime }))
            items(displayed.size) { index ->
                val e = displayed[index]
                Card(modifier = Modifier.padding(vertical = 6.dp)) {
                    Column(modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp)) {
                        val bgDesc = when (e.sym) {
                            '$' -> stringResource(id = R.string.sulog_blocked_label)
                            'x' -> stringResource(id = R.string.sulog_allowed_label)
                            'i' -> stringResource(id = R.string.sulog_ioctl_label)
                            else -> stringResource(id = R.string.sulog_other_label)
                        }
                        Text(text = "$bgDesc • uid=${e.uid} • uptime=${formatDuration(e.uptime)}")
                    }
                }
            }
        }
    }
}
