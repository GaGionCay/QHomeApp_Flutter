import 'package:dio/dio.dart';
import 'api_client.dart';
import 'iam_api_client.dart';

class EmailVerificationService {
  EmailVerificationService(this._apiClient);

  final ApiClient _apiClient;

  // Create a public Dio instance for IAM service (port 8088) without auth interceptors
  Dio get _publicDio {
    final baseUrl = IamApiClient.baseUrl; // IAM service runs on port 8088
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    // Add logging interceptor for debugging
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => print('🔍 EMAIL VERIFICATION API: $obj'),
    ));
    return dio;
  }

  Future<void> requestOtp(String email) async {
    try {
      print('📧 [EmailVerification] Gửi OTP cho email: $email');
      print('📧 [EmailVerification] Base URL: ${ApiClient.activeBaseUrl}');
      print('📧 [EmailVerification] Endpoint: /auth/request-email-verification');
      
      final response = await _publicDio.post(
        '/auth/request-email-verification',
        data: {'email': email},
      );
      
      print('✅ [EmailVerification] OTP đã được gửi thành công');
      print('📧 [EmailVerification] Response: ${response.data}');
    } on DioException catch (e) {
      print('❌ [EmailVerification] Lỗi gửi OTP: ${e.message}');
      print('❌ [EmailVerification] Status code: ${e.response?.statusCode}');
      print('❌ [EmailVerification] Response data: ${e.response?.data}');
      
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] is String) {
        throw Exception(responseData['message'] as String);
      }
      if (e.response?.statusCode == 429) {
        throw Exception('Bạn đã yêu cầu quá nhiều mã OTP. Vui lòng đợi một chút.');
      }
      throw Exception('Không thể gửi mã OTP. Vui lòng thử lại.');
    } catch (e) {
      print('❌ [EmailVerification] Lỗi không mong đợi: $e');
      rethrow;
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    try {
      final response = await _publicDio.post(
        '/auth/verify-email-otp',
        data: {
          'email': email,
          'otp': otp,
        },
      );
      if (response.data is Map && response.data['verified'] == true) {
        return true;
      }
      return false;
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map && responseData['message'] is String) {
        throw Exception(responseData['message'] as String);
      }
      throw Exception('Mã OTP không hợp lệ. Vui lòng thử lại.');
    }
  }

  Future<bool> checkEmailExists(String email) async {
    try {
      print('🔍 [EmailVerification] Kiểm tra email tồn tại: $email');
      print('🔍 [EmailVerification] IAM Base URL: ${IamApiClient.baseUrl}');
      
      // Use IAM service (port 8088) to check email existence via public endpoint
      final response = await _publicDio.get('/auth/check-email-exists/$email');
      print('✅ [EmailVerification] Email check response: ${response.data}');
      
      if (response.data is Map && response.data['exists'] == true) {
        print('✅ [EmailVerification] Email đã tồn tại');
        return true; // Email exists
      }
      print('✅ [EmailVerification] Email chưa tồn tại');
      return false; // Email does not exist
    } on DioException catch (e) {
      print('🔍 [EmailVerification] Email check response: ${e.response?.statusCode}');
      print('🔍 [EmailVerification] Response data: ${e.response?.data}');
      
      // If 404 or response indicates email doesn't exist, return false
      if (e.response?.statusCode == 404) {
        print('✅ [EmailVerification] Email chưa tồn tại (404)');
        return false; // Email does not exist
      }
      
      // If response contains exists: false, return false
      final responseData = e.response?.data;
      if (responseData is Map && responseData['exists'] == false) {
        print('✅ [EmailVerification] Email chưa tồn tại (from response)');
        return false;
      }
      
      print('❌ [EmailVerification] Lỗi khi kiểm tra email: ${e.message}');
      rethrow;
    } catch (e) {
      print('❌ [EmailVerification] Lỗi không mong đợi khi kiểm tra email: $e');
      rethrow;
    }
  }
}

