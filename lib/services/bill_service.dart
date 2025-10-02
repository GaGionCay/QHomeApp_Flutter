import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/monthly_bill_summary.dart';

class BillService {
  final String baseUrl = 'http://192.168.100.46:8080/api/bills';

  Future<List<dynamic>> getUserBills(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load bills: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<Map<String, dynamic>> getBillDetails(int billId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$billId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load bill details: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> payBill(int billId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$billId/pay'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return null;
      } else {
        return response.body;
      }
    } catch (e) {
      return 'Lỗi kết nối: $e';
    }
  }

  Future<List<MonthlyBillSummary>> fetchMonthlySummary(int userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$userId/monthly-summary'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => MonthlyBillSummary.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load monthly summary: ${response.body}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }
}
