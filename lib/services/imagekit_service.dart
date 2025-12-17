import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/api_client.dart';
import '../core/logger.dart';

/// Service for uploading images/files to ImageKit via backend API
class ImageKitService {
  final ApiClient apiClient;
  
  ImageKitService(this.apiClient);

  Future<Dio> _getDio() async {
    // Use data-docs-service base URL for ImageKit uploads
    final baseUrl = ApiClient.buildServiceBase(port: 8082, path: '/api');
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 120), // Longer timeout for uploads
      receiveTimeout: const Duration(seconds: 180),
      sendTimeout: const Duration(seconds: 180),
    ));
    
    // Add auth token
    final token = await apiClient.storage.readAccessToken();
    if (token != null) {
      dio.options.headers['Authorization'] = 'Bearer $token';
    }
    
    return dio;
  }

  /// Upload a single image/file to ImageKit
  /// 
  /// [file] - The file to upload (XFile or File)
  /// [folder] - Optional folder path in ImageKit (e.g., "household", "vehicle", "chat")
  /// Returns the URL of the uploaded file
  Future<String> uploadImage({
    required dynamic file, // XFile or File
    String? folder,
  }) async {
    try {
      AppLogger.debug('[ImageKitService] Uploading image to folder: $folder');
      
      final filePath = file is XFile ? file.path : (file as File).path;
      final fileName = file is XFile ? file.name : (file as File).path.split('/').last;
      
      final dio = await _getDio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        if (folder != null && folder.isNotEmpty) 'folder': folder,
      });

      final response = await dio.post(
        '/imagekit/upload',
        data: formData,
      );

      if (response.statusCode == 201 && response.data['url'] != null) {
        final imageUrl = response.data['url'] as String;
        AppLogger.success('[ImageKitService] ✅ Image uploaded successfully: $imageUrl');
        return imageUrl;
      } else {
        final errorMsg = response.data['error']?.toString() ?? 'Response không có URL';
        AppLogger.error('[ImageKitService] ❌ Upload failed: $errorMsg');
        throw Exception('Lỗi khi upload image: $errorMsg');
      }
    } on DioException catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi khi upload image', e);
      
      // Xử lý lỗi 500 từ server
      if (e.response?.statusCode == 500) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                       e.response?.data?.toString() ?? 
                       'Lỗi server (500) - Vui lòng thử lại sau';
        throw Exception('Lỗi server khi upload: $errorMsg');
      }
      
      // Xử lý các lỗi khác
      if (e.response != null) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                        e.response?.data?.toString() ?? 
                        'Lỗi không xác định';
        throw Exception('Lỗi khi upload image: $errorMsg');
      }
      
      // Lỗi network hoặc timeout
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw Exception('Kết nối quá chậm. Vui lòng kiểm tra kết nối mạng và thử lại.');
      }
      
      throw Exception('Lỗi khi upload image: ${e.message ?? e.toString()}');
    } catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi không mong đợi khi upload image', e);
      throw Exception('Lỗi khi upload image: ${e.toString()}');
    }
  }

  /// Upload multiple images/files to ImageKit
  /// 
  /// [files] - List of files to upload (XFile or File)
  /// [folder] - Optional folder path in ImageKit
  /// Returns list of URLs of uploaded files
  Future<List<String>> uploadImages({
    required List<dynamic> files, // List<XFile> or List<File>
    String? folder,
  }) async {
    try {
      AppLogger.debug('[ImageKitService] Uploading ${files.length} images to folder: $folder');
      
      final dio = await _getDio();
      final formData = FormData();
      
      for (final file in files) {
        final filePath = file is XFile ? file.path : (file as File).path;
        final fileName = file is XFile ? file.name : (file as File).path.split('/').last;
        formData.files.add(
          MapEntry(
            'files',
            await MultipartFile.fromFile(filePath, filename: fileName),
          ),
        );
      }
      
      if (folder != null && folder.isNotEmpty) {
        formData.fields.add(MapEntry('folder', folder));
      }

      final response = await dio.post(
        '/imagekit/upload-multiple',
        data: formData,
      );

      if (response.statusCode == 201 && response.data['urls'] != null) {
        final urls = List<String>.from(response.data['urls'] as List);
        AppLogger.success('[ImageKitService] ✅ Uploaded ${urls.length} images successfully');
        return urls;
      } else {
        final errorMsg = response.data['error']?.toString() ?? 'Response không có URLs';
        AppLogger.error('[ImageKitService] ❌ Upload failed: $errorMsg');
        throw Exception('Lỗi khi upload images: $errorMsg');
      }
    } on DioException catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi khi upload images', e);
      
      // Xử lý lỗi 500 từ server
      if (e.response?.statusCode == 500) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                       e.response?.data?.toString() ?? 
                       'Lỗi server (500) - Vui lòng thử lại sau';
        throw Exception('Lỗi server khi upload: $errorMsg');
      }
      
      // Xử lý các lỗi khác
      if (e.response != null) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                        e.response?.data?.toString() ?? 
                        'Lỗi không xác định';
        throw Exception('Lỗi khi upload images: $errorMsg');
      }
      
      // Lỗi network hoặc timeout
      if (e.type == DioExceptionType.connectionTimeout || 
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw Exception('Kết nối quá chậm. Vui lòng kiểm tra kết nối mạng và thử lại.');
      }
      
      throw Exception('Lỗi khi upload images: ${e.message ?? e.toString()}');
    } catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi không mong đợi khi upload images', e);
      throw Exception('Lỗi khi upload images: ${e.toString()}');
    }
  }

  /// Upload a video file to backend (NOT ImageKit - videos are self-hosted)
  /// 
  /// NOTE: This method uploads to backend /api/videos/upload endpoint.
  /// Videos are NEVER uploaded to ImageKit - only images use ImageKit.
  /// 
  /// [file] - The video file to upload (XFile or File)
  /// [category] - Category of video: 'repair_request', 'marketplace_post', 'direct_chat', 'group_chat', 'marketplace_comment'
  /// [ownerId] - Optional ID of the entity that owns the video (post_id, conversation_id, group_id, request_id)
  /// [uploadedBy] - ID of the user uploading the video
  /// [resolution] - Optional video resolution (e.g., '480p', '360p')
  /// [durationSeconds] - Optional video duration in seconds
  /// [width] - Optional video width in pixels
  /// [height] - Optional video height in pixels
  /// Returns the video URL and metadata (URL points to backend stream endpoint)
  Future<Map<String, dynamic>> uploadVideo({
    required dynamic file, // XFile or File
    required String category,
    String? ownerId,
    required String uploadedBy,
    String? resolution,
    int? durationSeconds,
    int? width,
    int? height,
  }) async {
    try {
      // Minimal logging - only log errors
      // Video uploads are frequent, don't spam logs
      
      final filePath = file is XFile ? file.path : (file as File).path;
      final fileName = file is XFile ? file.name : (file as File).path.split('/').last;
      
      final dio = await _getDio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
        'category': category,
        'uploadedBy': uploadedBy,
        if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
        if (resolution != null && resolution.isNotEmpty) 'resolution': resolution,
        if (durationSeconds != null) 'durationSeconds': durationSeconds.toString(),
        if (width != null) 'width': width.toString(),
        if (height != null) 'height': height.toString(),
      });

      final response = await dio.post(
        '/videos/upload',
        data: formData,
      );

      if (response.statusCode == 201 && response.data != null) {
        final videoData = response.data as Map<String, dynamic>;
        final videoUrl = videoData['fileUrl'] as String;
        // Success - no logging needed (too frequent)
        return videoData;
      } else {
        final errorMsg = response.data?['error']?.toString() ?? 'Response không có dữ liệu';
        AppLogger.error('[ImageKitService] ❌ Upload failed: $errorMsg');
        throw Exception('Lỗi khi upload video: $errorMsg');
      }
    } on DioException catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi khi upload video', e);
      
      // Xử lý lỗi 500 từ server
      if (e.response?.statusCode == 500) {
        final errorMsg = e.response?.data?['error']?.toString() ?? 
                       e.response?.data?.toString() ?? 
                       'Lỗi server (500) - Vui lòng thử lại sau';
        throw Exception('Lỗi server khi upload: $errorMsg');
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
        throw Exception('Kết nối quá chậm. Vui lòng kiểm tra kết nối mạng và thử lại.');
      }
      
      throw Exception('Lỗi khi upload video: ${e.message ?? e.toString()}');
    } catch (e) {
      AppLogger.error('[ImageKitService] ❌ Lỗi không mong đợi khi upload video', e);
      throw Exception('Lỗi khi upload video: ${e.toString()}');
    }
  }
}

