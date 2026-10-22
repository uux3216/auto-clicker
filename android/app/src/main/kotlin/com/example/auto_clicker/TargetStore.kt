package com.example.auto_clicker

import java.util.concurrent.CopyOnWriteArrayList

data class TargetPoint(val x: Float, val y: Float)

object TargetStore {
    val points = CopyOnWriteArrayList<TargetPoint>()
    @Volatile var enabled = false
    @Volatile var panelRequested = false

    @Synchronized fun ensureOne() {
        if (points.isEmpty()) points.add(TargetPoint(540f, 960f))
    }
    @Synchronized fun addPoint() {
        if (points.size < 20) {
            val last = points.lastOrNull() ?: TargetPoint(540f, 960f)
            points.add(TargetPoint(last.x + 45f, last.y + 45f))
        }
    }
    @Synchronized fun removeLast() {
        if (points.size > 1) points.removeAt(points.lastIndex)
    }
}
