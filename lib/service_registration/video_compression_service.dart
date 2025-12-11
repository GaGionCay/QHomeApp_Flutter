import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:flutter/material.dart';

/// Service để nén video xuống 720p hoặc 480p và xử lý rotation
class VideoCompressionService {
  VideoCompressionService._();
  static final VideoCompressionService instance = VideoCompressionService._();

  /// Nén video xuống 720p hoặc 480p tùy theo kích thước
  /// Nếu file > 30MB thì nén xuống 480p, ngược lại nén xuống 720p
  /// Tự động xử lý rotation nếu video bị nghiêng
  Future<File?> compressVideo({
    required String videoPath,
    required Function(String) onProgress,
  }) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) {
        return null;
      }

      // Kiểm tra rotation metadata của video gốc
      onProgress('Đang kiểm tra video...');
      final originalMediaInfo = await VideoCompress.getMediaInfo(videoPath);
      final hasRotation = originalMediaInfo?.orientation != null && 
                         originalMediaInfo!.orientation != 0;
      
      if (hasRotation) {
        debugPrint('📹 Video có rotation: ${originalMediaInfo.orientation}°');
        onProgress('Đang xử lý video bị nghiêng...');
      }

      final fileSizeMB = await file.length() / (1024 * 1024);
      
      // Quyết định độ phân giải dựa trên kích thước file
      // Giảm độ phân giải để tiết kiệm dung lượng: > 20MB thì dùng 360p, ngược lại dùng 480p
      final targetResolution = fileSizeMB > 20 ? 360 : 480;
      
      onProgress('Đang nén video xuống ${targetResolution}p${hasRotation ? ' và sửa rotation' : ''}...');

      // Nén video với chất lượng phù hợp
      // VideoCompress sẽ tự động xử lý rotation khi nén
      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoPath,
        quality: targetResolution == 360 
            ? VideoQuality.DefaultQuality   // 360p (lowest quality)
            : VideoQuality.LowQuality, // 480p
        deleteOrigin: false, // Không xóa file gốc
        includeAudio: true,
        frameRate: 24, // Giảm frame rate xuống 24fps để tiết kiệm dung lượng
      );

      if (mediaInfo == null || mediaInfo.path == null) {
        return null;
      }

      final compressedFile = File(mediaInfo.path!);
      
      // Kiểm tra rotation của video đã nén
      final compressedMediaInfo = await VideoCompress.getMediaInfo(compressedFile.path);
      if (compressedMediaInfo?.orientation != null && 
          compressedMediaInfo!.orientation != 0) {
        debugPrint('⚠️ Video đã nén vẫn có rotation: ${compressedMediaInfo.orientation}°');
        // VideoCompress đã xử lý rotation trong quá trình nén, nhưng metadata có thể vẫn còn
        // Điều này thường không ảnh hưởng đến playback vì rotation đã được apply vào video
      }
      
      // Nếu file nén vẫn > 30MB, thử nén lại với chất lượng thấp hơn (360p)
      final compressedSizeMB = await compressedFile.length() / (1024 * 1024);
      if (compressedSizeMB > 30 && targetResolution != 360) {
        onProgress('File vẫn lớn, đang nén lại xuống 360p...');
        
        // Xóa file nén 480p
        await compressedFile.delete();
        
        // Nén lại với chất lượng thấp hơn
        final lowQualityInfo = await VideoCompress.compressVideo(
          videoPath,
          quality: VideoQuality.DefaultQuality, // Default quality tương đương 360p
          deleteOrigin: false,
          includeAudio: true,
          frameRate: 24, // Giảm frame rate xuống 24fps
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


