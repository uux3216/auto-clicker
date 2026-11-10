package com.activity.monitor

import java.util.concurrent.TimeUnit

/**
 * Shizuku UserService process. The class itself is the Binder implementation;
 * it is not an Android Service and must not define onBind().
 */
class ShellUserService : IUserService.Stub() {

    override fun runCommand(command: String): String {
        val allowed = setOf(
            "dumpsys appops",
            "dumpsys media.camera",
            "dumpsys audio"
        )
        require(command in allowed) { "Command is not allowed" }

        val process = ProcessBuilder("sh", "-c", command)
            .redirectErrorStream(true)
            .start()

        val output = StringBuilder()
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(12)
        process.inputStream.bufferedReader().use { reader ->
            while (output.length < MAX_OUTPUT_CHARS &&
                System.nanoTime() < deadline
            ) {
                val line = reader.readLine() ?: break
                output.append(line).append('\n')
            }
        }

        val finished = process.waitFor(1, TimeUnit.SECONDS)
        if (!finished) process.destroyForcibly()

        return buildString {
            appendLine("EXIT_CODE=${if (finished) process.exitValue() else "TIMEOUT"}")
            append(output)
            if (output.length >= MAX_OUTPUT_CHARS) {
                appendLine("\n[Output truncated]")
            }
        }.take(MAX_OUTPUT_CHARS + 100)
    }

    private companion object {
        const val MAX_OUTPUT_CHARS = 100_000
    }
}
