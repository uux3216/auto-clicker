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
    private var token = 0
    private var gestureInFlight = false
    private var holdMs = 2000L
    private var breakMs = 1000L
    private var x = 540f
    private var y = 960f

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { stopRun() }

    override fun onDestroy() {
        stopRun()
        if (instance === this) instance = null
        super.onDestroy()
    }

    @Synchronized fun startRun(settings: Map<*, *>) {
        stopRun()
        latestSettings = settings
        holdMs = (((settings["holdSeconds"] as? Number)?.toDouble() ?: 2.0) * 1000.0)
            .toLong().coerceIn(1L, 60000L)
        breakMs = (((settings["holdBreakSeconds"] as? Number)?.toDouble() ?: 1.0) * 1000.0)
            .toLong().coerceIn(0L, 3600000L)
        val points = settings["points"] as? List<*>
        val point = points?.firstOrNull() as? Map<*, *>
        x = (point?.get("x") as? Number)?.toFloat() ?: 540f
        y = (point?.get("y") as? Number)?.toFloat() ?: 960f
        running = true
        token++
        val current = token
        handler.post { runHold(current) }
    }

    @Synchronized fun stopRun() {
        running = false
        token++
        handler.removeCallbacksAndMessages(null)
        // AccessibilityService cannot guarantee cancellation of a gesture already dispatched.
    }

    private fun runHold(current: Int) {
        if (!running || current != token || gestureInFlight) return
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, holdMs))
            .build()
        gestureInFlight = true
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (!running || current != token) return
                handler.postDelayed({ runHold(current) }, breakMs)
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (running && current == token) {
                    handler.postDelayed({ runHold(current) }, 250L)
                }
            }
        }, handler)
        if (!accepted) {
            gestureInFlight = false
            if (running && current == token) handler.postDelayed({ runHold(current) }, 300L)
        }
    }
}
