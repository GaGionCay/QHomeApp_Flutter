import 'package:dio/dio.dart';
import '../auth/api_client.dart';

class ServiceBookingService {
  final Dio _dio;

  ServiceBookingService(this._dio);

  // Lấy danh sách service types theo category code (ví dụ: "ENTERTAINMENT")
  // Trả về các loại dịch vụ như "BBQ", "Tennis", "Pool", v.v.
  Future<List<Map<String, dynamic>>> getServiceTypesByCategoryCode(
      String categoryCode) async {
    try {
      final response = await _dio.get(
        '/service-booking/categories/code/$categoryCode/service-types',
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy service types: $e');
      rethrow;
    }
  }

  // Lấy danh sách services theo category code và service type
  // Ví dụ: categoryCode="ENTERTAINMENT", serviceType="BBQ"
  Future<List<Map<String, dynamic>>> getServicesByCategoryCodeAndType(
      String categoryCode, String serviceType) async {
    try {
      final response = await _dio.get(
        '/service-booking/categories/code/$categoryCode/services/type/$serviceType',
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

  // Lấy danh sách services theo category code (ví dụ: "ENTERTAINMENT")
  // Deprecated: Nên sử dụng getServiceTypesByCategoryCode trước
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
  // serviceType là optional, nếu có thì chỉ trả về services thuộc type đó
  Future<List<Map<String, dynamic>>> getAvailableServices({
    required String categoryCode,
    required DateTime date,
    required String startTime, // Format: "14:00:00"
    required String endTime, // Format: "17:00:00"
    String? serviceType, // Optional: filter theo service type
  }) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      final queryParams = {
        'categoryCode': categoryCode,
        'date': dateStr,
        'startTime': startTime,
        'endTime': endTime,
      };
      
      // Thêm serviceType nếu có
      if (serviceType != null && serviceType.isNotEmpty) {
        queryParams['serviceType'] = serviceType;
      }
      
      final response = await _dio.get(
        '/service-booking/available',
        queryParameters: queryParams,
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
    // New fields for service-specific items
    List<Map<String, dynamic>>? selectedOptions,
    int? selectedComboId,
    int? selectedTicketId,
    int? selectedBarSlotId,
    int? extraHours,
  }) async {
    try {
      final dateStr = '${bookingDate.year}-${bookingDate.month.toString().padLeft(2, '0')}-${bookingDate.day.toString().padLeft(2, '0')}';
      
      final requestData = {
        'serviceId': serviceId,
        'bookingDate': dateStr,
        'startTime': startTime,
        'endTime': endTime,
        // durationHours không cần gửi, backend tự tính
        'numberOfPeople': numberOfPeople,
        if (purpose != null && purpose.isNotEmpty) 'purpose': purpose,
        'termsAccepted': termsAccepted,
        // Service-specific items
        if (selectedOptions != null && selectedOptions.isNotEmpty)
          'selectedOptions': selectedOptions.map((opt) => {
            'itemId': opt['itemId'],
            'itemType': 'OPTION',
            'itemCode': opt['itemCode'],
            'quantity': opt['quantity'],
          }).toList(),
        if (selectedComboId != null) 'selectedComboId': selectedComboId,
        if (selectedTicketId != null) 'selectedTicketId': selectedTicketId,
        if (selectedBarSlotId != null) 'selectedBarSlotId': selectedBarSlotId,
        if (extraHours != null && extraHours > 0) 'extraHours': extraHours,
      };
      
      final response = await _dio.post(
        '/service-booking/book',
        data: requestData,
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

  // Lấy danh sách time slots cho một service và ngày cụ thể
  Future<List<Map<String, dynamic>>> getTimeSlotsForService({
    required int serviceId,
    required DateTime date,
  }) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      final response = await _dio.get(
        '/service-booking/services/$serviceId/time-slots',
        queryParameters: {'date': dateStr},
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy time slots: $e');
      rethrow;
    }
  }

  // Lấy danh sách options cho service (BBQ)
  Future<List<Map<String, dynamic>>> getServiceOptions(int serviceId) async {
    try {
      final response = await _dio.get('/service-booking/services/$serviceId/options');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy options: $e');
      rethrow;
    }
  }

  // Lấy danh sách combos cho service (SPA, Bar)
  Future<List<Map<String, dynamic>>> getServiceCombos(int serviceId) async {
    try {
      final response = await _dio.get('/service-booking/services/$serviceId/combos');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy combos: $e');
      rethrow;
    }
  }

  // Lấy danh sách tickets cho service (Pool, Playground)
  Future<List<Map<String, dynamic>>> getServiceTickets(int serviceId) async {
    try {
      final response = await _dio.get('/service-booking/services/$serviceId/tickets');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy tickets: $e');
      rethrow;
    }
  }

  // Lấy danh sách bar slots (Bar)
  Future<List<Map<String, dynamic>>> getBarSlots(int serviceId) async {
    try {
      final response = await _dio.get('/service-booking/services/$serviceId/bar-slots');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }
      return [];
    } catch (e) {
      print('❌ Lỗi lấy bar slots: $e');
      rethrow;
    }
  }
}

