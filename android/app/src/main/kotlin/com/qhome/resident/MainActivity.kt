package com.qhome.resident

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
                "launchAppWithQR" -> {
                    val packageName = call.argument<String>("packageName")
                    val qrCode = call.argument<String>("qrCode")
                    val qrData = call.argument<Map<*, *>>("qrData")
                    if (packageName != null) {
                        val launched = launchAppWithQR(packageName, qrCode, qrData)
                        result.success(launched)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package name is null", null)
                    }
                }
                "copyToClipboard" -> {
                    val text = call.argument<String>("text")
                    if (text != null) {
                        copyToClipboard(text)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Text is null", null)
                    }
                }
                "showAppChooser" -> {
                    val url = call.argument<String>("url")
                    val packageNames = call.argument<List<String>>("packageNames")
                    val title = call.argument<String>("title") ?: "Chọn ứng dụng"
                    if (url != null && packageNames != null) {
                        val shown = showAppChooser(url, packageNames, title)
                        result.success(shown)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL or package names is null", null)
                    }
                }
                "showBankAppChooser" -> {
                    val packageNames = call.argument<List<String>>("packageNames")
                    val qrCode = call.argument<String>("qrCode")
                    val title = call.argument<String>("title") ?: "Chọn ứng dụng ngân hàng"
                    if (packageNames != null) {
                        val shown = showBankAppChooser(packageNames, qrCode, title)
                        result.success(shown)
                    } else {
                        result.error("INVALID_ARGUMENT", "Package names is null", null)
                    }
                }
                "showTextChooser" -> {
                    val text = call.argument<String>("text")
                    val title = call.argument<String>("title") ?: "Chọn ứng dụng"
                    val hint = call.argument<String>("hint")
                    if (text != null) {
                        val shown = showTextChooser(text, title, hint)
                        result.success(shown)
                    } else {
                        result.error("INVALID_ARGUMENT", "Text is null", null)
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
    
    private fun launchAppWithQR(packageName: String, qrCode: String?, qrData: Map<*, *>?): Boolean {
        return try {
            // Strategy 1: Try deep link with VietQR format
            if (qrCode != null) {
                val deepLinkSchemes = listOf(
                    "vietqr://transfer?qr=${Uri.encode(qrCode)}",
                    "napas://transfer?qr=${Uri.encode(qrCode)}",
                    "tpbank://transfer?qr=${Uri.encode(qrCode)}",
                    "bank://transfer?qr=${Uri.encode(qrCode)}",
                    "payment://transfer?qr=${Uri.encode(qrCode)}",
                )
                
                for (scheme in deepLinkSchemes) {
                    try {
                        val uri = Uri.parse(scheme)
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                        intent.setPackage(packageName)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        
                        val resolveInfo = packageManager.resolveActivity(intent, 0)
                        if (resolveInfo != null) {
                            startActivity(intent)
                            Log.d("MainActivity", "✅ Successfully launched app with deep link: $scheme")
                            return true
                        }
                    } catch (e: Exception) {
                        Log.d("MainActivity", "⚠️ Deep link failed for $scheme: ${e.message}")
                    }
                }
            }
            
            // Strategy 2: Try intent with ACTION_VIEW and QR code in data URI
            if (qrCode != null) {
                try {
                    // Create custom scheme with QR data
                    val qrDataUri = "bankqr://data?qr=${Uri.encode(qrCode)}"
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(qrDataUri))
                    intent.setPackage(packageName)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    
                    // Add QR data as extras
                    intent.putExtra("qr_code", qrCode)
                    intent.putExtra("QR_CODE", qrCode)
                    intent.putExtra("qrcode", qrCode)
                    intent.putExtra("qrData", qrCode)
                    intent.putExtra("data", qrCode)
                    
                    if (qrData != null) {
                        qrData["bin"]?.let { intent.putExtra("bin", it.toString()) }
                        qrData["accountNumber"]?.let { intent.putExtra("account", it.toString()) }
                        qrData["accountNumber"]?.let { intent.putExtra("accountNumber", it.toString()) }
                        qrData["amount"]?.let { intent.putExtra("amount", it.toString()) }
                        qrData["addInfo"]?.let { intent.putExtra("addInfo", it.toString()) }
                        qrData["addInfo"]?.let { intent.putExtra("content", it.toString()) }
                        qrData["addInfo"]?.let { intent.putExtra("note", it.toString()) }
                        qrData["bankName"]?.let { intent.putExtra("bankName", it.toString()) }
                    }
                    
                    val resolveInfo = packageManager.resolveActivity(intent, 0)
                    if (resolveInfo != null) {
                        startActivity(intent)
                        Log.d("MainActivity", "✅ Successfully launched app with ACTION_VIEW and QR data URI")
                        return true
                    }
                } catch (e: Exception) {
                    Log.d("MainActivity", "⚠️ ACTION_VIEW with QR data URI failed: ${e.message}")
                }
            }
            
            // Strategy 3: Try standard launch intent with QR extras (original method)
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                intent.action = Intent.ACTION_MAIN
                intent.addCategory(Intent.CATEGORY_LAUNCHER)
                
                if (qrCode != null) {
                    // Try various extra keys that bank apps might expect
                    intent.putExtra("qr_code", qrCode)
                    intent.putExtra("QR_CODE", qrCode)
                    intent.putExtra("qrcode", qrCode)
                    intent.putExtra("qrData", qrCode)
                    intent.putExtra("data", qrCode)
                    intent.putExtra("qrcode_data", qrCode)
                    intent.putExtra("scanned_data", qrCode)
                    intent.putExtra("qr_string", qrCode)
                    intent.putExtra("com.qhome.qr_code", qrCode)
                    intent.putExtra("com.bank.qr_code", qrCode)
                    intent.putExtra("com.vnpay.qr_code", qrCode)
                    intent.putExtra("com.tpb.qr_code", qrCode)
                    
                    // Also try with URI data
                    try {
                        intent.data = Uri.parse("content://qr?data=${Uri.encode(qrCode)}")
                    } catch (e: Exception) {
                        // Ignore if URI parsing fails
                    }
                }
                
                if (qrData != null) {
                    // Try various extra keys for QR data
                    qrData["bin"]?.let { 
                        intent.putExtra("qr_bin", it.toString())
                        intent.putExtra("bin", it.toString())
                        intent.putExtra("bank_bin", it.toString())
                    }
                    qrData["accountNumber"]?.let { 
                        intent.putExtra("qr_account", it.toString())
                        intent.putExtra("account", it.toString())
                        intent.putExtra("accountNumber", it.toString())
                        intent.putExtra("stk", it.toString())
                        intent.putExtra("receiver_account", it.toString())
                    }
                    qrData["amount"]?.let { 
                        intent.putExtra("qr_amount", it.toString())
                        intent.putExtra("amount", it.toString())
                        intent.putExtra("money", it.toString())
                        intent.putExtra("transfer_amount", it.toString())
                    }
                    qrData["addInfo"]?.let { 
                        intent.putExtra("qr_add_info", it.toString())
                        intent.putExtra("addInfo", it.toString())
                        intent.putExtra("content", it.toString())
                        intent.putExtra("note", it.toString())
                        intent.putExtra("description", it.toString())
                        intent.putExtra("message", it.toString())
                    }
                    qrData["bankName"]?.let { 
                        intent.putExtra("qr_bank_name", it.toString())
                        intent.putExtra("bankName", it.toString())
                        intent.putExtra("bank_name", it.toString())
                    }
                }
                
                startActivity(intent)
                Log.d("MainActivity", "✅ Successfully launched app with QR extras: $packageName")
                return true
            } else {
                Log.w("MainActivity", "No launch intent found for package: $packageName")
                return false
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Error launching app with QR $packageName: ${e.message}", e)
            return false
        }
    }
    
    private fun copyToClipboard(text: String) {
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("QR Code", text)
            clipboard.setPrimaryClip(clip)
            Log.d("MainActivity", "✅ Copied to clipboard: ${text.take(50)}...")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error copying to clipboard: ${e.message}", e)
            throw e
        }
    }
    
    private fun showAppChooser(url: String, packageNames: List<String>, title: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            // Tạo danh sách các intent cho các app có thể xử lý URL
            val chooserIntents = mutableListOf<Intent>()
            
            for (packageName in packageNames) {
                try {
                    // Kiểm tra xem app có được cài đặt không
                    packageManager.getPackageInfo(packageName, 0)
                    
                    // Tạo intent cho app cụ thể
                    val specificIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    specificIntent.setPackage(packageName)
                    specificIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    
                    // Kiểm tra xem app có thể xử lý intent này không
                    val resolveInfo = packageManager.resolveActivity(specificIntent, 0)
                    if (resolveInfo != null) {
                        chooserIntents.add(specificIntent)
                        Log.d("MainActivity", "✅ Added app to chooser: $packageName")
                    }
                } catch (e: Exception) {
                    Log.d("MainActivity", "⚠️ App $packageName not installed or cannot handle URL: ${e.message}")
                }
            }
            
            if (chooserIntents.isEmpty()) {
                Log.w("MainActivity", "No apps available for chooser")
                // Fallback: Sử dụng system chooser với intent gốc
                val chooser = Intent.createChooser(intent, title)
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(chooser)
                return true
            }
            
            // Tạo chooser với danh sách các app cụ thể
            val mainIntent = chooserIntents[0]
            chooserIntents.removeAt(0)
            
            val chooser = Intent.createChooser(mainIntent, title)
            chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, chooserIntents.toTypedArray())
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            startActivity(chooser)
            Log.d("MainActivity", "✅ Successfully showed app chooser with ${chooserIntents.size + 1} apps")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Error showing app chooser: ${e.message}", e)
            false
        }
    }
    
    private fun showBankAppChooser(packageNames: List<String>, qrCode: String?, title: String): Boolean {
        return try {
            // Tạo danh sách các intent cho các bank apps
            val chooserIntents = mutableListOf<Intent>()
            
            for (packageName in packageNames) {
                try {
                    // Kiểm tra xem app có được cài đặt không
                    packageManager.getPackageInfo(packageName, 0)
                    
                    // Tạo launch intent cho app
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                        
                        // Thêm QR code vào extras nếu có
                        if (qrCode != null) {
                            intent.putExtra("qr_code", qrCode)
                            intent.putExtra("QR_CODE", qrCode)
                            intent.putExtra("qrcode", qrCode)
                        }
                        
                        chooserIntents.add(intent)
                        Log.d("MainActivity", "✅ Added bank app to chooser: $packageName")
                    }
                } catch (e: Exception) {
                    Log.d("MainActivity", "⚠️ Bank app $packageName not installed: ${e.message}")
                }
            }
            
            if (chooserIntents.isEmpty()) {
                Log.w("MainActivity", "No bank apps available for chooser")
                return false
            }
            
            // Tạo chooser với danh sách các app
            val mainIntent = chooserIntents[0]
            chooserIntents.removeAt(0)
            
            val chooser = Intent.createChooser(mainIntent, title)
            if (chooserIntents.isNotEmpty()) {
                chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, chooserIntents.toTypedArray())
            }
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            startActivity(chooser)
            Log.d("MainActivity", "✅ Successfully showed bank app chooser with ${chooserIntents.size + 1} apps")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Error showing bank app chooser: ${e.message}", e)
            false
        }
    }
    
    private fun showTextChooser(text: String, title: String, hint: String?): Boolean {
        return try {
            // Chỉ copy vào clipboard nếu hint không null (tức là không phải Bank QR)
            // Bank QR không cần copy vào clipboard
            if (hint != null) {
                try {
                    copyToClipboard(text)
                    Log.d("MainActivity", "✅ Copied text to clipboard")
                } catch (e: Exception) {
                    Log.w("MainActivity", "⚠️ Error copying text to clipboard: ${e.message}")
                }
            }
            
            // Tạo Intent với ACTION_SEND và type text/plain
            // Android sẽ tự động hiển thị tất cả app có thể xử lý text
            val intent = Intent(Intent.ACTION_SEND)
            intent.type = "text/plain"
            intent.putExtra(Intent.EXTRA_TEXT, text)
            
            // Thêm hint nếu có
            if (hint != null) {
                intent.putExtra(Intent.EXTRA_SUBJECT, hint)
            }
            
            // Tạo chooser - Android sẽ tự động hiển thị tất cả app có thể xử lý text/plain
            val chooser = Intent.createChooser(intent, title)
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            
            startActivity(chooser)
            Log.d("MainActivity", "✅ Successfully showed text chooser")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Error showing text chooser: ${e.message}", e)
            false
        }
    }
}

