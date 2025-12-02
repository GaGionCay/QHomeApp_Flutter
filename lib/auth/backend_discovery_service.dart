import 'dart:async';
import 'dart:io' show Platform;
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
    // Store cached info for potential use in fallback
    BackendInfo? cachedBackendInfo = _getCachedBackendInfo();
    if (cachedBackendInfo != null && await _isBackendReachable(cachedBackendInfo)) {
      if (kDebugMode) {
        print('✅ Using cached backend: ${cachedBackendInfo.hostname}:${cachedBackendInfo.port}');
      }
      return cachedBackendInfo;
    }

    // Priority 6: Try mDNS hostname discovery (local network only)
    // Skip if device has no network or different network
    // Only try if we haven't found anything yet
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.contains(ConnectivityResult.wifi) || 
          connectivity.contains(ConnectivityResult.ethernet)) {
        if (kDebugMode) {
          print('🔍 Trying mDNS hostname: $_defaultBackendHostname');
        }
        final mdnsInfo = await _discoverByHostname(_defaultBackendHostname, _defaultBackendPort)
            .timeout(const Duration(seconds: 3), onTimeout: () {
          if (kDebugMode) {
            print('⏱️ mDNS discovery timeout (3s)');
          }
          return null;
        });
        if (mdnsInfo != null && await _isBackendReachable(mdnsInfo)) {
          if (kDebugMode) {
            print('✅ Discovered via mDNS: ${mdnsInfo.hostname}:${mdnsInfo.port}');
          }
          await _cacheBackendInfo(mdnsInfo);
          return mdnsInfo;
        }
      }
    } catch (e) {
      // Silently skip - this is expected if mDNS is not available
      if (kDebugMode) {
        print('ℹ️ mDNS discovery not available (expected)');
      }
    }

    // Priority 7: Try local network scanning (local network only)
    // Skip if device has no network or different network
    // Only try if we haven't found anything yet
    try {
      final connectivity = await _connectivity.checkConnectivity();
      if (connectivity.contains(ConnectivityResult.wifi) || 
          connectivity.contains(ConnectivityResult.ethernet)) {
        if (kDebugMode) {
          print('🔍 Scanning local network...');
        }
        final scanInfo = await _discoverByLocalNetworkScan()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          if (kDebugMode) {
            print('⏱️ Local network scan timeout (5s)');
          }
          return null;
        });
        if (scanInfo != null && await _isBackendReachable(scanInfo)) {
          if (kDebugMode) {
            print('✅ Discovered via local scan: ${scanInfo.hostname}:${scanInfo.port}');
          }
          await _cacheBackendInfo(scanInfo);
          return scanInfo;
        }
      }
    } catch (e) {
      // Silently skip - this is expected if local network scan fails
      if (kDebugMode) {
        print('ℹ️ Local network scan not available (expected)');
      }
    }

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

    // Before falling back to localhost/emulator IP, try cached backend one more time
    // This handles cases where backend might be temporarily unreachable but cached IP is still valid
    if (cachedBackendInfo != null) {
      if (kDebugMode) {
        print('⚠️ All discovery methods failed, but found cached backend: ${cachedBackendInfo.hostname}:${cachedBackendInfo.port}');
        print('   Will use cached backend (may retry connection later)');
      }
      // Use cached backend even if reachability check failed
      // The retry logic in ApiClient will handle connection failures
      return cachedBackendInfo;
    }

    // Fall back to localhost variants (works on web/desktop/emulator, not physical mobile)
    if (kDebugMode) {
      print('⚠️ All discovery methods failed, no cached backend found');
      if (kIsWeb) {
        print('⚠️ Using fallback: localhost:$_defaultBackendPort');
      } else if (Platform.isAndroid) {
        print('⚠️ Using fallback: 10.0.2.2:$_defaultBackendPort (Android emulator)');
        print('   For physical Android device, ensure backend is running and on same network');
        print('   Example: http://192.168.1.100:8989 (IP of your backend machine)');
      } else if (Platform.isIOS) {
        print('⚠️ Using fallback: localhost:$_defaultBackendPort (iOS simulator)');
        print('   For physical iOS device, ensure backend is running and on same network');
        print('   Example: http://192.168.1.100:8989 (IP of your backend machine)');
      } else {
        print('⚠️ Using fallback: localhost:$_defaultBackendPort');
      }
    }
    
    // Return appropriate localhost variant based on platform
    if (kIsWeb) {
      // Web: use localhost
      return BackendInfo(
        hostname: 'localhost',
        port: _defaultBackendPort,
        discoveryMethod: 'fallback',
      );
    } else if (Platform.isAndroid) {
      // Android: try emulator IP first
      // If saved URL exists and it's NOT an offline ngrok URL, use it as last resort
      if (savedManualUrl != null && savedManualUrl.isNotEmpty) {
        final isSavedNgrokUrl = savedManualUrl.contains('ngrok') || savedManualUrl.contains('ngrok-free.app');
        if (!isSavedNgrokUrl) {
          // Only use non-ngrok URLs (IP addresses) as last resort
          final parsedInfo = _parseUrl(savedManualUrl);
          if (parsedInfo != null) {
            if (kDebugMode) {
              print('⚠️ Using saved URL (IP address) as last resort: $savedManualUrl');
            }
            return parsedInfo;
          }
        }
      }
      return BackendInfo(
        hostname: '10.0.2.2',
        port: _defaultBackendPort,
        discoveryMethod: 'fallback_android_emulator',
      );
    } else if (Platform.isIOS) {
      // iOS: use localhost (works on simulator)
      // If saved URL exists and it's NOT an offline ngrok URL, use it as last resort
      if (savedManualUrl != null && savedManualUrl.isNotEmpty) {
        final isSavedNgrokUrl = savedManualUrl.contains('ngrok') || savedManualUrl.contains('ngrok-free.app');
        if (!isSavedNgrokUrl) {
          // Only use non-ngrok URLs (IP addresses) as last resort
          final parsedInfo = _parseUrl(savedManualUrl);
          if (parsedInfo != null) {
            if (kDebugMode) {
              print('⚠️ Using saved URL (IP address) as last resort: $savedManualUrl');
            }
            return parsedInfo;
          }
        }
      }
      return BackendInfo(
        hostname: 'localhost',
        port: _defaultBackendPort,
        discoveryMethod: 'fallback',
      );
    } else {
      // Desktop: use localhost
      return BackendInfo(
        hostname: 'localhost',
        port: _defaultBackendPort,
        discoveryMethod: 'fallback',
      );
    }
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
  Future<BackendInfo?> _discoverByLocalNetworkScan() async {
    try {
      if (kDebugMode) {
        print('🔍 Scanning local network...');
      }

      final deviceIp = await _networkInfo.getWifiIP();
      if (deviceIp == null) return null;

      // Extract network prefix (e.g., "192.168.1" from "192.168.1.100")
      final parts = deviceIp.split('.');
      if (parts.length < 3) return null;

      final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';

      // Scan common backend IPs in the network
      final commonBackendIps = [
        '$networkPrefix.1', // Router/gateway sometimes runs services
        '$networkPrefix.10',
        '$networkPrefix.100',
        '$networkPrefix.200',
        '$networkPrefix.254',
      ];

      for (final ip in commonBackendIps) {
        final info = await _tryBackendAtIp(ip, _defaultBackendPort);
        if (info != null) {
          if (kDebugMode) {
            print('✅ Found backend at: $ip:$_defaultBackendPort');
          }
          return info;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Local network scan failed: $e');
      }
    }
    return null;
  }

  /// Try to connect to backend at specific IP
  Future<BackendInfo?> _tryBackendAtIp(String ip, int port) async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 2);
      dio.options.receiveTimeout = const Duration(seconds: 2);

      final response = await dio.get('http://$ip:$port/api/health').timeout(
        const Duration(seconds: 2),
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
      // Silently fail and try next IP
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
  /// This works for both local network and internet (ngrok) connections
  void startNetworkChangeListener(Future<void> Function() onNetworkChanged) {
    _onNetworkChangedCallback = onNetworkChanged;
    
    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (kDebugMode) {
          print('🌐 Network connectivity changed: $results');
        }
        
        // Trigger re-discovery for any connectivity change:
        // - WiFi/Ethernet: Try local network discovery + ngrok URL
        // - Mobile data: Try ngrok URL (works even without local network)
        // - No network: Still try saved ngrok URL (might work if backend has internet)
        if (results.contains(ConnectivityResult.wifi) || 
            results.contains(ConnectivityResult.mobile) ||
            results.contains(ConnectivityResult.ethernet) ||
            results.isEmpty) { // Even if no network, try saved ngrok URL
          
          // Debounce: wait a bit before re-discovering to avoid rapid changes
          Future.delayed(const Duration(seconds: 2), () {
            if (_onNetworkChangedCallback != null) {
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
      print('👂 Started listening for network changes');
    }
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
      
      // 2. Try common local network IPs (if we have WiFi info)
      try {
        final connectivity = await _connectivity.checkConnectivity();
        if (connectivity.contains(ConnectivityResult.wifi) || 
            connectivity.contains(ConnectivityResult.ethernet)) {
          final deviceIp = await _networkInfo.getWifiIP();
          if (deviceIp != null) {
            if (kDebugMode) {
              print('  Device IP: $deviceIp');
            }
            final parts = deviceIp.split('.');
            if (parts.length >= 3) {
              final networkPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';
              // Try common backend IPs - expand range to find backend
              final commonIps = <String>[];
              
              // Try gateway/router first (usually .1)
              commonIps.add('$networkPrefix.1');
              
              // Try common server IPs
              commonIps.addAll([
                '$networkPrefix.10',
                '$networkPrefix.100',
                '$networkPrefix.200',
                '$networkPrefix.254',
              ]);
              
              // Also try device IP itself and nearby IPs (in case backend is on same device or nearby)
              final deviceIpParts = deviceIp.split('.');
              if (deviceIpParts.length == 4) {
                final lastOctet = int.tryParse(deviceIpParts[3]);
                if (lastOctet != null) {
                  // Try nearby IPs (expanded range)
                  for (int offset = -10; offset <= 10; offset++) {
                    final testIp = lastOctet + offset;
                    if (testIp > 0 && testIp < 255 && !commonIps.contains('$networkPrefix.$testIp')) {
                      commonIps.add('$networkPrefix.$testIp');
                    }
                  }
                }
              }
              
              if (kDebugMode) {
                print('  Will try ${commonIps.length} IP addresses in network $networkPrefix.x');
              }
              
              for (final ip in commonIps) {
                potentialBackends.add(BackendInfo(
                  hostname: ip,
                  ip: ip,
                  port: _defaultBackendPort,
                  discoveryMethod: 'scan',
                ));
              }
            }
          } else {
            if (kDebugMode) {
              print('  Cannot get device IP, will try limited IPs');
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('  Error getting network info: $e');
        }
      }
      
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
              final publicUrl = response.data['publicUrl'] as String?;
              if (publicUrl != null && publicUrl.isNotEmpty && !publicUrl.contains('your-ngrok-url')) {
                // Remove trailing slash if present
                final ngrokUrl = publicUrl.endsWith('/') 
                    ? publicUrl.substring(0, publicUrl.length - 1) 
                    : publicUrl;
                if (kDebugMode) {
                  print('✅ Backend found at ${backend.hostname}:${backend.port}');
                  print('✅ Backend exposed ngrok URL: $ngrokUrl');
                }
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
