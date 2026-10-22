package com.example.auto_clicker

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class TargetOverlayService : Service() {
    private lateinit var wm: WindowManager
    private var panel: View? = null
    private val targetViews = mutableListOf<View>()
    private var dragStartX = 0f
    private var dragStartY = 0f
    private var startX = 0
    private var startY = 0

    private fun overlayType() = if (Build.VERSION.SDK_INT >= 26)
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY else WindowManager.LayoutParams.TYPE_PHONE

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        TargetStore.ensureOne()
        showPanel()
        refreshTargets()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (panel == null) showPanel()
        refreshTargets()
        return START_STICKY
    }

    private fun params(width: Int, height: Int, gravity: Int = Gravity.TOP or Gravity.START) =
        WindowManager.LayoutParams(width, height, overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT).apply {
            this.gravity = gravity
            x = 20
            y = 140
        }

    private fun showPanel() {
        if (panel != null) return
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(8, 8, 8, 8)
            setBackgroundColor(Color.rgb(35, 35, 35))
        }
        val drag = TextView(this).apply {
            text = "⠿  DRAG PANEL HERE"
            textSize = 18f
            setTextColor(Color.WHITE)
            setPadding(20, 18, 20, 18)
            setBackgroundColor(Color.DKGRAY)
        }
        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fun button(label: String, color: Int, action: () -> Unit): Button =
            Button(this).apply {
                text = label
                setTextColor(Color.WHITE)
                setBackgroundColor(color)
                setOnClickListener { action() }
            }
        row1.addView(button("START", 0xff2e7d32.toInt()) {
            val s = AutoClickAccessibilityService.instance
            if (s != null) {
                val cfg = AutoClickAccessibilityService.latestSettings.toMutableMap()
                cfg["startedAtMs"] = System.currentTimeMillis()
                s.startRun(cfg)
            }
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row1.addView(button("PAUSE", 0xffef6c00.toInt()) {
            val s = AutoClickAccessibilityService.instance
            if (s?.isPaused() == true) s.resumeRun() else s?.pauseRun()
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row1.addView(button("STOP", 0xffc62828.toInt()) {
            AutoClickAccessibilityService.instance?.stopRun()
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row2.addView(button("+ POINT", 0xff1565c0.toInt()) {
            TargetStore.addPoint(); refreshTargets()
        }, LinearLayout.LayoutParams(0, -2, 1f))
        row2.addView(button("− POINT", 0xff6a1b9a.toInt()) {
            TargetStore.removeLast(); refreshTargets()
        }, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(drag)
        root.addView(row1)
        root.addView(row2)
        val lp = params(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT)
        drag.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartX = e.rawX; dragStartY = e.rawY
                    startX = lp.x; startY = lp.y; true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = startX + (e.rawX - dragStartX).toInt()
                    lp.y = startY + (e.rawY - dragStartY).toInt()
                    try { wm.updateViewLayout(root, lp) } catch (_: Exception) {}
                    true
                }
                else -> true
            }
        }
        wm.addView(root, lp)
        panel = root
    }

    fun refreshTargets() {
        if (!::wm.isInitialized) return
        targetViews.toList().forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        targetViews.clear()
        TargetStore.points.forEachIndexed { index, point ->
            val v = TextView(this).apply {
                text = "P${index + 1}"
                textSize = 13f
                setTextColor(Color.WHITE)
                setPadding(12, 10, 12, 10)
                setBackgroundColor(0xff1976d2.toInt())
                gravity = Gravity.CENTER
                elevation = 8f
            }
            val lp = params(WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT).apply {
                x = point.x.toInt().coerceAtLeast(0)
                y = point.y.toInt().coerceAtLeast(0)
            }
            v.setOnTouchListener { view, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartX = e.rawX; dragStartY = e.rawY
                        startX = lp.x; startY = lp.y
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        lp.x = (startX + e.rawX - dragStartX).toInt().coerceAtLeast(0)
                        lp.y = (startY + e.rawY - dragStartY).toInt().coerceAtLeast(0)
                        try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        TargetStore.points[index] = TargetPoint(lp.x.toFloat() + view.width / 2f, lp.y.toFloat() + view.height / 2f)
                        true
                    }
                    else -> true
                }
            }
            try { wm.addView(v, lp); targetViews.add(v) } catch (_: Exception) {}
        }
    }

    override fun onDestroy() {
        targetViews.forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        targetViews.clear()
        panel?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        panel = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
