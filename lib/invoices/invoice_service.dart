import 'dart:developer';
import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../models/invoice_line.dart';
import '../models/electricity_monthly.dart';
import '../models/invoice_category.dart';
import 'package:dio/dio.dart';

class InvoiceService {
  final ApiClient apiClient;
  final Dio? financeBillingDio;
  
  InvoiceService(this.apiClient, {this.financeBillingDio});

  Dio _financeBillingClient() {
    if (financeBillingDio != null) return financeBillingDio!;
    // Create finance-billing-service client (port 8085)
    final baseUrl = ApiClient.buildServiceBase(port: 8085);
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
    ));
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
      logPrint: (obj) => debugPrint('🔍 FINANCE DIO: $obj'),
    ));
    return dio;
  }

  Future<Dio> _prepareFinanceClient() async {
    final client = _financeBillingClient();
    final token = await apiClient.storage.readAccessToken();
    if (token != null) {
      client.options.headers['Authorization'] = 'Bearer $token';
    } else {
      client.options.headers.remove('Authorization');
    }
    return client;
  }

  Future<List<InvoiceLineResponseDto>> getMyInvoices({
    required String unitId,
    String? cycleId,
  }) async {
    try {
      debugPrint(
          '🔍 [InvoiceService] Lấy invoices của user hiện tại (unit=$unitId, cycle=$cycleId)');
      
      final client = await _prepareFinanceClient();
      final queryParameters = <String, dynamic>{'unitId': unitId};
      if (cycleId != null && cycleId.isNotEmpty) {
        queryParameters['cycleId'] = cycleId;
      }
      final res = await client.get(
        '/api/invoices/me',
        queryParameters: queryParameters,
      );
      
      if (res.statusCode != 200) {
        debugPrint('⚠️ [InvoiceService] API trả mã ${res.statusCode}: ${res.data}');
        return [];
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        debugPrint('ℹ️ [InvoiceService] Không có invoice nào cho user hiện tại');
        return [];
      }

      final invoices = (data)
          .map((json) => InvoiceLineResponseDto.fromJson(json))
          .toList();

      debugPrint('✅ [InvoiceService] Lấy được ${invoices.length} invoices cho user hiện tại');
      
      return invoices;
    } catch (e, s) {
      debugPrint('ℹ️ [InvoiceService] Không lấy được invoices (coi như đã thanh toán): $e');
      debugPrint('Chi tiết stacktrace: $s');
      return [];
    }
  }

  Future<List<InvoiceCategory>> getUnpaidInvoicesByCategory({
    required String unitId,
    String? cycleId,
  }) async {
    try {
      debugPrint(
          '🔍 [InvoiceService] Lấy hóa đơn chưa thanh toán theo nhóm dịch vụ (unit=$unitId, cycle=$cycleId)');

      final client = await _prepareFinanceClient();
      final queryParameters = <String, dynamic>{'unitId': unitId};
      if (cycleId != null && cycleId.isNotEmpty) {
        queryParameters['cycleId'] = cycleId;
      }
      final res = await client.get(
        '/api/invoices/me/unpaid-by-category',
        queryParameters: queryParameters,
      );

      if (res.statusCode != 200) {
        debugPrint('⚠️ [InvoiceService] API trả mã ${res.statusCode}: ${res.data}');
        return [];
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        debugPrint('ℹ️ [InvoiceService] Không còn hóa đơn chưa thanh toán');
        return [];
      }

      final categories = data
          .map((json) => InvoiceCategory.fromJson(
                Map<String, dynamic>.from(json as Map),
              ))
          .toList();

      debugPrint('✅ [InvoiceService] Có ${categories.length} nhóm hóa đơn chưa thanh toán');
      return categories;
    } catch (e, s) {
      debugPrint('ℹ️ [InvoiceService] Không lấy được hóa đơn chưa thanh toán (coi như đã thanh toán hết): $e');
      debugPrint('Chi tiết stacktrace: $s');
      return [];
    }
  }

  Future<List<InvoiceCategory>> getPaidInvoicesByCategory({
    required String unitId,
    String? cycleId,
  }) async {
    try {
      debugPrint(
          '🔍 [InvoiceService] Lấy hóa đơn đã thanh toán theo nhóm dịch vụ (unit=$unitId, cycle=$cycleId)');

      final client = await _prepareFinanceClient();
      final queryParameters = <String, dynamic>{'unitId': unitId};
      if (cycleId != null && cycleId.isNotEmpty) {
        queryParameters['cycleId'] = cycleId;
      }
      final res = await client.get(
        '/api/invoices/me/paid-by-category',
        queryParameters: queryParameters,
      );

      if (res.statusCode != 200) {
        debugPrint('⚠️ [InvoiceService] API trả mã ${res.statusCode}: ${res.data}');
        return [];
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        debugPrint('ℹ️ [InvoiceService] Không còn hóa đơn đã thanh toán');
        return [];
      }

      final categories = data
          .map((json) => InvoiceCategory.fromJson(
                Map<String, dynamic>.from(json as Map),
              ))
          .toList();

      debugPrint('✅ [InvoiceService] Có ${categories.length} nhóm hóa đơn đã thanh toán');
      return categories;
    } catch (e, s) {
      debugPrint('ℹ️ [InvoiceService] Không lấy được hóa đơn đã thanh toán: $e');
      debugPrint('Chi tiết stacktrace: $s');
      return [];
    }
  }

  @Deprecated('Use getMyInvoices() instead')
  Future<List<InvoiceLineResponseDto>> getInvoiceLinesByUnitId(String unitId) async {
    try {
      log('🔍 [InvoiceService] Lấy invoices cho unitId: $unitId');
      
      final res = await apiClient.dio.get('/invoices/unit/$unitId');
      
      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        throw Exception(
            res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        log('ℹ️ Không có invoice nào cho unitId: $unitId');
        return [];
      }

      final invoices = (data)
          .map((json) => InvoiceLineResponseDto.fromJson(json))
          .toList();

      log('✅ [InvoiceService] Lấy được ${invoices.length} invoices cho unitId: $unitId');
      
      return invoices;
    } catch (e, s) {
      log('❌ [InvoiceService] Lỗi getInvoiceLinesByUnitId($unitId): $e\n$s');
      rethrow;
    }
  }

  Future<String> createVnpayPaymentUrl(String invoiceId, {String? unitId}) async {
    try {
      log('💳 [InvoiceService] Tạo VNPAY URL cho invoice: $invoiceId');
      final client = await _prepareFinanceClient();
      final res = await client.post(
        '/api/invoices/$invoiceId/vnpay-url',
        queryParameters: unitId != null ? {'unitId': unitId} : null,
      );
      
      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        throw Exception(
            res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
      }

      if (res.data['paymentUrl'] == null) {
        throw Exception('Không thể tạo URL thanh toán');
      }

      log('✅ [InvoiceService] Tạo VNPAY URL thành công cho invoice $invoiceId');
      return res.data['paymentUrl'];
    } catch (e, s) {
      log('❌ [InvoiceService] Lỗi createVnpayPaymentUrl($invoiceId): $e\n$s');
      rethrow;
    }
  }

  Future<void> payInvoice(String invoiceId) async {
    try {
      log('💳 [InvoiceService] Thanh toán invoice (deprecated): $invoiceId');
      
      final res = await apiClient.dio.put('/invoices/$invoiceId/pay');
      
      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        throw Exception(
            res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
      }

      log('✅ [InvoiceService] Thanh toán invoice $invoiceId thành công');
    } catch (e, s) {
      log('❌ [InvoiceService] Lỗi payInvoice($invoiceId): $e\n$s');
      rethrow;
    }
  }

  Future<List<ElectricityMonthly>> getElectricityMonthlyData({String? unitId}) async {
    try {
      log('📊 [InvoiceService] Lấy dữ liệu tiền điện theo tháng');
      final client = await _prepareFinanceClient();
      final res = await client.get(
        '/api/invoices/electricity/monthly',
        queryParameters: unitId != null ? {'unitId': unitId} : null,
      );
      
      if (res.statusCode != 200) {
        log('⚠️ API tiền điện trả mã ${res.statusCode}: ${res.data}');
        return [];
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        log('ℹ️ Không có dữ liệu tiền điện');
        return [];
      }

      final monthlyData = (data)
          .map((json) => ElectricityMonthly.fromJson(json))
          .toList();

      log('✅ [InvoiceService] Lấy được ${monthlyData.length} tháng dữ liệu tiền điện');
      
      return monthlyData;
    } catch (e, s) {
      log('ℹ️ [InvoiceService] Không nhận được dữ liệu tiền điện (coi như đã thanh toán): $e');
      log('Chi tiết stacktrace: $s');
      return [];
    }
  }
}

