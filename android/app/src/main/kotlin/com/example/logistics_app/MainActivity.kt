package com.example.logistics_app

import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val configChannel = "com.efata.app/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            configChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "googleRoutesApiKey" -> result.success(readMetadata("com.efata.google.ROUTES_API_KEY"))
                else -> result.notImplemented()
            }
        }
    }

    private fun readMetadata(key: String): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA
            )
            appInfo.metaData?.getString(key).orEmpty()
        } catch (_: Exception) {
            ""
        }
    }
}
