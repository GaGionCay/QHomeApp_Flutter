import 'dart:developer';
import '../auth/api_client.dart';
import '../models/invoice_line.dart';

class InvoiceService {
  final ApiClient apiClient;
  
  InvoiceService(this.apiClient);

  /// Lấy danh sách invoice lines của user đang đăng nhập
  /// GET /api/invoices/me
  /// Lấy unitId từ user profile trong database
  Future<List<InvoiceLineResponseDto>> getMyInvoices() async {
    try {
      log('🔍 [InvoiceService] Lấy invoices của user hiện tại');
      
      final res = await apiClient.dio.get('/invoices/me');
      
      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        throw Exception(
            res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        log('ℹ️ Không có invoice nào cho user hiện tại');
        return [];
      }

      final invoices = (data as List)
          .map((json) => InvoiceLineResponseDto.fromJson(json))
          .toList();

      log('✅ [InvoiceService] Lấy được ${invoices.length} invoices cho user hiện tại');
      
      return invoices;
    } catch (e, s) {
      log('❌ [InvoiceService] Lỗi getMyInvoices(): $e\n$s');
      rethrow;
    }
  }

  /// Lấy danh sách invoice lines theo unitId (deprecated - nên dùng getMyInvoices)
  /// GET /api/invoices/unit/{unitId}
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

      final invoices = (data as List)
          .map((json) => InvoiceLineResponseDto.fromJson(json))
          .toList();

      log('✅ [InvoiceService] Lấy được ${invoices.length} invoices cho unitId: $unitId');
      
      return invoices;
    } catch (e, s) {
      log('❌ [InvoiceService] Lỗi getInvoiceLinesByUnitId($unitId): $e\n$s');
      rethrow;
    }
  }

  /// Tạo VNPAY payment URL cho invoice
  /// POST /api/invoices/{invoiceId}/vnpay-url
  Future<String> createVnpayPaymentUrl(String invoiceId) async {
    try {
      log('💳 [InvoiceService] Tạo VNPAY URL cho invoice: $invoiceId');
      
      final res = await apiClient.dio.post('/invoices/$invoiceId/vnpay-url');
      
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

  /// Thanh toán invoice - cập nhật status thành PAID (deprecated - dùng VNPAY thay thế)
  /// PUT /api/invoices/{invoiceId}/pay
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
}

