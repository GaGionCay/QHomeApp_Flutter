import 'package:dio/dio.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'token_storage.dart';
import 'auth_service.dart';

class ApiClient {
  //home
  static const String BASE_URL = 'http://192.168.100.33:8080/api';
  static const String FILE_BASE_URL = 'http://192.168.100.33:8080';
  //FBT
  //static const String BASE_URL = 'http://10.33.63.155:8080/api';
  //static const String FILE_BASE_URL = 'http://10.33.63.155:8080';
  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  TokenStorage get storage => _storage;

  ApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory ApiClient() {
    final storage = TokenStorage();
    final dio = Dio(BaseOptions(baseUrl: BASE_URL));
    final authService = AuthService(dio, storage);
    return ApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) {
          if (JwtDecoder.isExpired(token)) {
            try {
              await _authService.refreshToken();
            } catch (_) {
              await _storage.deleteAll();
            }
          }
          final newToken = await _storage.readAccessToken();
          if (newToken != null) {
            options.headers['Authorization'] = 'Bearer $newToken';
          }
        }
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) {
          options.headers['X-Device-Id'] = deviceId;
        }
        return handler.next(options);
      },
      onError: (err, handler) async {
        if (err.response?.statusCode == 401) {
          try {
            await _authService.refreshToken();
            final newAccess = await _storage.readAccessToken();
            if (newAccess != null) {
              final requestOptions = err.requestOptions;
              requestOptions.headers['Authorization'] = 'Bearer $newAccess';
              final cloned = await dio.fetch(requestOptions);
              return handler.resolve(cloned);
            }
          } catch (_) {
            await _storage.deleteAll();
          }
        }
        return handler.next(err);
      },
    ));
  }

  static Future<ApiClient> create() async {
    final storage = TokenStorage();
    final dio = Dio(BaseOptions(baseUrl: BASE_URL));
    final authService = AuthService(dio, storage);
    return ApiClient._(dio, storage, authService);
  }

  static String fileUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$FILE_BASE_URL$path';
  }
}
