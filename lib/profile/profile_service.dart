import 'package:dio/dio.dart';
import '../auth/api_client.dart';

class ProfileService {
  final Dio dio;

  ProfileService(this.dio);

  Future<Map<String, dynamic>> getProfile() async {
    final res = await dio.get('/users/me');
    final data = Map<String, dynamic>.from(res.data);

    if (data['avatarUrl'] != null && !data['avatarUrl'].toString().startsWith('http')) {
      data['avatarUrl'] = ApiClient.BASE_URL.replaceFirst('/api', '') + data['avatarUrl'];
    }
    return data;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await dio.put('/users/me', data: data);
    final updated = Map<String, dynamic>.from(res.data);

    if (updated['avatarUrl'] != null && !updated['avatarUrl'].toString().startsWith('http')) {
      updated['avatarUrl'] = ApiClient.BASE_URL.replaceFirst('/api', '') + updated['avatarUrl'];
    }
    return updated;
  }

  Future<String> uploadAvatar(String filePath) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: 'avatar.jpg'),
    });
    final res = await dio.post('/users/me/avatar', data: formData);

    String avatarUrl = res.data['avatarUrl'];
    if (!avatarUrl.startsWith('http')) {
      avatarUrl = ApiClient.BASE_URL.replaceFirst('/api', '') + avatarUrl;
    }
    return avatarUrl;
  }
  
}
