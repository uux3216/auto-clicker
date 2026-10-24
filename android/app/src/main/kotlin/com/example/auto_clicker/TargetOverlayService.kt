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
import android.widget.ImageButton
import android.widget.LinearLayout

class TargetOverlayService : Service() {
    private lateinit var wm: WindowManager
    private val overlays = mutableListOf<View>()
    private var startButton: ImageButton? = null
    private var stopButton: ImageButton? = null

    private fun overlayType() =
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

    private fun makeParams(x: Int, y: Int): WindowManager.LayoutParams =
        WindowManager.LayoutParams(
            dp(56), dp(56), overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            this.x = x
            this.y = y
        }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showFloatingIcons()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (overlays.isEmpty()) showFloatingIcons()
        return START_STICKY
    }

    private fun showFloatingIcons() {
        if (overlays.isNotEmpty()) return
        startButton = makeIcon(android.R.drawable.ic_media_play, 0xff16803c.toInt(), 24, 180) {
            val service = AutoClickAccessibilityService.instance
            if (service != null) {
                service.startHoldLoop(TargetStore.holdSeconds, TargetStore.breakSeconds)
            } else {
                // Accessibility must be enabled by the user in Android settings first.
            }
        }
        stopButton = makeIcon(android.R.drawable.ic_media_pause, 0xffc62828.toInt(), 24, 250) {
            AutoClickAccessibilityService.instance?.stopHoldLoop()
        }
    }

    private fun makeIcon(iconRes: Int, color: Int, x: Int, y: Int, action: () -> Unit): ImageButton {
        val button = ImageButton(this).apply {
            setImageResource(iconRes)
            setColorFilter(Color.WHITE)
            setBackgroundColor(color)
            contentDescription = if (color == 0xff16803c.toInt()) "Start hold automation" else "Stop hold automation"
            elevation = dp(8).toFloat()
            setOnClickListener { action() }
        }
        val lp = makeParams(x, y)
        button.setOnTouchListener(object : View.OnTouchListener {
            var downRawX = 0f
            var downRawY = 0f
            var initialX = 0
            var initialY = 0
            var moved = false
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downRawX = event.rawX
                        downRawY = event.rawY
                        initialX = lp.x
                        initialY = lp.y
                        moved = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - downRawX).toInt()
                        val dy = (event.rawY - downRawY).toInt()
                        if (kotlin.math.abs(dx) > dp(6) || kotlin.math.abs(dy) > dp(6)) moved = true
                        if (moved) {
                            lp.x = (initialX + dx).coerceAtLeast(0)
                            lp.y = (initialY + dy).coerceAtLeast(0)
                            try { wm.updateViewLayout(button, lp) } catch (_: Exception) {}
                            return true
                        }
                        return false
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!moved) action()
                        return true
                    }
                }
                return false
            }
        })
        try {
            wm.addView(button, lp)
            overlays.add(button)
        } catch (_: Exception) {}
        return button
    }

    override fun onDestroy() {
        AutoClickAccessibilityService.instance?.stopHoldLoop()
        overlays.toList().forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        overlays.clear()
        startButton = null
        stopButton = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
