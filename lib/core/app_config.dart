import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;

class AppConfig {
  static String get apiBaseUrl {
    return 'http://192.168.100.33:8989';
    
  }
  
  static const String apiPath = '/api';
  static String get fullApiBaseUrl => '${apiBaseUrl}$apiPath';
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
        if (kDebugMode) {
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