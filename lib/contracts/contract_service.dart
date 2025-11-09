import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../models/contract.dart';
import '../models/unit_info.dart';

class ContractService {
  final ApiClient apiClient;
  final Dio? contractsDio;

  ContractService(this.apiClient, {this.contractsDio});

  Dio _contractsClient() {
    if (contractsDio != null) {
      return contractsDio!;
    }
    const baseUrl = 'http://${ApiClient.HOST_IP}:8082/api';
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
      receiveTimeout: const Duration(seconds: ApiClient.TIMEOUT_SECONDS),
    ));
  }

  Future<List<UnitInfo>> getMyUnits() async {
    try {
      final response = await apiClient.dio.get('/residents/my-units');
      if (response.data is List) {
        return (response.data as List)
            .map((item) => UnitInfo.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ [ContractService] Lỗi getMyUnits: $e');
      return [];
    }
  }

  Future<List<ContractDto>> getContractsByUnit(String unitId) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.get('/contracts/unit/$unitId');
      if (response.statusCode != 200) {
        print('⚠️ [ContractService] API trả mã ${response.statusCode}: ${response.data}');
        return [];
      }

      if (response.data is List) {
        return (response.data as List)
            .map((item) => ContractDto.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
      }

      return [];
    } on DioException catch (e) {
      print('❌ [ContractService] DioException getContractsByUnit: ${e.message}');
      return [];
    } catch (e) {
      print('❌ [ContractService] Lỗi getContractsByUnit: $e');
      return [];
    }
  }
}
