import 'dart:io';
import 'package:dio/dio.dart';
import '../auth/api_client.dart';
import '../core/logger.dart';

/// Service for uploading videos to backend VideoStorageService
/// NO LONGER USES IMAGEKIT - videos now stored in backend data-docs-service
class VideoUploadService {
  final ApiClient apiClient;
  
  VideoUploadService(this.apiClient);

  Future<Dio> _getDio() async {
    // Use data-docs-service base URL for video uploads
    final baseUrl = ApiClient.buildServiceBase(port: 8082);
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 180), // Long timeout for video uploads
      receiveTimeout: const Duration(seconds: 240),
      sendTimeout: const Duration(seconds: 240),
    ));
    
    // Add auth token
    final token = await apiClient.storage.readAccessToken();
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
    
    return dio;
  }

  /// Upload a video file to backend VideoStorageService
  /// 
  /// [file] - The video file to upload (File or path string)
  /// [category] - Category of the video (e.g., "chat_message", "marketplace_post", "repair_request")
  /// [ownerId] - Optional owner ID (e.g., post ID, message ID)
  /// [uploadedBy] - User ID who uploaded the video
  /// 
  /// Returns a Map containing:
  /// - videoId: UUID of the uploaded video
  /// - streamingUrl: URL to stream the video
  /// - fileUrl: Full file URL (same as streamingUrl)
  Future<Map<String, dynamic>> uploadVideo({
    required dynamic file, // File or String path
    required String category,
    String? ownerId,
    String? uploadedBy,
    int? durationSeconds,
    int? width,
    int? height,
    String? resolution,
  }) async {
    try {
      AppLogger.debug('[VideoUploadService] Uploading video: category=$category, ownerId=$ownerId');
      
      final filePath = file is File ? file.path : file.toString();
      final fileName = filePath.split('/').last;
      
      final dio = await _getDio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'category': category,
        if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
        if (uploadedBy != null && uploadedBy.isNotEmpty) 'uploadedBy': uploadedBy,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (resolution != null) 'resolution': resolution,
      });

      final response = await dio.post(
        '/videos/upload',
        data: formData,
      );

      if (response.statusCode == 201 && response.data != null) {
        // Backend returns 'id' not 'videoId'
        final videoId = response.data['id'] as String?;
        final fileUrl = response.data['fileUrl'] as String?;
        
        if (videoId == null || fileUrl == null) {
          AppLogger.error('[VideoUploadService] ❌ Response thiếu id hoặc fileUrl. Response: ${response.data}');
          throw Exception('Response thiếu id hoặc fileUrl');
        }
        
        // Backend returns fileUrl as relative path: /api/videos/stream/{videoId}
        // Normalize it to use API Gateway base URL (not direct service URL)
        // This ensures ExoPlayer can load the video correctly
        String normalizedUrl = fileUrl;
        if (normalizedUrl.startsWith('/api/')) {
          // fileUrl is /api/videos/stream/{videoId}
          // buildServiceBase() returns base URL with /api already included
          // So we need to remove /api from fileUrl and prepend base URL
          final apiGatewayBase = ApiClient.buildServiceBase();
          final pathWithoutApi = normalizedUrl.substring(4); // Remove /api prefix
          normalizedUrl = '$apiGatewayBase$pathWithoutApi';
        } else if (normalizedUrl.startsWith('/')) {
          // Already relative but doesn't start with /api, prepend API Gateway base
          final apiGatewayBase = ApiClient.buildServiceBase();
          normalizedUrl = '$apiGatewayBase$normalizedUrl';
        }
        
        AppLogger.success('[VideoUploadService] ✅ Video uploaded successfully: videoId=$videoId, streamingUrl=$normalizedUrl');
        
        return {
          'videoId': videoId,
          'streamingUrl': normalizedUrl,
          'fileUrl': fileUrl, // Keep original relative path for reference
          'url': normalizedUrl,  // For backward compatibility
        };
      } else {
        final errorMsg = response.data?['error']?.toString() ?? 'Response không hợp lệ';
        AppLogger.error('[VideoUploadService] ❌ Upload failed: $errorMsg');
        throw Exception('Lỗi khi upload video: $errorMsg');
      }
    } on DioException catch (e) {
      AppLogger.error('[VideoUploadService] ❌ Lỗi khi upload video', e);
      
      // Xử lý lỗi 500 từ server
      if (e.response?.statusCode == 500) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                       e.response?.data?.toString() ?? 
                       'Lỗi server (500) - Vui lòng thử lại sau';
        throw Exception('Lỗi server khi upload video: $errorMsg');
      }
      
      // Xử lý các lỗi khác
      if (e.response != null) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                        e.response?.data?.toString() ?? 
                        'Lỗi không xác định';
        throw Exception('Lỗi khi upload video: $errorMsg');
      }
      
      // Lỗi network hoặc timeout
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw Exception('Kết nối quá chậm. Video quá lớn hoặc mạng chậm. Vui lòng thử lại.');
      }
      
      throw Exception('Lỗi khi upload video: ${e.message ?? e.toString()}');
    } catch (e) {
      AppLogger.error('[VideoUploadService] ❌ Lỗi không mong đợi khi upload video', e);
      throw Exception('Lỗi khi upload video: ${e.toString()}');
    }
  }

  /// Get video streaming URL from videoId
  /// Uses API Gateway base URL (not direct service URL) to ensure ExoPlayer can load videos
  String getStreamingUrl(String videoId) {
    // Use API Gateway base URL and construct relative path
    final apiGatewayBase = ApiClient.buildServiceBase();
    return '$apiGatewayBase/videos/stream/$videoId';
  }
}

