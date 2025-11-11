import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../contracts/contract_service.dart';
import '../core/push_notification_service.dart';
import '../login/login_screen.dart';
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
  } finally {
    await PushNotificationService.instance.unregisterToken();
    await storage.deleteAll();
    _isAuthenticated = false;
    notifyListeners();

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
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
