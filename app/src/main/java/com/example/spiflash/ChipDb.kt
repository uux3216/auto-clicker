package com.example.spiflash

data class ChipInfo(
    val mfr: Int,
    val type: Int,
    val cap: Int,
    val vendor: String,
    val part: String?,
    val sizeBytes: Int // 0 = অজানা
) {
    val idHex: String get() = "%02X %02X %02X".format(mfr, type, cap)
}

fun fmtSize(b: Int): String = if (b >= (1 shl 20)) "${b shr 20} MB" else "${b shr 10} KB"

/** ছোট ডাটাবেস — JEDEC ID থেকে নির্মাতা/পার্ট চেনা। দরকার মতো বাড়িয়ে নিন। */
object ChipDb {
    private val vendors = mapOf(
        0xEF to "Winbond", 0xC2 to "Macronix", 0xC8 to "GigaDevice",
        0x20 to "Micron/XMC", 0x1F to "Adesto/Atmel", 0x01 to "Spansion/Cypress",
        0xBF to "SST/Microchip", 0x9D to "ISSI", 0x85 to "Puya",
        0x0B to "XTX", 0x68 to "Boya", 0x5E to "Zbit", 0xA1 to "Fudan Micro"
    )

    private val parts = mapOf(
        0xEF4014 to "W25Q80", 0xEF4015 to "W25Q16", 0xEF4016 to "W25Q32",
        0xEF4017 to "W25Q64", 0xEF4018 to "W25Q128", 0xEF4019 to "W25Q256",
        0xC22014 to "MX25L8006E", 0xC22015 to "MX25L1606E", 0xC22016 to "MX25L3206E",
        0xC22017 to "MX25L6406E", 0xC22018 to "MX25L12805D",
        0xC84014 to "GD25Q80", 0xC84015 to "GD25Q16", 0xC84016 to "GD25Q32",
        0xC84017 to "GD25Q64", 0xC84018 to "GD25Q128"
    )

    fun describe(mfr: Int, type: Int, cap: Int): ChipInfo {
        // বেশির ভাগ চিপে cap বাইট = log2(সাইজ বাইটে)। 64KB..64MB
        val size = if (cap in 0x10..0x1A) 1 shl cap else 0
        val vendor = vendors[mfr] ?: "অজানা (0x%02X)".format(mfr)
        val part = parts[(mfr shl 16) or (type shl 8) or cap]
        return ChipInfo(mfr, type, cap, vendor, part, size)
    }
}
