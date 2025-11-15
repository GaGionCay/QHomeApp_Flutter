package com.qhome.resident

import android.content.Intent
import android.net.Uri
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.qhome.resident/app_launcher"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val launched = launchAppByPackageName(packageName)
                        result.success(launched)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "openUrlWithBrowser" -> {
                    val url = call.argument<String>("url")
                    val packageName = call.argument<String>("packageName")
                    if (url != null && packageName != null) {
                        val opened = openUrlWithBrowser(url, packageName)
                        result.success(opened)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL or package name is null", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun launchAppByPackageName(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.d("MainActivity", "Successfully launched app: $packageName")
                true
            } else {
                Log.w("MainActivity", "No launch intent found for package: $packageName")
                false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error launching app $packageName: ${e.message}", e)
            false
        }
    }
    
    private fun openUrlWithBrowser(url: String, packageName: String): Boolean {
        return try {
            // Kiểm tra xem package có được cài đặt không
            try {
                packageManager.getPackageInfo(packageName, 0)
            } catch (e: Exception) {
                Log.w("MainActivity", "Browser $packageName is not installed")
                return false
            }
            
            // Tạo intent với package cụ thể - mở trực tiếp không cần resolve
            // Việc setPackage sẽ đảm bảo chỉ browser cụ thể được mở, không hiển thị dialog
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.setPackage(packageName) // ✅ QUAN TRỌNG: Set package cụ thể để không hiển thị dialog
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            
            // Thử mở trực tiếp - không cần kiểm tra resolveActivity
            // Vì một số browser có thể xử lý URL dù không có resolveActivity
            try {
                startActivity(intent)
                Log.d("MainActivity", "✅ Successfully opened URL with browser: $packageName")
                return true
            } catch (e: android.content.ActivityNotFoundException) {
                // Browser không thể xử lý URL này
                Log.w("MainActivity", "Browser $packageName cannot handle URL: ${e.message}")
                return false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error opening URL with browser $packageName: ${e.message}", e)
            return false
        }
    }
}

