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
    private var completed = 0
    private var pointIndex = 0
    private var settings: Map<*, *> = emptyMap<Any, Any>()

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
        completed = 0
        pointIndex = 0
        running = true
        handler.post { runNext() }
    }

    fun stopRun() {
        running = false
        handler.removeCallbacksAndMessages(null)
        // AccessibilityService has no public "release finger now" API; dispatching a short
        // gesture is not equivalent to cancelling every in-flight gesture on every device.
    }

    private fun intValue(key: String, fallback: Int) = (settings[key] as? Number)?.toInt() ?: fallback
    private fun boolValue(key: String, fallback: Boolean) = settings[key] as? Boolean ?: fallback
    private fun mode() = settings["mode"] as? String ?: "single"

    private fun runNext() {
        if (!running) return
        val infinity = boolValue("infinity", true)
        val repeatLimit = if (mode() == "hold") 1 else intValue("repeatCount", 100)
        val points = settings["points"] as? List<*> ?: emptyList<Any>()
        val point = if (mode() == "multiple" && points.isNotEmpty()) {
            val map = points[pointIndex % points.size] as? Map<*, *> ?: emptyMap<Any, Any>()
            Pair((map["x"] as? Number)?.toFloat() ?: 540f, (map["y"] as? Number)?.toFloat() ?: 960f)
        } else Pair(
            (points.firstOrNull() as? Map<*, *>)?.get("x").let { (it as? Number)?.toFloat() ?: 540f },
            (points.firstOrNull() as? Map<*, *>)?.get("y").let { (it as? Number)?.toFloat() ?: 960f }
        )

        val hold = mode() == "hold"
        val duration = if (hold) intValue("holdMs", 3000).coerceAtLeast(1) else 80
        val path = Path().apply { moveTo(point.first, point.second) }
        val stroke = GestureDescription.StrokeDescription(path, 0, duration.toLong())
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                if (!running) return
                completed++
                if (mode() == "multiple" && points.isNotEmpty()) pointIndex++
                val breakMs = if (hold) intValue("holdBreakMs", 500) else intValue("breakMs", 100)
                val finished = !infinity && completed >= repeatLimit.coerceAtLeast(1) &&
                    (mode() != "multiple" || pointIndex % points.size == 0)
                if (finished) { running = false; return }
                handler.postDelayed({ runNext() }, breakMs.coerceAtLeast(0).toLong())
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                if (running) handler.postDelayed({ runNext() }, 100)
            }
        }, handler)
        if (!accepted && running) handler.postDelayed({ runNext() }, 250)
    }
}
