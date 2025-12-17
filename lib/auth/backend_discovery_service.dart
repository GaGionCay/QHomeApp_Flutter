import 'package:flutter/foundation.dart' show kDebugMode;

import '../core/app_config.dart';

/// Simple backend info for DEV LOCAL mode
/// No discovery - uses fixed baseUrl from AppConfig
class BackendInfo {
  final String hostname;
  final int port;
  final bool isHttps;
  final String discoveryMethod;

  BackendInfo({
    required this.hostname,
    required this.port,
    this.isHttps = false,
    this.discoveryMethod = 'fixed',
  });
  }

/// Simplified backend discovery service for DEV LOCAL mode
/// No auto-discovery, no network scanning, no health check switching
/// Uses fixed baseUrl from AppConfig
class BackendDiscoveryService {
  static BackendDiscoveryService? _instance;
  
  static BackendDiscoveryService get instance {
    _instance ??= BackendDiscoveryService._();
    return _instance!;
      }
  
  BackendDiscoveryService._();

  /// Initialize (no-op in DEV LOCAL mode)
  Future<void> initialize() async {
    if (kDebugMode) {
      print('✅ [BackendDiscoveryService] Initialized (DEV LOCAL mode - fixed baseUrl)');
          }
  }

  /// Get fixed backend info from AppConfig
  /// No discovery - just returns fixed configuration
  Future<BackendInfo> discoverBackend({
    String? manualHostname,
    int? manualPort,
    String? manualUrl,
  }) async {
    // Parse AppConfig.apiBaseUrl to extract hostname and port
    final baseUrl = AppConfig.apiBaseUrl;
    final uri = Uri.parse(baseUrl);
    
    final hostname = uri.host.isEmpty ? '127.0.0.1' : uri.host;
    final port = uri.port == 0 ? 8989 : uri.port;
    final isHttps = uri.scheme == 'https';
    
        if (kDebugMode) {
      print('✅ [BackendDiscoveryService] Using fixed baseUrl: $baseUrl');
      print('   Hostname: $hostname, Port: $port, HTTPS: $isHttps');
    }
    
        return BackendInfo(
          hostname: hostname,
          port: port,
      isHttps: isHttps,
      discoveryMethod: 'fixed',
    );
      }
      
  /// Get cached backend info (returns fixed info in DEV LOCAL mode)
  BackendInfo? getCachedBackendInfo() {
    final baseUrl = AppConfig.apiBaseUrl;
    final uri = Uri.parse(baseUrl);
    
        return BackendInfo(
      hostname: uri.host.isEmpty ? '127.0.0.1' : uri.host,
      port: uri.port == 0 ? 8989 : uri.port,
      isHttps: uri.scheme == 'https',
      discoveryMethod: 'fixed',
    );
  }

  /// Clear cache (no-op in DEV LOCAL mode)
  Future<void> clearCache() async {
      if (kDebugMode) {
      print('ℹ️ [BackendDiscoveryService] clearCache() called (no-op in DEV LOCAL mode)');
    }
  }

  /// Set manual backend URL (no-op in DEV LOCAL mode)
  Future<bool> setManualBackendUrl(String url) async {
        if (kDebugMode) {
      print('ℹ️ [BackendDiscoveryService] setManualBackendUrl() called (no-op in DEV LOCAL mode)');
      print('   Fixed baseUrl from AppConfig is used instead: ${AppConfig.apiBaseUrl}');
        }
        return false;
      }

  /// Clear manual backend URL (no-op in DEV LOCAL mode)
  Future<void> clearManualBackendUrl() async {
      if (kDebugMode) {
      print('ℹ️ [BackendDiscoveryService] clearManualBackendUrl() called (no-op in DEV LOCAL mode)');
    }
  }

  /// Start network change listener (no-op in DEV LOCAL mode)
  void startNetworkChangeListener(Future<void> Function() callback) {
      if (kDebugMode) {
      print('ℹ️ [BackendDiscoveryService] startNetworkChangeListener() called (no-op in DEV LOCAL mode)');
          }
        }
        
  /// Stop network change listener (no-op in DEV LOCAL mode)
  void stopNetworkChangeListener() {
    if (kDebugMode) {
      print('ℹ️ [BackendDiscoveryService] stopNetworkChangeListener() called (no-op in DEV LOCAL mode)');
    }
    }
  }
