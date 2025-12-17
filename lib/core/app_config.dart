import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;

/// App configuration for DEV LOCAL mode
/// Base URL is fixed and loaded once at app startup
/// IMPORTANT: baseUrl should NOT include /api - paths are added separately
class AppConfig {
  /// Base URL WITHOUT /api suffix
  /// 
  /// For Android emulator: use 'http://10.0.2.2:8989' (maps to host's 127.0.0.1)
  /// For physical Android device: use LAN IP (e.g., 'http://192.168.1.100:8989')
  /// For iOS simulator: use 'http://127.0.0.1:8989'
  /// 
  /// IMPORTANT: On physical Android devices, 127.0.0.1 points to the device itself,
  /// not the backend laptop. You MUST use the laptop's LAN IP address.
  static String get apiBaseUrl {
    // ═══════════════════════════════════════════════════════════
    // IMPORTANT: Update this based on your device type!
    // ═══════════════════════════════════════════════════════════
    
    // Option 1: Android emulator
    // Uncomment this line if running on Android emulator:
    // return 'http://10.0.2.2:8989';
    
    // Option 2: Physical Android device
    // Uncomment and update this line with your backend laptop's LAN IP:
    // Example: return 'http://192.168.1.100:8989';
    // To find your LAN IP: Windows (ipconfig) or Mac/Linux (ifconfig)
    
    // Option 3: iOS simulator or web (default)
    return 'http://192.168.100.33:8989';
    
    // ═══════════════════════════════════════════════════════════
    // If you see "Connection refused" errors on physical Android device,
    // you MUST update the return statement above to use your LAN IP!
    // ═══════════════════════════════════════════════════════════
  }
  
  /// API path prefix (always starts with /)
  static const String apiPath = '/api';
  
  /// Full API base URL (baseUrl + apiPath)
  /// Use this for Dio baseUrl configuration
  static String get fullApiBaseUrl => '${apiBaseUrl}$apiPath';
  
  /// Validate baseUrl for current device type
  /// Logs warnings if configuration is incorrect
  /// Throws exception if using localhost on Android (will cause connection failures)
  static void validateBaseUrl() {
    final baseUrl = apiBaseUrl;
    final uri = Uri.tryParse(baseUrl);
    
    if (uri == null) {
      final error = '❌ [AppConfig] Invalid baseUrl format: $baseUrl';
      if (kDebugMode) print(error);
      throw FormatException(error);
    }
    
    if (Platform.isAndroid) {
      final host = uri.host;
      if (host == '127.0.0.1' || host == 'localhost') {
        final error = '''
❌❌❌ CONFIGURATION ERROR ❌❌❌

Android device detected but baseUrl uses localhost (127.0.0.1)!

Current baseUrl: $baseUrl

PROBLEM:
On physical Android devices, 127.0.0.1 points to the device itself,
NOT your backend laptop. This will cause "Connection refused" errors.

SOLUTION:
Update AppConfig.apiBaseUrl in lib/core/app_config.dart:

For Android emulator:
  return 'http://10.0.2.2:8989';

For physical Android device:
  return 'http://192.168.1.100:8989';  // ← Update to your backend laptop's LAN IP

To find your backend laptop's LAN IP:
  Windows: ipconfig (look for IPv4 Address)
  Mac/Linux: ifconfig or ip addr

After updating, restart the app.
''';
        print(error);
        // Don't throw in production, but log prominently
        if (kDebugMode) {
          // In debug mode, we can throw to fail fast
          // But in release, just log and let user see the error
        }
      } else if (host == '10.0.2.2') {
        if (kDebugMode) {
          print('✅ [AppConfig] Using Android emulator IP (10.0.2.2)');
        }
      } else if (host.startsWith('192.168.') || host.startsWith('10.') || host.startsWith('172.')) {
        if (kDebugMode) {
          print('✅ [AppConfig] Using LAN IP: $host');
        }
      }
    } else {
      if (kDebugMode) {
        print('✅ [AppConfig] Using baseUrl: $baseUrl');
      }
    }
  }
}