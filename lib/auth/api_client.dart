import 'dart:async';
import 'dart:io' show Platform, HttpClient, X509Certificate;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import '../core/event_bus.dart';
import 'auth_service.dart';
import 'backend_discovery_service.dart';
import 'token_storage.dart';

class ApiClient {
  static const String localhostIp = 'localhost';

  // Use API Gateway port (8989) instead of individual service ports
  // API Gateway will route requests to appropriate microservices
  static const int apiPort = 8989;
  static const int timeoutSeconds = 15; // Increased for mobile hotspot compatibility

  // Dynamic host IP - will be discovered automatically
  static String _activeHostIp = kIsWeb ? localhostIp : localhostIp;
  static String _activeScheme = 'http'; // http or https
  static String _activeBaseUrl = 'http://$_activeHostIp:$apiPort/api';
  static String _activeFileBaseUrl = 'http://$_activeHostIp:$apiPort';
  
  // Track last discovery check time to avoid checking too frequently
  static DateTime? _lastDiscoveryCheck;
  static const Duration _discoveryCheckInterval = Duration(seconds: 10); // Check every 10 seconds (after initial discovery)
  static const Duration _initialDiscoveryCheckInterval = Duration(seconds: 3); // Check every 3 seconds during initial startup
  static Timer? _ngrokCheckTimer; // Periodic timer to check for ngrok URL
  static bool _hasFoundNgrokUrl = false; // Track if we've found ngrok URL at least once
  static int _initialDiscoveryAttempts = 0; // Track initial discovery attempts
  static const int _maxInitialDiscoveryAttempts = 20; // Try for 60 seconds (20 * 3s) during startup

  static bool _isInitialized = false;
  static Future<void>? _initializing;
  static late BackendDiscoveryService _discoveryService;

  static String get activeHostIp => _activeHostIp;
  static String get activeBaseUrl => _activeBaseUrl;
  static String get activeFileBaseUrl => _activeFileBaseUrl;
  static bool get isInitialized => _isInitialized;
  
  /// Get the discovery service instance (for use in error handlers)
  static BackendDiscoveryService? get discoveryService => _isInitialized ? _discoveryService : null;

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
    if (_isNgrokUrl(_activeHostIp)) {
      headers['ngrok-skip-browser-warning'] = 'true';
    }

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));
    
    // Configure SSL certificate validation for development
    // In development, allow self-signed certificates to avoid HandshakeException
    if (!kIsWeb && kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // Allow bad certificates in debug mode (development only)
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          print('⚠️ [ApiClient] SSL Certificate validation bypassed for $host:$port (DEBUG MODE ONLY)');
          return true; // Accept all certificates in debug mode
        };
        return client;
      };
    }

    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));
    
    // Configure SSL certificate validation for development
    if (!kIsWeb && kDebugMode) {
      (authDio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // Allow bad certificates in debug mode (development only)
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          print('⚠️ [ApiClient] SSL Certificate validation bypassed for $host:$port (DEBUG MODE ONLY)');
          return true; // Accept all certificates in debug mode
        };
        return client;
      };
    }

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
        
        // Start aggressive initial discovery (every 3 seconds) if ngrok URL not found
        // This handles the case where Flutter starts before backend
        if (!_isNgrokUrl(backendInfo.hostname)) {
          _startInitialDiscoveryRetry();
        }
        
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
              final isNewNgrok = _isNgrokUrl(backendInfo.hostname);
              final isCurrentNgrok = _isNgrokUrl(_activeHostIp);
      
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
  
  /// Public method to update active host (used for fallback scenarios)
  static void setActiveHost(String hostIp, [int port = apiPort, bool isHttps = false]) {
    _setActiveHost(hostIp, port, isHttps);
    if (kDebugMode) {
      print('🔄 [ApiClient] Updated active host to: $_activeBaseUrl');
    }
  }

  /// Public method to manually set ngrok URL
  /// This is useful when ngrok URL changes and app hasn't discovered it yet
  /// Usage: In Flutter DevTools console, run: ApiClient.setNgrokUrl('https://xxx.ngrok-free.app')
  static Future<void> setNgrokUrl(String ngrokUrl) async {
    if (kDebugMode) {
      print('🔧 [ApiClient] Manually setting ngrok URL: $ngrokUrl');
    }
    
    try {
      // Parse the URL
      final uri = Uri.parse(ngrokUrl);
      final hostname = uri.host;
      final isHttps = uri.scheme == 'https';
      
      // Validate it's an ngrok URL
      if (!_isNgrokUrl(hostname)) {
        print('⚠️ [ApiClient] Warning: URL does not appear to be an ngrok URL: $hostname');
      }
      
      // Set the active host
      _setActiveHost(hostname, 0, isHttps);
      _hasFoundNgrokUrl = true;
      
      // Save to preferences via discovery service
      if (_isInitialized) {
        await _discoveryService.setManualBackendUrl(ngrokUrl);
        if (kDebugMode) {
          print('✅ [ApiClient] Ngrok URL set and saved: $_activeBaseUrl');
        }
      }
      
      // Switch to normal periodic check
      _startPeriodicNgrokCheck();
      
    } catch (e) {
      print('❌ [ApiClient] Error setting ngrok URL: $e');
      rethrow;
    }
  }

  /// Force refresh discovery to find ngrok URL immediately
  /// This is useful when ngrok URL changes and app hasn't discovered it yet
  static void forceRefreshDiscovery() {
    if (kDebugMode) {
      print('🔄 [ApiClient] Force refreshing discovery...');
    }
    
    if (!_isInitialized) {
      print('⚠️ [ApiClient] ApiClient not initialized yet. Call ensureInitialized() first.');
      return;
    }
    
    // Check for ngrok URL immediately (runs in background)
    _checkForNgrokUrlInBackground();
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
          final isCurrentlyUsingNgrok = _isNgrokUrl(_activeHostIp);
          
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
        if (_isNgrokUrl(uri.host)) {
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

        // Check for HandshakeException or other connection errors
        final isHandshakeException = err.error != null && 
            (err.error.toString().contains('HandshakeException') || 
             err.error.toString().contains('Connection terminated during handshake'));
        final isConnectionError = err.response == null || isHandshakeException;
        
        if (isConnectionError) {
          print('⚠️ DIO CONNECTION ERROR: ${err.error}');
          if (isHandshakeException) {
            print('   Detected HandshakeException - SSL/TLS handshake failed');
            print('   This usually means ngrok URL is invalid or backend is unreachable');
          }
          
          // FormData cannot be reused after being finalized
          // Skip retry for FormData requests to avoid "FormData has already been finalized" error
          if (options.data is FormData) {
            print('⚠️ Skipping retry for FormData request - FormData cannot be reused');
            return handler.next(err);
          }
          
          // Check if we've exceeded maximum time
          final elapsedSeconds = (DateTime.now().millisecondsSinceEpoch - startTime) ~/ 1000;
          if (elapsedSeconds >= maxTotalTimeSeconds) {
            print('❌ Max retry time (${maxTotalTimeSeconds}s) exceeded. Giving up.');
            return handler.next(err);
          }
          
          // Check if error message indicates FormData finalized (even if check above didn't catch it)
          if (err.error != null && err.error.toString().contains('FormData has already been finalized')) {
            print('⚠️ FormData finalized error detected. Skipping retry.');
            return handler.next(err);
          }
          
          // If connection error (including HandshakeException), try to re-discover backend and retry until success
          if (!kIsWeb && _isInitialized && retryCount < maxRetries) {
            try {
              print('🔄 Connection error detected, attempting to re-discover backend... (attempt ${retryCount + 1}, elapsed: ${elapsedSeconds}s)');
              
              // If HandshakeException, clear cached ngrok URL first
              if (isHandshakeException && _isNgrokUrl(_activeHostIp)) {
                print('   HandshakeException detected with ngrok URL - clearing cached URL...');
                try {
                  await _discoveryService.clearManualBackendUrl();
                  print('✅ Cleared cached ngrok URL');
                } catch (clearErr) {
                  print('⚠️ Failed to clear cached ngrok URL: $clearErr');
                }
              }
              
              // Always re-discover to get latest ngrok URL
              final backendInfo = await _discoveryService.discoverBackend();
              final newBaseUrl = backendInfo.baseUrl;
              
              // Check if new backend is ngrok URL and current is not
              final isNewNgrok = _isNgrokUrl(backendInfo.hostname);
              final isCurrentNgrok = _isNgrokUrl(_activeHostIp);
              
              // Always update if:
              // 1. Base URL changed, OR
              // 2. New backend is ngrok URL and current is not (prefer ngrok over IP), OR
              // 3. HandshakeException occurred (force update to new backend)
              if (newBaseUrl != _activeBaseUrl || (isNewNgrok && !isCurrentNgrok) || isHandshakeException) {
                print('✅ Re-discovered backend: ${backendInfo.hostname}:${backendInfo.port} (${backendInfo.discoveryMethod})');
                if (isNewNgrok && !isCurrentNgrok) {
                  print('   Switching to ngrok URL (preferred over IP address)');
                }
                if (isHandshakeException) {
                  print('   Updating backend due to HandshakeException');
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
                // Check again if data is FormData before retry (might have been finalized in previous attempt)
                if (options.data is FormData) {
                  print('⚠️ Cannot retry - FormData has been finalized. Skipping retry.');
                  return handler.next(err);
                }
                final clonedResponse = await dio.fetch(options);
                print('✅ Retry successful after re-discovery (attempt ${retryCount + 1})');
                return handler.resolve(clonedResponse);
              } catch (retryErr) {
                print('⚠️ Retry ${retryCount + 1} after re-discovery failed: $retryErr');
                // Check if error is due to FormData being finalized
                if (retryErr.toString().contains('FormData has already been finalized') || 
                    retryErr.toString().contains('FormData')) {
                  print('⚠️ FormData finalized error detected. Stopping retry.');
                  return handler.next(err);
                }
                // Continue retrying - recursively call handler.next to retry again
                return handler.next(err);
              }
            } catch (discoveryErr) {
              print('⚠️ Re-discovery failed: $discoveryErr');
              
              // If we've tried multiple times and still getting connection errors,
              // clear the cached backend to force fresh discovery (hotspot IP may have changed)
              if (retryCount >= 2) {
                final errorStr = err.error.toString();
                final isNetworkUnreachable = errorStr.contains('Network is unreachable') ||
                                            errorStr.contains('connection timeout') ||
                                            errorStr.contains('Connection refused') ||
                                            errorStr.contains('Connection timed out');
                
                if (isNetworkUnreachable) {
                  print('🗑️ Backend unreachable after ${retryCount + 1} attempts, clearing cache...');
                  print('   This may indicate hotspot IP changed - will force fresh discovery');
                  try {
                    await _discoveryService.clearCache();
                    print('✅ Cleared cached backend, will try fresh discovery on next attempt');
                  } catch (clearErr) {
                    print('⚠️ Failed to clear cache: $clearErr');
                  }
                }
              }
              
              // If discovery fails, still retry (might be temporary issue)
              // But skip if FormData to avoid finalized error
              if (retryCount + 1 < maxRetries && options.data is! FormData) {
                options.extra['retryCount'] = retryCount + 1;
                options.extra['retryStartTime'] = startTime;
                final delaySeconds = (1 << retryCount).clamp(1, 10);
                await Future.delayed(Duration(seconds: delaySeconds));
                return handler.next(err);
              } else if (options.data is FormData) {
                print('⚠️ Skipping retry - FormData request cannot be retried');
                return handler.next(err);
              }
            }
          } else if (retryCount >= maxRetries) {
            print('❌ Max retries ($maxRetries) reached. Giving up.');
          }
        }

        // Check for ngrok offline error (ERR_NGROK_3200)
        // This happens when ngrok URL is cached but ngrok has stopped or URL changed
        if (err.response != null) {
          final headers = err.response!.headers;
          final responseData = err.response!.data;
          
          // Check for ngrok offline error
          // Only consider as ngrok offline if:
          // 1. There's explicit ngrok error code, OR
          // 2. Response contains "is offline" message
          // Don't treat 404 as ngrok offline - 404 usually means endpoint doesn't exist, not ngrok issue
          final hasNgrokErrorCode = headers.value('ngrok-error-code') == 'ERR_NGROK_3200';
          final hasOfflineMessage = responseData is String && responseData.contains('is offline');
          
          final isNgrokOffline = hasNgrokErrorCode || hasOfflineMessage;
          
          if (isNgrokOffline && !kIsWeb && _isInitialized) {
            print('⚠️ Detected ngrok offline error (ERR_NGROK_3200)');
            print('   Current ngrok URL is offline: $_activeHostIp');
            print('   Clearing cached ngrok URL and re-discovering...');
            
            try {
              // Clear cached ngrok URL
              await _discoveryService.clearManualBackendUrl();
              print('✅ Cleared cached ngrok URL');
              
              // Re-discover backend (will find new ngrok URL or fall back to IP)
              final backendInfo = await _discoveryService.discoverBackend();
              print('✅ Re-discovered backend: ${backendInfo.hostname}:${backendInfo.port} (${backendInfo.discoveryMethod})');
              
              // Update active host
              _setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
              
              // Update base URL for this request
              options.baseUrl = _activeBaseUrl;
              
              // Skip retry if FormData (cannot be reused after finalized)
              if (options.data is FormData) {
                print('⚠️ Skipping retry for FormData request after clearing ngrok URL - FormData cannot be reused');
                return handler.next(err);
              }
              
              // Retry the request with new base URL
              try {
                final clonedResponse = await dio.fetch(options);
                print('✅ Retry successful after clearing offline ngrok URL');
                return handler.resolve(clonedResponse);
              } catch (retryErr) {
                print('⚠️ Retry after clearing ngrok URL failed: $retryErr');
                // Check if error is due to FormData being finalized
                if (retryErr.toString().contains('FormData has already been finalized') || 
                    retryErr.toString().contains('FormData')) {
                  print('⚠️ FormData finalized error detected. Stopping retry.');
                  return handler.next(err);
                }
                // Continue to next error handler (401, etc.)
              }
            } catch (clearErr) {
              print('⚠️ Failed to clear ngrok URL and re-discover: $clearErr');
            }
          }
        }

        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();

          if (refreshToken == null || isRefreshing) {
            // Only auto-logout if no refresh token or already refreshing
            // This prevents logout during payment callback when token might be temporarily expired
            if (refreshToken == null) {
              print('⚠️ No refresh token available. User will need to login again.');
              // Only delete session data, keep fingerprint credentials
              await _storage.deleteSessionData();
              // Emit event to trigger logout and redirect to login
              AppEventBus().emit('auth_token_expired', {'reason': 'no_refresh_token'});
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
            // Check if refresh token itself is expired (401 or 403 from refresh endpoint)
            final refreshStatusCode = e.response?.statusCode;
            if (refreshStatusCode == 401 || refreshStatusCode == 403) {
              print('⚠️ REFRESH TOKEN EXPIRED: ${e.message}');
              print('⚠️ User session expired. Logging out...');
              // Delete session data and emit event to trigger logout
              await _storage.deleteSessionData();
              AppEventBus().emit('auth_token_expired', {'reason': 'refresh_token_expired'});
            } else {
              // Other errors - might be temporary network issue
              // But if refresh fails multiple times, it's likely expired
              print('⚠️ REFRESH FAILED: ${e.message}');
              print('⚠️ User session may be expired. Emitting auth_token_expired event...');
              // Emit event to trigger logout - better to logout than keep trying
              await _storage.deleteSessionData();
              AppEventBus().emit('auth_token_expired', {'reason': 'refresh_failed'});
            }
            return handler.next(e);
          } catch (e) {
            // Any other error during refresh - treat as expired
            print('⚠️ REFRESH ERROR: ${e.toString()}');
            print('⚠️ User session expired. Logging out...');
            await _storage.deleteSessionData();
            AppEventBus().emit('auth_token_expired', {'reason': 'refresh_error'});
            return handler.next(err);
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

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
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
        final isNgrokUrl = _isNgrokUrl(host);
        
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
        final isCurrentlyUsingNgrok = _isNgrokUrl(_activeHostIp);
        
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
          // Try multiple discovery URLs (localhost variants for different platforms)
          final discoveryUrls = <String>[];
          
          // Add current active host first
          discoveryUrls.add('$_activeScheme://$_activeHostIp:$apiPort/api/discovery/info');
          
          // Add platform-specific fallbacks
          if (Platform.isAndroid) {
            discoveryUrls.add('http://10.0.2.2:$apiPort/api/discovery/info'); // Android emulator
          }
          discoveryUrls.add('http://localhost:$apiPort/api/discovery/info'); // Desktop/web
          
          String? ngrokUrl;
          for (final discoveryUrl in discoveryUrls) {
            try {
              final dio = Dio();
              dio.options.connectTimeout = const Duration(seconds: 5); // Increased timeout
              dio.options.receiveTimeout = const Duration(seconds: 5);
              
              if (kDebugMode) {
                print('🔍 Trying discovery endpoint: $discoveryUrl');
              }
              
              final response = await dio.get(discoveryUrl).timeout(const Duration(seconds: 5));
          
              if (response.statusCode == 200 && response.data != null) {
                if (kDebugMode) {
                  print('✅ Discovery endpoint responded: ${response.data}');
                }
                
                // Parse response - handle both Map and dynamic types
                final data = response.data;
                String? publicUrl;
                String? httpUrl;
                String? httpsUrl;
                
                if (data is Map) {
                  publicUrl = data['publicUrl']?.toString();
                  httpUrl = data['httpUrl']?.toString();
                  httpsUrl = data['httpsUrl']?.toString();
                } else if (data is Map<String, dynamic>) {
                  publicUrl = data['publicUrl']?.toString();
                  httpUrl = data['httpUrl']?.toString();
                  httpsUrl = data['httpsUrl']?.toString();
                }
                
                // Prefer HTTP URL to avoid ngrok warning page, then HTTPS, then publicUrl
                if (httpUrl != null && httpUrl.isNotEmpty && !httpUrl.contains('your-ngrok-url')) {
                  ngrokUrl = httpUrl;
                } else if (httpsUrl != null && httpsUrl.isNotEmpty && !httpsUrl.contains('your-ngrok-url')) {
                  ngrokUrl = httpsUrl;
                } else if (publicUrl != null && publicUrl.isNotEmpty && !publicUrl.contains('your-ngrok-url')) {
                  ngrokUrl = publicUrl;
                }
                
                // Remove trailing slash
                if (ngrokUrl != null && ngrokUrl.endsWith('/')) {
                  ngrokUrl = ngrokUrl.substring(0, ngrokUrl.length - 1);
                }
                
                // Found ngrok URL - break loop
                if (ngrokUrl != null && ngrokUrl.isNotEmpty) {
                  break; // Success, exit loop
                }
              }
            } catch (e) {
              if (kDebugMode) {
                print('⚠️ Discovery failed for $discoveryUrl: $e');
              }
              // Continue to next URL
              continue;
            }
          }
          
          // If we found ngrok URL, use it
          if (ngrokUrl != null && ngrokUrl.isNotEmpty) {
            final ngrokUri = Uri.tryParse(ngrokUrl);
            if (ngrokUri != null && _isNgrokUrl(ngrokUri.host)) {
              // Found ngrok URL - verify it's reachable before switching
              try {
                final ngrokDio = Dio();
                ngrokDio.options.connectTimeout = const Duration(seconds: 5);
                ngrokDio.options.receiveTimeout = const Duration(seconds: 5);
                ngrokDio.options.headers['ngrok-skip-browser-warning'] = 'true';
                
                final ngrokHealthUrl = '$ngrokUrl/api/health';
                final ngrokResponse = await ngrokDio.get(ngrokHealthUrl).timeout(const Duration(seconds: 5));
                
                if (ngrokResponse.statusCode == 200) {
                  // Ngrok URL is reachable - switch to it immediately
                  print('🔄 Auto-discovered ngrok URL, switching from IP to ngrok...');
                  print('   Ngrok URL: $ngrokUrl');
                  
                  // Parse ngrok URL to extract hostname
                  final ngrokHostname = ngrokUri.host;
                  final isHttps = ngrokUri.scheme == 'https';
                  
                  // Switch to ngrok URL immediately
                  _setActiveHost(ngrokHostname, 0, isHttps); // Port 0 means no port in URL
                  print('✅ Switched to ngrok URL: $ngrokHostname');
                  print('   New base URL: $_activeBaseUrl');
                  
                  // Mark that we've found ngrok URL (stop aggressive initial discovery)
                  _hasFoundNgrokUrl = true;
                  
                  // Also save this ngrok URL to preferences for future use
                  try {
                    await _discoveryService.setManualBackendUrl(ngrokUrl);
                    print('💾 Saved ngrok URL to preferences');
                  } catch (e) {
                    print('⚠️ Failed to save ngrok URL: $e');
                  }
                } else {
                  if (kDebugMode) {
                    print('⚠️ Ngrok URL health check returned status ${ngrokResponse.statusCode}');
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  print('⚠️ Ngrok URL not reachable: $e');
                }
                // Ngrok URL not reachable - keep using IP address
              }
            } else {
              if (kDebugMode) {
                print('⚠️ Invalid ngrok URL format: $ngrokUrl');
              }
            }
          } else {
            if (kDebugMode) {
              print('⚠️ No valid ngrok URL found from any discovery endpoint');
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
      final isNgrokUrl = _isNgrokUrl(backendInfo.hostname);
      
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
  
  /// Start aggressive initial discovery retry
  /// This runs every 3 seconds during startup until ngrok URL is found or max attempts reached
  /// Handles the case where Flutter starts before backend
  static void _startInitialDiscoveryRetry() {
    if (kIsWeb) return;
    if (_hasFoundNgrokUrl) return; // Already found ngrok URL
    
    _initialDiscoveryAttempts = 0;
    
    if (kDebugMode) {
      print('🔄 Starting aggressive initial discovery (every ${_initialDiscoveryCheckInterval.inSeconds}s for ${_maxInitialDiscoveryAttempts * _initialDiscoveryCheckInterval.inSeconds}s)...');
      print('   This handles the case where Flutter starts before backend');
    }
    
    Timer.periodic(_initialDiscoveryCheckInterval, (timer) {
      if (!_isInitialized) {
        timer.cancel();
        return;
      }
      
      // Stop if we've found ngrok URL
      if (_hasFoundNgrokUrl) {
        if (kDebugMode) {
          print('✅ Found ngrok URL, stopping aggressive initial discovery');
        }
        timer.cancel();
        return;
      }
      
      // Stop if max attempts reached
      if (_initialDiscoveryAttempts >= _maxInitialDiscoveryAttempts) {
        if (kDebugMode) {
          print('⏱️ Initial discovery timeout (${_maxInitialDiscoveryAttempts * _initialDiscoveryCheckInterval.inSeconds}s), switching to normal periodic check');
        }
        timer.cancel();
        return;
      }
      
      _initialDiscoveryAttempts++;
      
      // Check for ngrok URL
      if (kDebugMode && _initialDiscoveryAttempts % 5 == 0) {
        print('🔍 Initial discovery attempt $_initialDiscoveryAttempts/$_maxInitialDiscoveryAttempts...');
      }
      
      _checkForNgrokUrlInBackground();
    });
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
      final isCurrentlyUsingNgrok = _isNgrokUrl(_activeHostIp);
      
      if (!isCurrentlyUsingNgrok) {
        // Check for ngrok URL in background
        _checkForNgrokUrlInBackground();
      }
    });
    
    if (kDebugMode) {
      print('🔄 Started periodic ngrok URL check (every ${_discoveryCheckInterval.inSeconds}s)');
    }
  }
}



