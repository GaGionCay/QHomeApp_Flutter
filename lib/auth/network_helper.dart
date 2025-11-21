import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class NetworkHelper {
  static const String lanHostIp = '192.168.100.33';
  static const String officeHostIp = '10.33.63.155';
  static const String localhostIp = 'localhost';
  
  static Future<String> detectHostIP({int port = 8080}) async {
    if (kIsWeb) return localhostIp;
    for (final ip in [lanHostIp, officeHostIp]) {
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
        socket.destroy();
        return ip;
      } catch (_) {}
    }
    return localhostIp;
  }
}

