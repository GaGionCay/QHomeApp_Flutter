import 'dart:io' show Platform, HttpClient, X509Certificate;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import '../core/app_config.dart';
import '../core/event_bus.dart';
import 'auth_service.dart';
import 'backend_discovery_service.dart';
import 'token_storage.dart';

/// Simplified ApiClient for DEV LOCAL mode
/// Uses fixed baseUrl from AppConfig - no discovery, no switching, no retry loops
class ApiClient {
  // Timeout configuration for DEV LOCAL mode
  static const int connectTimeoutSeconds = 10;
  static const int receiveTimeoutSeconds = 30;
  static const int sendTimeoutSeconds = 10;
  static const int maxRetries = 1; // Maximum 1 retry, no parallel retries

  // Fixed base URL from AppConfig - loaded once at startup, never changes
  static final String _activeBaseUrl = AppConfig.fullApiBaseUrl;
  static final String _activeFileBaseUrl = AppConfig.apiBaseUrl;

  static bool _isInitialized = false;
  static Future<void>? _initializing;
  static late BackendDiscoveryService _discoveryService;

  static String get activeHostIp {
    final uri = Uri.parse(AppConfig.apiBaseUrl);
    return uri.host.isEmpty ? '127.0.0.1' : uri.host;
  }
  
  static String get activeBaseUrl => _activeBaseUrl;
  static String get activeFileBaseUrl => _activeFileBaseUrl;
  static bool get isInitialized => _isInitialized;
  
  /// Get the discovery service instance (for compatibility)
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

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    
    // Configure SSL certificate validation for development
    if (!kIsWeb && kDebugMode) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          print('⚠️ [ApiClient] SSL Certificate validation bypassed for $host:$port (DEBUG MODE ONLY)');
          return true;
        };
        return client;
      };
    }

    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    
    if (!kIsWeb && kDebugMode) {
      (authDio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          print('⚠️ [ApiClient] SSL Certificate validation bypassed for authDio $host:$port (DEBUG MODE ONLY)');
          return true;
        };
        return client;
      };
    }

    final authService = AuthService(authDio, storage);
    return ApiClient._(dio, storage, authService);
  }

  static Future<void> _initializeFixedHost() async {
    if (kIsWeb) {
      // Web mode - use AppConfig directly
    } else {
      // Validate baseUrl configuration
      AppConfig.validateBaseUrl();
      
      // Initialize discovery service (simplified - no actual discovery)
      _discoveryService = BackendDiscoveryService.instance;
        await _discoveryService.initialize();
        
      // Log health check status (for monitoring only - does not change connection)
      _logHealthCheckStatus();
    }

    _isInitialized = true;
  }

  /// Log health check status (for monitoring only - does not change connection)
  static Future<void> _logHealthCheckStatus() async {
    // Run health check in background for logging only
    Future.microtask(() async {
      try {
        final dio = Dio();
        dio.options.connectTimeout = const Duration(seconds: 3);
        dio.options.receiveTimeout = const Duration(seconds: 3);
        
        final healthUrl = '$_activeBaseUrl/health';
        final response = await dio.get(healthUrl).timeout(const Duration(seconds: 3));
        
        if (response.statusCode == 200) {
    if (kDebugMode) {
            print('✅ [Health Check] Backend is reachable at $_activeBaseUrl');
    }
  }
      } catch (e) {
    if (kDebugMode) {
          print('⚠️ [Health Check] Backend not reachable at $_activeBaseUrl: $e');
          print('   (This is for logging only - connection will not be changed)');
        }
      }
    });
  }

  static Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }
    final init = _initializeFixedHost();
    _initializing = init;
    await init;
  }

 
  static String buildServiceBase({
    int? port, // Ignored in DEV LOCAL mode
    String path = '',
  }) {
    String normalizedPath = path;
    if (normalizedPath.isNotEmpty && !normalizedPath.startsWith('/')) {
      normalizedPath = '/$normalizedPath';
    }
    
    // Prevent double /api by checking if path already starts with /api
    if (normalizedPath.startsWith('/api/')) {
      // Path already includes /api, use baseUrl without /api
      final baseWithoutApi = AppConfig.apiBaseUrl;
      return '$baseWithoutApi$normalizedPath';
    }
    
    // Normal case: path doesn't include /api, use fullApiBaseUrl
    return '$_activeBaseUrl$normalizedPath';
  }

  /// Log error only after final retry failure (production-ready)
  void _logErrorAfterRetry(DioException error, int retryCount) {
    // Handle receiveTimeout: only log 1 concise line, no stacktrace, no retry
    if (error.type == DioExceptionType.receiveTimeout) {
      print('Backend is taking too long to respond.');
      return;
    }
    
    final uri = error.requestOptions.uri;
    final errorType = error.type.toString().split('.').last;
    
    if (error.type == DioExceptionType.connectionError || 
        error.type == DioExceptionType.connectionTimeout) {
      final errorMsg = error.error?.toString() ?? error.message ?? 'Connection error';
      if (errorMsg.contains('SocketException') || errorMsg.contains('Connection refused')) {
        final baseUri = Uri.parse(_activeBaseUrl);
        final host = baseUri.host;
        
        if (host == '127.0.0.1' || host == 'localhost') {
          print('❌ [ApiClient] Connection failed after $retryCount retry(ies): $_activeBaseUrl');
          print('   Using localhost on physical device - update app_config.dart with LAN IP');
        } else {
          print('❌ [ApiClient] Connection failed after $retryCount retry(ies): $host:${baseUri.port}');
        }
        return;
      }
    }
    
    // Log 5xx errors (backend errors)
    if (error.response != null && error.response!.statusCode != null && error.response!.statusCode! >= 500) {
      print('❌ [ApiClient] HTTP ${error.response?.statusCode}: ${uri.path}');
      return;
    }
    
    // Log other errors only if not recoverable
    if (error.response != null) {
      print('❌ [ApiClient] HTTP ${error.response?.statusCode} after $retryCount retry(ies): ${uri.path}');
    } else if (error.type != DioExceptionType.receiveTimeout) {
      print('❌ [ApiClient] $errorType after $retryCount retry(ies): ${uri.path}');
    }
  }

  void _setupInterceptors() {
    // Production-ready: No LogInterceptor - errors logged only after final retry failure

    // Retry interceptor - max 1 retry, no parallel retries, no retry loops
    dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        final options = error.requestOptions;
        final retryCount = options.extra['retryCount'] as int? ?? 0;
        
        // NO RETRY for receiveTimeout - fail fast to avoid overload
        if (error.type == DioExceptionType.receiveTimeout) {
          _logErrorAfterRetry(error, 0);
          return handler.next(error);
        }
        
        // Only retry for connection/send timeout, max 1 retry
        if (retryCount < maxRetries &&
            (error.type == DioExceptionType.connectionTimeout ||
             error.type == DioExceptionType.sendTimeout)) {
          options.extra['retryCount'] = retryCount + 1;
          // Wait a bit before retry (no parallel retries)
          await Future.delayed(const Duration(milliseconds: 500));
          try {
            final response = await dio.fetch(options);
            return handler.resolve(response);
          } catch (e) {
            // Retry failed - log error only after final retry
            _logErrorAfterRetry(error, retryCount + 1);
            return handler.next(error);
          }
        } else {
          // No more retries - log error
          _logErrorAfterRetry(error, retryCount);
        }
        // Pass to next interceptor (main error handler)
        return handler.next(error);
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Check network connectivity before making request
        if (!kIsWeb) {
          try {
            final connectivity = Connectivity();
            final connectivityResult = await connectivity.checkConnectivity();
            
            if (connectivityResult.contains(ConnectivityResult.none)) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'No network connectivity available. Please check your WiFi/mobile data connection.',
                  type: DioExceptionType.connectionError,
                ),
              );
            }
          } catch (e) {
            // Silent fail - connectivity check error not critical
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
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        // NO RETRY LOOPS - fail fast in DEV LOCAL mode
        // Connection errors are logged but not retried
        
        // Connection errors already logged in _logErrorAfterRetry
        // Just pass to next handler

        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();

          if (refreshToken == null || isRefreshing) {
            if (refreshToken == null) {
              await _storage.deleteSessionData();
              AppEventBus().emit('auth_token_expired', {'reason': 'no_refresh_token'});
            }
            return handler.next(err);
          }

          try {
            isRefreshing = true;
            await _authService.refreshToken();

            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              err.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
              final clonedResponse = await dio.fetch(err.requestOptions);
              return handler.resolve(clonedResponse);
            }
          } on DioException catch (e) {
            final refreshStatusCode = e.response?.statusCode;
            if (refreshStatusCode == 401 || refreshStatusCode == 403) {
              await _storage.deleteSessionData();
              AppEventBus().emit('auth_token_expired', {'reason': 'refresh_token_expired'});
            } else {
              await _storage.deleteSessionData();
              AppEventBus().emit('auth_token_expired', {'reason': 'refresh_failed'});
            }
            return handler.next(e);
          } catch (e) {
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
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: sendTimeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    return ApiClient._(dio, storage, authService);
  }

  static String fileUrl(String path) {
    if (path.startsWith('http')) {
      // If URL contains localhost or port 8082, replace with correct host
      final url = path;
      final uri = Uri.tryParse(url);
      if (uri != null && (url.contains('localhost') || url.contains('127.0.0.1') || uri.port == 8082)) {
        final baseUri = Uri.parse(AppConfig.apiBaseUrl);
        final host = baseUri.host.isEmpty ? '127.0.0.1' : baseUri.host;
        final scheme = baseUri.scheme;
        final port = baseUri.port == 0 ? null : baseUri.port;
        
          return Uri(
            scheme: scheme,
            host: host,
            port: port,
            path: uri.path,
            query: uri.query,
          ).toString();
        }
      return path;
    }
    
    return '$_activeFileBaseUrl$path';
  }
  
  /// Force refresh discovery (no-op in DEV LOCAL mode)
  static void forceRefreshDiscovery() {
    // No-op in DEV LOCAL mode
  }
  
  /// Set active host (no-op in DEV LOCAL mode)
  static void setActiveHost(String hostIp, [int port = 8989, bool isHttps = false]) {
    // No-op in DEV LOCAL mode
  }
}
