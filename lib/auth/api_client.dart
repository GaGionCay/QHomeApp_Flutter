import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';

import 'auth_service.dart';
import 'token_storage.dart';

class ApiClient {
  static const String LAN_HOST_IP = '192.168.100.33';
  static const String LAN_BACKUP_HOST_IP = '192.168.1.15'; 
  static const String OFFICE_HOST_IP = '10.33.63.155';
  static const String OFFICE_BACKUP_HOST_IP = '10.189.244.236'; 
  static const String LOCALHOST_IP = 'localhost';

  static const int API_PORT = 8081;
  static const int TIMEOUT_SECONDS = 10;

  static const String HOST_IP = kIsWeb ? LOCALHOST_IP : OFFICE_HOST_IP;
  static const String BASE_URL = 'http://$HOST_IP:$API_PORT/api';
  static const String FILE_BASE_URL = 'http://$HOST_IP:$API_PORT';

  static const Map<String, String> _wifiHostOverrides = {
    'WifiNha': LAN_HOST_IP,
    'WifiNha2': LAN_BACKUP_HOST_IP,
    'WifiCongTy': OFFICE_HOST_IP,
    'WifiCongTyMoi': OFFICE_BACKUP_HOST_IP,
  };

  static const Map<String, String> _localIpPrefixOverrides = {
    '192.168.100.': LAN_HOST_IP,
    '192.168.1.': LAN_BACKUP_HOST_IP,
    '10.33.': OFFICE_HOST_IP,
    '10.189.': OFFICE_BACKUP_HOST_IP,
  };

  static String _activeHostIp = HOST_IP;
  static String _activeBaseUrl = BASE_URL;
  static String _activeFileBaseUrl = FILE_BASE_URL;

  static bool _isInitialized = false;
  static Future<void>? _initializing;

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

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));

    final authService = AuthService(authDio, storage);

    print('🌐 ApiClient → Using $_activeBaseUrl');
    return ApiClient._(dio, storage, authService);
  }
  static Future<void> _initializeDynamicHost() async {
    if (kIsWeb) {
      _setActiveHost(LOCALHOST_IP);
    } else {
      try {
        final info = NetworkInfo();
        final wifiName = _normalizeWifiName(await info.getWifiName());
        final wifiIP = await info.getWifiIP();

        print('📶 Connected Wi-Fi: $wifiName | Device IP: $wifiIP');

        final overrideIp = _resolveIpForWifi(wifiName);
        _setActiveHost(
          overrideIp ?? _resolveIpByLocalAddress(wifiIP) ?? HOST_IP,
        );
      } catch (e) {
        print('⚠️ Network detect failed: $e');
        _setActiveHost(OFFICE_HOST_IP);
      }
    }

    _isInitialized = true;
  }

  static void _setActiveHost(String hostIp) {
    _activeHostIp = hostIp;
    _activeBaseUrl = 'http://$hostIp:$API_PORT/api';
    _activeFileBaseUrl = 'http://$hostIp:$API_PORT';
  }

  static String? _resolveIpForWifi(String? wifiName) {
    if (wifiName == null) return null;
    final normalized = wifiName.toLowerCase();
    for (final entry in _wifiHostOverrides.entries) {
      if (entry.key.toLowerCase() == normalized) {
        return entry.value;
      }
    }
    return null;
  }

  static String? _resolveIpByLocalAddress(String? wifiIP) {
    if (wifiIP == null) return null;
    for (final entry in _localIpPrefixOverrides.entries) {
      if (wifiIP.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  static String? _normalizeWifiName(String? wifiName) {
    if (wifiName == null) return null;
    return wifiName.replaceAll('"', '').trim();
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

  static String buildServiceBase({
    required int port,
    String path = '',
  }) {
    final normalizedPath = path.isEmpty
        ? ''
        : path.startsWith('/') ? path : '/$path';
    return 'http://$_activeHostIp:$port$normalizedPath';
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
    await ensureInitialized();

    final dio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: TIMEOUT_SECONDS),
    ));
    final authService = AuthService(authDio, storage);
    print('🌐 ApiClient.create() → $_activeBaseUrl');
    return ApiClient._(dio, storage, authService);
  }

  static String fileUrl(String path) {
    if (path.startsWith('http')) return path;
    return '$_activeFileBaseUrl$path';
  }
}
