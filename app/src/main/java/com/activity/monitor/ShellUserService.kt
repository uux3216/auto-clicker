package com.activity.monitor

import android.os.Binder
import java.io.InputStreamReader

/**
 * Runs inside Shizuku's shell-identity user-service process.
 * Only a fixed allowlist of read-only diagnostic commands is accepted.
 */
class ShellUserService : IUserService.Stub() {

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
