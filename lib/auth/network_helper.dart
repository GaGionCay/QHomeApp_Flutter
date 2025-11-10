import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class NetworkHelper {
  static const String LAN_HOST_IP = '192.168.100.33';
  static const String OFFICE_HOST_IP = '10.33.63.155';
  static const String LOCALHOST_IP = 'localhost';
  
  static Future<String> detectHostIP({int port = 8080}) async {
    if (kIsWeb) return LOCALHOST_IP;
    for (final ip in [LAN_HOST_IP, OFFICE_HOST_IP]) {
      try {
        final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
        socket.destroy();
        return ip;
      } catch (_) {}
    }
    return LOCALHOST_IP;
  }
}
