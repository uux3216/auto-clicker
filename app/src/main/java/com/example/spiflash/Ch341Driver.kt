package com.example.spiflash

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import java.io.IOException

/**
 * CH341A/B (VID 1A86, PID 5512) SPI-stream ড্রাইভার। CS0 (D0) ব্যবহার করে।
 * প্রোটোকলের রেফারেন্স: flashrom / ch341prog
 */
class Ch341Driver(private val manager: UsbManager, private val device: UsbDevice) {

    companion object {
        const val VID = 0x1A86
        const val PID = 0x5512

        private const val PACKET_LEN = 32
        // বাড়ালে স্পিড বাড়ে, তবে আগে টেস্ট করে নিন (বেশি হলে USB stall হতে পারে)
        private const val BATCH_PACKETS = 16
        private const val TIMEOUT_MS = 3000
        private const val READ_BUF = 1024

        private const val CMD_SPI_STREAM = 0xA8
        private const val CMD_UIO_STREAM = 0xAB
        private const val UIO_STM_END = 0x20
        private const val UIO_STM_DIR = 0x40
        private const val UIO_STM_OUT = 0x80

        // CH341 SPI ডেটা LSB-first পাঠায়, তাই প্রতিটি বাইটের বিট উল্টাতে হয়
        private val REV = IntArray(256) { (Integer.reverse(it) ushr 24) and 0xFF }

        private val CS_LOW = byteArrayOf(
            CMD_UIO_STREAM.toByte(), (UIO_STM_OUT or 0x36).toByte(), UIO_STM_END.toByte()
        )
        private val CS_HIGH = byteArrayOf(
            CMD_UIO_STREAM.toByte(), (UIO_STM_OUT or 0x37).toByte(), UIO_STM_END.toByte()
        )
    }

    private var conn: UsbDeviceConnection? = null
    private var iface: UsbInterface? = null
    private var epIn: UsbEndpoint? = null
    private var epOut: UsbEndpoint? = null

    fun open() {
        val c = manager.openDevice(device) ?: throw IOException("USB ডিভাইস খোলা যায়নি")
        val itf = device.getInterface(0)
        if (!c.claimInterface(itf, true)) {
            c.close()
            throw IOException("Interface claim ব্যর্থ")
        }
        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (i in 0 until itf.endpointCount) {
            val ep = itf.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) inEp = ep else outEp = ep
        }
        if (inEp == null || outEp == null) {
            c.releaseInterface(itf)
            c.close()
            throw IOException("Bulk endpoint পাওয়া যায়নি")
        }
        conn = c
        iface = itf
        epIn = inEp
        epOut = outEp
        setPins(true)
        flushIn()
    }

    fun close() {
        try { setPins(false) } catch (_: Exception) {}
        iface?.let { conn?.releaseInterface(it) }
        conn?.close()
        conn = null
        iface = null
    }

    private fun setPins(enable: Boolean) {
        val buf = byteArrayOf(
            CMD_UIO_STREAM.toByte(),
            (UIO_STM_OUT or 0x37).toByte(),                         // CS high, SCK low
            (UIO_STM_DIR or (if (enable) 0x3F else 0x00)).toByte(), // পিন output enable/disable
            UIO_STM_END.toByte()
        )
        bulkWrite(buf, buf.size)
    }

    private fun bulkWrite(buf: ByteArray, len: Int) {
        val c = conn ?: throw IOException("USB সংযুক্ত নয়")
        var off = 0
        while (off < len) {
            val n = c.bulkTransfer(epOut, buf, off, len - off, TIMEOUT_MS)
            if (n <= 0) throw IOException("USB write ব্যর্থ ($n)")
            off += n
        }
    }

    /** পুরনো/অবশিষ্ট ডেটা IN endpoint থেকে ফেলে দেয় */
    private fun flushIn() {
        val c = conn ?: return
        val tmp = ByteArray(READ_BUF)
        repeat(8) {
            if (c.bulkTransfer(epIn, tmp, tmp.size, 30) <= 0) return
        }
    }

    /**
     * need বাইট পড়ে। বাফার ইচ্ছে করে বড় রাখা হয়েছে (flashrom/ch341prog এর মতো),
     * যাতে ডিভাইস প্রত্যাশার চেয়ে বেশি পাঠালে overflow এরর না হয়।
     */
    private fun bulkRead(need: Int): ByteArray {
        val c = conn ?: throw IOException("USB সংযুক্ত নয়")
        val out = ByteArray(need)
        val tmp = ByteArray(READ_BUF)
        var got = 0
        var zeroTries = 0
        while (got < need) {
            val n = c.bulkTransfer(epIn, tmp, tmp.size, TIMEOUT_MS)
            if (n < 0) throw IOException("USB read ব্যর্থ ($n) — পেয়েছি $got/$need বাইট")
            if (n == 0) {
                if (++zeroTries > 10) throw IOException("USB read: খালি উত্তর — পেয়েছি $got/$need বাইট")
                continue
            }
            val take = minOf(n, need - got)
            System.arraycopy(tmp, 0, out, got, take)
            got += take
        }
        return out
    }

    /**
     * একটি SPI ট্রানজ্যাকশন: CS নামানো → tx বাইটগুলো পাঠানো → rxLen বাইট পড়া → CS তোলা।
     * ফেরত আসে শুধু tx-এর পরের rxLen বাইট।
     */
    @Synchronized
    fun spi(tx: ByteArray, rxLen: Int = 0): ByteArray {
        val total = tx.size + rxLen
        val resp = ByteArray(total)
        val perBatch = (PACKET_LEN - 1) * BATCH_PACKETS
        val out = ByteArray(CS_LOW.size + PACKET_LEN * BATCH_PACKETS)
        var pos = 0
        try {
            while (pos < total) {
                val n = minOf(perBatch, total - pos)
                var o = 0
                if (pos == 0) { // CS low প্রথম প্যাকেটের সাথেই যায় (ch341prog এর মতো)
                    System.arraycopy(CS_LOW, 0, out, 0, CS_LOW.size)
                    o = CS_LOW.size
                }
                var i = 0
                while (i < n) {
                    val cnt = minOf(PACKET_LEN - 1, n - i)
                    out[o++] = CMD_SPI_STREAM.toByte()
                    for (k in 0 until cnt) {
                        val idx = pos + i + k
                        val b = if (idx < tx.size) tx[idx].toInt() and 0xFF else 0xFF
                        out[o++] = REV[b].toByte()
                    }
                    i += cnt
                }
                bulkWrite(out, o)
                val r = bulkRead(n)
                for (k in 0 until n) resp[pos + k] = REV[r[k].toInt() and 0xFF].toByte()
                pos += n
            }
            bulkWrite(CS_HIGH, CS_HIGH.size) // CS high আলাদা ট্রান্সফারে
        } catch (e: IOException) {
            try { bulkWrite(CS_HIGH, CS_HIGH.size); flushIn() } catch (_: Exception) {}
            throw e
        }
        return resp.copyOfRange(tx.size, total)
    }
}
