import 'package:dio/dio.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'token_storage.dart';

class CustomerInteractionApiClient {
  // All requests go through API Gateway (port 8989)
  // Gateway routes /api/customer-interaction/** to customer-interaction-service (8086)

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  static String get baseUrl => ApiClient.buildServiceBase(
        path: '/api/customer-interaction',
      );

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  CustomerInteractionApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory CustomerInteractionApiClient() {
    assert(
      ApiClient.isInitialized,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: ApiClient.sendTimeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: ApiClient.connectTimeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.receiveTimeoutSeconds),
      sendTimeout: const Duration(seconds: ApiClient.sendTimeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    return CustomerInteractionApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 CUSTOMER INTERACTION LOG: $obj'),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        if (_isNgrokUrl(uri.host)) {
          options.headers['ngrok-skip-browser-warning'] = 'true';
        }
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) {
            // Only delete session data, keep fingerprint credentials
            await _storage.deleteSessionData();
            return handler.next(err);
          }
          try {
            isRefreshing = true;
            await _authService.refreshToken();
            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              final cloned = await dio.fetch(options);
              return handler.resolve(cloned);
            }
          } on DioException catch (e) {
            // Only delete session data, keep fingerprint credentials
            await _storage.deleteSessionData();
            return handler.next(e);
          } finally {
            isRefreshing = false;
          }
        }
        return handler.next(err);
      },
    ));
  }
}


