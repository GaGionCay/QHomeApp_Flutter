import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../contracts/contract_service.dart';
import '../core/app_router.dart';
import '../core/push_notification_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'iam_api_client.dart';
import 'token_storage.dart';

class AuthProvider extends ChangeNotifier {
  late final ApiClient apiClient;
  late final AuthService authService;
  final TokenStorage storage = TokenStorage();

  bool _isAuthenticated = false;
  bool _isLoading = true;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    apiClient = await ApiClient.create();
    // Tạo iamDio instance để login qua iam-service
    final iamDio = await _createIamDio();
    authService = AuthService(apiClient.dio, storage, iamDio: iamDio);

    final token = await storage.readAccessToken();

    if (token != null) {
      if (!JwtDecoder.isExpired(token)) {
        _isAuthenticated = true;
      } else {
        try {
          await authService.refreshToken();
          _isAuthenticated = true;
        } catch (_) {
          await storage.deleteAll();
          _isAuthenticated = false;
        }
      }
    } else {
      _isAuthenticated = false;
    }

    if (_isAuthenticated) {
      await _syncPushContext();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Login via iam-service (port 8088) - NEW METHOD
  /// Uses username instead of email
  Future<bool> loginViaIam(String username, String password) async {
    try {
      await authService.loginViaIam(username, password);
      _isAuthenticated = true;
      await _syncPushContext();
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ Login via IAM failed: $e');
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

  // Legacy methods (for backward compatibility)
  Future<void> enableBiometricLogin(String username, String password) async {
    await storage.writeBiometricCredentials(
      username: username,
      password: password,
    );
    await storage.writeBiometricEnabled(true);
  }

  Future<void> disableBiometricLogin() async {
    await storage.clearBiometricCredentials();
    await storage.writeBiometricEnabled(false);
  }

  Future<bool> isBiometricLoginEnabled() => storage.readBiometricEnabled();

  Future<({String username, String password})?> getBiometricCredentials() async {
    // Check if any biometric is enabled (fingerprint or legacy)
    final fingerprintEnabled = await storage.readFingerprintEnabled();
    final legacyEnabled = await storage.readBiometricEnabled();

    if (!fingerprintEnabled && !legacyEnabled) return null;
    
    final username = await storage.readBiometricUsername();
    final password = await storage.readBiometricPassword();
    if (username == null || password == null) {
      return null;
    }
    return (username: username, password: password);
  }

  Future<bool> tryBiometricLogin() async {
    final credentials = await getBiometricCredentials();
    if (credentials == null) return false;
    return loginViaIam(credentials.username, credentials.password);
  }

  // Fingerprint-specific methods
  Future<void> enableFingerprintLogin(String username, String password) async {
    // Store credentials (shared between fingerprint and face)
    await storage.writeBiometricCredentials(
      username: username,
      password: password,
    );
    await storage.writeFingerprintEnabled(true);
  }

  Future<void> disableFingerprintLogin() async {
    await storage.writeFingerprintEnabled(false);
    await storage.clearBiometricCredentials();
  }

  Future<bool> isFingerprintLoginEnabled() => storage.readFingerprintEnabled();

  // Face-specific methods removed per requirement

  Future<String?> getStoredUsername() => storage.readUsername();

  Future<bool> reauthenticateForBiometrics(String password) async {
    final username = await storage.readUsername();
    if (username == null) return false;
    try {
      await authService.loginViaIam(username, password);
      _isAuthenticated = true;
      await _syncPushContext();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Login via backend hiện tại (port 8080) - KEEP FOR BACKWARD COMPATIBILITY
  Future<bool> login(String email, String password) async {
    try {
      await authService.login(email, password);
      _isAuthenticated = true;
      await _syncPushContext();
      notifyListeners();
      return true;
    } catch (e) {
      _isAuthenticated = false;
      notifyListeners();
      return false;
    }
  }

Future<void> logout(BuildContext context) async {
  try {
    await authService.logout();
  } catch (e) {
    debugPrint('⚠️ Logout API error: $e');
  } finally {
    try {
      await PushNotificationService.instance.unregisterToken();
    } catch (e) {
      debugPrint('⚠️ Unregister token error: $e');
    }
    
    await storage.deleteAll();
    _isAuthenticated = false;
    notifyListeners();

    if (context.mounted) {
      // Use go_router to navigate to login screen
      context.go(AppRoute.login.path);
    }
  }
}

  Future<void> _syncPushContext() async {
    try {
      final profileService = ProfileService(apiClient.dio);
      final profile = await profileService.getProfile();

      final residentId =
          profile['residentId']?.toString() ?? profile['id']?.toString();
      await storage.writeResidentId(residentId);

      final roles = profile['roles'];
      if (roles is List && roles.isNotEmpty) {
        final primaryRole = roles.first?.toString();
        await storage.writeRole(primaryRole);
      } else {
        await storage.writeRole(null);
      }

      final contractService = ContractService(apiClient);
      final units = await contractService.getMyUnits();
      String? buildingId;
      if (units.isNotEmpty) {
        UnitInfo primaryUnit = units.first;
        if (residentId != null && residentId.isNotEmpty) {
          for (final unit in units) {
            if (unit.isPrimaryResident(residentId)) {
              primaryUnit = unit;
              break;
            }
          }
        }
        buildingId = primaryUnit.buildingId;
      }
      await storage.writeBuildingId(buildingId);

      await PushNotificationService.instance.refreshRegistration();
    } catch (e) {
      debugPrint('⚠️ Unable to sync push context: $e');
    }
  }

  Future<void> requestReset(String email) => authService.requestReset(email);
  Future<void> verifyOtp(String email, String otp) => authService.verifyOtp(email, otp);
  Future<void> confirmReset(String email, String otp, String newPassword) =>
      authService.confirmReset(email, otp, newPassword);

  Future<Dio> _createIamDio() async {
    return IamApiClient.createPublicDio();
  }
}
