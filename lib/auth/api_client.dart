import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'auth_service.dart';
import 'backend_discovery_service.dart';
import 'token_storage.dart';

class ApiClient {
  static const String localhostIp = 'localhost';

  // Use API Gateway port (8989) instead of individual service ports
  // API Gateway will route requests to appropriate microservices
  static const int apiPort = 8989;
  static const int timeoutSeconds = 10;

  // Dynamic host IP - will be discovered automatically
  static String _activeHostIp = kIsWeb ? localhostIp : localhostIp;
  static String _activeScheme = 'http'; // http or https
  static String _activeBaseUrl = 'http://$_activeHostIp:$apiPort/api';
  static String _activeFileBaseUrl = 'http://$_activeHostIp:$apiPort';
  
  // Track last discovery check time to avoid checking too frequently
  static DateTime? _lastDiscoveryCheck;
  static const _discoveryCheckInterval = Duration(seconds: 10); // Check every 10 seconds for ngrok URL
  static Timer? _ngrokCheckTimer; // Periodic timer to check for ngrok URL

  static bool _isInitialized = false;
  static Future<void>? _initializing;
  static late BackendDiscoveryService _discoveryService;

  static String get activeHostIp => _activeHostIp;
  static String get activeBaseUrl => _activeBaseUrl;
  static String get activeFileBaseUrl => _activeFileBaseUrl;
  static bool get isInitialized => _isInitialized;

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;

  bool isRefreshing = false;

  TokenStorage get storage => _storage;

  ApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory ApiClient() {
    final storage = TokenStorage();

    assert(
      _isInitialized,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    // Add ngrok-skip-browser-warning header if using ngrok URL
    final headers = <String, dynamic>{};
    if (_activeHostIp.contains('ngrok') || _activeHostIp.contains('ngrok-free.app')) {
      headers['ngrok-skip-browser-warning'] = 'true';
    }

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));

    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));

    final authService = AuthService(authDio, storage);

    print('🌐 ApiClient → Using $_activeBaseUrl');
    return ApiClient._(dio, storage, authService);
  }
  static Future<void> _initializeDynamicHost() async {
    if (kIsWeb) {
      _setActiveHost(localhostIp);
    } else {
      try {
        _discoveryService = BackendDiscoveryService();
        await _discoveryService.initialize();
        
        final backendInfo = await _discoveryService.discoverBackend();
        print('✅ Discovered backend: ${backendInfo.hostname}:${backendInfo.port} (${backendInfo.discoveryMethod})');
        
        _setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
        
        // Start listening for network changes
        _discoveryService.startNetworkChangeListener(_onNetworkChanged);
        
        // Check for ngrok URL immediately on startup
        _checkForNgrokUrlInBackground();
        
        // Start periodic check for ngrok URL (every 10 seconds)
        _startPeriodicNgrokCheck();
      } catch (e) {
        print('⚠️ Backend discovery failed: $e');
        // Fallback to localhost if discovery fails
        _setActiveHost(localhostIp, apiPort);
      }
    }

    _isInitialized = true;
  }

  /// Callback when network changes - re-discover backend
  static Future<void> _onNetworkChanged() async {
    if (kIsWeb) return;
    
    try {
      print('🔄 Network changed, re-discovering backend...');
      final backendInfo = await _discoveryService.discoverBackend();
      print('✅ Re-discovered backend: ${backendInfo.hostname}:${backendInfo.port} (${backendInfo.discoveryMethod})');
      
      // Check if new backend is ngrok URL and current is not (prefer ngrok)
      final isNewNgrok = backendInfo.hostname.contains('ngrok') || 
                         backendInfo.hostname.contains('ngrok-free.app');
      final isCurrentNgrok = _activeHostIp.contains('ngrok') || 
                            _activeHostIp.contains('ngrok-free.app');
      
      // Always update, but prioritize ngrok URL
      if (isNewNgrok && !isCurrentNgrok) {
        print('🔄 Switching to ngrok URL (preferred over IP address)');
      }
      
      _setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
      
      // Notify all existing clients to update their base URLs
      print('🔄 Updated active base URL to: $_activeBaseUrl');
      
      // Also check for ngrok URL in background (in case it wasn't discovered yet)
      _checkForNgrokUrlInBackground();
    } catch (e) {
      print('⚠️ Re-discovery failed: $e');
      // Keep using current host if re-discovery fails
      // Still try to check for ngrok URL
      _checkForNgrokUrlInBackground();
    }
  }

  static void _setActiveHost(String hostIp, [int port = apiPort, bool isHttps = false]) {
    _activeHostIp = hostIp;
    _activeScheme = isHttps ? 'https' : 'http';
    
    // Handle default ports and ngrok URLs (port = 0)
    if (port == 0) {
      // No port specified (e.g., ngrok URLs)
      _activeBaseUrl = '$_activeScheme://$hostIp/api';
      _activeFileBaseUrl = '$_activeScheme://$hostIp';
    } else if ((isHttps && port == 443) || (!isHttps && port == 80)) {
      // Default ports - don't include in URL
      _activeBaseUrl = '$_activeScheme://$hostIp/api';
      _activeFileBaseUrl = '$_activeScheme://$hostIp';
    } else {
      // Custom port - include in URL
      _activeBaseUrl = '$_activeScheme://$hostIp:$port/api';
      _activeFileBaseUrl = '$_activeScheme://$hostIp:$port';
    }
  }

  static Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }
    final init = _initializeDynamicHost();
    _initializing = init;
    await init;
  }

  /// Build service base URL
  /// For microservices architecture, all requests go through API Gateway (port 8989)
  /// API Gateway routes requests to appropriate services based on path
  /// Note: This method always returns a URL with /api prefix, as all requests go through API Gateway
  static String buildServiceBase({
    int? port, // Deprecated: kept for backward compatibility, but ignored
    String path = '',
  }) {
    // Normalize path - if path is provided, use it; otherwise default to /api
    final normalizedPath = path.isEmpty
        ? '/api'  // Default to /api for all requests through API Gateway
        : path.startsWith('/') ? path : '/$path';
    
    // Check if this is an ngrok URL - ngrok URLs don't need explicit port
    final isNgrokUrl = _activeHostIp.contains('ngrok') || 
                       _activeHostIp.contains('ngrok-free.app') ||
                       _activeHostIp.contains('ngrok.io');
    
    if (isNgrokUrl) {
      // Ngrok URLs don't need port - they automatically route to the configured port
      return '$_activeScheme://$_activeHostIp$normalizedPath';
    } else {
      // For local/other URLs, use API Gateway port (8989)
      const gatewayPort = apiPort; // 8989
      return '$_activeScheme://$_activeHostIp:$gatewayPort$normalizedPath';
    }
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 DIO LOG: $obj'),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Check network connectivity before making request
        if (!kIsWeb) {
          try {
            final connectivity = Connectivity();
            final connectivityResult = await connectivity.checkConnectivity();
            
            // If no network connectivity, fail immediately with clear error
            if (connectivityResult.contains(ConnectivityResult.none)) {
              print('❌ No network connectivity available. Cannot connect to backend.');
              print('   Please check your WiFi/mobile data connection.');
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'No network connectivity available. Please check your WiFi/mobile data connection.',
                  type: DioExceptionType.connectionError,
                ),
              );
            }
          } catch (e) {
            // If connectivity check fails, continue anyway (might be temporary issue)
            print('⚠️ Failed to check network connectivity: $e');
          }
        }
        
        // Periodically check for ngrok URL from backend (if not using ngrok already)
        // This ensures we automatically switch to ngrok URL when it becomes available
        if (!kIsWeb && _isInitialized) {
          final now = DateTime.now();
          final shouldCheck = _lastDiscoveryCheck == null || 
                              now.difference(_lastDiscoveryCheck!) > _discoveryCheckInterval;
          
          // Only check if we're not already using ngrok URL
          final isCurrentlyUsingNgrok = _activeHostIp.contains('ngrok') || 
                                       _activeHostIp.contains('ngrok-free.app');
          
          if (shouldCheck && !isCurrentlyUsingNgrok) {
            // Check for ngrok URL from backend discovery endpoint in background
            // Don't block the request - check asynchronously
            _checkForNgrokUrlInBackground();
          } else if (isCurrentlyUsingNgrok) {
            // If using ngrok, verify it's still reachable
            _checkForNgrokUrlInBackground();
          }
        }
        
        final token = await _storage.readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) {
          options.headers['X-Device-Id'] = deviceId;
        }
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        if (uri.host.contains('ngrok') || uri.host.contains('ngrok-free.app')) {
          options.headers['ngrok-skip-browser-warning'] = 'true';
        }
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        final retryCount = options.extra['retryCount'] ?? 0;
        const maxRetries = 20; // Maximum retries to prevent infinite loop (but retry until success)
        const maxTotalTimeSeconds = 60; // Maximum total time for all retries (60 seconds)
        final startTime = options.extra['retryStartTime'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        if (err.response == null) {
          print('⚠️ DIO CONNECTION ERROR: ${err.error}');
          
          // Check if we've exceeded maximum time
          final elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
          if (elapsedSeconds >= maxTotalTimeSeconds) {
            print('❌ Max retry time (${maxTotalTimeSeconds}s) exceeded. Giving up.');
            return handler.next(err);
          }
          
          // If connection error, try to re-discover backend and retry until success
          if (!kIsWeb && _isInitialized && retryCount < maxRetries) {
            try {
              print('🔄 Connection error detected, attempting to re-discover backend... (attempt ${retryCount + 1}, elapsed: ${elapsedSeconds}s)');
              
              // Always re-discover to get latest ngrok URL
              final backendInfo = await _discoveryService.discoverBackend();
              final newBaseUrl = backendInfo.baseUrl;
              
              // Check if new backend is ngrok URL and current is not
              final isNewNgrok = backendInfo.hostname.contains('ngrok') || backendInfo.hostname.contains('ngrok-free.app');
              final isCurrentNgrok = _activeHostIp.contains('ngrok') || _activeHostIp.contains('ngrok-free.app');
              
              // Always update if:
              // 1. Base URL changed, OR
              // 2. New backend is ngrok URL and current is not (prefer ngrok over IP)
              if (newBaseUrl != _activeBaseUrl || (isNewNgrok && !isCurrentNgrok)) {
                print('✅ Re-discovered backend: ${backendInfo.hostname}:${backendInfo.port} (${backendInfo.discoveryMethod})');
                if (isNewNgrok && !isCurrentNgrok) {
                  print('   Switching to ngrok URL (preferred over IP address)');
                }
                _setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
              }
              
              // Update base URL for this request
              options.baseUrl = _activeBaseUrl;
              
              // Store retry start time if not set
              if (options.extra['retryStartTime'] == null) {
                options.extra['retryStartTime'] = startTime;
              }
              
              // Add retry count
              options.extra['retryCount'] = retryCount + 1;
              
              // Exponential backoff with cap: wait before retry (1s, 2s, 4s, 8s, max 10s)
              final delaySeconds = (1 << retryCount).clamp(1, 10); // 1, 2, 4, 8, 10, 10, 10... seconds
              print('   Waiting ${delaySeconds}s before retry...');
              await Future.delayed(Duration(seconds: delaySeconds));
              
              // Retry the request with new base URL
              try {
                final clonedResponse = await dio.fetch(options);
                print('✅ Retry successful after re-discovery (attempt ${retryCount + 1})');
                return handler.resolve(clonedResponse);
              } catch (retryErr) {
                print('⚠️ Retry ${retryCount + 1} after re-discovery failed: $retryErr');
                // Continue retrying - recursively call handler.next to retry again
                return handler.next(err);
              }
            } catch (discoveryErr) {
              print('⚠️ Re-discovery failed: $discoveryErr');
              
              // If we've tried multiple times and still getting "Network is unreachable",
              // clear the cached backend to force fresh discovery
              if (retryCount >= 3 && err.error.toString().contains('Network is unreachable')) {
                print('🗑️ Cached backend unreachable after multiple attempts, clearing cache...');
                try {
                  await _discoveryService.clearCache();
                  print('✅ Cleared cached backend, will try fresh discovery on next attempt');
                } catch (clearErr) {
                  print('⚠️ Failed to clear cache: $clearErr');
                }
              }
              
              // If discovery fails, still retry (might be temporary issue)
              if (retryCount + 1 < maxRetries) {
                options.extra['retryCount'] = retryCount + 1;
                options.extra['retryStartTime'] = startTime;
                final delaySeconds = (1 << retryCount).clamp(1, 10);
                await Future.delayed(Duration(seconds: delaySeconds));
                return handler.next(err);
              }
            }
          } else if (retryCount >= maxRetries) {
            print('❌ Max retries ($maxRetries) reached. Giving up.');
          }
        }

        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();

          if (refreshToken == null || isRefreshing) {
            // Only auto-logout if no refresh token or already refreshing
            // This prevents logout during payment callback when token might be temporarily expired
            if (refreshToken == null) {
              print('⚠️ No refresh token available. User will need to login again.');
              await _storage.deleteAll();
            } else {
              print('⚠️ Token refresh already in progress. Retrying request...');
            }
            return handler.next(err);
          }

          try {
            isRefreshing = true;
            await _authService.refreshToken();

            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              final clonedResponse = await dio.fetch(options);
              return handler.resolve(clonedResponse);
            }
          } on DioException catch (e) {
            // Don't auto-logout immediately on refresh failure
            // Token might be temporarily expired during payment callback
            // User can continue using app, and will be logged out naturally on next critical request
            print('⚠️ REFRESH FAILED: ${e.message}');
            print('⚠️ User session may be expired. Will retry on next request.');
            // Don't delete tokens immediately - allow user to continue
            // Tokens will be cleared naturally if refresh continues to fail
            return handler.next(e);
          } finally {
            isRefreshing = false;
          }
        }
        return handler.next(err);
      },
    ));
  }

  static Future<ApiClient> create() async {
    final storage = TokenStorage();
    await ensureInitialized();

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    print('🌐 ApiClient.create() → $_activeBaseUrl');
    return ApiClient._(dio, storage, authService);
  }

  static String fileUrl(String path) {
    if (path.startsWith('http')) {
      // Nếu URL chứa localhost hoặc port 8082, thay thế bằng host đúng
      final url = path;
      final uri = Uri.tryParse(url);
      if (uri != null && (url.contains('localhost') || url.contains('127.0.0.1') || uri.port == 8082)) {
        final host = _activeHostIp;
        final scheme = _activeScheme;
        
        // Check if this is an ngrok URL - ngrok URLs don't need explicit port
        final isNgrokUrl = host.contains('ngrok') || 
                         host.contains('ngrok-free.app') ||
                         host.contains('ngrok.io');
        
        if (isNgrokUrl) {
          // Ngrok URLs don't need port - they automatically route to the configured port
          return Uri(
            scheme: scheme,
            host: host,
            path: uri.path,
            query: uri.query,
          ).toString();
        } else {
          // For non-ngrok URLs, include port only if it's not a default port
          final port = uri.port != 0 && uri.port != 80 && uri.port != 443 ? uri.port : null;
          return Uri(
            scheme: scheme,
            host: host,
            port: port,
            path: uri.path,
            query: uri.query,
          ).toString();
        }
      }
      // If URL already has correct host, return as is
      return path;
    }
    
    // For relative paths, use activeFileBaseUrl (already handles ngrok correctly)
    return '$_activeFileBaseUrl$path';
  }
  
  /// Check for ngrok URL from backend discovery endpoint in background
  /// This runs asynchronously and doesn't block requests
  /// Also checks if current ngrok URL is still reachable, if not, switch to IP address
  static void _checkForNgrokUrlInBackground() {
    _lastDiscoveryCheck = DateTime.now();
    
    // Run in background without blocking
    Future.microtask(() async {
      try {
        // If currently using ngrok URL, check if it's still reachable
        final isCurrentlyUsingNgrok = _activeHostIp.contains('ngrok') || 
                                     _activeHostIp.contains('ngrok-free.app');
        
        if (isCurrentlyUsingNgrok) {
          // Check if ngrok URL is still reachable
          try {
            final dio = Dio();
            dio.options.connectTimeout = const Duration(seconds: 3);
            dio.options.receiveTimeout = const Duration(seconds: 3);
            dio.options.headers['ngrok-skip-browser-warning'] = 'true';
            
            final healthUrl = '$_activeBaseUrl/health';
            final response = await dio.get(healthUrl).timeout(const Duration(seconds: 3));
            
            if (response.statusCode != 200) {
              // Ngrok URL not reachable - switch to IP address
              print('⚠️ Ngrok URL not reachable, switching to IP address...');
              await _switchToIpAddress();
            }
          } catch (e) {
            // Ngrok URL not reachable - switch to IP address
            print('⚠️ Ngrok URL connection failed, switching to IP address...');
            await _switchToIpAddress();
          }
        } else {
          // Not using ngrok - check if ngrok URL is available from backend
          // Try to get ngrok URL from backend discovery endpoint
          // Use the current active host (IP address) to reach backend
          final discoveryUrl = '$_activeScheme://$_activeHostIp:$apiPort/api/discovery/info';
          
          final dio = Dio();
          dio.options.connectTimeout = const Duration(seconds: 2);
          dio.options.receiveTimeout = const Duration(seconds: 2);
          
          final response = await dio.get(discoveryUrl).timeout(const Duration(seconds: 2));
          
          if (response.statusCode == 200 && response.data != null) {
            final publicUrl = response.data['publicUrl'] as String?;
            
            if (publicUrl != null && publicUrl.isNotEmpty && 
                (publicUrl.contains('ngrok') || publicUrl.contains('ngrok-free.app'))) {
              // Found ngrok URL - verify it's reachable before switching
              try {
                final ngrokDio = Dio();
                ngrokDio.options.connectTimeout = const Duration(seconds: 3);
                ngrokDio.options.receiveTimeout = const Duration(seconds: 3);
                ngrokDio.options.headers['ngrok-skip-browser-warning'] = 'true';
                
                final ngrokHealthUrl = '$publicUrl/api/health';
                final ngrokResponse = await ngrokDio.get(ngrokHealthUrl).timeout(const Duration(seconds: 3));
                
                if (ngrokResponse.statusCode == 200) {
                  // Ngrok URL is reachable - switch to it immediately
                  print('🔄 Auto-discovered ngrok URL, switching from IP to ngrok...');
                  print('   Ngrok URL: $publicUrl');
                  
                  // Parse ngrok URL to extract hostname
                  final ngrokUri = Uri.parse(publicUrl);
                  final ngrokHostname = ngrokUri.host;
                  final isHttps = ngrokUri.scheme == 'https';
                  
                  // Switch to ngrok URL immediately
                  _setActiveHost(ngrokHostname, 0, isHttps); // Port 0 means no port in URL
                  print('✅ Switched to ngrok URL: $ngrokHostname');
                  print('   New base URL: $_activeBaseUrl');
                  
                  // Also save this ngrok URL to preferences for future use
                  try {
                    await _discoveryService.setManualBackendUrl(publicUrl);
                    print('💾 Saved ngrok URL to preferences');
                  } catch (e) {
                    print('⚠️ Failed to save ngrok URL: $e');
                  }
                }
              } catch (e) {
                // Ngrok URL not reachable - keep using IP address
              }
            }
          }
        }
      } catch (e) {
        // Silently fail - this is a background check, don't spam logs
        // Only log if it's a significant error
      }
    });
  }
  
  /// Switch from ngrok URL to IP address
  static Future<void> _switchToIpAddress() async {
    try {
      // Clear saved ngrok URL
      await _discoveryService.clearManualBackendUrl();
      
      // Re-discover to get IP address
      final backendInfo = await _discoveryService.discoverBackend();
      final isNgrokUrl = backendInfo.hostname.contains('ngrok') || 
                        backendInfo.hostname.contains('ngrok-free.app');
      
      if (!isNgrokUrl) {
        // Found IP address - switch to it
        print('🔄 Switching from ngrok URL to IP address...');
        _setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
        print('✅ Switched to IP address: ${backendInfo.hostname}:${backendInfo.port}');
      }
    } catch (e) {
      print('⚠️ Failed to switch to IP address: $e');
    }
  }
  
  /// Start periodic check for ngrok URL
  /// This checks every 10 seconds if ngrok URL is available
  static void _startPeriodicNgrokCheck() {
    if (kIsWeb) return;
    
    // Cancel existing timer if any
    _ngrokCheckTimer?.cancel();
    
    // Start periodic check
    _ngrokCheckTimer = Timer.periodic(_discoveryCheckInterval, (timer) {
      if (!_isInitialized) {
        timer.cancel();
        return;
      }
      
      // Only check if not currently using ngrok
      final isCurrentlyUsingNgrok = _activeHostIp.contains('ngrok') || 
                                   _activeHostIp.contains('ngrok-free.app');
      
      if (!isCurrentlyUsingNgrok) {
        // Check for ngrok URL in background
        _checkForNgrokUrlInBackground();
      }
    });
    
    print('🔄 Started periodic ngrok URL check (every ${_discoveryCheckInterval.inSeconds}s)');
  }
}


