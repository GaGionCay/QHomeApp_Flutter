import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/material.dart';

/// Service để nén video xuống 720p hoặc 480p
class VideoCompressionService {
  VideoCompressionService._();
  static final VideoCompressionService instance = VideoCompressionService._();

  /// Nén video xuống 720p hoặc 480p tùy theo kích thước
  /// Nếu file > 30MB thì nén xuống 480p, ngược lại nén xuống 720p
  Future<File?> compressVideo({
    required String videoPath,
    required Function(String) onProgress,
  }) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        return null;
      }

      final fileSizeMB = await file.length() / (1024 * 1024);
      
      // Quyết định độ phân giải dựa trên kích thước file
      // Nếu > 30MB hoặc quá nặng thì dùng 480p, ngược lại dùng 720p
      final targetResolution = fileSizeMB > 30 ? 480 : 720;
      
      onProgress('Đang nén video xuống ${targetResolution}p...');

      // Nén video với chất lượng phù hợp
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoPath,
        quality: targetResolution == 480 
            ? VideoQuality.LowQuality   // 480p
            : VideoQuality.MediumQuality, // 720p
        deleteOrigin: false, // Không xóa file gốc
        includeAudio: true,
      );

      if (mediaInfo == null || mediaInfo.path == null) {
        return null;
      }

      final compressedFile = File(mediaInfo.path!);
      
      // Nếu file nén vẫn > 30MB, thử nén lại với chất lượng thấp hơn (480p)
      final compressedSizeMB = await compressedFile.length() / (1024 * 1024);
      if (compressedSizeMB > 30 && targetResolution != 480) {
        onProgress('File vẫn lớn, đang nén lại xuống 480p...');
        
        // Xóa file nén 720p
        await compressedFile.delete();
        
        // Nén lại với chất lượng thấp hơn
        final lowQualityInfo = await VideoCompress.compressVideo(
          videoPath,
          quality: VideoQuality.LowQuality, // Low quality tương đương 480p
          deleteOrigin: false,
          includeAudio: true,
        );

        if (lowQualityInfo == null || lowQualityInfo.path == null) {
          return null;
        }

        return File(lowQualityInfo.path!);
      }

      return compressedFile;
    } catch (e) {
      debugPrint('⚠️ Lỗi nén video: $e');
      return null;
    }
  }

  /// Xóa file tạm thời sau khi nén
  Future<void> deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi xóa file tạm: $e');
    }
  }
}

