import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';

class NetworkHelper {
  static const String localhostIp = 'localhost';
  
  /// Detect host IP by trying to connect to common network gateway IPs
  /// This is a fallback method - prefer using BackendDiscoveryService
  static Future<String> detectHostIP({int port = 8080}) async {
    if (kIsWeb) return localhostIp;
    
    try {
      final networkInfo = NetworkInfo();
      final wifiIp = await networkInfo.getWifiIP();
      
      if (wifiIp != null) {
        // Extract network prefix (e.g., "192.168.1" from "192.168.1.100")
        final parts = wifiIp.split('.');
        if (parts.length >= 3) {
          final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          
          // Try common gateway/server IPs in the network
          final commonIps = [
            '$networkPrefix.1',  // Router/gateway
            '$networkPrefix.10',
            '$networkPrefix.100',
            '$networkPrefix.200',
            '$networkPrefix.254',
          ];
          
          for (final ip in commonIps) {
            try {
              final socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 200));
              socket.destroy();
              return ip;
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Fall through to localhost
    }
    
    return localhostIp;
  }
}


