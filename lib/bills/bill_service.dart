import 'dart:developer';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';

class BillService {
  final ApiClient apiClient;
  BillService(this.apiClient);

  Future<List<BillDto>> getUnpaidBills() async {
    try {
      final res = await apiClient.dio.get('/bills/unpaid');
      return (res.data['data'] as List)
          .map((json) => BillDto.fromJson(json))
          .toList();
    } catch (e, s) {
      log('❌ Lỗi getUnpaidBills: $e\n$s');
      rethrow;
    }
  }

  Future<List<BillDto>> getPaidBills() async {
    try {
      final res = await apiClient.dio.get('/bills/paid');
      return (res.data['data'] as List)
          .map((json) => BillDto.fromJson(json))
          .toList();
    } catch (e, s) {
      log('❌ Lỗi getPaidBills: $e\n$s');
      rethrow;
    }
  }

  Future<BillDto> payBill(int billId) async {
    try {
      final res = await apiClient.dio.post('/bills/$billId/pay');
      return BillDto.fromJson(res.data['data']);
    } catch (e, s) {
      log('❌ Lỗi payBill($billId): $e\n$s');
      rethrow;
    }
  }

  Future<BillDto> getBillDetail(int id) async {
    try {
      final res = await apiClient.dio.get('/bills/$id');
      return BillDto.fromJson(res.data['data']);
    } catch (e, s) {
      log('❌ Lỗi getBillDetail($id): $e\n$s');
      rethrow;
    }
  }

  Future<List<BillStatistics>> getStatistics(
      {String billType = 'Tất cả'}) async {
    try {
      final mappedType = _mapBillType(billType);

      final res = await apiClient.dio.get(
        '/bills/statistics',
        queryParameters: {
          if (mappedType != null) 'billType': mappedType,
        },
      );

      if (res.data == null || res.data['data'] == null) {
        log('⚠️ API trả về null khi getStatistics($billType)');
        return [];
      }

      return (res.data['data'] as List)
          .map((json) => BillStatistics.fromJson(json))
          .toList();
    } catch (e, s) {
      log('❌ Lỗi getStatistics($billType): $e\n$s');
      rethrow;
    }
  }

  Future<List<BillDto>> getBillsByMonthAndType(String month,
      {String billType = 'Tất cả'}) async {
    try {
      final mappedType = _mapBillType(billType);
      log('📡 [BillService] Fetching bills => month: $month | type: $mappedType');

      final res = await apiClient.dio.get(
        '/bills/by-month',
        queryParameters: {
          'month': month,
          if (mappedType != null) 'billType': mappedType,
        },
      );

      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        throw Exception(
            res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
      }

      final data = res.data['data'] as List?;
      if (data == null || data.isEmpty) {
        log('ℹ️ Không có hóa đơn nào cho tháng $month và loại $billType');
        return [];
      }

      return data.map((json) => BillDto.fromJson(json)).toList();
    } catch (e, s) {
      log('❌ Lỗi getBillsByMonthAndType($month, $billType): $e\n$s');
      rethrow;
    }
  }

  Future<String> createVnpayPaymentUrl(int billId) async {
    try {
      final res = await apiClient.dio.post('/bills/$billId/vnpay-url');
      log('📡 Response tạo URL: ${res.data}');

      if (res.statusCode == 200 && res.data['paymentUrl'] != null) {
        return res.data['paymentUrl'];
      } else {
        throw Exception(res.data['message'] ?? 'Không thể tạo URL thanh toán');
      }
    } catch (e, s) {
      log('❌ Lỗi tạo URL: $e\n$s');
      rethrow;
    }
  }

  Future<void> openVnpayPayment(int billId) async {
    try {
      log('🔄 Đang tạo URL thanh toán cho billId: $billId...');
      final url = await createVnpayPaymentUrl(billId);

      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        log('🌐 Đã mở trình duyệt để thanh toán');
      } else {
        throw Exception('Không thể mở liên kết thanh toán');
      }
    } catch (e, s) {
      log('❌ Lỗi khi mở VNPAY: $e\n$s');
      rethrow;
    }
  }

  String? _mapBillType(String type) {
    switch (type.toUpperCase()) {
      case 'ĐIỆN':
      case 'DIEN':
      case 'ELECTRIC':
      case 'ELECTRICITY':
        return 'ELECTRICITY';
      case 'NƯỚC':
      case 'NUOC':
      case 'WATER':
        return 'WATER';
      case 'INTERNET':
        return 'INTERNET';
      case 'TẤT CẢ':
      case 'TAT CA':
      case 'ALL':
        return null;
      default:
        return null;
    }
  }
}


class BillDto {
  final int id;
  final String billType;
  final double amount;
  final String status;
  final String billingMonth; 
  final String paymentDate; 
  final String? description; 

  BillDto({
    required this.id,
    required this.billType,
    required this.amount,
    required this.status,
    required this.billingMonth,
    required this.paymentDate,
    this.description,
  });

  factory BillDto.fromJson(Map<String, dynamic> json) {
    return BillDto(
      // ID từ Long (Java) sang int (Dart)
      id: (json['id'] is String)
          ? int.tryParse(json['id']) ?? 0
          : json['id'] ?? 0,
      billType: json['billType'] ?? '',
      amount: (json['amount'] is num) ? json['amount'].toDouble() : 0.0,
      status: json['status'] ?? 'UNKNOWN',
      billingMonth: json['billingMonth'] ?? '',
      paymentDate: json['paymentDate'] ?? '',
      description: json['description'],
    );
  }
}

class BillStatistics {
  final String month;
  final String billType;
  final double totalAmount;

  BillStatistics({
    required this.month,
    required this.billType,
    required this.totalAmount,
  });

  factory BillStatistics.fromJson(Map<String, dynamic> json) {
    return BillStatistics(
      month: json['month'] ?? '',
      billType: json['billType'] ?? '',
      totalAmount:
          (json['totalAmount'] is num) ? json['totalAmount'].toDouble() : 0.0,
    );
  }
}
