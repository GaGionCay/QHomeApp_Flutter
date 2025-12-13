import 'dart:async';
import 'dart:io' show Platform, NetworkInterface, InternetAddressType;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for discovering backend server on the local network
/// Supports multiple strategies:
/// 1. mDNS/Bonjour service discovery (e.g., qhome-api.local)
/// 2. Local network scanning for known ports
/// 3. User-provided manual configuration
/// 4. Cached IP from previous successful connection
class BackendDiscoveryService {
  static const String _cacheKeyBackendIp = 'cached_backend_ip';
  static const String _cacheKeyBackendPort = 'cached_backend_port';
  static const String _cacheKeyBackendHostname = 'cached_backend_hostname';
  static const String _cacheKeyManualBackendUrl = 'manual_backend_url'; // For ngrok/public IP
  
  static const String _defaultBackendHostname = 'qhome-api.local';
  // Use API Gateway port (8989) - Gateway routes to all microservices
  static const int _defaultBackendPort = 8989;
  static const int _discoveryTimeoutSeconds = 5;
  
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  late SharedPreferences _prefs;
  
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Future<void> Function()? _onNetworkChangedCallback;

  /// Initialize the discovery service
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Discover backend server
  /// Strategy (optimized for mobile devices, different networks, and no network):
  /// 1. Try manual URL (ngrok/public IP) first - works even without local network
  /// 2. Try to auto-detect ngrok URL from ngrok API (if accessible)
  /// 3. Try cached backend info
  /// 4. Try mDNS hostname if available (local network only)
  /// 5. Try local network scan (local network only)
  /// 6. Fall back to default IP
  Future<BackendInfo> discoverBackend({
    String? manualHostname,
    int? manualPort,
    String? manualUrl, // Full URL (e.g., https://xxx.ngrok.io or http://public-ip:port)
  }) async {
    if (kDebugMode) {
      print('🔍 Starting backend discovery...');
    }

    // Priority 1: Manual URL (ngrok/public IP) - highest priority
    // This works even when device has no network or different network
    // Prefer ngrok URLs over IP addresses, but verify reachability
    final savedManualUrl = _prefs.getString(_cacheKeyManualBackendUrl);
    if (savedManualUrl != null && savedManualUrl.isNotEmpty) {
      final parsedInfo = _parseUrl(savedManualUrl);
      if (parsedInfo != null) {
        // Check if it's an ngrok URL
        final isNgrokUrl = savedManualUrl.contains('ngrok') || savedManualUrl.contains('ngrok-free.app');
        
        // Always check reachability - if not reachable, don't use it
        final isReachable = await _isBackendReachable(parsedInfo);
        
        if (isReachable) {
          if (kDebugMode) {
            if (isNgrokUrl) {
              print('✅ Using saved ngrok URL (verified): $savedManualUrl');
            } else {
              print('✅ Using saved manual URL: $savedManualUrl');
            }
          }
          return parsedInfo;
        } else {
          // Not reachable - clear it and try other methods
          if (kDebugMode) {
            if (isNgrokUrl) {
              print('⚠️ Saved ngrok URL not reachable (ngrok may have stopped), will try other methods');
            } else {
              print('⚠️ Saved manual URL not reachable, will try other methods');
            }
          }
          // Clear unreachable URL to force re-discovery
          await _prefs.remove(_cacheKeyManualBackendUrl);
          // Continue to check for new ngrok URL or IP address
        }
      }
    }

    // Priority 2: Manual URL provided as parameter
    if (manualUrl != null && manualUrl.isNotEmpty) {
      final parsedInfo = _parseUrl(manualUrl);
      if (parsedInfo != null && await _isBackendReachable(parsedInfo)) {
        if (kDebugMode) {
          print('✅ Using provided manual URL: $manualUrl');
        }
        await _saveManualUrl(manualUrl);
        return parsedInfo;
      }
    }

    // Priority 3: Try to get ngrok URL from backend discovery endpoint
    // This works if we can reach backend via local network first
    // Backend will expose its ngrok URL via /api/discovery/info
    // Try this BEFORE mDNS/local scan to get ngrok URL quickly
    // ALWAYS prefer ngrok URL over IP address if available and reachable
    if (kDebugMode) {
      print('🔍 Trying to get ngrok URL from backend discovery endpoint...');
    }
    final discoveryUrl = await _tryGetNgrokUrlFromBackend();
    if (discoveryUrl != null && discoveryUrl.isNotEmpty) {
      final parsedInfo = _parseUrl(discoveryUrl);
      if (parsedInfo != null) {
        // Check reachability - only use ngrok URL if it's actually reachable
        // If ngrok stopped, the URL won't be reachable, so we'll fall back to IP address
        final isReachable = await _isBackendReachable(parsedInfo);
        if (isReachable) {
          if (kDebugMode) {
            print('✅ Got ngrok URL from backend discovery (verified): $discoveryUrl');
          }
          // Save and use ngrok URL (it's reachable)
          await _saveManualUrl(discoveryUrl);
          return parsedInfo;
        } else {
          if (kDebugMode) {
            print('⚠️ Got ngrok URL from backend but not reachable (ngrok may have stopped)');
            print('   Will try IP address instead');
          }
          // Don't use unreachable ngrok URL - continue to try IP address
        }
      }
    }

    // Priority 4: Try to auto-detect ngrok URL from ngrok API
    // This only works if ngrok is running on the same machine (web/desktop)
    // Note: On mobile devices, this won't work - skip silently
    try {
      final autoNgrokUrl = await _tryAutoDetectNgrokUrl();
      if (autoNgrokUrl != null) {
        final parsedInfo = _parseUrl(autoNgrokUrl);
        if (parsedInfo != null && await _isBackendReachable(parsedInfo)) {
          if (kDebugMode) {
            print('✅ Auto-detected ngrok URL from ngrok API: $autoNgrokUrl');
          }
          await _saveManualUrl(autoNgrokUrl);
          return parsedInfo;
        }
      }
    } catch (e) {
      // Silently skip - this is expected on mobile devices
      // ngrok API is not accessible from mobile devices
    }

    // Priority 4: Manual hostname:port provided
    if (manualHostname != null && manualPort != null) {
      if (kDebugMode) {
        print('✅ Using manual backend: $manualHostname:$manualPort');
      }
      return BackendInfo(
        hostname: manualHostname,
        port: manualPort,
        discoveryMethod: 'manual',
      );
    }

    // Priority 5: Try cached backend info
    // BUT: Check if cached IP is in same subnet as current device IP
    // If different subnet (e.g., switched from WiFi to mobile hotspot), clear cache and scan new subnet
    BackendInfo? cachedBackendInfo = _getCachedBackendInfo();
    if (cachedBackendInfo != null) {
      // Get current device IP to check subnet
      String? currentDeviceIp;
      try {
        final interfaces = await NetworkInterface.list(
          includeLinkLocal: false,
          type: InternetAddressType.IPv4,
        );
        
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            final ip = addr.address;
            final parts = ip.split('.');
            if (parts.length == 4) {
              final first = int.tryParse(parts[0]);
              final second = int.tryParse(parts[1]);
              if (first != null && second != null) {
                // Check if private IP
                if (first == 10 || (first == 172 && second >= 16 && second <= 31) || 
                    (first == 192 && second == 168)) {
                  currentDeviceIp = ip;
                  break;
                }
              }
            }
          }
          if (currentDeviceIp != null) break;
        }
        
        if (currentDeviceIp == null) {
          currentDeviceIp = await _networkInfo.getWifiIP();
        }
      } catch (e) {
        // Ignore
      }
      
      // Check if cached IP is in same subnet as current device IP
      bool isSameSubnet = false;
      if (currentDeviceIp != null && cachedBackendInfo.hostname.contains('.')) {
        final deviceParts = currentDeviceIp.split('.');
        final cachedParts = cachedBackendInfo.hostname.split('.');
        
        if (deviceParts.length >= 3 && cachedParts.length >= 3) {
          final deviceSubnet = '${deviceParts[0]}.${deviceParts[1]}.${deviceParts[2]}';
          final cachedSubnet = '${cachedParts[0]}.${cachedParts[1]}.${cachedParts[2]}';
          isSameSubnet = deviceSubnet == cachedSubnet;
          
          if (kDebugMode && !isSameSubnet) {
            print('⚠️ Cached backend IP (${cachedBackendInfo.hostname}) is in different subnet ($cachedSubnet)');
            print('   Current device subnet: $deviceSubnet');
            print('   Clearing cache and scanning new subnet...');
          }
        }
      }
      
      // If same subnet, try cached backend
      if (isSameSubnet && await _isBackendReachable(cachedBackendInfo)) {
        if (kDebugMode) {
          print('✅ Using cached backend (same subnet): ${cachedBackendInfo.hostname}:${cachedBackendInfo.port}');
        }
        return cachedBackendInfo;
      } else if (!isSameSubnet && currentDeviceIp != null) {
        // Different subnet - clear cache and continue to scan new subnet
        if (kDebugMode) {
          print('🗑️ Clearing cached backend (different subnet detected)');
        }
        await clearCache();
        cachedBackendInfo = null; // Don't use cached backend
      } else if (cachedBackendInfo != null) {
        // Same subnet but not reachable - try anyway but will fall through to scan
        if (kDebugMode) {
          print('⚠️ Cached backend not reachable, will try network scan...');
        }
      }
    }

    // Priority 6 & 7: REMOVED - Local network scanning and mDNS discovery
    // In ngrok-only architecture, we don't scan local networks
    // All communication goes through ngrok public URL

    // Priority 8: If we have saved manual URL but it wasn't reachable,
    // try it again as last resort (might be temporary network issue)
    // BUT: Don't use ngrok URLs as last resort if they're offline (they won't come back)
    if (savedManualUrl != null && savedManualUrl.isNotEmpty) {
      final isSavedNgrokUrl = savedManualUrl.contains('ngrok') || savedManualUrl.contains('ngrok-free.app');
      
      // If it's an ngrok URL and we already checked it's not reachable, don't use it
      // (ngrok URLs don't come back - they're permanently offline if not reachable)
      if (isSavedNgrokUrl) {
        if (kDebugMode) {
          print('⚠️ Saved ngrok URL was not reachable, skipping as last resort (ngrok URLs don\'t recover)');
        }
        // Don't use offline ngrok URL - continue to fallback
      } else {
        // For non-ngrok URLs (IP addresses), try as last resort (might be temporary network issue)
        final parsedInfo = _parseUrl(savedManualUrl);
        if (parsedInfo != null) {
          if (kDebugMode) {
            print('⚠️ Using saved manual URL (IP address) as last resort: $savedManualUrl');
          }
          return parsedInfo;
        }
      }
    }

    // In ngrok-only architecture, we don't fall back to localhost/IP addresses
    // Return placeholder that indicates ngrok URL is required
    if (kDebugMode) {
      print('❌ No ngrok URL found!');
      print('Ngrok URL is required for connection.');
      print('Please ensure:');
      print('1. Backend is running with ngrok tunnel active');
      print('2. VNPAY_BASE_URL environment variable is set to ngrok URL');
      print('3. Or manually set ngrok URL in app settings');
    }
    
    // Return placeholder URL - app will start but API calls will fail gracefully
    // Background discovery will continue to try to find ngrok URL
    return BackendInfo(
      hostname: 'ngrok-url-required.please-set-manually',
      port: _defaultBackendPort,
      discoveryMethod: 'placeholder',
    );
  }

  /// Try to discover backend via hostname (mDNS)
  Future<BackendInfo?> _discoverByHostname(String hostname, int port) async {
    try {
      if (kDebugMode) {
        print('🔍 Trying mDNS hostname: $hostname');
      }

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: _discoveryTimeoutSeconds);
      dio.options.receiveTimeout = const Duration(seconds: _discoveryTimeoutSeconds);

      final response = await dio.get('http://$hostname:$port/api/health').timeout(
        const Duration(seconds: _discoveryTimeoutSeconds),
      );

      if (response.statusCode == 200) {
        return BackendInfo(
          hostname: hostname,
          ip: null, // mDNS doesn't need explicit IP
          port: port,
          discoveryMethod: 'mdns',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ mDNS discovery failed: $e');
      }
    }
    return null;
  }

  /// Discover backend via local network scanning
  /// Scans common local network IP ranges
  /// Supports both scenarios:
  /// 1. Mobile hotspot: Phone is hotspot, laptop connects to it
  /// 2. WiFi hotspot: Both phone and laptop connect to same WiFi router
  /// Strategy:
  /// 1. Detect device's private IP using NetworkInterface (more reliable than network_info_plus)
  /// 2. Filter out public IPs (mobile data) - only use private IPs for subnet scanning
  /// 3. Scan subnet intelligently: priority IPs first (gateway/router), then comprehensive scan
  /// 4. If no private IP found, try common mobile hotspot subnets
  Future<BackendInfo?> _discoverByLocalNetworkScan() async {
    try {
      final connectivity = await _connectivity.checkConnectivity();
      final networkType = connectivity.isNotEmpty ? connectivity.first : ConnectivityResult.none;
      final isWifi = connectivity.contains(ConnectivityResult.wifi) || connectivity.contains(ConnectivityResult.ethernet);
      final isMobileHotspot = connectivity.contains(ConnectivityResult.mobile) && !isWifi;
      
      if (kDebugMode) {
        print('🔍 Scanning local network (network type: $networkType)...');
        if (isWifi) {
          print('   📶 WiFi/Ethernet detected - scanning for backend on same WiFi/router');
        } else if (isMobileHotspot) {
          print('   📱 Mobile hotspot detected - scanning for backend on hotspot subnet');
        }
      }

      String? deviceIp;
      
      // Helper function to check if IP is private (local network)
      bool isPrivateIp(String ip) {
        final parts = ip.split('.');
        if (parts.length != 4) return false;
        final first = int.tryParse(parts[0]);
        final second = int.tryParse(parts[1]);
        if (first == null || second == null) return false;
        
        // Private IP ranges:
        // 10.0.0.0/8 (10.0.0.0 - 10.255.255.255)
        // 172.16.0.0/12 (172.16.0.0 - 172.31.255.255)
        // 192.168.0.0/16 (192.168.0.0 - 192.168.255.255)
        if (first == 10) return true;
        if (first == 172 && second >= 16 && second <= 31) return true;
        if (first == 192 && second == 168) return true;
        return false;
      }
      
      // Step 1: Try to get private IP from NetworkInterface (most reliable)
      // This works for both WiFi and mobile hotspot scenarios
      try {
        final interfaces = await NetworkInterface.list(
          includeLinkLocal: false,
          type: InternetAddressType.IPv4,
        );
        
        final privateIps = <String>[];
        final allIps = <String>[];
        
        for (final interface in interfaces) {
          // Check if this is a hotspot interface (common names)
          final isHotspotInterface = interface.name.toLowerCase().contains('hotspot') ||
                                     interface.name.toLowerCase().contains('ap') ||
                                     (interface.name.toLowerCase().contains('wlan') && 
                                      !interface.name.toLowerCase().contains('wifi'));
          
          // Check if this is a WiFi interface (common names)
          final isWifiInterface = interface.name.toLowerCase().contains('wifi') ||
                                  interface.name.toLowerCase().contains('wireless') ||
                                  interface.name.toLowerCase().contains('ethernet') ||
                                  (interface.name.toLowerCase().contains('wlan') && 
                                   !isHotspotInterface);
          
          for (final addr in interface.addresses) {
            final ip = addr.address;
            allIps.add(ip);
            
            if (isPrivateIp(ip)) {
              privateIps.add(ip);
              if (kDebugMode) {
                String label = '';
                if (isHotspotInterface) label = ' [MOBILE_HOTSPOT]';
                else if (isWifiInterface) label = ' [WIFI]';
                print('📱 Found private IP: $ip (interface: ${interface.name}$label)');
              }
            }
          }
        }
        
        // Prioritize private IPs (works for both WiFi and mobile hotspot scenarios)
        if (privateIps.isNotEmpty) {
          deviceIp = privateIps.first;
          if (kDebugMode) {
            print('✅ Using private IP for subnet detection: $deviceIp');
            if (isWifi) {
              print('   📶 WiFi scenario: Will scan subnet for backend on same router');
            } else if (isMobileHotspot) {
              print('   📱 Mobile hotspot scenario: Will scan subnet for laptop IP');
            }
          }
        } else if (allIps.isNotEmpty) {
          // Fallback to any IP if no private IP found
          deviceIp = allIps.first;
          if (kDebugMode) {
            print('⚠️ No private IP found, using public IP: $deviceIp');
            if (isMobileHotspot) {
              print('   📱 Mobile hotspot: This may not work - laptop IP is in private range');
            } else {
              print('   📶 WiFi: This may not work - need private IP for subnet scan');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Failed to get IP from NetworkInterface: $e');
        }
      }
      
      // Step 2: Fallback to network_info_plus if NetworkInterface didn't work
      if (deviceIp == null || deviceIp.isEmpty) {
        try {
          deviceIp = await _networkInfo.getWifiIP();
          if (deviceIp != null && deviceIp.isNotEmpty) {
            if (kDebugMode) {
              print('📱 Found device IP via network_info_plus: $deviceIp');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ Failed to get IP from network_info_plus: $e');
          }
        }
      }
      
      // Step 3: If still no IP found, try common hotspot/WiFi subnets
      if (deviceIp == null || deviceIp.isEmpty) {
        if (kDebugMode) {
          print('⚠️ Could not get device IP address');
          if (isWifi) {
            print('   Will try common WiFi router subnets instead...');
          } else {
            print('   Will try common mobile hotspot subnets instead...');
          }
        }
        return await _tryCommonHotspotSubnets();
      }
      
      if (kDebugMode) {
        print('📱 Device IP: $deviceIp');
      }
      
      // Check if IP is private - if not, try common hotspot/WiFi subnets
      if (!isPrivateIp(deviceIp)) {
        if (kDebugMode) {
          print('⚠️ Device IP is public ($deviceIp), not suitable for local network scan');
          if (isWifi) {
            print('   For WiFi, need private IP (10.x.x.x, 192.168.x.x, 172.16-31.x.x)');
            print('   Will try common WiFi router subnets instead...');
          } else {
            print('   For mobile hotspot, need private IP (10.x.x.x, 192.168.x.x, 172.16-31.x.x)');
            print('   Will try common mobile hotspot subnets instead...');
          }
        }
        return await _tryCommonHotspotSubnets();
      }
      
      // Step 4: Extract subnet and perform comprehensive scan
      final parts = deviceIp.split('.');
      if (parts.length < 3) {
        if (kDebugMode) {
          print('⚠️ Invalid IP format: $deviceIp');
        }
        return null;
      }
      
      final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
      
      if (kDebugMode) {
        print('🌐 Detected subnet: $networkPrefix.x');
        if (isWifi) {
          print('🔍 Scanning subnet for WiFi scenario (both devices on same WiFi/router)...');
          print('   Priority: Gateway/router IP (.1), then common server IPs');
        } else {
          print('🔍 Scanning subnet for mobile hotspot scenario...');
        }
      }
      
      // Strategy: Scan with priority order
      // For WiFi scenario: Gateway/router (.1) is highest priority
      // For mobile hotspot: Known laptop IPs have priority
      // 1. Priority IPs (gateway/router): .1, .2, .3, .254
      // 2. Known laptop IP (.236) for subnet 10.141.70.x - HIGHEST PRIORITY for hotspot
      // 3. Device IP itself and nearby IPs (±100 range)
      // 4. Remaining IPs in subnet (1-254, excluding already tried)
      
      final priorityIps = <int>[];
      
      // For WiFi scenario: Gateway/router (.1) is highest priority
      if (isWifi) {
        priorityIps.addAll([1, 2, 3, 10, 100, 254]); // Gateway/router first
        if (kDebugMode) {
          print('   🎯 WiFi scenario - prioritizing gateway/router IP (.1)');
        }
      } else {
        // For mobile hotspot: Known laptop IPs have priority
        priorityIps.addAll([1, 2, 3, 254]); // Gateway still important
      }
      
      // For subnet 10.141.70.x, add laptop IP (.236) to highest priority (both scenarios)
      if (networkPrefix == '10.141.70') {
        priorityIps.insert(0, 236); // Add .236 as first priority
        if (kDebugMode) {
          print('🎯 Subnet 10.141.70.x detected - prioritizing laptop IP (.236)');
        }
      }
      
      final triedIps = <int>{...priorityIps};
      
      // Step 1: Try priority IPs first
      // For WiFi: Gateway/router (.1) first
      // For hotspot: Known laptop IPs first
      for (final lastOctet in priorityIps) {
        final ip = '$networkPrefix.$lastOctet';
        if (kDebugMode) {
          String label = '';
          if (lastOctet == 1) label = ' (GATEWAY/ROUTER)';
          else if (lastOctet == 236) label = ' (LAPTOP)';
          else if (lastOctet == 2 || lastOctet == 3) label = ' (COMMON_ROUTER)';
          print('🔍 Priority IP: $ip$label');
        }
        final info = await _tryBackendAtIp(ip, _defaultBackendPort);
        if (info != null) {
          if (kDebugMode) {
            print('✅ Found backend via priority scan: $ip:$_defaultBackendPort');
            if (isWifi) {
              print('   📶 WiFi scenario: Backend found on same WiFi/router');
            } else {
              print('   📱 Mobile hotspot scenario: Backend found on hotspot subnet');
            }
          }
          await _cacheBackendInfo(info);
          return info;
        }
      }
      
      // Step 2: Try device IP itself and nearby IPs (±100 range)
      // This covers cases where laptop IP is near device IP (common in mobile hotspot)
      if (parts.length == 4) {
        final deviceLastOctet = int.tryParse(parts[3]);
        if (deviceLastOctet != null) {
          // Try device IP itself first
          final deviceIpFull = '$networkPrefix.$deviceLastOctet';
          if (kDebugMode) {
            print('🔍 Trying device IP: $deviceIpFull');
          }
          if (!triedIps.contains(deviceLastOctet)) {
            final deviceInfo = await _tryBackendAtIp(deviceIpFull, _defaultBackendPort);
            if (deviceInfo != null) {
              if (kDebugMode) {
                print('✅ Found backend at device IP: $deviceIpFull:$_defaultBackendPort');
              }
              await _cacheBackendInfo(deviceInfo);
              return deviceInfo;
            }
            triedIps.add(deviceLastOctet);
          }
          
          // Scan nearby IPs (±100 range)
          // For WiFi: This covers cases where backend is on same subnet but different IP
          // For hotspot: This covers laptop IP near device IP
          if (kDebugMode) {
            print('🔍 Scanning nearby IPs (±100 range from device IP $deviceLastOctet)...');
            if (isWifi) {
              print('   📶 WiFi scenario: Scanning for backend on same subnet');
            } else {
              print('   📱 Hotspot scenario: Scanning for laptop IP near device');
            }
          }
          for (int offset = 1; offset <= 100; offset++) {
            // Try IPs above device IP
            final testIpAbove = deviceLastOctet + offset;
            if (testIpAbove > 0 && testIpAbove < 255 && !triedIps.contains(testIpAbove)) {
              final ip = '$networkPrefix.$testIpAbove';
              triedIps.add(testIpAbove);
              final info = await _tryBackendAtIp(ip, _defaultBackendPort);
              if (info != null) {
                if (kDebugMode) {
                  print('✅ Found backend via nearby scan: $ip:$_defaultBackendPort');
                }
                await _cacheBackendInfo(info);
                return info;
              }
            }
            
            // Try IPs below device IP
            final testIpBelow = deviceLastOctet - offset;
            if (testIpBelow > 0 && testIpBelow < 255 && !triedIps.contains(testIpBelow)) {
              final ip = '$networkPrefix.$testIpBelow';
              triedIps.add(testIpBelow);
              final info = await _tryBackendAtIp(ip, _defaultBackendPort);
              if (info != null) {
                if (kDebugMode) {
                  print('✅ Found backend via nearby scan: $ip:$_defaultBackendPort');
                }
                await _cacheBackendInfo(info);
                return info;
              }
            }
          }
        }
      }
      
      // Step 3: Scan remaining IPs in subnet (1-254, excluding already tried)
      // This ensures we cover ALL IPs including high numbers like 236
      if (kDebugMode) {
        print('🔍 Scanning remaining IPs in subnet (excluding ${triedIps.length} already tried)...');
      }
      
      // Scan remaining IPs (all 1-254, excluding already tried)
      for (int lastOctet = 1; lastOctet < 255; lastOctet++) {
        if (triedIps.contains(lastOctet)) continue;
        triedIps.add(lastOctet);
        
        final ip = '$networkPrefix.$lastOctet';
        final info = await _tryBackendAtIp(ip, _defaultBackendPort);
        if (info != null) {
          if (kDebugMode) {
            print('✅ Found backend via comprehensive scan: $ip:$_defaultBackendPort');
          }
          await _cacheBackendInfo(info);
          return info;
        }
      }
      
      if (kDebugMode) {
        print('⚠️ Comprehensive scan completed: scanned ${triedIps.length} IPs in subnet $networkPrefix.x, backend not found');
      }
      
      // Before falling back to emulator IP, try common hotspot/WiFi subnets
      // This handles cases where:
      // - Device IP is public (mobile data) but backend is on hotspot subnet
      // - Subnet scan didn't find backend, try common router subnets
      if (kDebugMode) {
        if (isWifi) {
          print('⚠️ Subnet scan didn\'t find backend, trying common WiFi router subnets as last resort...');
        } else {
          print('⚠️ Trying common mobile hotspot subnets as last resort...');
        }
      }
      final hotspotResult = await _tryCommonHotspotSubnets();
      if (hotspotResult != null) {
        return hotspotResult;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Local network scan failed: $e');
      }
      
      // On error, still try common subnets as fallback
      try {
        final connectivity = await _connectivity.checkConnectivity();
        final isWifiFallback = connectivity.contains(ConnectivityResult.wifi) || connectivity.contains(ConnectivityResult.ethernet);
        
        if (kDebugMode) {
          if (isWifiFallback) {
            print('⚠️ Trying common WiFi router subnets as fallback...');
          } else {
            print('⚠️ Trying common mobile hotspot subnets as fallback...');
          }
        }
        final hotspotResult = await _tryCommonHotspotSubnets();
        if (hotspotResult != null) {
          return hotspotResult;
        }
      } catch (e2) {
        if (kDebugMode) {
          print('❌ Fallback subnet scan also failed: $e2');
        }
      }
    }
    
    return null;
  }
  
  /// Try common mobile hotspot subnets
  /// This is used when device IP is public (mobile data) but backend is on hotspot subnet
  /// Also used as fallback for WiFi scenario when subnet scan didn't find backend
  /// Common mobile hotspot subnets:
  /// - 192.168.43.x (Android hotspot)
  /// - 172.20.10.x (iOS hotspot)
  /// - 192.168.137.x (Windows hotspot)
  /// - 10.141.70.x (User's specific hotspot)
  /// Common WiFi router subnets:
  /// - 192.168.1.x, 192.168.0.x (Most common router subnets)
  /// - 10.0.0.x, 10.0.1.x (Some routers use 10.x.x.x)
  Future<BackendInfo?> _tryCommonHotspotSubnets() async {
    if (kDebugMode) {
      print('🔍 Trying common hotspot/WiFi subnets...');
    }
    
    // Common subnets for both mobile hotspot and WiFi scenarios
    final hotspotSubnets = [
      '10.141.70',  // User's specific hotspot subnet (priority)
      '192.168.1',  // Most common WiFi router subnet (high priority for WiFi)
      '192.168.0',  // Common WiFi router subnet
      '192.168.43', // Android hotspot
      '172.20.10',  // iOS hotspot
      '192.168.137', // Windows hotspot
      '10.0.0',     // Common private subnet (some routers use this)
      '10.0.1',     // Common router subnet
    ];
    
    // For each subnet, try priority IPs first, then scan nearby IPs
    for (final subnet in hotspotSubnets) {
      if (kDebugMode) {
        print('🔍 Trying subnet: $subnet.x');
      }
      
      // Priority IPs: gateway/router (.1) is highest priority for WiFi
      // For hotspot: Known laptop IPs (.236) also have priority
      final priorityIps = [1, 2, 3, 10, 100, 236, 254]; // Gateway first, then laptop IP
      
      for (final lastOctet in priorityIps) {
        final ip = '$subnet.$lastOctet';
        if (kDebugMode) {
          print('  🔍 Priority IP: $ip');
        }
        final info = await _tryBackendAtIp(ip, _defaultBackendPort);
        if (info != null) {
          if (kDebugMode) {
            print('✅ Found backend in hotspot subnet: $ip:$_defaultBackendPort');
          }
          await _cacheBackendInfo(info);
          return info;
        }
      }
      
      // If priority IPs didn't work, try scanning nearby IPs around .236 (user's laptop)
      if (subnet == '10.141.70') {
        if (kDebugMode) {
          print('  🔍 Scanning around laptop IP (.236) in subnet $subnet.x...');
        }
        for (int offset = 1; offset <= 20; offset++) {
          // Try IPs around 236
          final testIpAbove = 236 + offset;
          final testIpBelow = 236 - offset;
          
          if (testIpAbove < 255) {
            final ip = '$subnet.$testIpAbove';
            final info = await _tryBackendAtIp(ip, _defaultBackendPort);
            if (info != null) {
              if (kDebugMode) {
                print('✅ Found backend near laptop IP: $ip:$_defaultBackendPort');
              }
              await _cacheBackendInfo(info);
              return info;
            }
          }
          
          if (testIpBelow > 0) {
            final ip = '$subnet.$testIpBelow';
            final info = await _tryBackendAtIp(ip, _defaultBackendPort);
            if (info != null) {
              if (kDebugMode) {
                print('✅ Found backend near laptop IP: $ip:$_defaultBackendPort');
              }
              await _cacheBackendInfo(info);
              return info;
            }
          }
        }
      }
    }
    
    if (kDebugMode) {
      print('⚠️ Common hotspot subnets scan completed, backend not found');
    }
    return null;
  }

  /// Try to connect to backend at specific IP
  /// Uses shorter timeout for faster scanning
  /// Tries multiple endpoints to increase success rate
  Future<BackendInfo?> _tryBackendAtIp(String ip, int port) async {
    final dio = Dio();
    // Shorter timeout for faster scanning (1s instead of 2s)
    dio.options.connectTimeout = const Duration(seconds: 1);
    dio.options.receiveTimeout = const Duration(seconds: 1);

    // Try multiple endpoints - discovery/health is more reliable
    final endpoints = [
      '/api/discovery/health',  // Discovery health endpoint (preferred)
      '/api/health',             // General health endpoint
      '/api/discovery/info',     // Discovery info endpoint
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await dio.get('http://$ip:$port$endpoint').timeout(
          const Duration(seconds: 1),
        );

        if (response.statusCode == 200) {
          return BackendInfo(
            hostname: ip,
            ip: ip,
            port: port,
            discoveryMethod: 'scan',
          );
        }
      } catch (_) {
        // Try next endpoint
        continue;
      }
    }
    
    return null;
  }

  /// Check if backend is reachable
  /// For ngrok URLs, this works even when device has no local network
  Future<bool> _isBackendReachable(BackendInfo info) async {
    try {
      final dio = Dio();
      // Longer timeout for ngrok URLs (internet connection)
      final timeout = info.isHttps || info.hostname.contains('ngrok') 
          ? const Duration(seconds: 10) 
          : const Duration(seconds: 3);
      dio.options.connectTimeout = timeout;
      dio.options.receiveTimeout = timeout;

      // Add ngrok-skip-browser-warning header for ngrok URLs
      final isNgrokUrl = info.hostname.contains('ngrok') || info.hostname.contains('ngrok-free.app');
      if (isNgrokUrl) {
        dio.options.headers['ngrok-skip-browser-warning'] = 'true';
      }

      final url = info.baseUrl;
      // Try health endpoint, or just base URL if health doesn't exist
      final healthUrl = url.endsWith('/health') ? url : '$url/health';
      
      try {
        final response = await dio.get(healthUrl).timeout(timeout);
        
        // Check for ngrok offline error in response
        if (response.headers.value('ngrok-error-code') == 'ERR_NGROK_3200') {
          if (kDebugMode) {
            print('⚠️ Ngrok offline error detected in reachability check: ${info.baseUrl}');
          }
          return false;
        }
        
        // Check response data for offline message
        if (response.data is String && (response.data as String).contains('is offline')) {
          if (kDebugMode) {
            print('⚠️ Ngrok offline message detected in reachability check: ${info.baseUrl}');
          }
          return false;
        }
        
        return response.statusCode == 200;
      } catch (e) {
        // If health endpoint fails, try base URL
        try {
          final response = await dio.get(url).timeout(timeout);
          
          // Check for ngrok offline error
          if (response.headers.value('ngrok-error-code') == 'ERR_NGROK_3200') {
            if (kDebugMode) {
              print('⚠️ Ngrok offline error detected in reachability check: ${info.baseUrl}');
            }
            return false;
          }
          
          // Check response data for offline message
          if (response.data is String && (response.data as String).contains('is offline')) {
            if (kDebugMode) {
              print('⚠️ Ngrok offline message detected in reachability check: ${info.baseUrl}');
            }
            return false;
          }
          
          // Accept 200-499 (even 4xx means server is reachable, just endpoint might not exist)
          // But reject 404 with ngrok error code (means ngrok is offline)
          if (response.statusCode == 404 && isNgrokUrl) {
            // This might be ngrok offline, but we can't be sure without checking headers/data
            // Let's be conservative and return false for 404 on ngrok URLs
            return false;
          }
          
          return response.statusCode != null && response.statusCode! < 500;
        } catch (err) {
          // Check if error response contains ngrok offline info
          if (err is DioException && err.response != null) {
            final headers = err.response!.headers;
            final responseData = err.response!.data;
            
            if (headers.value('ngrok-error-code') == 'ERR_NGROK_3200' ||
                (responseData is String && responseData.contains('is offline'))) {
              if (kDebugMode) {
                print('⚠️ Ngrok offline error detected in error response: ${info.baseUrl}');
              }
              return false;
            }
          }
          return false;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Reachability check failed for ${info.baseUrl}: $e');
      }
      return false;
    }
  }

  /// Get cached backend info
  /// Get cached backend info (public method for use in error handlers)
  BackendInfo? getCachedBackendInfo() {
    return _getCachedBackendInfo();
  }
  
  BackendInfo? _getCachedBackendInfo() {
    try {
      final hostname = _prefs.getString(_cacheKeyBackendHostname);
      final port = _prefs.getInt(_cacheKeyBackendPort);

      if (hostname != null && port != null) {
        if (kDebugMode) {
          print('📦 Found cached backend: $hostname:$port');
        }
        return BackendInfo(
          hostname: hostname,
          port: port,
          discoveryMethod: 'cache',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to retrieve cached backend info: $e');
      }
    }
    return null;
  }

  /// Cache backend info for next startup
  Future<void> _cacheBackendInfo(BackendInfo info) async {
    try {
      await _prefs.setString(_cacheKeyBackendHostname, info.hostname);
      await _prefs.setInt(_cacheKeyBackendPort, info.port);
      if (kDebugMode) {
        print('💾 Cached backend: ${info.hostname}:${info.port}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to cache backend info: $e');
      }
    }
  }

  /// Clear cached backend info (user manual reset)
  Future<void> clearCache() async {
    try {
      await _prefs.remove(_cacheKeyBackendHostname);
      await _prefs.remove(_cacheKeyBackendPort);
      await _prefs.remove(_cacheKeyBackendIp);
      if (kDebugMode) {
        print('🗑️ Cleared cached backend info');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to clear cache: $e');
      }
    }
  }

  /// Save manual backend URL (ngrok/public IP)
  Future<void> _saveManualUrl(String url) async {
    try {
      await _prefs.setString(_cacheKeyManualBackendUrl, url);
      if (kDebugMode) {
        print('💾 Saved manual backend URL: $url');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save manual URL: $e');
      }
    }
  }

  /// Set manual backend URL (public method for settings)
  Future<bool> setManualBackendUrl(String url) async {
    try {
      final parsedInfo = _parseUrl(url);
      if (parsedInfo == null) {
        if (kDebugMode) {
          print('❌ Invalid URL format: $url');
        }
        return false;
      }

      // Test if URL is reachable
      if (await _isBackendReachable(parsedInfo)) {
        await _saveManualUrl(url);
        if (kDebugMode) {
          print('✅ Manual backend URL set and verified: $url');
        }
        return true;
      } else {
        if (kDebugMode) {
          print('❌ Backend URL not reachable: $url');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to set manual URL: $e');
      }
      return false;
    }
  }

  /// Get current manual backend URL
  String? getManualBackendUrl() {
    return _prefs.getString(_cacheKeyManualBackendUrl);
  }

  /// Clear manual backend URL
  Future<void> clearManualBackendUrl() async {
    try {
      await _prefs.remove(_cacheKeyManualBackendUrl);
      if (kDebugMode) {
        print('🗑️ Cleared manual backend URL');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to clear manual URL: $e');
      }
    }
  }

  /// Parse URL string to BackendInfo
  /// Supports formats:
  /// - http://hostname:port
  /// - https://hostname:port
  /// - http://hostname:port/api
  /// - https://xxx.ngrok.io
  /// - https://xxx.ngrok.io/api
  BackendInfo? _parseUrl(String url) {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        return null;
      }

      // Extract hostname and port
      String hostname = uri.host;
      int port = uri.port;
      
      // Check if this is an ngrok URL
      final isNgrokUrl = hostname.contains('ngrok') || hostname.contains('ngrok-free.app');

      // If no port specified:
      // - For ngrok URLs: use 0 (will be handled in baseUrl getter to not show port)
      // - For other HTTPS URLs: use 443 (default HTTPS port)
      // - For HTTP URLs: use default backend port
      if (port == 0) {
        if (isNgrokUrl) {
          // Ngrok URLs don't need explicit port (they auto-route)
          // Use 0 to indicate "no port in URL"
          port = 0;
        } else if (uri.scheme == 'https') {
          port = 443;
        } else {
          port = _defaultBackendPort;
        }
      }

      // Remove /api from path if present (we'll add it back when building baseUrl)
      return BackendInfo(
        hostname: hostname,
        port: port,
        discoveryMethod: 'manual_url',
        isHttps: uri.scheme == 'https',
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to parse URL: $url, error: $e');
      }
      return null;
    }
  }

  /// Start listening for network changes
  /// When network changes, automatically re-discover backend
  /// Optimized for mobile hotspot scenario: detects when hotspot IP changes
  /// This works for both local network and internet (ngrok) connections
  void startNetworkChangeListener(Future<void> Function() onNetworkChanged) {
    _onNetworkChangedCallback = onNetworkChanged;
    
    // Track previous network state to detect changes
    List<ConnectivityResult>? _previousConnectivity;
    String? _previousDeviceIp;
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        if (kDebugMode) {
          print('🌐 Network connectivity changed: $results');
        }
        
        // Get current device IP to detect IP changes (important for mobile hotspot)
        String? currentDeviceIp;
        try {
          // Try NetworkInterface first (more reliable)
          final interfaces = await NetworkInterface.list(
            includeLinkLocal: false,
            type: InternetAddressType.IPv4,
          );
          
          for (final interface in interfaces) {
            for (final addr in interface.addresses) {
              final ip = addr.address;
              // Check if IP is private (for hotspot scenario)
              final parts = ip.split('.');
              if (parts.length == 4) {
                final first = int.tryParse(parts[0]);
                final second = int.tryParse(parts[1]);
                if (first != null && second != null) {
                  if (first == 10 || (first == 172 && second >= 16 && second <= 31) || 
                      (first == 192 && second == 168)) {
                    currentDeviceIp = ip;
                    break;
                  }
                }
              }
            }
            if (currentDeviceIp != null) break;
          }
          
          // Fallback to network_info_plus
          if (currentDeviceIp == null) {
            currentDeviceIp = await _networkInfo.getWifiIP();
          }
        } catch (e) {
          // Ignore errors
        }
        
        // Detect if IP changed (important for mobile hotspot scenario)
        final ipChanged = _previousDeviceIp != null && 
                         currentDeviceIp != null && 
                         _previousDeviceIp != currentDeviceIp;
        
        // Detect if connectivity type changed
        final connectivityChanged = _previousConnectivity == null ||
                                   (_previousConnectivity != null && !_listEquals(_previousConnectivity!, results));
        
        if (kDebugMode) {
          if (ipChanged) {
            print('📱 Device IP changed: $_previousDeviceIp → $currentDeviceIp');
            print('   This may indicate hotspot IP changed - will re-discover backend');
          }
          if (connectivityChanged) {
            print('🌐 Connectivity type changed');
          }
        }
        
        // Update previous state
        _previousConnectivity = results;
        _previousDeviceIp = currentDeviceIp;
        
        // Trigger re-discovery for any connectivity change or IP change:
        // - WiFi/Ethernet: Try local network discovery + ngrok URL
        // - Mobile data: Try ngrok URL (works even without local network)
        // - IP changed: Force re-discovery (hotspot IP may have changed)
        // - No network: Still try saved ngrok URL (might work if backend has internet)
        if (results.contains(ConnectivityResult.wifi) || 
            results.contains(ConnectivityResult.mobile) ||
            results.contains(ConnectivityResult.ethernet) ||
            ipChanged || // Force re-discovery if IP changed
            results.isEmpty) { // Even if no network, try saved ngrok URL
          
          // Debounce: wait a bit before re-discovering to avoid rapid changes
          // Longer delay if IP changed (hotspot may need more time to stabilize)
          final delaySeconds = ipChanged ? 3 : 2;
          Future.delayed(Duration(seconds: delaySeconds), () async {
            if (_onNetworkChangedCallback != null) {
              // Clear cache if IP changed to force fresh discovery
              if (ipChanged) {
                if (kDebugMode) {
                  print('🗑️ Clearing cache due to IP change (hotspot IP may have changed)');
                }
                try {
                  await clearCache();
                } catch (e) {
                  if (kDebugMode) {
                    print('⚠️ Failed to clear cache: $e');
                  }
                }
              }
              _onNetworkChangedCallback!();
            }
          });
        } else {
          if (kDebugMode) {
            print('⚠️ No network connectivity available, but will try saved ngrok URL');
          }
          // Still try re-discovery with saved ngrok URL
          Future.delayed(const Duration(seconds: 2), () {
            if (_onNetworkChangedCallback != null) {
              _onNetworkChangedCallback!();
            }
          });
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ Connectivity listener error: $error');
        }
      },
    );
    
    if (kDebugMode) {
      print('👂 Started listening for network changes (mobile hotspot optimized)');
    }
  }
  
  /// Helper function to compare lists
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Stop listening for network changes
  void stopNetworkChangeListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _onNetworkChangedCallback = null;
    if (kDebugMode) {
      print('🛑 Stopped listening for network changes');
    }
  }

  /// Try to get ngrok URL from backend discovery endpoint
  /// This works if we can reach backend via local network first
  /// Strategy: Try common local network IPs and localhost to find backend, then ask for ngrok URL
  Future<String?> _tryGetNgrokUrlFromBackend() async {
    try {
      // List of potential backend locations to try
      final potentialBackends = <BackendInfo>[];
      
      // 1. Try cached backend first
      final cachedInfo = _getCachedBackendInfo();
      if (cachedInfo != null) {
        if (kDebugMode) {
          print('  Trying cached backend: ${cachedInfo.hostname}:${cachedInfo.port}');
        }
        potentialBackends.add(cachedInfo);
      }
      
      // 2. REMOVED - Local network IP scanning
      // In ngrok-only architecture, we don't scan local network IPs
      // Only use localhost/10.0.2.2 for emulator/web bootstrap
      
      // 3. Try localhost variants (works on web/desktop/emulator)
      // Android emulator uses 10.0.2.2 to access host machine's localhost
      // iOS simulator uses localhost directly
      // Web/Desktop uses localhost
      if (kIsWeb) {
        // Web: use localhost
        potentialBackends.add(BackendInfo(
          hostname: 'localhost',
          ip: 'localhost',
          port: _defaultBackendPort,
          discoveryMethod: 'localhost',
        ));
      } else if (Platform.isAndroid) {
        // Android: try emulator IP first, then localhost
        potentialBackends.add(BackendInfo(
          hostname: '10.0.2.2',
          ip: '10.0.2.2',
          port: _defaultBackendPort,
          discoveryMethod: 'android_emulator',
        ));
        potentialBackends.add(BackendInfo(
          hostname: 'localhost',
          ip: 'localhost',
          port: _defaultBackendPort,
          discoveryMethod: 'localhost',
        ));
      } else if (Platform.isIOS) {
        // iOS: use localhost (works on simulator)
        potentialBackends.add(BackendInfo(
          hostname: 'localhost',
          ip: 'localhost',
          port: _defaultBackendPort,
          discoveryMethod: 'localhost',
        ));
      } else {
        // Desktop: use localhost
        potentialBackends.add(BackendInfo(
          hostname: 'localhost',
          ip: 'localhost',
          port: _defaultBackendPort,
          discoveryMethod: 'localhost',
        ));
      }
      
      if (kDebugMode) {
        print('  Total ${potentialBackends.length} potential backends to try');
      }
      
      // Try each potential backend to get ngrok URL (with parallel requests for speed)
      // But limit concurrent requests to avoid overwhelming the network
      const batchSize = 10;
      for (int i = 0; i < potentialBackends.length; i += batchSize) {
        final batch = potentialBackends.skip(i).take(batchSize).toList();
        
        final futures = batch.map((backend) async {
          try {
            final dio = Dio();
            dio.options.connectTimeout = const Duration(seconds: 1);
            dio.options.receiveTimeout = const Duration(seconds: 1);
            
            // Try discovery endpoint
            final discoveryUrl = '${backend.baseUrl}/discovery/info';
            
            if (kDebugMode && i == 0) {
              // Only log first batch to avoid spam
              print('  Trying: $discoveryUrl');
            }
            
            final response = await dio.get(discoveryUrl).timeout(
              const Duration(seconds: 1),
            );
            
            if (response.statusCode == 200 && response.data != null) {
              // Prefer HTTP URL to avoid ngrok warning page
              final httpUrl = response.data['httpUrl'] as String?;
              final httpsUrl = response.data['httpsUrl'] as String?;
              final publicUrl = response.data['publicUrl'] as String?;
              
              String? ngrokUrl;
              
              // Priority 1: Use HTTP URL if available (avoids ngrok warning page)
              if (httpUrl != null && httpUrl.isNotEmpty && !httpUrl.contains('your-ngrok-url')) {
                ngrokUrl = httpUrl.endsWith('/') 
                    ? httpUrl.substring(0, httpUrl.length - 1) 
                    : httpUrl;
                if (kDebugMode) {
                  print('✅ Backend found at ${backend.hostname}:${backend.port}');
                  print('✅ Using HTTP tunnel (avoids ngrok warning page): $ngrokUrl');
                }
              }
              // Priority 2: Use HTTPS URL if HTTP not available
              else if (httpsUrl != null && httpsUrl.isNotEmpty && !httpsUrl.contains('your-ngrok-url')) {
                ngrokUrl = httpsUrl.endsWith('/') 
                    ? httpsUrl.substring(0, httpsUrl.length - 1) 
                    : httpsUrl;
                if (kDebugMode) {
                  print('✅ Backend found at ${backend.hostname}:${backend.port}');
                  print('⚠️ Using HTTPS tunnel (may have ngrok warning page): $ngrokUrl');
                }
              }
              // Priority 3: Fallback to publicUrl
              else if (publicUrl != null && publicUrl.isNotEmpty && !publicUrl.contains('your-ngrok-url')) {
                ngrokUrl = publicUrl.endsWith('/') 
                    ? publicUrl.substring(0, publicUrl.length - 1) 
                    : publicUrl;
                if (kDebugMode) {
                  print('✅ Backend found at ${backend.hostname}:${backend.port}');
                  print('✅ Backend exposed ngrok URL: $ngrokUrl');
                }
              }
              
              if (ngrokUrl != null) {
                // Cache the working backend for next time
                await _cacheBackendInfo(backend);
                return ngrokUrl;
              }
            }
          } catch (e) {
            // Silently continue - this backend is not available
          }
          return null;
        });
        
        // Wait for first successful response in this batch
        final results = await Future.wait(futures);
        for (final result in results) {
          if (result != null) {
            return result;
          }
        }
        
        // Small delay between batches
        if (i + batchSize < potentialBackends.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error getting ngrok URL from backend: $e');
      }
    }
    return null;
  }

  /// Try to auto-detect ngrok URL from ngrok API
  /// This only works if ngrok is running on the same machine (web/desktop)
  /// On mobile devices, user needs to set manually in Settings
  Future<String?> _tryAutoDetectNgrokUrl() async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 2);
      dio.options.receiveTimeout = const Duration(seconds: 2);

      // Try to access ngrok API (only works if ngrok is on same machine)
      final response = await dio.get('http://localhost:4040/api/tunnels').timeout(
        const Duration(seconds: 2),
      );

      if (response.statusCode == 200 && response.data != null) {
        final tunnels = response.data['tunnels'] as List?;
        if (tunnels != null && tunnels.isNotEmpty) {
          // Find HTTPS tunnel
          for (final tunnel in tunnels) {
            final publicUrl = tunnel['public_url'] as String?;
            if (publicUrl != null && publicUrl.startsWith('https://')) {
              // Remove trailing slash if present
              final ngrokUrl = publicUrl.endsWith('/') 
                  ? publicUrl.substring(0, publicUrl.length - 1) 
                  : publicUrl;
              if (kDebugMode) {
                print('✅ Found ngrok URL: $ngrokUrl');
              }
              return ngrokUrl;
            }
          }
        }
      }
    } catch (e) {
      // Silently fail - this is expected on mobile devices
      // ngrok API is not accessible from mobile devices
    }
    return null;
  }
}

/// Backend server information
class BackendInfo {
  final String hostname;
  final String? ip;
  final int port;
  final String discoveryMethod; // 'manual', 'mdns', 'scan', 'cache', 'fallback', 'manual_url'
  final bool isHttps;

  BackendInfo({
    required this.hostname,
    this.ip,
    required this.port,
    required this.discoveryMethod,
    this.isHttps = false,
  });

  String get scheme => isHttps ? 'https' : 'http';
  
  /// Build base URL, handling default ports correctly
  /// - Port 0: No port in URL (for ngrok URLs)
  /// - Port 443 (HTTPS): No port in URL (default HTTPS port)
  /// - Port 80 (HTTP): No port in URL (default HTTP port)
  /// - Other ports: Include port in URL
  String get baseUrl {
    if (port == 0) {
      // No port specified (e.g., ngrok URLs)
      return '$scheme://$hostname/api';
    } else if ((isHttps && port == 443) || (!isHttps && port == 80)) {
      // Default ports - don't include in URL
      return '$scheme://$hostname/api';
    } else {
      // Custom port - include in URL
      return '$scheme://$hostname:$port/api';
    }
  }
  
  String get fileBaseUrl {
    if (port == 0) {
      return '$scheme://$hostname';
    } else if ((isHttps && port == 443) || (!isHttps && port == 80)) {
      return '$scheme://$hostname';
    } else {
      return '$scheme://$hostname:$port';
    }
  }

  @override
  String toString() =>
      'BackendInfo(hostname=$hostname, port=$port, method=$discoveryMethod, https=$isHttps)';
}

