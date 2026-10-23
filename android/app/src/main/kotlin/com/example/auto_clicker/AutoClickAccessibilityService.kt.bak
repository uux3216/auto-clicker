package com.example.auto_clicker

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class AutoClickAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "HoldClickerDebug"
        @Volatile var instance: AutoClickAccessibilityService? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    @Volatile private var gestureInFlight = false
    @Volatile private var runToken = 0

    override fun onServiceConnected() {
        instance = this
        TargetStore.accessibilityConnected = true
        TargetStore.report("ACCESSIBILITY_CONNECTED", "Accessibility Service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {
        Log.w(TAG, "ACCESSIBILITY_INTERRUPTED")
        TargetStore.report("ACCESSIBILITY_INTERRUPTED", "Android interrupted the service", "Accessibility interrupted")
        stopHoldLoop()
    }

    override fun onDestroy() {
        Log.w(TAG, "SERVICE_DESTROYED")
        TargetStore.accessibilityConnected = false
        TargetStore.report("SERVICE_DESTROYED", "Accessibility Service disconnected", "Service destroyed")
        stopHoldLoop()
        if (instance === this) instance = null
        super.onDestroy()
    }

    @Synchronized fun startHoldLoop(holdSeconds: Long, breakSeconds: Long) {
        Log.i(TAG, "START_REQUEST: holdSeconds=$holdSeconds breakSeconds=$breakSeconds serviceConnected=${instance != null}")
        TargetStore.report("START_REQUEST", "Starting hold loop")
        stopHoldLoop()
        TargetStore.holdSeconds = holdSeconds.coerceIn(1, 3600)
        TargetStore.breakSeconds = breakSeconds.coerceIn(0, 86400)
        running = true
        TargetStore.running = true
        runToken++
        val token = runToken
        Log.i(TAG, "STARTED: token=$token hold=${TargetStore.holdSeconds}s break=${TargetStore.breakSeconds}s")
        TargetStore.report("RUNNING", "Running: hold ${TargetStore.holdSeconds}s, break ${TargetStore.breakSeconds}s")
        handler.post { runGesture(token) }
    }

    @Synchronized fun stopHoldLoop() {
        Log.i(TAG, "STOP_REQUEST: running=$running gestureInFlight=$gestureInFlight token=$runToken")
        running = false
        TargetStore.running = false
        runToken++
        handler.removeCallbacksAndMessages(null)
        TargetStore.gestureInFlight = false
        TargetStore.report("STOPPED", "Stopped; an already-dispatched gesture may finish")
        Log.i(TAG, "STOPPED: future cycles cancelled; Android may still complete a gesture already dispatched")
    }

    private fun runGesture(token: Int) {
        if (token != runToken || !running || gestureInFlight) {
            Log.d(TAG, "SKIP_GESTURE: token=$token currentToken=$runToken running=$running inFlight=$gestureInFlight")
            return
        }

        val display = resources.displayMetrics
        val targetX = TargetStore.targetX
        val targetY = TargetStore.targetY

        if (targetX < 0f || targetY < 0f) {
            Log.e(TAG, "TARGET_INVALID: x=$targetX y=$targetY; drag target point before starting")
            TargetStore.report("TARGET_INVALID", "Target point position is not set", "Target X/Y < 0")
            running = false
            TargetStore.running = false
            return
        }

        val x = targetX.coerceIn(1f, (display.widthPixels - 1).toFloat())
        val y = targetY.coerceIn(1f, (display.heightPixels - 1).toFloat())
        val durationMs = (TargetStore.holdSeconds * 1000L).coerceIn(1L, 60000L)
        Log.i(TAG, "GESTURE_PREPARE: x=$x y=$y display=${display.widthPixels}x${display.heightPixels} density=${display.density} durationMs=$durationMs")
        TargetStore.report("GESTURE_PREPARE", "Sending hold at X=${x.toInt()}, Y=${y.toInt()} for ${durationMs}ms")

        val path = Path().apply { moveTo(x, y) }
        val gesture = try {
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "GESTURE_BUILD_FAILED", e)
            running = false
            TargetStore.running = false
            return
        }

        gestureInFlight = true
        TargetStore.gestureInFlight = true
        val accepted = try {
            dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    gestureInFlight = false
                    TargetStore.gestureInFlight = false
                    TargetStore.lastAccepted = "Completed"
                    TargetStore.report("GESTURE_COMPLETED", "Hold completed at X=${x.toInt()}, Y=${y.toInt()}") 
                    Log.i(TAG, "GESTURE_COMPLETED: token=$token running=$running currentToken=$runToken")
                    if (token != runToken || !running) return
                    val delay = TargetStore.breakSeconds * 1000L
                    Log.d(TAG, "BREAK_START: ${delay}ms")
                    handler.postDelayed({
                        Log.d(TAG, "BREAK_END: scheduling next gesture")
                        runGesture(token)
                    }, delay)
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    gestureInFlight = false
                    TargetStore.gestureInFlight = false
                    TargetStore.lastAccepted = "Cancelled"
                    TargetStore.report("GESTURE_CANCELLED", "Android cancelled the gesture", "Gesture cancelled")
                    Log.e(TAG, "GESTURE_CANCELLED: token=$token running=$running currentToken=$runToken")
                    if (token != runToken || !running) return
                    handler.postDelayed({ runGesture(token) }, 500L)
                }
            }, handler)
        } catch (e: Exception) {
            gestureInFlight = false
            Log.e(TAG, "DISPATCH_EXCEPTION", e)
            TargetStore.report("DISPATCH_EXCEPTION", "Exception while sending gesture", e.toString())
            false
        }

        TargetStore.lastAccepted = accepted.toString()
        TargetStore.report("DISPATCH_RESULT", "Android accepted gesture request: $accepted", if (!accepted) "dispatchGesture returned false" else null)
        Log.i(TAG, "DISPATCH_RESULT: accepted=$accepted")
        if (!accepted) {
            gestureInFlight = false
            Log.e(TAG, "DISPATCH_REJECTED: Android did not accept this gesture")
            TargetStore.report("DISPATCH_REJECTED", "Android rejected the gesture", "dispatchGesture returned false")
            if (token == runToken && running) {
                handler.postDelayed({ runGesture(token) }, 1000L)
            }
        }
    }
}
