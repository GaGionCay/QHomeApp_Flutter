import 'package:dio/dio.dart';
import '../auth/api_client.dart';

class ServiceBookingService {
  final Dio _dio;

  ServiceBookingService(this._dio);

  // Lấy danh sách services theo category code (ví dụ: "ENTERTAINMENT")
  Future<List<Map<String, dynamic>>> getServicesByCategoryCode(
      String categoryCode) async {
    try {
      final response = await _dio.get(
        '/service-booking/categories/code/$categoryCode/services',
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy services: $e');
      rethrow;
    }
  }

  // Lấy chi tiết service theo ID
  Future<Map<String, dynamic>> getServiceById(int serviceId) async {
    try {
      final response = await _dio.get('/service-booking/services/$serviceId');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      print('❌ Lỗi lấy chi tiết service: $e');
      rethrow;
    }
  }

  // Lấy danh sách available services theo category code, date, và time range
  Future<List<Map<String, dynamic>>> getAvailableServices({
    required String categoryCode,
    required DateTime date,
    required String startTime, // Format: "14:00:00"
    required String endTime, // Format: "17:00:00"
  }) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      final response = await _dio.get(
        '/service-booking/available',
        queryParameters: {
          'categoryCode': categoryCode,
          'date': dateStr,
          'startTime': startTime,
          'endTime': endTime,
        },
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy available services: $e');
      rethrow;
    }
  }

  // Tạo booking
  Future<Map<String, dynamic>> createBooking({
    required int serviceId,
    required DateTime bookingDate,
    required String startTime,
    required String endTime,
    required double durationHours,
    required int numberOfPeople,
    String? purpose,
    required bool termsAccepted,
  }) async {
    try {
      final dateStr = '${bookingDate.year}-${bookingDate.month.toString().padLeft(2, '0')}-${bookingDate.day.toString().padLeft(2, '0')}';
      
      final response = await _dio.post(
        '/service-booking/book',
        data: {
          'serviceId': serviceId,
          'bookingDate': dateStr,
          'startTime': startTime,
          'endTime': endTime,
          // durationHours không cần gửi, backend tự tính
          'numberOfPeople': numberOfPeople,
          if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
          'termsAccepted': termsAccepted,
        },
      );

      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      print('❌ Lỗi tạo booking: $e');
      rethrow;
    }
  }

  // Lấy VNPAY payment URL
  Future<String> getVnpayPaymentUrl(int bookingId) async {
    try {
      final response = await _dio.post(
        '/service-booking/$bookingId/vnpay-url',
      );

      if (response.data['success'] == true) {
        return response.data['paymentUrl'] as String;
      }
      throw Exception(response.data['message'] ?? 'Lỗi tạo URL thanh toán');
    } catch (e) {
      print('❌ Lỗi lấy VNPAY URL: $e');
      rethrow;
    }
  }

  // Lấy danh sách bookings của user
  Future<List<Map<String, dynamic>>> getMyBookings() async {
    try {
      final response = await _dio.get('/service-booking/my-bookings');

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy bookings: $e');
      rethrow;
    }
  }

  // Lấy chi tiết booking
  Future<Map<String, dynamic>> getBookingById(int bookingId) async {
    try {
      final response = await _dio.get('/service-booking/my-bookings/$bookingId');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      print('❌ Lỗi lấy chi tiết booking: $e');
      rethrow;
    }
  }

  // Lấy danh sách bookings chưa thanh toán
  Future<List<Map<String, dynamic>>> getUnpaidBookings() async {
    try {
      final response = await _dio.get('/service-booking/unpaid');

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy unpaid bookings: $e');
      rethrow;
    }
  }
}

