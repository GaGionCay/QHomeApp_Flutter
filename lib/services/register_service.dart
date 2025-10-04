import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service để gửi request đăng ký dịch vụ cư dân
class RegisterService {
  final String baseUrl = 'http://localhost:8080/api/register-service';

  /// Gửi đăng ký dịch vụ
  /// userId: id người dùng
  /// serviceType: tên dịch vụ đã chọn
  /// note: ghi chú/ lý do (có thể null)
  Future<bool> registerService({
    required int userId,
    required String serviceType,
    String? note,
  }) async {
    try {
      final url = Uri.parse(baseUrl);

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          // nếu sau này có jwt token thì thêm header Authorization
        },
        body: jsonEncode({
          'userId': userId,
          'serviceType': serviceType,
          'note': note ?? '',
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error registering service: $e');
      return false;
    }
  }
}
