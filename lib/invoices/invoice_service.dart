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

  Future<List<InvoiceLineResponseDto>> getMyInvoices({String? unitId}) async {
    if (unitId == null || unitId.isEmpty) {
      debugPrint('⚠️ [InvoiceService] unitId bị trống khi lấy invoices – trả về danh sách rỗng');
      return [];
    }

    try {
      debugPrint('🔍 [InvoiceService] Lấy invoices cho unitId=$unitId từ finance-billing (group theo serviceCode)');

      final client = await _prepareFinanceClient();
      final res = await client.get('/api/invoices/unit/$unitId');

      if (res.statusCode != 200) {
        debugPrint('⚠️ [InvoiceService] API trả mã ${res.statusCode}: ${res.data}');
        return [];
      }

      final data = res.data;
      if (data is! List) {
        debugPrint('⚠️ [InvoiceService] Payload invoices không phải dạng List: ${res.data.runtimeType}');
        return [];
      }

      final List<InvoiceLineResponseDto> flattened = [];

      for (final invoiceRaw in data) {
        if (invoiceRaw is! Map) continue;
        final invoice = Map<String, dynamic>.from(invoiceRaw);

        final String invoiceId = invoice['id']?.toString() ?? '';
        final String payerUnit = invoice['payerUnitId']?.toString() ?? unitId;
        final String status = invoice['status']?.toString() ?? 'UNKNOWN';
        final List<dynamic>? lines = invoice['lines'] as List<dynamic>?;

        if (lines == null || lines.isEmpty) continue;

        for (final lineRaw in lines) {
          if (lineRaw is! Map) continue;
          final line = Map<String, dynamic>.from(lineRaw);

          final mappedJson = <String, dynamic>{
            'payerUnitId': payerUnit,
            'invoiceId': invoiceId,
            'serviceDate': _formatServiceDate(line['serviceDate']),
            'description': line['description']?.toString() ?? '',
            'quantity': _toDouble(line['quantity']),
            'unit': line['unit']?.toString() ?? '',
            'unitPrice': _toDouble(line['unitPrice']),
            'taxAmount': _toDouble(line['taxAmount']),
            'lineTotal': _toDouble(line['lineTotal']),
            'serviceCode': line['serviceCode']?.toString() ?? '',
            'status': status,
          };

          flattened.add(
            InvoiceLineResponseDto.fromJson(mappedJson),
          );
        }
      }

      debugPrint('✅ [InvoiceService] Flatten được ${flattened.length} dòng hóa đơn cho unitId=$unitId');
      return flattened;
    } catch (e, s) {
      debugPrint('ℹ️ [InvoiceService] Không lấy được invoices (coi như đã thanh toán): $e');
      debugPrint('Chi tiết stacktrace: $s');
      return [];
    }
  }

  Future<List<InvoiceCategory>> getUnpaidInvoicesByCategory({String? unitId}) async {
    try {
      debugPrint('🔍 [InvoiceService] Lấy hóa đơn chưa thanh toán theo serviceCode (client grouping)');
      final invoices = await getMyInvoices(unitId: unitId);
      final unpaid = invoices.where((inv) => !inv.isPaid).toList();
      final categories = _groupInvoicesByService(unpaid);
      debugPrint('✅ [InvoiceService] Có ${categories.length} nhóm hóa đơn chưa thanh toán');
      return categories;
    } catch (e, s) {
      debugPrint('ℹ️ [InvoiceService] Không lấy được hóa đơn chưa thanh toán (coi như đã thanh toán hết): $e');
      debugPrint('Chi tiết stacktrace: $s');
      return [];
    }
  }

  Future<List<InvoiceCategory>> getPaidInvoicesByCategory({String? unitId}) async {
    try {
      debugPrint('🔍 [InvoiceService] Lấy hóa đơn đã thanh toán theo serviceCode (client grouping)');
      final invoices = await getMyInvoices(unitId: unitId);
      final paid = invoices.where((inv) => inv.isPaid).toList();
      final categories = _groupInvoicesByService(paid);
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

  List<InvoiceCategory> _groupInvoicesByService(List<InvoiceLineResponseDto> invoices) {
    if (invoices.isEmpty) return [];

    final Map<String, List<InvoiceLineResponseDto>> grouped = {};

    for (final invoice in invoices) {
      final code = (invoice.serviceCode.isNotEmpty
              ? invoice.serviceCode.toUpperCase()
              : 'OTHER')
          .trim();
      grouped.putIfAbsent(code, () => []).add(invoice);
    }

    final List<InvoiceCategory> categories = grouped.entries.map((entry) {
      final serviceInvoices = entry.value;
      final total = serviceInvoices.fold<double>(
        0,
        (prev, invoice) => prev + invoice.lineTotal,
      );
      final displayName = serviceInvoices.first.serviceCodeDisplay;

      return InvoiceCategory(
        categoryCode: entry.key,
        categoryName: displayName,
        totalAmount: total,
        invoiceCount: serviceInvoices.length,
        invoices: serviceInvoices,
      );
    }).toList();

    categories.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

    return categories;
  }

  String _formatServiceDate(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }
}

