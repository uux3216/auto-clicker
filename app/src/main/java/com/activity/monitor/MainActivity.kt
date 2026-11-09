package com.activity.monitor

import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.ImageView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import rikka.shizuku.Shizuku
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private const val SHIZUKU_REQUEST_CODE = 4102

private enum class PermissionCategory(val title: String, val permissions: Set<String>) {
    CAMERA("Camera", setOf("android.permission.CAMERA")),
    MICROPHONE("Microphone", setOf("android.permission.RECORD_AUDIO")),
    LOCATION("Location", setOf(
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_BACKGROUND_LOCATION"
    )),
    GALLERY("Gallery", setOf(
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.READ_MEDIA_IMAGES",
        "android.permission.READ_MEDIA_VIDEO"
    )),
    FILES("Files", setOf(
        "android.permission.READ_EXTERNAL_STORAGE",
        "android.permission.WRITE_EXTERNAL_STORAGE",
        "android.permission.MANAGE_EXTERNAL_STORAGE"
    ))
}

private data class AppEntry(
    val label: String,
    val packageName: String,
    val isSystem: Boolean,
    val permissions: List<Pair<String, Boolean>>
)

private data class SensorState(
    val resource: String,
    val packageName: String?,
    val status: String,
    val detail: String
)

private data class DiagnosticResult(
    val camera: SensorState,
    val microphone: SensorState,
    val rawSummary: String,
    val timestamp: String
)

class MainActivity : ComponentActivity() {
    @Volatile private var remoteService: IUserService? = null
    @Volatile private var remoteServiceError: String? = null

    private val userServiceArgs by lazy {
        Shizuku.UserServiceArgs(
            ComponentName(this, ShellUserService::class.java)
        ).daemon(false)
            .processNameSuffix("activity-monitor")
            .tag("activity-monitor-shell-service")
            .version(1)
    }

    private val userServiceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            remoteService = IUserService.Stub.asInterface(service)
            remoteServiceError = null
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remoteService = null
            remoteServiceError = "Shizuku UserService disconnected. Reconnect and retry."
        }
    }

    private fun bindRemoteService() {
        if (!Shizuku.pingBinder()) {
            remoteServiceError = "Shizuku service is not running."
            return
        }
        if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
            remoteServiceError = "Grant Shizuku permission first."
            return
        }
        try {
            Shizuku.bindUserService(userServiceArgs, userServiceConnection)
        } catch (t: Throwable) {
            remoteServiceError = t.message ?: "Could not bind Shizuku UserService."
        }
    }
    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == SHIZUKU_REQUEST_CODE &&
                grantResult == PackageManager.PERMISSION_GRANTED
            ) {
                bindRemoteService()
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Shizuku.addRequestPermissionResultListener(permissionListener)

        if (shizukuPermissionGranted()) bindRemoteService()

        setContent {
            MaterialTheme {
                ActivityMonitorScreen(
                    hasShizukuPermission = { shizukuPermissionGranted() },
                    shizukuRunning = { Shizuku.pingBinder() },
                    requestShizukuPermission = { requestShizukuAccess() },
                    getInventory = { loadPermissionInventory() },
                    runDiagnostic = { collectDiagnostic() }
                )
            }
        }
    }

    override fun onDestroy() {
        Shizuku.removeRequestPermissionResultListener(permissionListener)
        runCatching { Shizuku.unbindUserService(userServiceArgs, userServiceConnection, true) }
        remoteService = null
        super.onDestroy()
    }

    private fun shizukuPermissionGranted(): Boolean {
        return try {
            Shizuku.pingBinder() &&
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    private fun requestShizukuAccess() {
        try {
            if (!Shizuku.pingBinder()) return
            if (Shizuku.isPreV11()) return
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
            }
        } catch (_: Exception) {
            // The UI displays current Shizuku state and can be retried.
        }
    }

    @Suppress("DEPRECATION")
    private fun loadPermissionInventory(): List<AppEntry> {
        val pm = packageManager
        val relevant = PermissionCategory.values().flatMap { it.permissions }.toSet()
        return pm.getInstalledPackages(PackageManager.GET_PERMISSIONS).mapNotNull { pkg ->
            val requested = pkg.requestedPermissions ?: return@mapNotNull null
            val flags = pkg.requestedPermissionsFlags ?: IntArray(requested.size)
            val matches = requested.mapIndexedNotNull { index, permission ->
                if (permission !in relevant) return@mapIndexedNotNull null
                val granted = index < flags.size &&
                    (flags[index] and android.content.pm.PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
                permission to granted
            }
            if (matches.isEmpty()) return@mapNotNull null
            val appInfo = pkg.applicationInfo ?: return@mapNotNull null
            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            val label = try {
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                pkg.packageName
            }
            AppEntry(label, pkg.packageName, isSystem, matches)
        }.sortedBy { it.label.lowercase(Locale.getDefault()) }
    }

    private fun runShell(command: String): String {
        check(Shizuku.pingBinder()) { "Shizuku service is not running." }
        check(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
            "Activity Monitor has not been granted Shizuku permission."
        }
        val service = remoteService
        if (service == null) {
            bindRemoteService()
            throw IllegalStateException(
                remoteServiceError ?: "Shizuku UserService is connecting. Wait a moment and tap Test now again."
            )
        }
        return service.runCommand(command)
    }

    private fun collectDiagnostic(): DiagnosticResult {
        // These dumps are diagnostic sources, not a guaranteed public live-usage API.
        val appOps = runShell("dumpsys appops")
        val cameraDump = runCatching { runShell("dumpsys media.camera") }.getOrDefault("")
        val audioDump = runCatching { runShell("dumpsys audio") }.getOrDefault("")

        val camera = findConservativeActivePackage(
            resource = "Camera",
            dumps = listOf(cameraDump, appOps),
            activeHints = listOf("active camera", "camera client", "client package", "camera device")
        )
        val microphone = findConservativeActivePackage(
            resource = "Microphone",
            dumps = listOf(audioDump, appOps),
            activeHints = listOf("recording", "record track", "active microphone", "audio record")
        )

        val summary = buildString {
            appendLine("dumpsys appops: ${appOps.length} characters")
            appendLine("dumpsys media.camera: ${cameraDump.length} characters")
            appendLine("dumpsys audio: ${audioDump.length} characters")
            appendLine()
            appendLine("Camera diagnostic excerpt:")
            appendLine(cameraDump.take(1800).ifBlank { "No output / access denied" })
            appendLine()
            appendLine("Audio diagnostic excerpt:")
            appendLine(audioDump.take(1800).ifBlank { "No output / access denied" })
        }

        return DiagnosticResult(
            camera = camera,
            microphone = microphone,
            rawSummary = summary,
            timestamp = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        )
    }

    private fun findConservativeActivePackage(
        resource: String,
        dumps: List<String>,
        activeHints: List<String>
    ): SensorState {
        val combined = dumps.joinToString("\n").lowercase(Locale.ROOT)
        val packages = loadPermissionInventory()
            .filter { app ->
                val permission = if (resource == "Camera") {
                    "android.permission.CAMERA"
                } else {
                    "android.permission.RECORD_AUDIO"
                }
                app.permissions.any { it.first == permission }
            }
            .map { it.packageName }
            .filter { it.lowercase(Locale.ROOT) in combined }

        val hasActiveHint = activeHints.any { it in combined }
        return when {
            packages.size == 1 && hasActiveHint -> SensorState(
                resource, packages.first(), "Possible active client",
                "Package name and an activity hint were found in system diagnostics. Verify on-device."
            )
            packages.isNotEmpty() -> SensorState(
                resource, null, "Source not confirmed",
                "Matching package text found, but no reliable active-client attribution."
            )
            else -> SensorState(
                resource, null, "Not identified",
                "System diagnostic output did not expose a reliable active package."
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityMonitorScreen(
    hasShizukuPermission: () -> Boolean,
    shizukuRunning: () -> Boolean,
    requestShizukuPermission: () -> Unit,
    getInventory: () -> List<AppEntry>,
    runDiagnostic: () -> DiagnosticResult
) {
    var inventory by remember { mutableStateOf(emptyList<AppEntry>()) }
    var selected by remember { mutableStateOf(PermissionCategory.CAMERA) }
    var showSystem by remember { mutableStateOf(false) }
    var shizukuUp by remember { mutableStateOf(shizukuRunning()) }
    var shizukuGranted by remember { mutableStateOf(hasShizukuPermission()) }
    var diagnostic by remember { mutableStateOf<DiagnosticResult?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var autoMonitor by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun refreshDiagnostic() {
        if (busy || !shizukuUp || !shizukuGranted) return
        scope.launch {
            busy = true
            try {
                diagnostic = withContext(Dispatchers.IO) { runDiagnostic() }
                error = null
            } catch (t: Throwable) {
                error = t.message ?: "Diagnostic failed."
            } finally {
                busy = false
            }
        }
    }

    LaunchedEffect(Unit) {
        inventory = getInventory()
        while (isActive) {
            shizukuUp = shizukuRunning()
            shizukuGranted = hasShizukuPermission()
            inventory = getInventory()
            if (autoMonitor && shizukuUp && shizukuGranted && !busy) {
                refreshDiagnostic()
            }
            delay(if (autoMonitor) 4000 else 8000)
        }
    }

    val visibleApps = inventory.filter { app ->
        (showSystem || !app.isSystem) &&
            app.permissions.any { it.first in selected.permissions }
    }

    Scaffold(topBar = { TopAppBar(title = { Text("Activity Monitor") }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Shizuku connection", style = MaterialTheme.typography.titleMedium)
                    Text("Service: ${if (shizukuUp) "Running" else "Not running"}")
                    Text("Permission: ${if (shizukuGranted) "Granted" else "Not granted"}")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = requestShizukuPermission, enabled = shizukuUp && !shizukuGranted) {
                            Text("Grant Shizuku")
                        }
                        OutlinedButton(
                            onClick = {
                                if (!shizukuUp) error = "Start Shizuku first."
                                else if (!shizukuGranted) error = "Grant Shizuku permission first."
                                else refreshDiagnostic()
                            },
                            enabled = shizukuUp && shizukuGranted && !busy
                        ) { Text(if (busy) "Checking…" else "Test now") }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Switch(checked = autoMonitor, onCheckedChange = { autoMonitor = it })
                        Spacer(Modifier.width(8.dp))
                        Text("Auto diagnostic polling (~4 sec)")
                    }
                    Text(
                        "Important: this is best-effort diagnostics, not guaranteed real-time sensor attribution. A positive result is labelled 'Possible', never definitive.",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }

            diagnostic?.let { result ->
                Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Sensor diagnostics · ${result.timestamp}", style = MaterialTheme.typography.titleMedium)
                        SensorRow(result.camera)
                        HorizontalDivider()
                        SensorRow(result.microphone)
                        var expanded by remember { mutableStateOf(false) }
                        TextButton(onClick = { expanded = !expanded }) {
                            Text(if (expanded) "Hide diagnostic excerpts" else "Show diagnostic excerpts")
                        }
                        if (expanded) {
                            Text(result.rawSummary, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(12.dp))
            }

            ScrollableTabRow(
                selectedTabIndex = PermissionCategory.values().indexOf(selected),
                edgePadding = 8.dp
            ) {
                PermissionCategory.values().forEach { category ->
                    val count = inventory.count { app ->
                        (showSystem || !app.isSystem) &&
                            app.permissions.any { it.first in category.permissions }
                    }
                    Tab(
                        selected = selected == category,
                        onClick = { selected = category },
                        text = {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(category.title)
                                Text("$count", style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    )
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 12.dp)) {
                Checkbox(checked = showSystem, onCheckedChange = { showSystem = it })
                Text("Show system app")
                Spacer(Modifier.weight(1f))
                Text("${visibleApps.size} apps", style = MaterialTheme.typography.labelMedium)
            }
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(visibleApps, key = { it.packageName + selected.name }) { app ->
                    val matching = app.permissions.filter { it.first in selected.permissions }
                    Card {
                        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.Top) {
                            AppIcon(app.packageName, Modifier.size(44.dp))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(app.label, style = MaterialTheme.typography.titleMedium)
                                Text(app.packageName, style = MaterialTheme.typography.bodySmall)
                                matching.forEach { (permission, granted) ->
                                    Text(
                                        "${permissionLabel(permission)}: ${if (granted) "Granted" else "Not granted"}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = if (granted) MaterialTheme.colorScheme.primary
                                        else MaterialTheme.colorScheme.error
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SensorRow(state: SensorState) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("${state.resource}: ${state.status}", style = MaterialTheme.typography.titleSmall)
        Text(state.packageName ?: "App package not confirmed", style = MaterialTheme.typography.bodyMedium)
        Text(state.detail, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun AppIcon(packageName: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            ImageView(ctx).apply {
                scaleType = ImageView.ScaleType.FIT_CENTER
                setImageDrawable(runCatching {
                    ctx.packageManager.getApplicationIcon(packageName)
                }.getOrElse {
                    ctx.getDrawable(android.R.drawable.sym_def_app_icon)
                })
            }
        },
        update = { view ->
            view.setImageDrawable(runCatching {
                context.packageManager.getApplicationIcon(packageName)
            }.getOrElse {
                context.getDrawable(android.R.drawable.sym_def_app_icon)
            })
        }
    )
}

private fun permissionLabel(permission: String): String = when (permission) {
    "android.permission.CAMERA" -> "Camera"
    "android.permission.RECORD_AUDIO" -> "Microphone"
    "android.permission.ACCESS_FINE_LOCATION" -> "Precise location"
    "android.permission.ACCESS_COARSE_LOCATION" -> "Approximate location"
    "android.permission.ACCESS_BACKGROUND_LOCATION" -> "Background location"
    "android.permission.READ_EXTERNAL_STORAGE" -> "Read shared storage"
    "android.permission.WRITE_EXTERNAL_STORAGE" -> "Write shared storage"
    "android.permission.READ_MEDIA_IMAGES" -> "Read images"
    "android.permission.READ_MEDIA_VIDEO" -> "Read videos"
    "android.permission.MANAGE_EXTERNAL_STORAGE" -> "Manage all files"
    else -> permission.substringAfterLast('.')
}
