import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final _storage = const FlutterSecureStorage();

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

  Future<String?> readAccessToken() async => _storage.read(key: 'accessToken');

  Future<String?> readRefreshToken() async =>
      _storage.read(key: 'refreshToken');

  Future<String?> readDeviceId() async => _storage.read(key: 'deviceId');
  Future<String?> readResidentId() async => _storage.read(key: 'residentId');
  Future<String?> readBuildingId() async => _storage.read(key: 'buildingId');
  Future<String?> readRole() async => _storage.read(key: 'role');

  Future<void> deleteAll() async => _storage.deleteAll();
}
