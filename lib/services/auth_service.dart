import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  //final String baseUrl = 'http://192.168.100.46:8080/api/auth';
  final String baseUrl = 'http://localhost:8080/api/auth';

  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body); // Trả về thông tin user
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  Future<String?> logout() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return null; // Đăng xuất thành công
      } else {
        return response.body; // Trả về lỗi từ server
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  Future<String?> resetPassword(String email, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'newPassword': newPassword}),
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        return response.body;
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

  Future<String?> requestOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/request-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        return null; // thành công
      } else {
        return response.body;
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  Future<String?> confirmReset(String email, String otp, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/confirm-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp, 'newPassword': newPassword}),
      );

      if (response.statusCode == 200) {
        return null; // thành công
      } else {
        return response.body;
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  Future<String?> verifyOtp(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        return response.body;
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  
}
