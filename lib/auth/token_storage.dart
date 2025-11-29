import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static final _storage = FlutterSecureStorage();

  Future<void> writeAccessToken(dynamic token) async =>
      _storage.write(key: 'accessToken', value: token?.toString());

  Future<void> writeRefreshToken(dynamic token) async =>
      _storage.write(key: 'refreshToken', value: token?.toString());

  Future<void> writeDeviceId(dynamic id) async =>
      _storage.write(key: 'deviceId', value: id?.toString());

  Future<void> writeResidentId(dynamic id) async =>
      _storage.write(key: 'residentId', value: id?.toString());

  Future<void> writeBuildingId(dynamic id) async =>
      _storage.write(key: 'buildingId', value: id?.toString());

  Future<void> writeRole(dynamic role) async =>
      _storage.write(key: 'role', value: role?.toString());

  Future<void> writeUsername(String? username) async =>
      _storage.write(key: 'username', value: username);

  Future<String?> readAccessToken() async => _storage.read(key: 'accessToken');

  Future<String?> readRefreshToken() async =>
      _storage.read(key: 'refreshToken');

  Future<String?> readDeviceId() async => _storage.read(key: 'deviceId');
  Future<String?> readResidentId() async => _storage.read(key: 'residentId');
  Future<String?> readBuildingId() async => _storage.read(key: 'buildingId');
  Future<String?> readRole() async => _storage.read(key: 'role');
  Future<String?> readUsername() async => _storage.read(key: 'username');

  Future<void> writeBiometricCredentials({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: 'biometricUsername', value: username);
    await _storage.write(key: 'biometricPassword', value: password);
  }

  Future<void> writeBiometricEnabled(bool enabled) async =>
      _storage.write(key: 'biometricEnabled', value: enabled.toString());

  Future<String?> readBiometricUsername() async =>
      _storage.read(key: 'biometricUsername');

  Future<String?> readBiometricPassword() async =>
      _storage.read(key: 'biometricPassword');

  Future<bool> readBiometricEnabled() async {
    final value = await _storage.read(key: 'biometricEnabled');
    return value == 'true';
  }

  Future<void> clearBiometricCredentials() async {
    await _storage.delete(key: 'biometricUsername');
    await _storage.delete(key: 'biometricPassword');
  }

  // Fingerprint-specific methods
  Future<void> writeFingerprintEnabled(bool enabled) async =>
      _storage.write(key: 'fingerprintEnabled', value: enabled.toString());

  Future<bool> readFingerprintEnabled() async {
    final value = await _storage.read(key: 'fingerprintEnabled');
    return value == 'true';
  }

  // Face-specific methods removed per requirement

  // Clear both fingerprint and face settings
  Future<void> clearAllBiometricSettings() async {
    await _storage.delete(key: 'biometricUsername');
    await _storage.delete(key: 'biometricPassword');
    await _storage.delete(key: 'biometricEnabled');
    await _storage.delete(key: 'fingerprintEnabled');
    await _storage.delete(key: 'faceEnabled');
  }

  /// Delete all data including biometric credentials
  Future<void> deleteAll() async => _storage.deleteAll();

  /// Delete only session data (tokens, user info) but keep biometric credentials
  /// This allows fingerprint to remain enabled after logout or token expiration
  Future<void> deleteSessionData() async {
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'refreshToken');
    await _storage.delete(key: 'deviceId');
    await _storage.delete(key: 'residentId');
    await _storage.delete(key: 'buildingId');
    await _storage.delete(key: 'role');
    await _storage.delete(key: 'username');
    // Note: biometricUsername, biometricPassword, biometricEnabled, 
    // fingerprintEnabled are NOT deleted here - they persist across sessions
  }
}
