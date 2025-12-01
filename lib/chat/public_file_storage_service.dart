import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as path;

/// Service to manage file storage in Android public directories
class PublicFileStorageService {
  static const String appFolderName = 'MyApp';

  /// Get file type from mimeType or file extension
  static String getFileType(String? mimeType, String fileName) {
    if (mimeType == null || mimeType.isEmpty) {
      final ext = path.extension(fileName).toLowerCase();
      return _getFileTypeFromExtension(ext);
    }

    if (mimeType.startsWith('image/')) {
      return 'image';
    } else if (mimeType.startsWith('video/')) {
      return 'video';
    } else if (mimeType.startsWith('audio/')) {
      return 'audio';
    } else {
      return 'document';
    }
  }

  static String _getFileTypeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
      case '.bmp':
        return 'image';
      case '.mp4':
      case '.avi':
      case '.mov':
      case '.mkv':
      case '.webm':
        return 'video';
      case '.mp3':
      case '.wav':
      case '.aac':
      case '.ogg':
      case '.m4a':
        return 'audio';
      default:
        return 'document';
    }
  }

  /// Get file extension from fileName
  static String getFileExtension(String fileName) {
    return path.extension(fileName).toLowerCase().replaceFirst('.', '');
  }

  /// Get directory path based on file type
  /// For Android 10+ (API 29+), we use app-private directories to avoid permission issues
  /// Images/videos are saved via gal package which handles MediaStore integration
  static Future<Directory> getPublicDirectory(String fileType) async {
    // Use app's documents directory for all file types
    // This avoids permission issues on Android 10+
    final documentsDir = await getApplicationDocumentsDirectory();
    final baseDir = Directory('${documentsDir.path}/chat_files');
    
    switch (fileType) {
      case 'image':
        return Directory('${baseDir.path}/images');
      case 'video':
        return Directory('${baseDir.path}/videos');
      case 'audio':
        return Directory('${baseDir.path}/audio');
      case 'document':
      default:
        return Directory('${baseDir.path}/documents');
    }
  }

  /// Check if file already exists in public directory
  static Future<String?> getExistingFilePath(String fileName, String fileType) async {
    try {
      final publicDir = await getPublicDirectory(fileType);
      if (!await publicDir.exists()) {
        return null;
      }

      final file = File('${publicDir.path}/$fileName');
      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      print('⚠️ [PublicFileStorageService] Error checking existing file: $e');
      return null;
    }
  }

  /// Save file to directory
  /// For images/videos on Android, also saves to gallery via gal package
  static Future<String> saveToPublicDirectory(
    File sourceFile,
    String fileName,
    String fileType,
  ) async {
    try {
      // For images on Android, use gal package to save directly to gallery
      // This saves to Pictures/<TênApp>/ and makes it appear in gallery
      if (Platform.isAndroid && fileType == 'image') {
        try {
          final bytes = await sourceFile.readAsBytes();
          await Gal.putImageBytes(
            bytes,
            name: fileName,
            album: appFolderName,
          );
          print('✅ [PublicFileStorageService] Saved image to gallery: $fileName');
          
          // Also save a copy to app-private directory for reference
          final storageDir = await getPublicDirectory(fileType);
          if (!await storageDir.exists()) {
            await storageDir.create(recursive: true);
          }
          final targetFile = File('${storageDir.path}/$fileName');
          await sourceFile.copy(targetFile.path);
          
          return targetFile.path; // Return local path for reference
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving to gallery: $e');
          // Fall through to regular file save
        }
      }
      
      // For videos and other files, save to app-private directory
      final storageDir = await getPublicDirectory(fileType);
      
      // Create directory if it doesn't exist
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      // Copy file to storage directory
      final targetFile = File('${storageDir.path}/$fileName');
      await sourceFile.copy(targetFile.path);

      // For videos on Android, also save to gallery using gal package
      if (Platform.isAndroid && fileType == 'video') {
        try {
          await Gal.putImageBytes(
            await targetFile.readAsBytes(),
            name: fileName,
            album: appFolderName,
          );
          print('✅ [PublicFileStorageService] Saved video to gallery: $fileName');
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving video to gallery: $e');
          // Continue even if gallery save fails - file is still saved locally
        }
      }

      return targetFile.path;
    } catch (e) {
      print('❌ [PublicFileStorageService] Error saving file: $e');
      rethrow;
    }
  }

  /// Download file from URL and save to public directory
  static Future<String> downloadAndSave(
    String fileUrl,
    String fileName,
    String fileType,
    Function(int received, int total)? onProgress,
  ) async {
    try {
      // Check if file already exists
      final existingPath = await getExistingFilePath(fileName, fileType);
      if (existingPath != null) {
        return existingPath;
      }

      // Download file to temporary location first
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      // Download using HTTP
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(fileUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Failed to download file: ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final sink = tempFile.openWrite();
      try {
        await for (final data in response) {
          sink.add(data);
          receivedBytes += data.length;
          
          if (onProgress != null && totalBytes > 0) {
            onProgress(receivedBytes, totalBytes);
          }
        }
      } finally {
        await sink.close();
      }

      // Save to public directory
      final savedPath = await saveToPublicDirectory(tempFile, fileName, fileType);

      // Delete temporary file
      try {
        await tempFile.delete();
      } catch (e) {
        print('⚠️ [PublicFileStorageService] Error deleting temp file: $e');
      }

      return savedPath;
    } catch (e) {
      print('❌ [PublicFileStorageService] Error downloading and saving: $e');
      rethrow;
    }
  }
}

