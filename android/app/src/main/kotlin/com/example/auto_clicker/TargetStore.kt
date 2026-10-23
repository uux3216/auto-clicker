package com.example.auto_clicker

data class TargetPoint(val x: Float, val y: Float)

object TargetStore {
    @Volatile var enabled = false
    @Volatile var targetX = 540f
    @Volatile var targetY = 960f
}
