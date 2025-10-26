import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'token_storage.dart';

class AuthService {
  final Dio dio;
  final TokenStorage storage;

  AuthService(this.dio, this.storage);

  Future<void> ensureDeviceId() async {
    final d = await storage.readDeviceId();
    if (d == null) {
      final id = const Uuid().v4();
      await storage.writeDeviceId(id);
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    await ensureDeviceId();
    final deviceId = await storage.readDeviceId();

    final res = await dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: Options(headers: {'X-Device-Id': deviceId}),
    );

    final data = Map<String, dynamic>.from(res.data);

    // Ép kiểu tất cả giá trị quan trọng thành String để an toàn
    if (data['accessToken'] != null) {
      await storage.writeAccessToken(data['accessToken'].toString());
      await storage.writeRefreshToken(data['refreshToken']?.toString());
    }

    // ⚠️ Ép userId về String để tránh lỗi “int is not a subtype of String”
    if (data['userId'] != null) {
      data['userId'] = data['userId'].toString();
    }

    return data;
  }

  Future<void> refreshToken() async {
    await ensureDeviceId();
    final deviceId = await storage.readDeviceId();
    final refresh = await storage.readRefreshToken();
    if (refresh == null) throw Exception('No refresh token');
    final res = await dio.post('/auth/refresh-token',
        data: {'refreshToken': refresh},
        options: Options(headers: {'X-Device-Id': deviceId}));
    final data = Map<String, dynamic>.from(res.data);
    if (data['accessToken'] != null) {
      await storage.writeAccessToken(data['accessToken'].toString());
      await storage.writeRefreshToken(data['refreshToken']?.toString());
    } else {
      throw Exception('Refresh failed');
    }
  }

  Future<void> logout() async {
    await ensureDeviceId();
    final deviceId = await storage.readDeviceId();
    final accessToken = await storage.readAccessToken();

    try {
      await dio.post(
        '/auth/logout',
        options: Options(
          headers: {
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            if (deviceId != null) 'X-Device-Id': deviceId,
          },
        ),
      );
    } catch (e) {
      print('Logout failed: $e');
    } finally {
      await storage.deleteAll();
    }
  }

  Future<void> requestReset(String email) async {
    await dio.post('/auth/request-reset', data: {'email': email});
  }

  Future<void> verifyOtp(String email, String otp) async {
    await dio.post('/auth/verify-otp', data: {'email': email, 'otp': otp});
  }

  Future<void> confirmReset(
      String email, String otp, String newPassword) async {
    await dio.post('/auth/confirm-reset',
        data: {'email': email, 'otp': otp, 'newPassword': newPassword});
  }
}
