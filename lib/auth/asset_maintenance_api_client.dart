import 'package:dio/dio.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'token_storage.dart';

class AssetMaintenanceApiClient {
  AssetMaintenanceApiClient._(
    this.dio,
    this._storage,
    this._authService,
  ) {
    _setupInterceptors();
  }

  factory AssetMaintenanceApiClient() {
    assert(
      ApiClient.isInitialized,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      ),
    );
    final authDio = Dio(
      BaseOptions(
        baseUrl: ApiClient.activeBaseUrl,
        connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
        receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      ),
    );
    final authService = AuthService(authDio, storage);
    return AssetMaintenanceApiClient._(dio, storage, authService);
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool _isRefreshing = false;

  // All requests go through API Gateway (port 8989)
  // Gateway routes /api/asset-maintenance/** to asset-maintenance-service (8084)
  static String get _baseUrl =>
      ApiClient.buildServiceBase(
        path: '/api/asset-maintenance',
      );

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestBody: true,
        requestHeader: true,
        responseBody: true,
        responseHeader: true,
        error: true,
        logPrint: (object) {
          final logString = object.toString();
          
          // Suppress logging for expected "Booking not found" errors (400/404)
          // Pattern 1: DioException with 400/404 for booking requests
          if (logString.contains('DioException') && 
              (logString.contains('status code of 400') || 
               logString.contains('status code of 404'))) {
            // Check if URI contains bookings (might be on same or different line)
            // We'll suppress this and related lines
            return;
          }
          
          // Pattern 2: URI contains /bookings/ with 400/404 status
          if (logString.contains('/bookings/') && 
              (logString.contains('statusCode: 400') ||
               logString.contains('statusCode: 404'))) {
            return;
          }
          
          // Pattern 3: Status code 400/404 (likely part of booking error sequence)
          if ((logString.contains('statusCode: 400') ||
               logString.contains('statusCode: 404')) &&
              logString.contains('uri:') &&
              logString.contains('/bookings/')) {
            return;
          }
          
          // Pattern 4: Response body with "Booking not found" message
          if (logString.contains('Booking not found') ||
              logString.contains('"message":"Booking not found')) {
            return;
          }
          
          // Pattern 5: Response Text line that might contain the error message
          if (logString.contains('Response Text:') && 
              logString.contains('not found')) {
            return;
          }
          
          // Print normally
          print('🔍 ASSET DIO: $object');
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
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
        onError: (error, handler) async {
          final options = error.requestOptions;
          if (error.response?.statusCode == 401) {
            final refreshToken = await _storage.readRefreshToken();
            if (refreshToken == null || _isRefreshing) {
              // Only delete session data, keep fingerprint credentials
              await _storage.deleteSessionData();
              return handler.next(error);
            }
            try {
              _isRefreshing = true;
              await _authService.refreshToken();
              final newAccessToken = await _storage.readAccessToken();
              if (newAccessToken != null) {
                options.headers['Authorization'] = 'Bearer $newAccessToken';
                final cloned = await dio.fetch(options);
                return handler.resolve(cloned);
              }
            } on DioException catch (refreshError) {
              // Only delete session data, keep fingerprint credentials
              await _storage.deleteSessionData();
              return handler.next(refreshError);
            } finally {
              _isRefreshing = false;
            }
          }
          return handler.next(error);
        },
      ),
    );
  }
}


