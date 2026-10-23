package com.example.auto_clicker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.autoclicker/control"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableFloating" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                            result.success(false)
                        } else {
                            startService(Intent(this, TargetOverlayService::class.java))
                            result.success(true)
                        }
                    }
                    "disableFloating" -> {
                        AutoClickAccessibilityService.instance?.stopHoldLoop()
                        stopService(Intent(this, TargetOverlayService::class.java))
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "saveSettings" -> {
                        val map = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        TargetStore.holdSeconds = ((map["holdSeconds"] as? Number)?.toLong() ?: 3L).coerceIn(1, 3600)
                        TargetStore.breakSeconds = ((map["breakSeconds"] as? Number)?.toLong() ?: 1L).coerceIn(0, 86400)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
