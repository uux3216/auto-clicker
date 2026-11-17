package com.example.spiflash

import java.io.IOException

/** স্ট্যান্ডার্ড SPI NOR ফ্ল্যাশের কমান্ড: ID, read, erase, program, verify */
class SpiFlash(private val drv: Ch341Driver) {

    companion object {
        private const val BLOCK = 16 * 1024
        private const val PAGE = 256
    }

    private var addr4 = false // ১৬MB-এর বেশি চিপে 4-byte address

    fun configure(sizeBytes: Int) {
        addr4 = sizeBytes > 16 * 1024 * 1024
    }

    fun readJedecId(): IntArray {
        val r = drv.spi(byteArrayOf(0x9F.toByte()), 3)
        return IntArray(3) { r[it].toInt() and 0xFF }
    }

    fun readStatus(): Int = drv.spi(byteArrayOf(0x05), 1)[0].toInt() and 0xFF

    private fun cmd(op3: Int, op4: Int, addr: Int): ByteArray =
        if (addr4) byteArrayOf(
            op4.toByte(), (addr ushr 24).toByte(), (addr ushr 16).toByte(),
            (addr ushr 8).toByte(), addr.toByte()
        ) else byteArrayOf(
            op3.toByte(), (addr ushr 16).toByte(), (addr ushr 8).toByte(), addr.toByte()
        )

    private fun writeEnable() {
        drv.spi(byteArrayOf(0x06))
        if ((readStatus() and 0x02) == 0) {
            throw IOException("Write Enable ব্যর্থ (WEL সেট হয়নি) — ক্লিপ/WP পিন চেক করুন")
        }
    }

    private fun waitReady(timeoutMs: Long, pollMs: Long, onTick: ((Int) -> Unit)? = null) {
        val t0 = System.currentTimeMillis()
        var lastSec = -1
        while (true) {
            if ((readStatus() and 0x01) == 0) return
            val el = System.currentTimeMillis() - t0
            if (el > timeoutMs) throw IOException("টাইমআউট: চিপ BUSY অবস্থায় আটকে আছে")
            val sec = (el / 1000).toInt()
            if (sec != lastSec) {
                lastSec = sec
                onTick?.invoke(sec)
            }
            if (pollMs > 0) Thread.sleep(pollMs)
        }
    }

    fun read(addr: Int, len: Int): ByteArray = drv.spi(cmd(0x03, 0x13, addr), len)

    fun readAll(size: Int, onProgress: (Float) -> Unit): ByteArray {
        val out = ByteArray(size)
        var off = 0
        while (off < size) {
            val n = minOf(BLOCK, size - off)
            val blk = read(off, n)
            System.arraycopy(blk, 0, out, off, n)
            off += n
            onProgress(off.toFloat() / size)
        }
        return out
    }

    fun chipErase(onTick: (Int) -> Unit) {
        writeEnable()
        drv.spi(byteArrayOf(0xC7.toByte()))
        waitReady(10 * 60 * 1000L, 100, onTick)
    }

    fun program(data: ByteArray, onProgress: (Float) -> Unit) {
        var addr = 0
        var pages = 0
        while (addr < data.size) {
            val n = minOf(PAGE - (addr and (PAGE - 1)), data.size - addr)
            var blank = true
            for (i in 0 until n) {
                if (data[addr + i] != 0xFF.toByte()) { blank = false; break }
            }
            if (!blank) { // ইরেজ করা চিপে 0xFF লেখা আর না লেখা একই
                writeEnable()
                drv.spi(cmd(0x02, 0x12, addr) + data.copyOfRange(addr, addr + n))
                waitReady(5000, 0)
            }
            addr += n
            pages++
            if (pages % 64 == 0 || addr >= data.size) onProgress(addr.toFloat() / data.size)
        }
    }

    /** মিল থাকলে -1, না থাকলে প্রথম গরমিলের অফসেট */
    fun verify(expected: ByteArray, onProgress: (Float) -> Unit): Int {
        var off = 0
        while (off < expected.size) {
            val n = minOf(BLOCK, expected.size - off)
            val blk = read(off, n)
            for (i in 0 until n) if (blk[i] != expected[off + i]) return off + i
            off += n
            onProgress(off.toFloat() / expected.size)
        }
        return -1
    }

    /** পুরো চিপ 0xFF কি না — মিল থাকলে -1, নইলে প্রথম গরমিলের অফসেট */
    fun verifyBlank(size: Int, onProgress: (Float) -> Unit): Int {
        var off = 0
        while (off < size) {
            val n = minOf(BLOCK, size - off)
            val blk = read(off, n)
            for (i in 0 until n) if (blk[i] != 0xFF.toByte()) return off + i
            off += n
            onProgress(off.toFloat() / size)
        }
        return -1
    }
}
