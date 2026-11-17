package com.example.spiflash

import android.app.Application
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class UiState(
    val connected: Boolean = false,
    val busy: Boolean = false,
    val chip: ChipInfo? = null,
    val sizeOverride: Int = 0,
    val statusReg: Int? = null,
    val progress: Float = 0f,
    val message: String = "CH341 সংযোগ করুন",
    val logs: List<String> = emptyList(),
    val dumpSize: Int = 0,
    val dumpVersion: Int = 0,
    val fileName: String? = null,
    val fileSize: Int = 0,
    val eraseBeforeWrite: Boolean = true
)

class MainViewModel(app: Application) : AndroidViewModel(app) {

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui

    private val usb: UsbManager = app.getSystemService(UsbManager::class.java)
    private var driver: Ch341Driver? = null
    private var flash: SpiFlash? = null
    private var job: Job? = null

    @Volatile
    var dump: ByteArray? = null
        private set
    private var fileData: ByteArray? = null

    private inline fun upd(f: UiState.() -> UiState) {
        _ui.update { it.f() }
    }

    private fun addLog(s: String) = upd { copy(logs = (logs + s).takeLast(60)) }

    fun setMessage(s: String) = upd { copy(message = s) }
    fun setSizeOverride(bytes: Int) = upd { copy(sizeOverride = bytes) }
    fun setEraseBeforeWrite(v: Boolean) = upd { copy(eraseBeforeWrite = v) }

    // ---------- সংযোগ ----------

    fun connect(device: UsbDevice) {
        if (driver != null) return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val d = Ch341Driver(usb, device)
                d.open()
                driver = d
                flash = SpiFlash(d)
                upd { copy(connected = true, message = "CH341 সংযুক্ত") }
                addLog("CH341 সংযুক্ত হয়েছে")
                doDetect()
            } catch (e: Exception) {
                addLog("সংযোগ ব্যর্থ: ${e.message}")
                upd { copy(message = "সংযোগ ব্যর্থ") }
            }
        }
    }

    fun disconnect() {
        val running = job
        running?.cancel()
        viewModelScope.launch(Dispatchers.IO) {
            running?.join()
            runCatching { driver?.close() }
            driver = null
            flash = null
            upd { copy(connected = false, busy = false, chip = null, statusReg = null, message = "সংযোগ বিচ্ছিন্ন") }
            addLog("সংযোগ বিচ্ছিন্ন")
        }
    }

    fun cancel() {
        job?.cancel()
    }

    override fun onCleared() {
        runCatching { driver?.close() }
        super.onCleared()
    }

    // ---------- সাধারণ সাহায্যকারী ----------

    private fun launchOp(title: String, block: CoroutineScope.() -> Unit) {
        if (_ui.value.busy) return
        upd { copy(busy = true, progress = 0f, message = title) }
        job = viewModelScope.launch(Dispatchers.IO) {
            try {
                block()
            } catch (e: CancellationException) {
                addLog("বাতিল করা হয়েছে")
                upd { copy(message = "বাতিল") }
            } catch (e: Exception) {
                addLog("ত্রুটি: ${e.message ?: e.javaClass.simpleName}")
                upd { copy(message = "ত্রুটি হয়েছে") }
            } finally {
                upd { copy(busy = false) }
            }
        }
    }

    private fun CoroutineScope.ticker(): (Float) -> Unit = { p ->
        ensureActive()
        upd { copy(progress = p) }
    }

    private fun chipSize(): Int {
        val s = _ui.value
        val n = s.chip?.sizeBytes ?: 0
        return if (n > 0) n else s.sizeOverride
    }

    private fun requireChip(): Pair<SpiFlash, Int> {
        val f = flash ?: throw IllegalStateException("প্রোগ্রামার সংযুক্ত নেই")
        if (_ui.value.chip == null) throw IllegalStateException("আগে চিপ শনাক্ত করুন")
        val size = chipSize()
        if (size <= 0) throw IllegalStateException("চিপের সাইজ বেছে নিন")
        f.configure(size)
        return f to size
    }

    // ---------- শনাক্ত ----------

    fun detect() = launchOp("চিপ শনাক্ত করা হচ্ছে…") { doDetect() }

    private fun doDetect() {
        val f = flash ?: throw IllegalStateException("প্রোগ্রামার সংযুক্ত নেই")
        val id = f.readJedecId()
        val idHex = id.joinToString(" ") { "%02X".format(it) }
        if (id.all { it == 0x00 } || id.all { it == 0xFF }) {
            upd { copy(chip = null, statusReg = null, message = "চিপ পাওয়া যায়নি") }
            addLog("চিপ পাওয়া যায়নি (ID: $idHex) — ক্লিপের দিক, সংযোগ ও ভোল্টেজ চেক করুন")
            return
        }
        val info = ChipDb.describe(id[0], id[1], id[2])
        val sr = f.readStatus()
        upd { copy(chip = info, statusReg = sr, message = "চিপ পাওয়া গেছে") }
        addLog("চিপ: ${info.vendor} ${info.part ?: ""} [${info.idHex}] " +
            if (info.sizeBytes > 0) fmtSize(info.sizeBytes) else "সাইজ অজানা")
    }

    // ---------- রিড ----------

    fun readChip() = launchOp("চিপ পড়া হচ্ছে…") {
        val (f, size) = requireChip()
        val t0 = System.currentTimeMillis()
        val data = f.readAll(size, ticker())
        dump = data
        val sec = (System.currentTimeMillis() - t0) / 1000.0
        upd { copy(dumpSize = data.size, dumpVersion = dumpVersion + 1, message = "পড়া সম্পূর্ণ", progress = 1f) }
        addLog("${data.size / 1024} KB পড়া হয়েছে (%.1f সেকেন্ড)".format(sec))
    }

    fun saveDump(uri: Uri) {
        val d = dump ?: return
        viewModelScope.launch(Dispatchers.IO) {
            try {
                getApplication<Application>().contentResolver.openOutputStream(uri)?.use { it.write(d) }
                addLog("ডাম্প সেভ হয়েছে (${d.size} bytes)")
            } catch (e: Exception) {
                addLog("সেভ ব্যর্থ: ${e.message}")
            }
        }
    }

    // ---------- ইরেজ ----------

    fun eraseChip() = launchOp("ইরেজ হচ্ছে…") {
        val (f, size) = requireChip()
        doErase(f, size)
        upd { copy(message = "ইরেজ সম্পূর্ণ", progress = 1f) }
    }

    private fun CoroutineScope.doErase(f: SpiFlash, size: Int) {
        val t0 = System.currentTimeMillis()
        f.chipErase { sec ->
            ensureActive()
            upd { copy(message = "ইরেজ হচ্ছে… ${sec}s") }
        }
        addLog("ইরেজ কমান্ড শেষ (${(System.currentTimeMillis() - t0) / 1000}s), ব্ল্যাঙ্ক চেক হচ্ছে")
        upd { copy(message = "ব্ল্যাঙ্ক ভেরিফাই হচ্ছে…", progress = 0f) }
        val bad = f.verifyBlank(size, ticker())
        if (bad >= 0) {
            throw IllegalStateException(
                "ইরেজ ব্যর্থ — অফসেট 0x%X এ 0xFF নেই। Write-protect (BP বিট) থাকতে পারে।".format(bad)
            )
        }
        addLog("ইরেজ ও ব্ল্যাঙ্ক ভেরিফাই সফল")
    }

    // ---------- ফাইল, রাইট, ভেরিফাই ----------

    fun loadFile(uri: Uri) {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val cr = getApplication<Application>().contentResolver
                val bytes = cr.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("ফাইল খোলা যায়নি")
                var name = "file.bin"
                cr.query(uri, null, null, null, null)?.use { c ->
                    val i = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (i >= 0 && c.moveToFirst()) name = c.getString(i)
                }
                fileData = bytes
                upd { copy(fileName = name, fileSize = bytes.size) }
                addLog("ফাইল লোড: $name (${bytes.size} bytes)")
            } catch (e: Exception) {
                addLog("ফাইল লোড ব্যর্থ: ${e.message}")
            }
        }
    }

    private fun requireFile(size: Int): ByteArray {
        val data = fileData ?: throw IllegalStateException("আগে ফাইল বাছুন")
        if (data.size > size) {
            throw IllegalStateException("ফাইল (${data.size} B) চিপের চেয়ে বড় ($size B)")
        }
        return data
    }

    fun writeFile() = launchOp("রাইট শুরু হচ্ছে…") {
        val (f, size) = requireChip()
        val data = requireFile(size)
        if (_ui.value.eraseBeforeWrite) doErase(f, size)
        upd { copy(message = "রাইট হচ্ছে…", progress = 0f) }
        val t0 = System.currentTimeMillis()
        f.program(data, ticker())
        addLog("রাইট শেষ (${(System.currentTimeMillis() - t0) / 1000}s), ভেরিফাই হচ্ছে")
        upd { copy(message = "ভেরিফাই হচ্ছে…", progress = 0f) }
        val bad = f.verify(data, ticker())
        if (bad >= 0) {
            throw IllegalStateException(
                "ভেরিফাই ব্যর্থ — অফসেট 0x%X এ মিল নেই। চিপ ইরেজ করা ছিল কি না বা write-protect দেখুন।".format(bad)
            )
        }
        addLog("রাইট ও ভেরিফাই সফল")
        upd { copy(message = "রাইট সম্পূর্ণ", progress = 1f) }
    }

    fun verifyFile() = launchOp("ভেরিফাই হচ্ছে…") {
        val (f, size) = requireChip()
        val data = requireFile(size)
        val bad = f.verify(data, ticker())
        if (bad >= 0) {
            throw IllegalStateException("ভেরিফাই ব্যর্থ — অফসেট 0x%X এ মিল নেই".format(bad))
        }
        addLog("ভেরিফাই সফল — চিপ ও ফাইল মিলেছে")
        upd { copy(message = "ভেরিফাই সফল", progress = 1f) }
    }
}
