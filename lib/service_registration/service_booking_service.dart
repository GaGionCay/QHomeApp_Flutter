import 'dart:math';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../auth/asset_maintenance_api_client.dart';

class ServiceBookingService {
  ServiceBookingService(AssetMaintenanceApiClient client) : _client = client;

  final AssetMaintenanceApiClient _client;

  Dio get _dio => _client.dio;

  Future<List<Map<String, dynamic>>> getActiveCategories() async {
    try {
      final response = await _dio.get('/resident/categories');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách danh mục dịch vụ.');
    }
  }

  Future<List<Map<String, dynamic>>> getServicesByCategory(String categoryCode) async {
    try {
      final response = await _dio.get('/resident/categories/$categoryCode/services');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> getServiceDetail(String serviceId) async {
    try {
      final response = await _dio.get('/resident/services/$serviceId');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải thông tin dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> getServiceBookingCatalog(String serviceId) async {
    try {
      final response = await _dio.get('/services/$serviceId/booking/catalog');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh mục đặt dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> createBooking({
    required String serviceId,
    required DateTime bookingDate,
    required String startTime,
    required String endTime,
    required double durationHours,
    required int numberOfPeople,
    required num totalAmount,
    String? purpose,
    bool termsAccepted = true,
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final payload = {
        'serviceId': serviceId,
        'bookingDate': _formatDate(bookingDate),
        'startTime': startTime,
        'endTime': endTime,
        'durationHours': double.parse(durationHours.toStringAsFixed(2)),
        'numberOfPeople': numberOfPeople,
        'totalAmount': double.parse(totalAmount.toStringAsFixed(2)),
        'termsAccepted': termsAccepted,
        if (purpose != null && purpose.trim().isNotEmpty) 'purpose': purpose.trim(),
        if (items != null && items.isNotEmpty)
          'items': items.map((item) => Map<String, dynamic>.from(item)).toList(),
      };

      final response = await _dio.post('/bookings', data: payload);
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tạo yêu cầu đặt dịch vụ.');
    }
  }

  Future<List<Map<String, dynamic>>> getMyBookings() async {
    try {
      final response = await _dio.get('/bookings');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách đặt dịch vụ của bạn.');
    }
  }

  Future<List<Map<String, dynamic>>> getUnpaidBookings() async {
    try {
      final response = await _dio.get('/bookings/unpaid');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách dịch vụ chưa thanh toán.');
    }
  }

  Future<List<Map<String, dynamic>>> getPaidBookings() async {
    try {
      final response = await _dio.get('/bookings/paid');
      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách dịch vụ đã thanh toán.');
    }
  }

  Future<Map<String, dynamic>> getBookingById(String bookingId) async {
    try {
      final response = await _dio.get('/bookings/$bookingId');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải thông tin đặt dịch vụ.');
    }
  }

  Future<Map<String, dynamic>> createVnpayPaymentUrl(String bookingId) async {
    try {
      final response = await _dio.post('/bookings/$bookingId/vnpay-url');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể khởi tạo thanh toán VNPAY.');
    }
  }

  Future<Map<String, dynamic>> cancelBooking(String bookingId, {String? reason}) async {
    try {
      final payload = {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      };
      final response = await _dio.patch(
        '/bookings/$bookingId/cancel',
        data: payload.isEmpty ? null : payload,
      );
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể hủy đặt dịch vụ.');
    }
  }

  Future<List<Map<String, dynamic>>> getBookedSlots({
    required String serviceId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final params = <String, String>{};
      final formatter = DateFormat('yyyy-MM-dd');
      if (from != null) {
        params['from'] = formatter.format(from);
      }
      if (to != null) {
        params['to'] = formatter.format(to);
      }

      final response = await _dio.get(
        '/resident/services/$serviceId/booked-slots',
        queryParameters: params.isEmpty ? null : params,
      );

      if (response.data is List) {
        return List<Map<String, dynamic>>.from(
          (response.data as List).map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }
      return const [];
    } on DioException catch (e) {
      throw _wrapDioException(e, 'Không thể tải danh sách slot đã được đặt.');
    }
  }

  String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Exception _wrapDioException(DioException error, String fallback) {
    if (error.response?.data is Map) {
      final data = Map<String, dynamic>.from(error.response!.data as Map);
      final message = data['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return Exception(message);
      }
    }
    return Exception(fallback);
  }

  /// Helper to build booking item payload.
  Map<String, dynamic> buildBookingItem({
    required String itemType,
    required String itemId,
    required String itemCode,
    required String itemName,
    required int quantity,
    required num unitPrice,
    num? totalPrice,
  }) {
    final price = totalPrice ?? unitPrice * max(quantity, 1);
    return {
      'itemType': itemType,
      'itemId': itemId,
      'itemCode': itemCode,
      'itemName': itemName,
      'quantity': quantity,
      'unitPrice': double.parse(unitPrice.toStringAsFixed(2)),
      'totalPrice': double.parse(price.toStringAsFixed(2)),
    };
  }
}
