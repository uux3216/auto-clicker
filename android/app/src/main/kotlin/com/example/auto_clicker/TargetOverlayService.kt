package com.example.auto_clicker

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class TargetOverlayService : Service() {
    private lateinit var wm: WindowManager
    private val overlays = mutableListOf<View>()

    private fun overlayType() =
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun makeParams(width: Int, height: Int, x: Int, y: Int) =
        WindowManager.LayoutParams(
            width, height, overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showFloatingControls()
        showTargetPoint()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (overlays.isEmpty()) {
            showFloatingControls()
            showTargetPoint()
        }
        return START_STICKY
    }

    private fun showFloatingControls() {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(4), dp(4), dp(4), dp(4))
            alpha = 0.78f
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(0x33000000)
                cornerRadius = dp(12).toFloat()
            }
            contentDescription = "Floating controls; drag any icon to move the row"
        }
        val lp = makeParams(WindowManager.LayoutParams.WRAP_CONTENT, dp(42), dp(12), dp(120))
        addIconToBar(bar, "▶", 0xff36b86a.toInt(), "Start")
        addIconToBar(bar, "■", 0xffffb74d.toInt(), "Stop")
        addIconToBar(bar, "×", 0xffef5350.toInt(), "Close floating controls")
        // Keep the three controls together in one row; dragging any icon moves the whole row.
        for (i in 0 until bar.childCount) {
            attachDragAndClick(bar.getChildAt(i), lp, when (i) {
                0 -> ({
                    val service = AutoClickAccessibilityService.instance
                    if (service != null) service.startHoldLoop(TargetStore.holdSeconds, TargetStore.breakSeconds)
                    else Toast.makeText(this, "আগে Accessibility Service চালু করুন", Toast.LENGTH_LONG).show()
                })
                1 -> ({
                    val service = AutoClickAccessibilityService.instance
                    if (service != null) service.stopHoldLoop()
                    else Toast.makeText(this, "Accessibility Service চালু নেই", Toast.LENGTH_SHORT).show()
                })
                else -> ({ AutoClickAccessibilityService.instance?.stopHoldLoop(); stopSelf() })
            }, bar)
        }
        addOverlay(bar, lp)
    }

    private fun addIconToBar(
        bar: LinearLayout, symbol: String, tint: Int, description: String
    ) {
        val button = TextView(this).apply {
            text = symbol
            textSize = 24f
            setTextColor(tint)
            gravity = Gravity.CENTER
            setBackgroundColor(Color.TRANSPARENT)
            contentDescription = description
            setPadding(dp(3), dp(3), dp(3), dp(3))
        }
        val params = LinearLayout.LayoutParams(dp(40), dp(40)).apply {
            marginStart = dp(5)
            marginEnd = dp(5)
        }
        bar.addView(button, params)
    }

    private fun showTargetPoint() {
        val markerSize = dp(44)
        val marker = object : View(this) {
            private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xff1565c0.toInt(); style = Paint.Style.STROKE; strokeWidth = dp(2).toFloat()
            }
            private val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xff1565c0.toInt(); style = Paint.Style.FILL
            }
            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val c = width / 2f
                canvas.drawCircle(c, height / 2f, c - dp(3), ring)
                canvas.drawCircle(c, height / 2f, dp(3).toFloat(), dot)
            }
        }.apply { contentDescription = "Drag to set touch position" }
        val initialX = (TargetStore.targetX - markerSize / 2f).toInt().coerceAtLeast(0)
        val initialY = (TargetStore.targetY - markerSize / 2f).toInt().coerceAtLeast(0)
        val lp = makeParams(markerSize, markerSize, initialX, initialY)
        marker.setOnTouchListener(object : View.OnTouchListener {
            var downX = 0f
            var downY = 0f
            var startX = 0
            var startY = 0
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = e.rawX; downY = e.rawY
                        startX = lp.x; startY = lp.y
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        lp.x = (startX + e.rawX - downX).toInt().coerceAtLeast(0)
                        lp.y = (startY + e.rawY - downY).toInt().coerceAtLeast(0)
                        try { wm.updateViewLayout(marker, lp) } catch (_: Exception) {}
                        TargetStore.targetX = lp.x + marker.width / 2f
                        TargetStore.targetY = lp.y + marker.height / 2f
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        TargetStore.targetX = lp.x + marker.width / 2f
                        TargetStore.targetY = lp.y + marker.height / 2f
                        return true
                    }
                }
                return true
            }
        })
        marker.viewTreeObserver.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                marker.viewTreeObserver.removeOnGlobalLayoutListener(this)
                marker.invalidate()
            }
        })
        addOverlay(marker, lp)
    }

    private fun attachDragAndClick(
        view: View,
        lp: WindowManager.LayoutParams,
        action: () -> Unit,
        movingView: View = view
    ) {
        view.setOnTouchListener(object : View.OnTouchListener {
            var downX = 0f
            var downY = 0f
            var startX = 0
            var startY = 0
            var moved = false
            override fun onTouch(v: View, e: MotionEvent): Boolean {
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = e.rawX; downY = e.rawY
                        startX = lp.x; startY = lp.y
                        moved = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (e.rawX - downX).toInt()
                        val dy = (e.rawY - downY).toInt()
                        if (kotlin.math.abs(dx) > dp(6) || kotlin.math.abs(dy) > dp(6)) moved = true
                        if (moved) {
                            lp.x = (startX + dx).coerceAtLeast(0)
                            lp.y = (startY + dy).toInt().coerceAtLeast(0)
                            try { wm.updateViewLayout(movingView, lp) } catch (_: Exception) {}
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!moved) action()
                        return true
                    }
                }
                return true
            }
        })
    }

    private fun addOverlay(view: View, lp: WindowManager.LayoutParams) {
        try {
            wm.addView(view, lp)
            overlays.add(view)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        AutoClickAccessibilityService.instance?.stopHoldLoop()
        overlays.toList().forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        overlays.clear()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
