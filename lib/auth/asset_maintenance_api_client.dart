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
    final storage = TokenStorage();

    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
        receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      ),
    );

    final authDio = Dio(
      BaseOptions(
        baseUrl: ApiClient.BASE_URL,
        connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
        receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      ),
    );

    final authService = AuthService(authDio, storage);

    return AssetMaintenanceApiClient._(dio, storage, authService);
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool _isRefreshing = false;

  static const int _apiPort = 8084;
  static String get _baseUrl =>
      'http://${ApiClient.HOST_IP}:$_apiPort/api/asset-maintenance';

  void _setupInterceptors() {
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestBody: true,
        requestHeader: true,
        responseBody: true,
        responseHeader: true,
        error: true,
        logPrint: (object) => print('🔍 ASSET DIO: $object'),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
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
        onError: (error, handler) async {
          final options = error.requestOptions;

          if (error.response?.statusCode == 401) {
            final refreshToken = await _storage.readRefreshToken();
            if (refreshToken == null || _isRefreshing) {
              await _storage.deleteAll();
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
              await _storage.deleteAll();
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

