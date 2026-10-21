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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                        startActivity(intent)
                    }
                    val settings = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    AutoClickAccessibilityService.latestSettings = settings
                    val service = AutoClickAccessibilityService.instance
                    if (service == null) {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.error("ACCESSIBILITY_DISABLED", "Enable Auto Clicker gesture service in Accessibility settings, then return and press Start again.", null)
                    } else {
                        service.startRun(settings)
                        result.success(true)
                    }
                }
                "stop" -> {
                    AutoClickAccessibilityService.instance?.stopRun()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
