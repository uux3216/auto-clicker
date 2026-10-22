package com.example.auto_clicker

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.graphics.drawable.GradientDrawable
import kotlin.math.max
import kotlin.math.min

data class TargetPoint(var x: Float, var y: Float)

object TargetStore {
    val points: MutableList<TargetPoint> = mutableListOf(TargetPoint(300f, 600f))
    @Volatile var currentMode: String = "single"
    @Volatile var running: Boolean = false
}

class TargetOverlayService : Service() {
    private lateinit var wm: WindowManager
    private val targetViews = mutableListOf<View>()
    private val panelViews = mutableListOf<View>()
    private var panel: LinearLayout? = null
    private var addButton: Button? = null
    private var stopButton: Button? = null

    private fun overlayParams(w: Int, h: Int, x: Int, y: Int) = WindowManager.LayoutParams(
        w, h, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    ).apply { gravity = Gravity.TOP or Gravity.START; this.x = x; this.y = y }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showPanel()
        refreshTargets()
    }

    private fun showPanel() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(8, 6, 8, 6)
            background = GradientDrawable().apply {
                setColor(Color.argb(235, 30, 30, 30)); cornerRadius = 24f
            }
        }
        val drag = TextView(this).apply {
            text = "↕"
            textSize = 20f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            setPadding(8, 4, 8, 4)
        }
        val add = Button(this).apply {
            text = "+"
            textSize = 18f
            setOnClickListener {
                if (TargetStore.points.size < 10) {
                    TargetStore.points.add(TargetPoint(300f + TargetStore.points.size * 35f, 600f + TargetStore.points.size * 35f))
                    refreshTargets()
                }
            }
        }
        val stop = Button(this).apply {
            text = "STOP"
            textSize = 14f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(210, 25, 45))
            setOnClickListener {
                AutoClickAccessibilityService.instance?.stopRun()
                TargetStore.running = false
                text = "STOPPED"
                postDelayed({ if (this@TargetOverlayService.stopButton === this) text = "STOP" }, 1000)
            }
        }
        drag.setOnTouchListener(PanelDragListener(box))
        box.addView(drag)
        box.addView(add)
        box.addView(stop)
        panel = box; addButton = add; stopButton = stop
        try {
            wm.addView(box, overlayParams(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, 30, 160))
            panelViews.add(box)
        } catch (_: Exception) {}
    }

    private inner class PanelDragListener(private val view: View) : View.OnTouchListener {
        private var sx = 0f; private var sy = 0f; private var ox = 0; private var oy = 0
        override fun onTouch(v: View, event: MotionEvent): Boolean {
            val lp = view.layoutParams as? WindowManager.LayoutParams ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { sx = event.rawX; sy = event.rawY; ox = lp.x; oy = lp.y; return true }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = ox + (event.rawX - sx).toInt(); lp.y = oy + (event.rawY - sy).toInt()
                    try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
                    return true
                }
            }
            return true
        }
    }

    private fun refreshTargets() {
        targetViews.forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        targetViews.clear()
        TargetStore.points.forEachIndexed { index, point ->
            val v = TextView(this).apply {
                text = "P${index + 1}"
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.WHITE)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb(220, 20, 110, 240))
                    setStroke(3, Color.WHITE)
                }
                setOnTouchListener(TargetDragListener(this, index))
            }
            val size = 58
            try {
                wm.addView(v, overlayParams(size, size, point.x.toInt() - size / 2, point.y.toInt() - size / 2))
                targetViews.add(v)
            } catch (_: Exception) {}
        }
    }

    private inner class TargetDragListener(private val view: View, private val index: Int) : View.OnTouchListener {
        private var sx = 0f; private var sy = 0f; private var ox = 0; private var oy = 0
        override fun onTouch(v: View, event: MotionEvent): Boolean {
            val lp = view.layoutParams as? WindowManager.LayoutParams ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> { sx = event.rawX; sy = event.rawY; ox = lp.x; oy = lp.y; return true }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = max(0, ox + (event.rawX - sx).toInt())
                    lp.y = max(0, oy + (event.rawY - sy).toInt())
                    try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
                    TargetStore.points.getOrNull(index)?.let { it.x = lp.x + view.width / 2f; it.y = lp.y + view.height / 2f }
                    return true
                }
            }
            return true
        }
    }

    override fun onDestroy() {
        targetViews.forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        panelViews.forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        targetViews.clear(); panelViews.clear()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
