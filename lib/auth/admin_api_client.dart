import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

import 'api_client.dart';
import 'auth_service.dart';
import 'backend_discovery_service.dart';
import 'token_storage.dart';

class AdminApiClient {
  static const int apiPort = 8086;
  static const int timeoutSeconds = 10;

  /// Check if hostname is an ngrok URL
  static bool _isNgrokUrl(String hostname) {
    return hostname.contains('ngrok-free.dev') ||
           hostname.contains('ngrok-free.app') ||
           hostname.contains('ngrok.io') ||
           hostname.contains('ngrok.app');
  }

  // Note: buildServiceBase() already includes /api in the base URL
  static String get baseUrl =>
      ApiClient.buildServiceBase();

  static Dio createPublicDio() {
    assert(
      ApiClient.isInitialized || kIsWeb,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    
    // Add ngrok-skip-browser-warning header if using ngrok URL
    final headers = <String, dynamic>{};
    try {
      final activeHostIp = ApiClient.activeHostIp;
      if (_isNgrokUrl(activeHostIp)) {
        headers['ngrok-skip-browser-warning'] = '1';
        headers['User-Agent'] = 'QHome-Resident-App/1.0';
        print('✅ [AdminApiClient] Added ngrok-skip-browser-warning=1 and User-Agent to BaseOptions for: $activeHostIp');
      }
    } catch (e) {
      // ApiClient might not be initialized yet, will add in interceptor
    }
    
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));
    
    // Add authentication interceptor FIRST (before LogInterceptor) so headers are added before logging
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.readAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
          print('🔍 [AdminApiClient] Added Authorization header');
        } else {
          print('⚠️ [AdminApiClient] No access token found in storage');
        }
        final deviceId = await storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        final host = uri.host.isNotEmpty ? uri.host : (baseUrl.contains('://') ? Uri.parse(baseUrl).host : '');
        final fullUrl = uri.toString();
        if (_isNgrokUrl(host) || _isNgrokUrl(baseUrl) || _isNgrokUrl(fullUrl)) {
          // Use '1' as value (some ngrok versions prefer this over 'true')
          options.headers['ngrok-skip-browser-warning'] = '1';
          // Also add User-Agent to help ngrok identify this as an app request
          options.headers['User-Agent'] = 'QHome-Resident-App/1.0';
          print('✅ [AdminApiClient] Added ngrok-skip-browser-warning=1 and User-Agent headers for: $host (URL: $fullUrl)');
        }
        
        return handler.next(options);
      },
    ));
    
    // Add LogInterceptor AFTER authentication interceptor so it logs the headers
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 ADMIN PUBLIC API LOG: $obj'),
    ));
    
    return dio;
  }

  final Dio dio;
  final TokenStorage _storage;
  final AuthService _authService;
  bool isRefreshing = false;

  AdminApiClient._(this.dio, this._storage, this._authService) {
    _setupInterceptors();
  }

  factory AdminApiClient() {
    assert(
      ApiClient.isInitialized || kIsWeb,
      'ApiClient.ensureInitialized() must be awaited before creating clients.',
    );

    final storage = TokenStorage();
    
    // Add ngrok-skip-browser-warning header if using ngrok URL
    final headers = <String, dynamic>{};
    try {
      final activeHostIp = ApiClient.activeHostIp;
      if (_isNgrokUrl(activeHostIp)) {
        headers['ngrok-skip-browser-warning'] = '1';
        headers['User-Agent'] = 'QHome-Resident-App/1.0';
        print('✅ [AdminApiClient] Added ngrok-skip-browser-warning=1 and User-Agent to BaseOptions for: $activeHostIp');
      }
    } catch (e) {
      // ApiClient might not be initialized yet, will add in interceptor
    }
    
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));
    final authDio = Dio(BaseOptions(
      baseUrl: ApiClient.activeBaseUrl,
      connectTimeout: const Duration(seconds: timeoutSeconds),
      receiveTimeout: const Duration(seconds: timeoutSeconds),
      headers: headers,
    ));
    final authService = AuthService(authDio, storage);
    return AdminApiClient._(dio, storage, authService);
  }

  void _setupInterceptors() {
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 ADMIN API LOG: $obj'),
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.readAccessToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        final deviceId = await _storage.readDeviceId();
        if (deviceId != null) options.headers['X-Device-Id'] = deviceId;
        
        // Add ngrok-skip-browser-warning header for ngrok URLs
        final uri = options.uri;
        final host = uri.host.isNotEmpty ? uri.host : (baseUrl.contains('://') ? Uri.parse(baseUrl).host : '');
        final fullUrl = uri.toString();
        if (_isNgrokUrl(host) || _isNgrokUrl(baseUrl) || _isNgrokUrl(fullUrl)) {
          // Use '1' as value (some ngrok versions prefer this over 'true')
          options.headers['ngrok-skip-browser-warning'] = '1';
          // Also add User-Agent to help ngrok identify this as an app request
          options.headers['User-Agent'] = 'QHome-Resident-App/1.0';
          print('✅ [AdminApiClient] Added ngrok-skip-browser-warning=1 and User-Agent headers for: $host (URL: $fullUrl)');
        }
        
        return handler.next(options);
      },
      onError: (err, handler) async {
        final options = err.requestOptions;
        
        // Handle 403 error from ngrok warning page
        // When ngrok free plan shows warning page, it returns 403 "Access denied"
        // Solution: Fallback to local IP if available (but NOT for VNPay requests)
        if (err.response?.statusCode == 403) {
          final responseData = err.response!.data;
          final isNgrok403 = responseData is Map && 
                             responseData['message'] == 'Access denied' &&
                             (_isNgrokUrl(options.uri.host) || _isNgrokUrl(baseUrl));
          
          // Check if this is a VNPay-related request (need ngrok for callback)
          final requestPath = options.uri.path.toLowerCase();
          final isVnpayRequest = requestPath.contains('vnpay') || 
                                 requestPath.contains('payment') ||
                                 requestPath.contains('callback');
          
          if (isNgrok403 && !kIsWeb && !isVnpayRequest) {
            print('⚠️ Detected ngrok 403 "Access denied" error');
            print('   This is likely ngrok warning page blocking the request');
            print('   Request path: ${options.uri.path}');
            print('   Attempting to fallback to local IP...');
            
            try {
              // Use the discovery service instance from ApiClient (already initialized)
              final discoveryService = ApiClient.discoveryService;
              if (discoveryService == null) {
                print('⚠️ ApiClient not initialized yet, cannot fallback to local IP');
                throw Exception('ApiClient not initialized');
              }
              
              // Clear manual ngrok URL to force discovery to find local IP instead
              print('🗑️ Clearing cached ngrok URL to force local IP discovery...');
              try {
                await discoveryService.clearManualBackendUrl();
                print('✅ Cleared cached ngrok URL');
              } catch (clearErr) {
                print('⚠️ Failed to clear cached ngrok URL: $clearErr');
                // Continue anyway - discovery might still find local IP
              }
              
              // Force re-discovery to find local IP (skip ngrok)
              print('🔍 Re-discovering backend (preferring local IP over ngrok)...');
              
              // Clear cache to force fresh discovery without ngrok
              try {
                await discoveryService.clearCache();
                print('✅ Cleared backend cache to force fresh discovery');
              } catch (clearErr) {
                print('⚠️ Failed to clear cache: $clearErr');
              }
              
              final backendInfo = await discoveryService.discoverBackend();
              
              // Check if we found a local IP (not ngrok)
              final isLocalIp = !backendInfo.hostname.contains('ngrok') && 
                               !backendInfo.hostname.contains('ngrok-free');
              
              if (isLocalIp) {
                print('✅ Found local IP: ${backendInfo.hostname}:${backendInfo.port}');
                print('   Updating ApiClient to use local IP instead of ngrok...');
                
                // Update ApiClient active host
                ApiClient.setActiveHost(backendInfo.hostname, backendInfo.port, backendInfo.isHttps);
                
                // Update base URL for this request
                final newBaseUrl = ApiClient.buildServiceBase();
                options.baseUrl = newBaseUrl;
                
                // Update headers to remove ngrok-specific headers
                options.headers.remove('ngrok-skip-browser-warning');
                
                print('✅ Updated base URL to: $newBaseUrl');
                print('   Retrying request with local IP...');
                
                // Retry the request with local IP
                try {
                  // Re-add auth token if needed
                  final token = await _storage.readAccessToken();
                  if (token != null) {
                    options.headers['Authorization'] = 'Bearer $token';
                  }
                  
                  final clonedResponse = await dio.fetch(options);
                  print('✅ Retry successful after fallback to local IP');
                  return handler.resolve(clonedResponse);
                } catch (retryErr) {
                  print('⚠️ Retry with local IP failed: $retryErr');
                  // Continue to 401 handler or return error
                }
              } else {
                // Re-discovery still returned ngrok URL
                // Try to get cached local IP from discovery service
                print('⚠️ Re-discovery still returned ngrok URL');
                print('   Attempting to use cached local IP if available...');
                
                try {
                  // Try to get cached backend info (might be local IP)
                  final cachedInfo = discoveryService.getCachedBackendInfo();
                  if (cachedInfo != null) {
                    final cachedIsLocalIp = !cachedInfo.hostname.contains('ngrok') && 
                                           !cachedInfo.hostname.contains('ngrok-free');
                    if (cachedIsLocalIp) {
                      print('✅ Found cached local IP: ${cachedInfo.hostname}:${cachedInfo.port}');
                      print('   Using cached local IP instead of ngrok...');
                      
                      // Update ApiClient active host
                      ApiClient.setActiveHost(cachedInfo.hostname, cachedInfo.port, cachedInfo.isHttps);
                      
                      // Update base URL for this request
                      final newBaseUrl = ApiClient.buildServiceBase();
                      options.baseUrl = newBaseUrl;
                      
                      // Update headers to remove ngrok-specific headers
                      options.headers.remove('ngrok-skip-browser-warning');
                      
                      print('✅ Updated base URL to: $newBaseUrl');
                      print('   Retrying request with cached local IP...');
                      
                      // Retry the request with cached local IP
                      try {
                        // Re-add auth token if needed
                        final token = await _storage.readAccessToken();
                        if (token != null) {
                          options.headers['Authorization'] = 'Bearer $token';
                        }
                        
                        final clonedResponse = await dio.fetch(options);
                        print('✅ Retry successful after fallback to cached local IP');
                        return handler.resolve(clonedResponse);
                      } catch (retryErr) {
                        print('⚠️ Retry with cached local IP failed: $retryErr');
                      }
                    }
                  }
                } catch (cacheErr) {
                  print('⚠️ Failed to get cached backend info: $cacheErr');
                }
                
                print('⚠️ Cannot fallback to local IP');
                print('   Solution: Access ngrok URL in browser first to unlock warning page');
                print('   Or use local IP by connecting both devices to same WiFi/hotspot');
              }
            } catch (fallbackErr) {
              print('⚠️ Failed to fallback to local IP: $fallbackErr');
              print('   Solution: Access ngrok URL in browser first to unlock warning page');
            }
          } else if (isNgrok403 && isVnpayRequest) {
            // VNPay requests need ngrok URL for callback - don't fallback
            print('⚠️ Detected ngrok 403 "Access denied" error for VNPay request');
            print('   VNPay requires ngrok URL for callback - cannot fallback to local IP');
            print('   Solution: Access ngrok URL in browser first to unlock warning page');
            print('   URL: ${_isNgrokUrl(baseUrl) ? baseUrl : options.uri.toString()}');
            print('   After unlocking, VNPay callbacks will work correctly');
          }
        }
        
        if (err.response?.statusCode == 401) {
          final refreshToken = await _storage.readRefreshToken();
          if (refreshToken == null || isRefreshing) return handler.next(err);
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

  String fileUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    // Note: buildServiceBase() already includes /api in the base URL
    return '${ApiClient.buildServiceBase()}$path';
  }
}

