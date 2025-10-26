import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _storage = const FlutterSecureStorage();

  Future<void> writeAccessToken(dynamic token) async =>
      _storage.write(key: 'accessToken', value: token?.toString());

  Future<void> writeRefreshToken(dynamic token) async =>
      _storage.write(key: 'refreshToken', value: token?.toString());

  Future<void> writeDeviceId(dynamic id) async =>
      _storage.write(key: 'deviceId', value: id?.toString());

  Future<String?> readAccessToken() async => _storage.read(key: 'accessToken');

  Future<String?> readRefreshToken() async =>
      _storage.read(key: 'refreshToken');

  Future<String?> readDeviceId() async => _storage.read(key: 'deviceId');

  Future<void> deleteAll() async => _storage.deleteAll();
}
