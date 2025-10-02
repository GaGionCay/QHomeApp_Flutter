import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final String baseUrl = 'http://localhost:8080/api/auth';

  /// Đăng nhập
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'id': data['id'],
          'email': data['email'],
          'token': data['token'],
        };
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Đăng xuất
  Future<String?> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        return 'Đăng xuất thất bại';
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  /// Lấy dịch vụ user
  Future<List<Map<String, dynamic>>> getUserServices(int userId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
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

  /// Yêu cầu OTP
  Future<String?> requestOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/request-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      return "Nếu email hợp lệ, OTP đã được gửi";
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  /// Đổi mật khẩu bằng OTP
  Future<String?> confirmReset(String email, String otp, String newPassword) async {
    try {
      // Kiểm tra password policy trước khi gửi lên backend
      final error = validatePassword(newPassword);
      if (error != null) {
        return error; // Ngắt sớm nếu password không đạt policy
      }

      final response = await http.post(
        Uri.parse('$baseUrl/confirm-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        return 'OTP không hợp lệ hoặc mật khẩu không đạt yêu cầu';
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  /// Verify OTP
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
        return 'OTP không hợp lệ hoặc đã hết hạn';
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  /// ✅ Helper: validate password policy
  /// - ≥8 ký tự
  /// - có chữ hoa
  /// - có chữ thường
  /// - có số
  /// - có ký tự đặc biệt
  String? validatePassword(String password) {
    if (password.length < 8) {
      return "Mật khẩu phải có ít nhất 8 ký tự";
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return "Mật khẩu phải chứa ít nhất 1 chữ hoa";
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return "Mật khẩu phải chứa ít nhất 1 chữ thường";
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return "Mật khẩu phải chứa ít nhất 1 số";
    }
    if (!RegExp(r'[!@#\$&*~%^&*(),.?":{}|<>]').hasMatch(password)) {
      return "Mật khẩu phải chứa ít nhất 1 ký tự đặc biệt";
    }
    return null; // hợp lệ
  }
}
