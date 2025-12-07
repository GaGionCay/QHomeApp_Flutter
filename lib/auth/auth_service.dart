import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'token_storage.dart';
import 'iam_api_client.dart';

class AuthService {
  final Dio dio;
  final TokenStorage storage;
  final Dio? iamDio;

  AuthService(this.dio, this.storage, {this.iamDio});

  Dio _iamClient() => iamDio ?? IamApiClient.createPublicDio();

  Future<void> ensureDeviceId() async {
    final d = await storage.readDeviceId();
    if (d == null) {
      final id = Uuid().v4();
      await storage.writeDeviceId(id);
    }
  }

  Future<Map<String, dynamic>> loginViaIam(String username, String password) async {
    final iamClient = _iamClient();
    final res = await iamClient.post('/auth/login', data: {'username': username, 'password': password});
    final data = Map<String, dynamic>.from(res.data);
    if (data['accessToken'] != null) await storage.writeAccessToken(data['accessToken'].toString());
    if (data['userInfo'] is Map<String, dynamic>) {
      final userInfo = Map<String, dynamic>.from(data['userInfo']);
      await storage.writeUsername(userInfo['username']?.toString() ?? username);
    } else if (data['username'] != null) {
      await storage.writeUsername(data['username']?.toString());
    } else {
      await storage.writeUsername(username);
    }
    if (data['userInfo'] != null) {
      final userInfo = Map<String, dynamic>.from(data['userInfo']);
      data['userId'] = userInfo['userId']?.toString();
      data['username'] = userInfo['username'];
      data['email'] = userInfo['email'];
      data['roles'] = userInfo['roles'];
      data['permissions'] = userInfo['permissions'];
    }
    return data;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    await ensureDeviceId();
    final deviceId = await storage.readDeviceId();
    final res = await dio.post('/auth/login', data: {'email': email, 'password': password},
        options: Options(headers: {'X-Device-Id': deviceId}));
    final data = Map<String, dynamic>.from(res.data);
    await storage.writeUsername(email);
    if (data['accessToken'] != null) {
      await storage.writeAccessToken(data['accessToken'].toString());
      await storage.writeRefreshToken(data['refreshToken']?.toString());
    }
    if (data['userId'] != null) data['userId'] = data['userId'].toString();
    return data;
  }

  Future<void> refreshToken() async {
    await ensureDeviceId();
    final deviceId = await storage.readDeviceId();
    final refresh = await storage.readRefreshToken();
    if (refresh == null) throw Exception('No refresh token');
    final res = await dio.post('/auth/refresh-token',
        data: {'refreshToken': refresh}, options: Options(headers: {'X-Device-Id': deviceId}));
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
      await dio.post('/auth/logout',
          options: Options(headers: {
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            if (deviceId != null) 'X-Device-Id': deviceId,
          }));
    } catch (e) {
      print('Logout failed: $e');
    } finally {
      // Only delete session data, keep fingerprint credentials
      await storage.deleteSessionData();
    }
  }

  Future<void> requestReset(String email) async {
    final client = _iamClient();
    try {
      await client.post('/auth/request-reset', data: {'email': email});
    } on DioException catch (e) {
      // Extract error message from response
      String errorMessage = 'Yêu cầu thất bại';
      
      if (e.response != null && e.response!.data != null) {
        final responseData = e.response!.data;
        
        // Handle Map response (most common case)
        if (responseData is Map) {
          final dataMap = Map<String, dynamic>.from(responseData);
          errorMessage = dataMap['message']?.toString() ?? errorMessage;
        } 
        // Handle String response
        else if (responseData is String) {
          errorMessage = responseData;
        }
      } else if (e.message != null) {
        errorMessage = e.message!;
      }
      
      throw Exception(errorMessage);
    }
  }

  Future<void> verifyOtp(String email, String otp) async {
    final client = _iamClient();
    await client.post('/auth/verify-otp', data: {'email': email, 'otp': otp});
  }

  Future<void> confirmReset(String email, String otp, String newPassword) async {
    final client = _iamClient();
    await client.post('/auth/confirm-reset',
        data: {'email': email, 'otp': otp, 'newPassword': newPassword});
  }
}

