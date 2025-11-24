import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
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
    // All requests go through API Gateway (port 8989)
    // Gateway routes /api/data-docs/** to data-docs-service (8082)
    // Note: buildServiceBase() already includes /api in the base URL
    final baseUrl = ApiClient.buildServiceBase();
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
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

  Future<ContractDto?> getContractById(String contractId) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.get('/contracts/$contractId');
      if (response.statusCode != 200) {
        print('⚠️ [ContractService] API trả mã ${response.statusCode}: ${response.data}');
        return null;
      }

      if (response.data is Map) {
        return ContractDto.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      return null;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException getContractById: ${e.message}');
      if (e.response?.statusCode == 404) {
        print('⚠️ [ContractService] Contract không tồn tại: $contractId');
      }
      return null;
    } catch (e) {
      print('❌ [ContractService] Lỗi getContractById: $e');
      return null;
    }
  }

  Future<String?> downloadContractFile(
    String contractId,
    String fileId,
    String fileName,
    Function(int received, int total)? onProgress,
  ) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      // Get download directory
      Directory? downloadDir;
      if (Platform.isAndroid) {
        // For Android, use Downloads directory
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          downloadDir = Directory('${directory.path}/../Download');
          if (!await downloadDir.exists()) {
            downloadDir = await getExternalStorageDirectory();
          }
        }
      } else if (Platform.isIOS) {
        // For iOS, use Documents directory
        downloadDir = await getApplicationDocumentsDirectory();
      }

      if (downloadDir == null) {
        throw Exception('Không thể truy cập thư mục lưu trữ');
      }

      // Ensure directory exists
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // Create file path
      final filePath = '${downloadDir.path}/$fileName';

      // Download file
      await client.download(
        '/contracts/$contractId/files/$fileId/download',
        filePath,
        onReceiveProgress: onProgress,
      );

      return filePath;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException downloadContractFile: ${e.message}');
      if (e.response?.statusCode == 404) {
        print('⚠️ [ContractService] File không tồn tại: $fileId');
      }
      return null;
    } catch (e) {
      print('❌ [ContractService] Lỗi downloadContractFile: $e');
      return null;
    }
  }
}

