package com.example.auto_clicker

import android.util.Log

object TargetStore {
    private const val TAG = "HoldClickerDebug"

    @Volatile var holdSeconds: Long = 3
    @Volatile var breakSeconds: Long = 1
    @Volatile var running: Boolean = false
    @Volatile var targetX: Float = -1f
        set(value) { field = value; Log.d(TAG, "TARGET_X_UPDATED: $value") }
    @Volatile var targetY: Float = -1f
        set(value) { field = value; Log.d(TAG, "TARGET_Y_UPDATED: $value") }

    @Volatile var debugStatus: String = "App started"
    @Volatile var debugEvent: String = "WAITING"
    @Volatile var lastAccepted: String = "Not sent"
    @Volatile var lastError: String = "None"
    @Volatile var accessibilityConnected: Boolean = false
    @Volatile var overlayVisible: Boolean = false
    @Volatile var gestureInFlight: Boolean = false
    @Volatile var lastUpdateMs: Long = System.currentTimeMillis()

    @Synchronized fun report(event: String, status: String, error: String? = null) {
        debugEvent = event
        debugStatus = status
        if (error != null) lastError = error
        lastUpdateMs = System.currentTimeMillis()
        Log.i(TAG, "$event: $status${if (error != null) " ERROR=$error" else ""}")
    }
}
