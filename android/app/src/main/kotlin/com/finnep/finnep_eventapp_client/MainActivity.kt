package com.finnep.finnep_eventapp_client

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.finnep.eventapp/cache_path").setMethodCallHandler { call, result ->
            if (call.method == "getCachePath") {
                val dir = cacheDir ?: applicationContext.cacheDir
                result.success(dir.absolutePath)
            } else {
                result.notImplemented()
            }
        }
    }
}
