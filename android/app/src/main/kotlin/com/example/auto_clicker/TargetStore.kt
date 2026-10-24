package com.example.auto_clicker

object TargetStore {
    @Volatile var holdSeconds: Long = 3
    @Volatile var breakSeconds: Long = 1
    @Volatile var running: Boolean = false
    @Volatile var targetX: Int = -1
    @Volatile var targetY: Int = -1
}
