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
    @Volatile private var generation = 0
    private var settings: Map<*, *> = emptyMap<Any, Any>()
    private var completed = 0
    private var pointIndex = 0

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { stopRun() }
    override fun onDestroy() {
        stopRun()
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun startRun(newSettings: Map<*, *>) {
        stopRun()
        settings = newSettings
        TargetStore.currentMode = settings["mode"] as? String ?: "single"
        completed = 0; pointIndex = 0; running = true; TargetStore.running = true
        val token = generation
        handler.post { if (running && token == generation) runNext(token) }
    }

    fun stopRun() {
        running = false
        TargetStore.running = false
        generation++
        handler.removeCallbacksAndMessages(null)
        // Cancellation callback is best-effort; Android can finish an in-flight gesture asynchronously.
        try { dispatchGesture(GestureDescription.Builder().build(), null, handler) } catch (_: Exception) {}
    }

    private fun intValue(key: String, fallback: Int) = (settings[key] as? Number)?.toInt() ?: fallback
    private fun boolValue(key: String, fallback: Boolean) = settings[key] as? Boolean ?: fallback
    private fun mode() = settings["mode"] as? String ?: "single"

    private fun runNext(token: Int) {
        if (!running || token != generation) return
        val infinite = boolValue("infinity", true)
        val repeatLimit = if (mode() == "hold") 1 else intValue("repeatCount", 100).coerceAtLeast(1)
        val points = TargetStore.points.toList()
        val chosen = if (mode() == "multiple" && points.isNotEmpty()) points[pointIndex % points.size]
            else points.firstOrNull() ?: TargetPoint(300f, 600f)

        val isHold = mode() == "hold"
        val duration = if (isHold) intValue("holdMs", 3000).coerceAtLeast(1) else 70
        val path = Path().apply { moveTo(chosen.x, chosen.y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.toLong())
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                if (!running || token != generation) return
                completed++
                if (mode() == "multiple" && points.isNotEmpty()) pointIndex++
                val isEndOfRound = mode() != "multiple" || points.isEmpty() || pointIndex % points.size == 0
                val done = !infinite && isEndOfRound && completed >= repeatLimit * if (mode() == "multiple") points.size else 1
                if (done) { stopRun(); return }
                val pause = if (isHold) intValue("holdBreakMs", 500) else intValue("breakMs", 100)
                handler.postDelayed({ if (running && token == generation) runNext(token) }, pause.coerceAtLeast(0).toLong())
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                // If Stop has been pressed, do not restart. Otherwise retry conservatively.
                if (running && token == generation) handler.postDelayed({ runNext(token) }, 150)
            }
        }, handler)
        if (!accepted && running && token == generation) handler.postDelayed({ runNext(token) }, 250)
    }
}
