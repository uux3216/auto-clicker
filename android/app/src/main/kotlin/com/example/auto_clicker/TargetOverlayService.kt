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
import android.widget.ImageView
import android.widget.LinearLayout

class TargetOverlayService : Service() {
    private lateinit var wm: WindowManager
    private var panel: View? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var downX = 0f
    private var downY = 0f
    private var initialX = 0
    private var initialY = 0

    private fun overlayType() =
        if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
        showPanel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (panel == null) showPanel()
        return START_STICKY
    }

    private fun iconButton(symbol: String, color: Int, action: () -> Unit): ImageView {
        return ImageView(this).apply {
            setImageResource(
                if (symbol == "play") android.R.drawable.ic_media_play
                else android.R.drawable.ic_media_pause
            )
            setColorFilter(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
            }
            setPadding(18, 18, 18, 18)
            contentDescription = null
            setOnClickListener { action() }
            elevation = 8f
        }
    }

    private fun showPanel() {
        if (panel != null) return
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(4, 4, 4, 4)
            background = GradientDrawable().apply {
                setColor(0x66000000)
                cornerRadius = 40f
            }
        }
        root.addView(iconButton("play", 0xff16a34a.toInt()) {
            AutoClickAccessibilityService.instance?.startRun(
                AutoClickAccessibilityService.latestSettings
            )
        }, LinearLayout.LayoutParams(56, 56).apply { marginEnd = 8 })
        root.addView(iconButton("stop", 0xffdc2626.toInt()) {
            AutoClickAccessibilityService.instance?.stopRun()
        }, LinearLayout.LayoutParams(56, 56))

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = 160
        }
        root.setOnTouchListener { view, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    initialX = lp.x
                    initialY = lp.y
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (kotlin.math.abs(dx) > 8 || kotlin.math.abs(dy) > 8) {
                        lp.x = initialX + dx
                        lp.y = initialY + dy
                        try { wm.updateViewLayout(view, lp) } catch (_: Exception) {}
                        true
                    } else false
                }
                else -> false
            }
        }
        wm.addView(root, lp)
        panel = root
        panelParams = lp
    }

    override fun onDestroy() {
        panel?.let { try { wm.removeView(it) } catch (_: Exception) {} }
        panel = null
        panelParams = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
