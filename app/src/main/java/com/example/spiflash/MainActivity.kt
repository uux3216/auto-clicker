package com.example.spiflash

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.launch

private const val ACTION_USB_PERMISSION = "com.example.spiflash.USB_PERMISSION"
private const val HEADER_ITEMS = 7 // hex সারির আগে LazyColumn-এর আইটেম সংখ্যা

class MainActivity : ComponentActivity() {

    private val vm: MainViewModel by viewModels()
    private val usb by lazy { getSystemService(UsbManager::class.java) }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val dev = usbDeviceFrom(intent)
                    if (dev != null && intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        vm.connect(dev)
                    } else {
                        vm.setMessage("USB পারমিশন দেওয়া হয়নি")
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> vm.disconnect()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)

        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    AppScreen(vm = vm, onConnect = { scanAndConnect() })
                }
            }
        }
        scanAndConnect()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        scanAndConnect()
    }

    override fun onDestroy() {
        unregisterReceiver(receiver)
        super.onDestroy()
    }

    private fun usbDeviceFrom(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private fun scanAndConnect() {
        val dev = usb.deviceList.values.firstOrNull {
            it.vendorId == Ch341Driver.VID && it.productId == Ch341Driver.PID
        }
        if (dev == null) {
            vm.setMessage("CH341 পাওয়া যায়নি — OTG কেবল ও প্রোগ্রামার চেক করুন")
            return
        }
        if (usb.hasPermission(dev)) {
            vm.connect(dev)
        } else {
            val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val pi = PendingIntent.getBroadcast(
                this, 0, Intent(ACTION_USB_PERMISSION).setPackage(packageName), flags
            )
            usb.requestPermission(dev, pi)
        }
    }
}

// ======================= UI =======================

@OptIn(ExperimentalLayoutApi::class, ExperimentalMaterial3Api::class)
@Composable
fun AppScreen(vm: MainViewModel, onConnect: () -> Unit) {
    val s by vm.ui.collectAsState()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    val openFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) vm.loadFile(uri)
    }
    val saveFile = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/octet-stream")
    ) { uri ->
        if (uri != null) vm.saveDump(uri)
    }

    var gotoText by remember { mutableStateOf("") }
    var pending by remember { mutableStateOf<Pair<String, () -> Unit>?>(null) }

    val dump = remember(s.dumpVersion) { vm.dump }
    val rows = if (s.dumpSize > 0) (s.dumpSize + 7) / 8 else 0

    pending?.let { (msg, act) ->
        AlertDialog(
            onDismissRequest = { pending = null },
            text = { Text(msg) },
            confirmButton = { TextButton(onClick = { act(); pending = null }) { Text("হ্যাঁ") } },
            dismissButton = { TextButton(onClick = { pending = null }) { Text("না") } }
        )
    }

    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(horizontal = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // 1
        item { Text("SPI Flash Programmer (CH341A/B)", style = MaterialTheme.typography.titleLarge) }

        // 2
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        if (s.connected) "● CH341 সংযুক্ত" else "○ সংযুক্ত নয়",
                        style = MaterialTheme.typography.titleMedium
                    )
                    if (s.connected) {
                        OutlinedButton(onClick = vm::disconnect, enabled = !s.busy) { Text("বিচ্ছিন্ন করুন") }
                    } else {
                        Button(onClick = onConnect) { Text("CH341 সংযোগ করুন") }
                    }
                }
            }
        }

        // 3
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("চিপের তথ্য", style = MaterialTheme.typography.titleMedium)
                    val c = s.chip
                    if (c == null) {
                        Text("এখনো শনাক্ত হয়নি")
                    } else {
                        Text("নির্মাতা: ${c.vendor}")
                        Text("পার্ট: ${c.part ?: "অজানা (ডাটাবেসে নেই)"}")
                        Text("JEDEC ID: ${c.idHex}")
                        Text("সাইজ: ${if (c.sizeBytes > 0) fmtSize(c.sizeBytes) else "অজানা — নিচে বাছুন"}")
                        s.statusReg?.let { Text("Status Register: 0x%02X".format(it)) }
                        if (c.sizeBytes == 0) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                listOf(512 shl 10, 1 shl 20, 2 shl 20, 4 shl 20, 8 shl 20, 16 shl 20).forEach { b ->
                                    FilterChip(
                                        selected = s.sizeOverride == b,
                                        onClick = { vm.setSizeOverride(b) },
                                        label = { Text(fmtSize(b)) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // 4
        item {
            val en = s.connected && !s.busy
            val chipOk = en && s.chip != null
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Button(onClick = vm::detect, enabled = en) { Text("চিপ শনাক্ত") }
                    Button(onClick = vm::readChip, enabled = chipOk) { Text("রিড") }
                    OutlinedButton(
                        onClick = { saveFile.launch("flash_dump.bin") },
                        enabled = s.dumpSize > 0 && !s.busy
                    ) { Text("ডাম্প সেভ") }
                    Button(
                        onClick = {
                            pending = "পুরো চিপ ইরেজ হবে, ডাটা ফেরত পাওয়া যাবে না। চালিয়ে যাবেন?" to { vm.eraseChip() }
                        },
                        enabled = chipOk
                    ) { Text("ইরেজ") }
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    OutlinedButton(onClick = { openFile.launch(arrayOf("*/*")) }, enabled = !s.busy) {
                        Text("ফাইল বাছুন")
                    }
                    Button(
                        onClick = {
                            val extra = if (s.eraseBeforeWrite) "আগে পুরো চিপ ইরেজ হবে। " else ""
                            pending = "${extra}চিপে ডাটা লেখা হবে। চালিয়ে যাবেন?" to { vm.writeFile() }
                        },
                        enabled = chipOk && s.fileSize > 0
                    ) { Text("রাইট") }
                    Button(onClick = vm::verifyFile, enabled = chipOk && s.fileSize > 0) { Text("ভেরিফাই") }
                }
                s.fileName?.let { Text("ফাইল: $it (${s.fileSize} bytes)", fontSize = 13.sp) }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(checked = s.eraseBeforeWrite, onCheckedChange = vm::setEraseBeforeWrite)
                    Spacer(Modifier.width(8.dp))
                    Text("লেখার আগে ইরেজ করুন")
                }
            }
        }

        // 5
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.message, style = MaterialTheme.typography.bodyLarge)
                if (s.busy) {
                    LinearProgressIndicator(progress = { s.progress }, modifier = Modifier.fillMaxWidth())
                    OutlinedButton(onClick = vm::cancel) { Text("বাতিল") }
                }
            }
        }

        // 6
        item {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("লগ", style = MaterialTheme.typography.titleMedium)
                    s.logs.takeLast(8).forEach { Text(it, fontSize = 12.sp) }
                }
            }
        }

        // 7
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = gotoText,
                    onValueChange = { gotoText = it.filter { ch -> ch.isLetterOrDigit() }.take(8) },
                    label = { Text("অফসেট (hex)") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                Spacer(Modifier.width(8.dp))
                Button(
                    onClick = {
                        val off = gotoText.toLongOrNull(16)
                        if (off != null && off < s.dumpSize) {
                            scope.launch { listState.scrollToItem(HEADER_ITEMS + (off / 8).toInt()) }
                        }
                    },
                    enabled = s.dumpSize > 0
                ) { Text("যাও") }
            }
        }

        items(rows) { r ->
            dump?.let { d ->
                Text(hexLine(d, r), fontFamily = FontFamily.Monospace, fontSize = 11.sp, maxLines = 1)
            }
        }
    }
}

private fun hexLine(d: ByteArray, row: Int): String {
    val off = row * 8
    val sb = StringBuilder()
    sb.append("%06X: ".format(off))
    for (i in 0 until 8) {
        val p = off + i
        if (p < d.size) sb.append("%02X ".format(d[p].toInt() and 0xFF)) else sb.append("   ")
    }
    sb.append('|')
    for (i in 0 until 8) {
        val p = off + i
        if (p < d.size) {
            val b = d[p].toInt() and 0xFF
            sb.append(if (b in 32..126) b.toChar() else '.')
        } else {
            sb.append(' ')
        }
    }
    sb.append('|')
    return sb.toString()
}
