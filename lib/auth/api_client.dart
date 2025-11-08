import 'package:dio/dio.dart';
import 'token_storage.dart';
import 'auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb; 
class ApiClient {
  
static const String LAN_HOST_IP = '192.168.100.33'; 
  static const String LOCALHOST_IP = 'localhost'; // <-- Thêm hằng số này
  static const int API_PORT = 8081; // Changed to base-service port
  static const int TIMEOUT_SECONDS = 10;

  // SỬA DÒNG NÀY: Dùng localhost nếu là web, ngược lại dùng IP LAN
  static final String HOST_IP = kIsWeb ? LOCALHOST_IP : LAN_HOST_IP; 

  static final String BASE_URL = 'http://$HOST_IP:$API_PORT/api';
  
  static final String FILE_BASE_URL = 'http://$HOST_IP:$API_PORT';

  final Dio dio;
  // ignore: unused_field
  final Dio _authDio;
  final TokenStorage _storage;
  final AuthService _authService;
  
  bool isRefreshing = false; 

  TokenStorage get storage => _storage;

  ApiClient._(this.dio, this._storage, this._authService, this._authDio) {
    _setupInterceptors();
  }

  factory ApiClient() {
    final storage = TokenStorage();
    
    final dio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS), 
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    final authDio = Dio(BaseOptions(
      baseUrl: BASE_URL,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS), 
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    final authService = AuthService(authDio, storage); 
    
    return ApiClient._(dio, storage, authService, authDio);
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
        final options = err.requestOptions;
        
        if (err.response == null) {
           print('⚠️ DIO CONNECTION ERROR: ${err.error}');
        }
        
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          
          if (refreshToken == null || isRefreshing) {
            await _storage.deleteAll();
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
            print('🔥 REFRESH FAILED: Token will be deleted.');
            await _storage.deleteAll();
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
    final dio = Dio(BaseOptions(
        baseUrl: BASE_URL,
        connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
        receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));
    final authDio = Dio(BaseOptions(
        baseUrl: BASE_URL,
        connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
        receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));
    final authService = AuthService(authDio, storage);
    return ApiClient._(dio, storage, authService, authDio);
  }

  static String fileUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$FILE_BASE_URL$path';
  }
}