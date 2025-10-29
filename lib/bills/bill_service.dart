import 'dart:developer';
import '../auth/api_client.dart';
// import các DTO nếu chúng ở file riêng
// import 'bill_dtos.dart'; 

class BillService {
  final ApiClient apiClient;
  BillService(this.apiClient);

  /// Lấy danh sách hóa đơn chưa thanh toán.
  Future<List<BillDto>> getUnpaidBills() async {
    try {
      final res = await apiClient.dio.get('/bills/unpaid');
      // API trả về Map<String, dynamic> với key 'data' chứa List
      return (res.data['data'] as List)
          .map((json) => BillDto.fromJson(json))
          .toList();
    } catch (e, s) {
      log('❌ Lỗi getUnpaidBills: $e\n$s');
      rethrow;
    }
  }

  /// Lấy danh sách hóa đơn đã thanh toán.
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

  /// Thanh toán hóa đơn theo ID.
  /// Spring Controller trả về Bill, nên Service nên trả về BillDto đã thanh toán.
  Future<BillDto> payBill(int billId) async {
    try {
      final res = await apiClient.dio.post('/bills/$billId/pay');
      // Controller trả về Map có key 'data' chứa đối tượng Bill đã thanh toán
      return BillDto.fromJson(res.data['data']);
    } catch (e, s) {
      log('❌ Lỗi payBill($billId): $e\n$s');
      rethrow;
    }
  }

  /// Lấy chi tiết hóa đơn theo ID.
  Future<BillDto> getBillDetail(int id) async {
    try {
      final res = await apiClient.dio.get('/bills/$id');
      // Controller trả về Map có key 'data' chứa đối tượng Bill
      return BillDto.fromJson(res.data['data']);
    } catch (e, s) {
      log('❌ Lỗi getBillDetail($id): $e\n$s');
      rethrow;
    }
  }

  /// Lấy thống kê hóa đơn theo tháng và loại.
  Future<List<BillStatistics>> getStatistics({String billType = 'Tất cả'}) async {
    try {
      // mappedType là null nếu là 'Tất cả', API Spring Controller sẽ dùng defaultValue='ALL'
      final mappedType = _mapBillType(billType); 
      
      final res = await apiClient.dio.get(
        '/bills/statistics',
        queryParameters: {
          if (mappedType != null) 'billType': mappedType,
          // Nếu mappedType là null, query parameter 'billType' sẽ không được gửi, 
          // và Controller sẽ dùng defaultValue "ALL".
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

  /// Lấy danh sách hóa đơn theo tháng và loại.
  Future<List<BillDto>> getBillsByMonthAndType(String month, {String billType = 'Tất cả'}) async {
    try {
      final mappedType = _mapBillType(billType);
      log('📡 [BillService] Fetching bills => month: $month | type: $mappedType');

      final res = await apiClient.dio.get(
        '/bills/by-month',
        queryParameters: {
          'month': month,
          if (mappedType != null) 'billType': mappedType,
          // Nếu mappedType là null, billType sẽ không được gửi
        },
      );

      if (res.statusCode != 200) {
        log('⚠️ API trả mã ${res.statusCode}: ${res.data}');
        // Nếu API trả lỗi (400), ném Exception với message từ server nếu có
        throw Exception(res.data['message'] ?? 'Server trả lỗi ${res.statusCode}');
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

  /// Hàm ánh xạ loại hóa đơn từ ngôn ngữ người dùng sang enum/String của API.
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
        return null; // Trả về null để không thêm query param, API sẽ dùng ALL mặc định.
      default:
        return null;
    }
  }
}

// --- DTO Cập Nhật ---

class BillDto {
  final int id;
  final String billType;
  final double amount;
  final String status;
  final String billingMonth; // Đổi tên biến để khớp hơn với JSON
  final String paymentDate; // Đổi tên biến để khớp hơn với JSON
  final String? description; // Thêm trường có thể có

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
      id: (json['id'] is String) ? int.tryParse(json['id']) ?? 0 : json['id'] ?? 0, 
      billType: json['billType'] ?? '',
      amount: (json['amount'] is num) ? json['amount'].toDouble() : 0.0,
      status: json['status'] ?? 'UNKNOWN',
      billingMonth: json['billingMonth'] ?? '', // Khớp với tên trường trong API
      paymentDate: json['paymentDate'] ?? '', // Khớp với tên trường trong API
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
      totalAmount: (json['totalAmount'] is num) ? json['totalAmount'].toDouble() : 0.0,
    );
  }
}