import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:network_info_plus/network_info_plus.dart';

import 'auth_service.dart';
import 'token_storage.dart';

class ApiClient {
  static const String lanHostIp = '192.168.100.33';
  //static const String lanHostIp = '192.168.100.28';
  static const String lanBackupHostIp = '192.168.1.15'; 
  static const String officeHostIp = '10.33.63.155';
  //static const String officeBackupHostIp = '10.34.38.236'; 
  static const String officeBackupHostIp = '192.168.100.28'; 
  static const String localhostIp = 'localhost';

  static const int apiPort = 8081;
  static const int timeoutSeconds = 10;

  static const String hostIp = kIsWeb ? localhostIp : officeBackupHostIp;
  static const String baseUrl = 'http://$hostIp:$apiPort/api';
  static const String fileBaseUrl = 'http://$hostIp:$apiPort';

  static const Map<String, String> _wifiHostOverrides = {
    'WifiNha': lanHostIp,
    'WifiNha2': lanBackupHostIp,
    'WifiCongTy': officeHostIp,
    'WifiCongTyMoi': officeBackupHostIp,
  };

  static const Map<String, String> _localIpPrefixOverrides = {
    '192.168.100.': lanHostIp,
    '192.168.1.': lanBackupHostIp,
    '10.33.': officeHostIp,
    '10.189.': officeBackupHostIp,
  };

  static String _activeHostIp = hostIp;
  static String _activeBaseUrl = baseUrl;
  static String _activeFileBaseUrl = fileBaseUrl;

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
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));

    final authDio = Dio(BaseOptions(
      baseUrl: _activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
    ));

    final authService = AuthService(authDio, storage);

    print('🌐 ApiClient → Using $_activeBaseUrl');
    return ApiClient._(dio, storage, authService);
  }
  static Future<void> _initializeDynamicHost() async {
    if (kIsWeb) {
      _setActiveHost(localhostIp);
    } else {
      try {
        final info = NetworkInfo();
        final wifiName = _normalizeWifiName(await info.getWifiName());
        final wifiIP = await info.getWifiIP();

        print('📶 Connected Wi-Fi: $wifiName | Device IP: $wifiIP');

        final overrideIp = _resolveIpForWifi(wifiName);
        _setActiveHost(
          overrideIp ?? _resolveIpByLocalAddress(wifiIP) ?? hostIp,
        );
      } catch (e) {
        print('⚠️ Network detect failed: $e');
        _setActiveHost(officeHostIp);
      }
    }

    _isInitialized = true;
  }

  static void _setActiveHost(String hostIp) {
    _activeHostIp = hostIp;
    _activeBaseUrl = 'http://$hostIp:$apiPort/api';
    _activeFileBaseUrl = 'http://$hostIp:$apiPort';
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
            // Only auto-logout if no refresh token or already refreshing
            // This prevents logout during payment callback when token might be temporarily expired
            if (refreshToken == null) {
              print('⚠️ No refresh token available. User will need to login again.');
              await _storage.deleteAll();
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
            // Don't auto-logout immediately on refresh failure
            // Token might be temporarily expired during payment callback
            // User can continue using app, and will be logged out naturally on next critical request
            print('⚠️ REFRESH FAILED: ${e.message}');
            print('⚠️ User session may be expired. Will retry on next request.');
            // Don't delete tokens immediately - allow user to continue
            // Tokens will be cleared naturally if refresh continues to fail
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

  static String fileUrl(String path) {
    if (path.startsWith('http')) {
      // Nếu URL chứa localhost, thay thế bằng IP đúng
      final url = path;
      if (url.contains('localhost') || url.contains('127.0.0.1')) {
        // Extract port và path từ URL gốc
        final uri = Uri.tryParse(url);
        if (uri != null) {
          // Lấy port từ URL gốc hoặc dùng port mặc định
          final port = uri.port != 0 ? uri.port : apiPort;
          final host = _activeHostIp;
          // Giữ nguyên scheme (http/https)
          final scheme = uri.scheme;
          // Rebuild URL với IP đúng
          return Uri(
            scheme: scheme,
            host: host,
            port: port,
            path: uri.path,
            query: uri.query,
          ).toString();
        }
      }
      return path;
    }
    return '$_activeFileBaseUrl$path';
  }
}


