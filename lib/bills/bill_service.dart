import 'dart:developer';
import '../auth/api_client.dart';

class BillService {
  final ApiClient apiClient;
  BillService(this.apiClient);

  /// Lấy danh sách hóa đơn chưa thanh toán
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

  /// Lấy danh sách hóa đơn đã thanh toán
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

  /// Thanh toán hóa đơn
  Future<void> payBill(int billId) async {
    try {
      await apiClient.dio.post('/bills/$billId/pay');
    } catch (e, s) {
      log('❌ Lỗi payBill($billId): $e\n$s');
      rethrow;
    }
  }

  /// Chi tiết hóa đơn
  Future<BillDto> getBillDetail(int id) async {
    try {
      final res = await apiClient.dio.get('/bills/$id');
      return BillDto.fromJson(res.data['data']);
    } catch (e, s) {
      log('❌ Lỗi getBillDetail($id): $e\n$s');
      rethrow;
    }
  }

  /// Thống kê hóa đơn theo loại (truyền 'Tất cả' nếu muốn lấy toàn bộ)
  Future<List<BillStatistics>> getStatistics({String billType = 'Tất cả'}) async {
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

  /// Lấy hóa đơn theo tháng và loại (backend: /bills/by-month)
  Future<List<BillDto>> getBillsByMonthAndType(String month, String billType) async {
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
        throw Exception('Server trả lỗi ${res.statusCode}');
      }

      if (res.data == null || res.data['data'] == null) {
        log('⚠️ API trả về null khi getBillsByMonthAndType($month, $billType)');
        return [];
      }

      final data = res.data['data'] as List;
      if (data.isEmpty) {
        log('ℹ️ Không có hóa đơn nào cho tháng $month và loại $billType');
        return [];
      }

      return data.map((json) => BillDto.fromJson(json)).toList();
    } catch (e, s) {
      log('❌ Lỗi getBillsByMonthAndType($month, $billType): $e\n$s');
      rethrow;
    }
  }

  /// ------------------------- HELPER -------------------------
  /// Map loại hóa đơn tiếng Việt → backend code
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

/// ------------------------- DTO -------------------------

class BillDto {
  final int id;
  final String billType;
  final double amount;
  final String status;
  final String month;   // mapping từ billingMonth
  final String dueDate; // mapping từ paymentDate hoặc để ''

  BillDto({
    required this.id,
    required this.billType,
    required this.amount,
    required this.status,
    required this.month,
    required this.dueDate,
  });

  factory BillDto.fromJson(Map<String, dynamic> json) {
    return BillDto(
      id: json['id'] ?? 0,
      billType: json['billType'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status'] ?? 'UNKNOWN',
      month: json['billingMonth'] ?? '',
      dueDate: json['paymentDate'] ?? '',
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
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
    );
  }
}
