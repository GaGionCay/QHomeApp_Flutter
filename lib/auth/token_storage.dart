import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _storage = const FlutterSecureStorage();

  Future<void> writeAccessToken(String token) async =>
      _storage.write(key: 'accessToken', value: token);

  Future<void> writeRefreshToken(String token) async =>
      _storage.write(key: 'refreshToken', value: token);

  Future<String?> readAccessToken() async => _storage.read(key: 'accessToken');
  Future<String?> readRefreshToken() async => _storage.read(key: 'refreshToken');

  Future<void> writeDeviceId(String id) async =>
      _storage.write(key: 'deviceId', value: id);
  Future<String?> readDeviceId() async => _storage.read(key: 'deviceId');

  Future<void> deleteAll() async => _storage.deleteAll();
}
