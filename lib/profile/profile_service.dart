import 'dart:io';
import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../services/imagekit_service.dart';

class ProfileService {
  final Dio dio;
  final ImageKitService _imageKitService;

  ProfileService(this.dio) : _imageKitService = ImageKitService(ApiClient());

  Future<Map<String, dynamic>> getProfile() async {
    final res = await dio.get('/users/me');
    final data = Map<String, dynamic>.from(res.data);

    // ✅ Ép kiểu id sang String để tránh lỗi type
    if (data['id'] != null) {
      data['id'] = data['id'].toString();
    }

    if (data['avatarUrl'] != null &&
        !data['avatarUrl'].toString().startsWith('http')) {
      data['avatarUrl'] =
          ApiClient.activeFileBaseUrl + data['avatarUrl'];
    }
    return data;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await dio.put('/users/me', data: data);
    final updated = Map<String, dynamic>.from(res.data);

    if (updated['avatarUrl'] != null &&
        !updated['avatarUrl'].toString().startsWith('http')) {
      updated['avatarUrl'] =
          ApiClient.activeFileBaseUrl + updated['avatarUrl'];
    }
    return updated;
  }

  Future<String> uploadAvatar(String filePath) async {
    try {
      // Upload to ImageKit first
      final file = File(filePath);
      final imageUrl = await _imageKitService.uploadImage(
        file: file,
        folder: 'profile/avatars',
      );

      // Then update profile with ImageKit URL
      final res = await dio.put(
        '/users/me',
        data: {'avatarUrl': imageUrl},
      );

      String avatarUrl = res.data['avatarUrl'] ?? imageUrl;
      return avatarUrl;
    } on DioException catch (e) {
      print('DioError: ${e.response?.statusCode}');
      print('DioError data: ${e.response?.data}');
      print('DioError message: ${e.message}');
      rethrow;
    } catch (e) {
      print('Unexpected error: $e');
      rethrow;
    }
  }
}
