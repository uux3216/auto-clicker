package com.example.auto_clicker

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import kotlin.math.abs

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
            this.x = x.coerceAtLeast(0)
            this.y = y.coerceAtLeast(0)
        }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showFloatingItems()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (overlays.isEmpty()) showFloatingItems()
        return START_STICKY
    }

    private fun showFloatingItems() {
        if (overlays.isNotEmpty()) return
        val metrics = resources.displayMetrics
        if (TargetStore.targetX < 0f || TargetStore.targetY < 0f) {
            TargetStore.targetX = metrics.widthPixels / 2f
            TargetStore.targetY = metrics.heightPixels / 2f
        }
        addTargetPoint()
        addControlIcon(android.R.drawable.ic_media_play, 0xff16803c.toInt(), dp(20), dp(170)) {
            val service = AutoClickAccessibilityService.instance
            if (service != null) {
                service.startHoldLoop(TargetStore.holdSeconds, TargetStore.breakSeconds)
            } else {
                // The user must enable this app's Accessibility Service in Android settings.
            }
        }
        addControlIcon(android.R.drawable.ic_media_pause, 0xffc62828.toInt(), dp(20), dp(238)) {
            AutoClickAccessibilityService.instance?.stopHoldLoop()
        }
    }

    private fun addControlIcon(iconRes: Int, color: Int, x: Int, y: Int, action: () -> Unit) {
        val button = ImageButton(this).apply {
            setImageResource(iconRes)
            setColorFilter(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
            }
            contentDescription = null
            setPadding(dp(14), dp(14), dp(14), dp(14))
            elevation = dp(6).toFloat()
        }
        val lp = makeParams(dp(56), dp(56), x, y)
        installDrag(button, lp, onClick = action)
        try { wm.addView(button, lp); overlays.add(button) } catch (_: Exception) {}
    }

    private fun addTargetPoint() {
        val size = dp(42)
        val point = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_mylocation)
            setColorFilter(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xff1976d2.toInt())
                setStroke(dp(2), Color.WHITE)
            }
            setPadding(dp(8), dp(8), dp(8), dp(8))
            contentDescription = "Drag target point"
            elevation = dp(8).toFloat()
        }
        val lp = makeParams(
            size, size,
            (TargetStore.targetX - size / 2f).toInt(),
            (TargetStore.targetY - size / 2f).toInt()
        )
        installDrag(point, lp, onClick = null, isTarget = true)
        try { wm.addView(point, lp); overlays.add(point) } catch (_: Exception) {}
    }

    private fun installDrag(
        view: View,
        lp: WindowManager.LayoutParams,
        onClick: (() -> Unit)?,
        isTarget: Boolean = false
    ) {
        view.setOnTouchListener(object : View.OnTouchListener {
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
                        if (abs(dx) > dp(5) || abs(dy) > dp(5)) moved = true
                        if (moved) {
                            lp.x = (initialX + dx).coerceAtLeast(0)
                            lp.y = (initialY + dy).coerceAtLeast(0)
                            try { wm.updateViewLayout(v, lp) } catch (_: Exception) {}
                            if (isTarget) {
                                TargetStore.targetX = lp.x + v.width / 2f
                                TargetStore.targetY = lp.y + v.height / 2f
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!moved) onClick?.invoke()
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> return true
                }
                return false
            }
        })
    }

    override fun onDestroy() {
        AutoClickAccessibilityService.instance?.stopHoldLoop()
        overlays.toList().forEach { try { wm.removeView(it) } catch (_: Exception) {} }
        overlays.clear()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
