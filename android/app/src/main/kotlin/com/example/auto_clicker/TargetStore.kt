package com.example.auto_clicker

object TargetStore {
    @Volatile var holdSeconds: Long = 3
    @Volatile var breakSeconds: Long = 1
    @Volatile var running: Boolean = false

    // Center coordinates of the draggable floating target, in screen pixels.
    @Volatile var targetX: Float = -1f
    @Volatile var targetY: Float = -1f
}
