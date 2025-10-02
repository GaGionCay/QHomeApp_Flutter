import 'dart:convert';
import 'package:http/http.dart' as http;

class RegisterService {
  final String baseUrl = 'http://192.168.100.46:8080/api/services';

  /// Đăng ký dịch vụ mới
  Future<String?> registerService({
    required int id,
    required String email,
    required String serviceType,
    required String details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': id.toString(),
          'email': email,
          'serviceType': serviceType,
          'details': details,
        }),
      );

      if (response.statusCode == 200) {
        return null; // Thành công
      } else {
        return response.body; // Trả về lỗi từ server
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  /// Lấy danh sách dịch vụ đã đăng ký của user
  Future<List<Map<String, dynamic>>> getUserServices(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Lỗi: ${response.body}');
      }
    } catch (e) {
      throw Exception('Lỗi kết nối: $e');
    }
  }
}