import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage.dart';

class MarketplaceApiClient {
  // All requests go through API Gateway (port 8989)
  // Gateway routes /api/marketplace/** to marketplace-service

  static String get baseUrl => ApiClient.buildServiceBase(
        path: '/api/marketplace',
      );

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  MarketplaceApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory MarketplaceApiClient() {
    assert(
      ApiClient.isInitialized,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
    ));
    final authService = AuthService(authDio, storage);
    return MarketplaceApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 MARKETPLACE API LOG: $obj'),
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
        
        // Increase timeout for different request types
        
        // 1. GET /posts - List posts (may include many posts with videos)
        if (options.path == '/posts' && options.method == 'GET') {
          final newOptions = options.copyWith(
            receiveTimeout: const Duration(seconds: 60), // 60 seconds for list with videos
            sendTimeout: const Duration(seconds: 30),
          );
          return handler.next(newOptions);
        }
        
        // 2. GET /posts/{id} - Post detail (may include video)
        if (options.path.contains('/posts/') && 
            !options.path.contains('/comments') && 
            !options.path.contains('/status') &&
            options.method == 'GET') {
          final newOptions = options.copyWith(
            receiveTimeout: const Duration(seconds: 90), // 90 seconds for post with video
            sendTimeout: const Duration(seconds: 30),
          );
          return handler.next(newOptions);
        }
        
        // 3. POST /posts - Create post (upload video/images)
        if (options.path == '/posts' && options.method == 'POST') {
          final newOptions = options.copyWith(
            receiveTimeout: const Duration(seconds: 120), // 120 seconds for upload
            sendTimeout: const Duration(seconds: 120), // 120 seconds for upload
          );
          return handler.next(newOptions);
        }
        
        // 4. PUT /posts/{id} - Update post (upload video/images)
        if (options.path.contains('/posts/') && 
            !options.path.contains('/comments') && 
            !options.path.contains('/status') &&
            options.method == 'PUT') {
          final newOptions = options.copyWith(
            receiveTimeout: const Duration(seconds: 120), // 120 seconds for upload
            sendTimeout: const Duration(seconds: 120), // 120 seconds for upload
          );
          return handler.next(newOptions);
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


