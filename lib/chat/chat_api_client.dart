import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage.dart';

class ChatApiClient {
  static String get baseUrl => ApiClient.buildServiceBase(
        path: '/api/chat',
      );

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  ChatApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory ChatApiClient() {
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
    return ChatApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        print('📤 [ChatApiClient] ${options.method} ${options.path}');
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        final statusCode = err.response?.statusCode;
        final path = options.path;
        
        // Log error for debugging
        print('❌ [ChatApiClient] Error ${statusCode ?? 'unknown'} on ${options.method} $path');
        
        if (statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) {
            await _storage.deleteSessionData();
            return handler.next(err);
          }
          try {
            isRefreshing = true;
            print('🔄 [ChatApiClient] Refreshing token for 401 error...');
            await _authService.refreshToken();
            final newAccessToken = await _storage.readAccessToken();
            if (newAccessToken != null) {
              options.headers['Authorization'] = 'Bearer $newAccessToken';
              print('✅ [ChatApiClient] Token refreshed, retrying request...');
              final cloned = await dio.fetch(options);
              return handler.resolve(cloned);
            }
          } on DioException catch (e) {
            print('❌ [ChatApiClient] Token refresh failed: ${e.message}');
            await _storage.deleteSessionData();
            return handler.next(e);
          } finally {
            isRefreshing = false;
          }
        } else if (statusCode == 404) {
          // Log 404 for debugging (might be service not ready or endpoint doesn't exist)
          print('⚠️ [ChatApiClient] 404 on $path - Service might not be ready or endpoint not found');
        }
        
        return handler.next(err);
      },
    ));
  }
}

