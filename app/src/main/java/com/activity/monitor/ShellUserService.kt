package com.activity.monitor

import android.content.Intent
import android.os.IBinder
import rikka.shizuku.Shizuku

/**
 * Runs in the Shizuku UserService process under the granted shell identity.
 * Exposes a narrowly allowlisted set of read-only diagnostics over AIDL.
 */
class ShellUserService : Shizuku.UserService() {

    private val binder = object : IUserService.Stub() {
        override fun runCommand(command: String): String {
            val allowed = setOf(
                "dumpsys appops",
                "dumpsys media.camera",
                "dumpsys audio"
            )
            require(command in allowed) { "Command is not allowed" }

            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            val stdout = process.inputStream.bufferedReader().use { it.readText() }
            val stderr = process.errorStream.bufferedReader().use { it.readText() }
            val exit = process.waitFor()

            return buildString {
                appendLine("EXIT_CODE=$exit")
                if (stdout.isNotBlank()) appendLine(stdout)
                if (stderr.isNotBlank()) appendLine(stderr)
            }.trim()
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder
}
