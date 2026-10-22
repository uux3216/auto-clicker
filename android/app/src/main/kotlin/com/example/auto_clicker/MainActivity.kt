package com.example.auto_clicker

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.auto_clicker/control")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableOverlay" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                            result.success("Grant 'Display over other apps', return to Auto Clicker, and tap Enable again.")
                        } else {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success("Enable Auto Clicker gesture service in Accessibility settings, then return and tap Enable again.")
                            // Overlay will be started on the next enable tap, after accessibility settings visit.
                            if (AutoClickAccessibilityService.instance != null) {
                                startService(Intent(this, TargetOverlayService::class.java))
                            }
                        }
                    }
                    "start" -> {
                        val settings = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        AutoClickAccessibilityService.latestSettings = settings
                        val service = AutoClickAccessibilityService.instance
                        if (service == null) {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.error("ACCESSIBILITY_DISABLED", "Enable Auto Clicker gesture service in Accessibility settings, return to the app, then tap Start.", null)
                        } else {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                                result.error("OVERLAY_PERMISSION", "Grant Display over other apps permission first.", null)
                            } else {
                                startService(Intent(this, TargetOverlayService::class.java))
                                service.startRun(settings)
                                result.success(true)
                            }
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
