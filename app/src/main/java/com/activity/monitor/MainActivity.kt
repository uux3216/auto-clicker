package com.activity.monitor

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class AppPermissionInfo(
    val appName: String,
    val packageName: String,
    val permissions: List<Pair<String, Boolean>>
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                ActivityMonitorScreen(
                    hasUsageAccess = { hasUsageAccess() },
                    openUsageSettings = {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    },
                    getForegroundApp = { findForegroundApp() },
                    getPermissionInventory = { loadPermissionInventory() }
                )
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun findForegroundApp(): String? {
        if (!hasUsageAccess()) return null

        val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val begin = end - 10 * 60 * 1000L
        val events = usage.queryEvents(begin, end)
        val event = UsageEvents.Event()
        var foregroundPackage: String? = null

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> foregroundPackage = event.packageName
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (foregroundPackage == event.packageName) foregroundPackage = null
                }
            }
        }
        return foregroundPackage
    }

    @Suppress("DEPRECATION")
    private fun loadPermissionInventory(): List<AppPermissionInfo> {
        val pm = packageManager
        val packages = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
        val relevant = mapOf(
            "android.permission.CAMERA" to "Camera",
            "android.permission.RECORD_AUDIO" to "Microphone",
            "android.permission.ACCESS_FINE_LOCATION" to "Precise location",
            "android.permission.ACCESS_COARSE_LOCATION" to "Approximate location",
            "android.permission.ACCESS_BACKGROUND_LOCATION" to "Background location",
            "android.permission.READ_EXTERNAL_STORAGE" to "Read shared storage",
            "android.permission.WRITE_EXTERNAL_STORAGE" to "Write shared storage",
            "android.permission.READ_MEDIA_IMAGES" to "Read images",
            "android.permission.READ_MEDIA_VIDEO" to "Read videos",
            "android.permission.READ_MEDIA_AUDIO" to "Read audio"
        )

        return packages.mapNotNull { info ->
            val requested = info.requestedPermissions ?: return@mapNotNull null
            val flags = info.requestedPermissionsFlags ?: IntArray(requested.size)
            val found = requested.mapIndexedNotNull { index, permission ->
                val label = relevant[permission] ?: return@mapIndexedNotNull null
                val granted = index < flags.size &&
                    (flags[index] and PackageManager.REQUESTED_PERMISSION_GRANTED) != 0
                label to granted
            }
            if (found.isEmpty()) return@mapNotNull null
            val appName = try {
                pm.getApplicationLabel(info.applicationInfo!!).toString()
            } catch (_: Exception) {
                info.packageName
            }
            AppPermissionInfo(appName, info.packageName, found)
        }.sortedBy { it.appName.lowercase(Locale.getDefault()) }
    }
}

@Composable
private fun ActivityMonitorScreen(
    hasUsageAccess: () -> Boolean,
    openUsageSettings: () -> Unit,
    getForegroundApp: () -> String?,
    getPermissionInventory: () -> List<AppPermissionInfo>
) {
    var usageGranted by remember { mutableStateOf(hasUsageAccess()) }
    var foregroundApp by remember { mutableStateOf<String?>(null) }
    var inventory by remember { mutableStateOf(emptyList<AppPermissionInfo>()) }
    var lastUpdated by remember { mutableStateOf("Waiting for access") }

    LaunchedEffect(Unit) {
        while (true) {
            usageGranted = hasUsageAccess()
            if (usageGranted) {
                foregroundApp = getForegroundApp()
                inventory = getPermissionInventory()
                lastUpdated = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
            }
            delay(2000)
        }
    }

    Scaffold(
        topBar = {
            TopAppBarCompat()
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Card {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text("Live app activity", style = MaterialTheme.typography.titleLarge)
                        Spacer(Modifier.height(8.dp))
                        if (usageGranted) {
                            Text("Usage Access: Enabled", color = MaterialTheme.colorScheme.primary)
                            Text(
                                foregroundApp ?: "No foreground app event detected",
                                style = MaterialTheme.typography.headlineSmall
                            )
                            Text("Updated: $lastUpdated", style = MaterialTheme.typography.bodySmall)
                        } else {
                            Text("Usage Access is required to identify the foreground app.")
                            Spacer(Modifier.height(8.dp))
                            Button(onClick = openUsageSettings) {
                                Text("Grant Usage Access")
                            }
                        }
                    }
                }
            }
            item {
                Text("Permission inventory", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Shows permissions requested by installed apps and whether Android reports them as granted. This is not live permission usage.",
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (usageGranted && inventory.isEmpty()) {
                item { Text("No matching permissions found.") }
            }
            items(inventory, key = { it.packageName }) { app ->
                Card {
                    Column(Modifier.fillMaxWidth().padding(12.dp)) {
                        Text(app.appName, style = MaterialTheme.typography.titleMedium)
                        Text(app.packageName, style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(6.dp))
                        app.permissions.forEach { (name, granted) ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(name, modifier = Modifier.weight(1f))
                                Text(
                                    if (granted) "Granted" else "Not granted",
                                    color = if (granted) MaterialTheme.colorScheme.primary
                                    else MaterialTheme.colorScheme.error,
                                    style = MaterialTheme.typography.labelMedium
                                )
                            }
                        }
                    }
                }
            }
            item {
                Text(
                    "Privacy note: Android 12 does not expose a general public API for third-party apps to read every other app's live camera, microphone, location, or file-access events. This app does not claim to detect those events.",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TopAppBarCompat() {
    TopAppBar(title = { Text("Activity Monitor") })
}
