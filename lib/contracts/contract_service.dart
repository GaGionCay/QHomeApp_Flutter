import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
    // Gateway routes /api/contracts/** directly to data-docs-service (8082)
    // Note: ApiClient.activeBaseUrl already includes /api
    // So we use activeBaseUrl directly (no need for /data-docs prefix)
    final baseUrl = ApiClient.activeBaseUrl;
    return Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
      receiveTimeout: const Duration(seconds: ApiClient.timeoutSeconds),
    ));
  }

  Future<List<UnitInfo>> getMyUnits({int retryCount = 0}) async {
    try {
      // Add small delay on retry to allow token refresh to complete
      if (retryCount > 0) {
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
      
      // Explicitly add Authorization header (same as other methods in this service)
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        apiClient.dio.options.headers['Authorization'] = 'Bearer $token';
        print('✅ [ContractService] getMyUnits: Token found, length: ${token.length}');
      } else {
        print('⚠️ [ContractService] getMyUnits: No access token available');
        // Don't proceed without token - will result in 401/403
        throw Exception('No access token available. Please login again.');
      }
      
      print('🔍 [ContractService] getMyUnits: Calling /residents/my-units');
      final response = await apiClient.dio.get('/residents/my-units');
      if (response.data is List) {
        return (response.data as List)
            .map((item) => UnitInfo.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      
      // Handle 401 Unauthorized - token expired and no refresh token
      if (statusCode == 401) {
        print('⚠️ [ContractService] getMyUnits: 401 Unauthorized - Token expired');
        print('⚠️ [ContractService] User needs to login again');
        // Don't return empty list - rethrow to let caller handle
        // This allows the app to show proper error or redirect to login
        rethrow;
      }
      
      // Handle 403 Forbidden - user doesn't have permission
      // Sometimes 403 can occur if token is being refreshed - retry once
      if (statusCode == 403) {
        print('⚠️ [ContractService] getMyUnits: 403 Forbidden - User does not have permission');
        print('⚠️ [ContractService] Response data: ${e.response?.data}');
        
        // Retry once if this is the first attempt (might be token refresh timing issue)
        if (retryCount == 0) {
          print('🔄 [ContractService] Retrying getMyUnits after 403...');
          return getMyUnits(retryCount: 1);
        }
        
        print('⚠️ [ContractService] User may not have access to this resource after retry');
        // Rethrow to let caller handle - this is an authorization issue
        rethrow;
      }
      
      print('❌ [ContractService] DioException getMyUnits: ${e.message}');
      if (e.response != null) {
        print('❌ [ContractService] Response status: ${e.response?.statusCode}');
        print('❌ [ContractService] Response data: ${e.response?.data}');
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

      // Note: On Android 10+, we don't need storage permission for app-specific directories
      // We'll use app-specific directory which doesn't require any permission
      // Only log permission status for debugging, but don't block the download
      if (Platform.isAndroid) {
        try {
          final status = await Permission.storage.status;
          if (status.isGranted) {
            print('✅ [ContractService] Storage permission granted');
          } else {
            print('⚠️ [ContractService] Storage permission not granted, will use app-specific directory (no permission needed)');
          }
        } catch (e) {
          // Permission handler might not be available (MissingPluginException)
          // This is fine - we'll use app-specific directory which doesn't need permission
          print('⚠️ [ContractService] Could not check permission status, using app-specific directory: $e');
        }
      }

      // Get download directory
      Directory? downloadDir;
      if (Platform.isAndroid) {
        // For Android 10+, prefer app-specific directory (no permission needed)
        // This works even if permission_handler is not available
        try {
          // Try app-specific external storage first (no permission needed on Android 10+)
          final appDir = await getExternalStorageDirectory();
          if (appDir != null) {
            // Create Download subdirectory in app-specific storage
            downloadDir = Directory('${appDir.path}/Download');
            if (!await downloadDir.exists()) {
              await downloadDir.create(recursive: true);
            }
            print('✅ [ContractService] Using app-specific Download directory: ${downloadDir.path}');
          } else {
            // Fallback to public Downloads (requires permission)
            try {
              final directory = await getExternalStorageDirectory();
              if (directory != null) {
                final downloadsPath = '${directory.path.split('/Android')[0]}/Download';
                downloadDir = Directory(downloadsPath);
                if (!await downloadDir.exists()) {
                  await downloadDir.create(recursive: true);
                }
                print('✅ [ContractService] Using public Download directory: ${downloadDir.path}');
              }
            } catch (e) {
              print('⚠️ [ContractService] Could not access public Downloads: $e');
            }
          }
        } catch (e) {
          print('⚠️ [ContractService] Could not access external storage, using app directory: $e');
          downloadDir = await getApplicationDocumentsDirectory();
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

      // Sanitize fileName to remove invalid characters
      String sanitizedFileName = fileName
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
          .replaceAll(RegExp(r'\s+'), '_');

      // Create file path
      final filePath = '${downloadDir.path}/$sanitizedFileName';

      // Check if file already exists and add number suffix if needed
      String finalFilePath = filePath;
      int counter = 1;
      while (await File(finalFilePath).exists()) {
        final extension = sanitizedFileName.substring(sanitizedFileName.lastIndexOf('.'));
        final nameWithoutExt = sanitizedFileName.substring(0, sanitizedFileName.lastIndexOf('.'));
        final newFileName = '${nameWithoutExt}_$counter$extension';
        finalFilePath = '${downloadDir.path}/$newFileName';
        counter++;
      }

      // Download file
      await client.download(
        '/contracts/$contractId/files/$fileId/download',
        finalFilePath,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          validateStatus: (status) => status! < 500,
        ),
      );

      print('✅ [ContractService] File downloaded to: $finalFilePath');

      // If file is an image, save to gallery (Android/iOS)
      final isImage = _isImageFile(fileName);
      if (isImage && Platform.isAndroid) {
        try {
          // Request photos permission for Android 13+
          if (await Permission.photos.isGranted || 
              await Permission.storage.isGranted) {
            await Gal.putImage(finalFilePath);
            print('✅ [ContractService] Image saved to gallery');
          } else {
            // Try to request permission
            final photosStatus = await Permission.photos.request();
            final storageStatus = await Permission.storage.request();
            if (photosStatus.isGranted || storageStatus.isGranted) {
              await Gal.putImage(finalFilePath);
              print('✅ [ContractService] Image saved to gallery');
            } else {
              print('⚠️ [ContractService] Photos permission not granted, image saved to app directory only');
            }
          }
        } catch (e) {
          // If gal package fails, file is still downloaded, just not in gallery
          print('⚠️ [ContractService] Could not save image to gallery: $e');
        }
      } else if (isImage && Platform.isIOS) {
        try {
          await Gal.putImage(finalFilePath);
          print('✅ [ContractService] Image saved to gallery');
        } catch (e) {
          print('⚠️ [ContractService] Could not save image to gallery: $e');
        }
      }

      return finalFilePath;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException downloadContractFile: ${e.message}');
      if (e.response?.statusCode == 404) {
        print('⚠️ [ContractService] File không tồn tại: $fileId');
        throw Exception('File không tồn tại');
      }
      throw Exception('Lỗi tải file: ${e.message}');
    } catch (e) {
      print('❌ [ContractService] Lỗi downloadContractFile: $e');
      throw Exception('Lỗi tải file: $e');
    }
  }

  bool _isImageFile(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif']
        .contains(extension);
  }

  /// Get contracts that need to show popup to resident (renewal reminders)
  Future<List<ContractDto>> getContractsNeedingPopup(String unitId) async {
    try {
      print('🔍 [ContractService] getContractsNeedingPopup called with unitId: $unitId');
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final url = '/contracts/unit/$unitId/popup';
      print('🔍 [ContractService] Calling API: ${client.options.baseUrl}$url');
      
      final response = await client.get(url);
      print('✅ [ContractService] API response status: ${response.statusCode}');
      print('✅ [ContractService] API response data: ${response.data}');
      
      if (response.statusCode != 200) {
        print('⚠️ [ContractService] API trả mã ${response.statusCode}: ${response.data}');
        return [];
      }

      if (response.data is List) {
        final contracts = (response.data as List)
            .map((item) => ContractDto.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
        print('✅ [ContractService] Parsed ${contracts.length} contract(s) from response');
        return contracts;
      }

      print('⚠️ [ContractService] Response data is not a List: ${response.data.runtimeType}');
      return [];
    } on DioException catch (e) {
      print('❌ [ContractService] DioException getContractsNeedingPopup: ${e.message}');
      print('❌ [ContractService] DioException response: ${e.response?.data}');
      print('❌ [ContractService] DioException request: ${e.requestOptions.uri}');
      return [];
    } catch (e) {
      print('❌ [ContractService] Lỗi getContractsNeedingPopup: $e');
      print('❌ [ContractService] Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  /// Get active contracts for a unit
  Future<List<ContractDto>> getActiveContractsByUnit(String unitId) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final response = await client.get('/contracts/unit/$unitId/active');
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
      print('❌ [ContractService] DioException getActiveContractsByUnit: ${e.message}');
      return [];
    } catch (e) {
      print('❌ [ContractService] Lỗi getActiveContractsByUnit: $e');
      return [];
    }
  }

  /// Create payment URL for contract renewal
  Future<Map<String, dynamic>?> createRenewalPaymentUrl({
    required String contractId,
    required DateTime startDate,
    required DateTime endDate,
    String? createdBy,
  }) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final requestBody = {
        'contractId': contractId,
        'startDate': startDate.toIso8601String().split('T')[0],
        'endDate': endDate.toIso8601String().split('T')[0],
      };

      final queryParams = createdBy != null ? '?createdBy=$createdBy' : '';
      final response = await client.post(
        '/contracts/$contractId/renew/payment$queryParams',
        data: requestBody,
      );

      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }

      return null;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException createRenewalPaymentUrl: ${e.message}');
      if (e.response != null) {
        print('⚠️ Response: ${e.response?.data}');
      }
      return null;
    } catch (e) {
      print('❌ [ContractService] Lỗi createRenewalPaymentUrl: $e');
      return null;
    }
  }

  /// Cancel contract
  Future<ContractDto?> cancelContract(String contractId, {String? updatedBy}) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final queryParams = updatedBy != null ? '?updatedBy=$updatedBy' : '';
      final response = await client.put('/contracts/$contractId/cancel$queryParams');

      if (response.statusCode == 200 && response.data is Map) {
        return ContractDto.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      return null;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException cancelContract: ${e.message}');
      return null;
    } catch (e) {
      print('❌ [ContractService] Lỗi cancelContract: $e');
      return null;
    }
  }

  /// Complete contract renewal after payment
  Future<ContractDto?> completeRenewalPayment({
    required String contractId,
    required String residentId,
    String? vnpayTransactionRef,
  }) async {
    try {
      final client = _contractsClient();
      final token = await apiClient.storage.readAccessToken();
      if (token != null) {
        client.options.headers['Authorization'] = 'Bearer $token';
      }

      final queryParams = '?residentId=$residentId${vnpayTransactionRef != null ? '&vnpayTransactionRef=$vnpayTransactionRef' : ''}';
      final response = await client.post('/contracts/$contractId/renew/complete$queryParams');

      if (response.statusCode == 200 && response.data is Map) {
        return ContractDto.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      return null;
    } on DioException catch (e) {
      print('❌ [ContractService] DioException completeRenewalPayment: ${e.message}');
      return null;
    } catch (e) {
      print('❌ [ContractService] Lỗi completeRenewalPayment: $e');
      return null;
    }
  }
}

