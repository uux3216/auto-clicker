package com.example.auto_clicker

object TargetStore {
    @Volatile var holdSeconds: Long = 3
    @Volatile var breakSeconds: Long = 1
    @Volatile var running: Boolean = false

    // Coordinates in physical screen pixels; updated by the draggable P1 marker.
    @Volatile var targetX: Float = 540f
    @Volatile var targetY: Float = 960f
}
