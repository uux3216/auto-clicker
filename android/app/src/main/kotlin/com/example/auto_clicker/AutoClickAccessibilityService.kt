package com.example.auto_clicker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

class AutoClickAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile var instance: AutoClickAccessibilityService? = null
        @Volatile var latestSettings: Map<*, *> = emptyMap<Any, Any>()
    }

    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    @Volatile private var paused = false
    private var completedCycles = 0
    private var pointIndex = 0
    private var settings: Map<*, *> = emptyMap<Any, Any>()
    private var gestureInFlight = false
    private var runToken = 0

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { stopRun() }
    override fun onDestroy() {
        stopRun()
        if (instance === this) instance = null
        super.onDestroy()
    }

    @Synchronized fun startRun(newSettings: Map<*, *>) {
        stopRun()
        settings = newSettings
        latestSettings = newSettings
        completedCycles = 0
        pointIndex = 0
        paused = false
        running = true
        runToken++
        val token = runToken
        handler.post { if (token == runToken) runNext(token) }
    }

    @Synchronized fun stopRun() {
        running = false
        paused = false
        runToken++
        handler.removeCallbacksAndMessages(null)
        // Android does not expose a guaranteed force-release/cancel API for every dispatched gesture.
    }

    @Synchronized fun pauseRun() {
        if (running) paused = true
    }

    @Synchronized fun resumeRun() {
        if (running && paused) {
            paused = false
            handler.post { runNext(runToken) }
        }
    }

    fun isRunning() = running
    fun isPaused() = paused

    private fun intValue(key: String, fallback: Int) =
        (settings[key] as? Number)?.toInt() ?: fallback
    private fun longValue(key: String, fallback: Long) =
        (settings[key] as? Number)?.toLong() ?: fallback
    private fun boolValue(key: String, fallback: Boolean) =
        settings[key] as? Boolean ?: fallback
    private fun mode() = settings["mode"] as? String ?: "single"

    private fun runNext(token: Int) {
        if (token != runToken || !running || paused || gestureInFlight) return
        val infinity = boolValue("infinity", true)
        val mode = mode()
        val points = TargetStore.points.toList().ifEmpty {
            val configured = settings["points"] as? List<*> ?: emptyList<Any>()
            configured.mapNotNull {
                val m = it as? Map<*, *> ?: return@mapNotNull null
                TargetPoint((m["x"] as? Number)?.toFloat() ?: 540f,
                    (m["y"] as? Number)?.toFloat() ?: 960f)
            }
        }
        if (points.isEmpty()) {
            stopRun()
            return
        }

        val point = if (mode == "multiple") points[pointIndex.coerceIn(0, points.lastIndex)]
                    else points.first()
        val hold = mode == "hold"
        val duration = if (hold) intValue("holdMs", 3000).coerceIn(1, 60000) else 80
        val path = Path().apply { moveTo(point.x, point.y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, duration.toLong()))
            .build()

        gestureInFlight = true
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (token != runToken || !running) return
                if (paused) return
                if (mode == "multiple") {
                    pointIndex++
                    if (pointIndex >= points.size) {
                        pointIndex = 0
                        completedCycles++
                    }
                } else {
                    completedCycles++
                }

                val repeatSeconds = longValue("repeatSeconds", 100L).coerceIn(1L, 86400L)
                val startedAt = (settings["startedAtMs"] as? Number)?.toLong()
                val elapsedMs = if (startedAt == null) 0L else System.currentTimeMillis() - startedAt
                val finishedByTime = !infinity && startedAt != null && elapsedMs >= repeatSeconds * 1000L
                val breakMs = if (hold) intValue("holdBreakMs", 500) else intValue("breakMs", 100)
                if (finishedByTime) {
                    running = false
                    return
                }
                handler.postDelayed({ runNext(token) }, breakMs.coerceIn(0, 60000).toLong())
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (token != runToken || !running || paused) return
                handler.postDelayed({ runNext(token) }, 250)
            }
        }, handler)
        if (!accepted) {
            gestureInFlight = false
            if (running && !paused && token == runToken) {
                handler.postDelayed({ runNext(token) }, 300)
            }
        }
    }
}
