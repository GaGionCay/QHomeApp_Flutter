import 'dart:convert';
import 'package:flutter_application_1/services/api_client.dart';

class RegisterServiceService {
  final ApiClient apiClient;

  RegisterServiceService({required this.apiClient});

  Future<Map<String, dynamic>> registerService({
    required String serviceType,
    required String date,
    String? note,
  }) async {
    final dto = {
      'serviceType': serviceType,
      'date': date,
      'note': note ?? '',
    };

    final response = await apiClient.post('/register-service', body: dto);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }

    throw Exception('Failed to register service: ${response.statusCode}');
  }

  Future<List<dynamic>> getMyServices() async {
    final response = await apiClient.get('/register-service/me');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  Future<Map<String, dynamic>?> getServiceDetail(int id) async {
    final services = await getMyServices();
    return services.firstWhere((e) => e['id'] == id, orElse: () => null);
  }
}
