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
    }

    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    @Volatile private var gestureInFlight = false
    @Volatile private var runToken = 0

    override fun onServiceConnected() { instance = this }
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() { stopHoldLoop() }

    override fun onDestroy() {
        stopHoldLoop()
        if (instance === this) instance = null
        super.onDestroy()
    }

    @Synchronized fun startHoldLoop(holdSeconds: Long, breakSeconds: Long) {
        stopHoldLoop()
        TargetStore.holdSeconds = holdSeconds.coerceIn(1, 3600)
        TargetStore.breakSeconds = breakSeconds.coerceIn(0, 86400)
        running = true
        TargetStore.running = true
        runToken++
        handler.post { runGesture(runToken) }
    }

    @Synchronized fun stopHoldLoop() {
        running = false
        TargetStore.running = false
        runToken++
        handler.removeCallbacksAndMessages(null)
        // Android does not expose a guaranteed API to cancel every already-dispatched gesture.
        // The token prevents any new cycle from being scheduled after Stop.
    }

    private fun runGesture(token: Int) {
        if (token != runToken || !running || gestureInFlight) return

        val display = resources.displayMetrics
        // Use the user-positioned P1 marker, clamped inside the current display.
        val x = TargetStore.targetX.coerceIn(1f, (display.widthPixels - 1).toFloat())
        val y = TargetStore.targetY.coerceIn(1f, (display.heightPixels - 1).toFloat())
        val path = Path().apply { moveTo(x, y); lineTo(x + 0.1f, y + 0.1f) }
        val durationMs = (TargetStore.holdSeconds * 1000L).coerceIn(1L, 60000L)
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
            .build()

        gestureInFlight = true
        val accepted = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (token != runToken || !running) return
                val delay = TargetStore.breakSeconds * 1000L
                handler.postDelayed({ runGesture(token) }, delay)
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                gestureInFlight = false
                if (token != runToken || !running) return
                handler.postDelayed({ runGesture(token) }, 500L)
            }
        }, handler)

        if (!accepted) {
            gestureInFlight = false
            if (token == runToken && running) {
                handler.postDelayed({ runGesture(token) }, 1000L)
            }
        }
    }
}
