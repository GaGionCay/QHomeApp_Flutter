import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
	// Hãy thay đổi 'http://localhost:8080' bằng địa chỉ IP của máy chủ Spring Boot (nếu đang chạy trên thiết bị vật lý hoặc emulator)
	final String baseUrl = 'http://localhost:8080/api/auth';

	/// Đăng nhập (Authentication)
	/// Trả về Map chứa user data (thành công) hoặc Map chứa 'error' message (thất bại).
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
					'id': data['id'] as int,
					'email': data['email'] as String,
					'token': data['token'] as String,
					'name': data['name'] as String?,
				};
			} else {
				// Xử lý thông báo lỗi cụ thể từ Backend
				String errorMessage = "Đăng nhập thất bại.";
				try {
					final errorData = jsonDecode(response.body);
					// Ưu tiên sử dụng thông báo lỗi chi tiết từ backend
					errorMessage = errorData['message'] ?? errorMessage; 
				} catch (_) {
					// Nếu không phải JSON, dựa vào status code
					if (response.statusCode == 401) {
						errorMessage = "Email hoặc mật khẩu không chính xác.";
					} else if (response.statusCode == 403) {
						errorMessage = "Tài khoản của bạn đã bị khóa tạm thời.";
					} else {
						errorMessage = "Lỗi Server (${response.statusCode}).";
					}
				}
				// Trả về map chứa lỗi để LoginPage hiển thị
				return {'error': errorMessage};
			}
		} catch (e) {
			// Lỗi kết nối
			return {'error': 'Lỗi kết nối Server. Vui lòng kiểm tra địa chỉ host.'};
		}
	}

	/// Đăng xuất (Revoke Token - Tùy chọn)
	Future<String?> logout(String token) async {
		try {
			final response = await http.post(
				Uri.parse('$baseUrl/logout'), // Giả định có endpoint /logout để revoke token
				headers: {
					'Content-Type': 'application/json',
					'Authorization': 'Bearer $token',
				},
			);

			if (response.statusCode == 200) {
				return null; // Thành công
			} else {
				// Đăng xuất thường không yêu cầu token hợp lệ, nên nếu thất bại, vẫn cho phép client clear session
				return 'Đăng xuất thất bại';
			}
		} catch (e) {
			return 'Lỗi kết nối khi gọi logout: $e';
		}
	}

	/// Lấy dịch vụ user (Ví dụ về API cần JWT)
	Future<List<Map<String, dynamic>>> getUserServices(
		int userId,
		String token,
	) async {
		try {
			// Sử dụng token trong header Authorization
			final response = await http.get(
				Uri.parse('$baseUrl/user/$userId'),
				headers: {
					'Content-Type': 'application/json',
					'Authorization': 'Bearer $token', // JWT Token
				},
			);

			if (response.statusCode == 200) {
				final List<dynamic> data = jsonDecode(response.body);
				return data.cast<Map<String, dynamic>>();
			} else if (response.statusCode == 401 || response.statusCode == 403) {
				throw Exception('Phiên làm việc hết hạn. Vui lòng đăng nhập lại.');
			} else {
				throw Exception('Lỗi khi tải dịch vụ: ${response.body}');
			}
		} catch (e) {
			throw Exception('Lỗi kết nối: $e');
		}
	}

	/// Yêu cầu OTP (Reset Password)
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

	/// Xác nhận đổi mật khẩu (Confirm Reset)
	Future<String?> confirmReset(
		String email,
		String otp,
		String newPassword,
	) async {
		try {
			final error = validatePassword(newPassword);
			if (error != null) return error;

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
				return null; // thành công
			} else {
				final data = jsonDecode(response.body);
				return data['message'] ??
					'OTP không hợp lệ hoặc mật khẩu không đạt yêu cầu';
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

	/// Helper: validate password policy
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
