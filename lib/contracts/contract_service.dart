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
}

