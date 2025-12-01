import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as path;

/// Service to manage file storage in Android public directories
class PublicFileStorageService {
  static const String appFolderName = 'QHomeBase';

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

  /// Get Android app documents directory (accessible without special permissions)
  /// This directory is in /storage/emulated/0/Android/data/<package>/files/Documents
  /// Files here can be accessed via file manager and opened by other apps
  static Future<Directory> getAndroidAppDocumentsDirectory() async {
    if (Platform.isAndroid) {
      // Use getExternalStorageDirectory which gives us app-private external storage
      // This is accessible without MANAGE_EXTERNAL_STORAGE permission
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final documentsDir = Directory('${externalDir.path}/Documents');
        if (!await documentsDir.exists()) {
          await documentsDir.create(recursive: true);
        }
        return documentsDir;
      }
    }
    
    // Fallback to app documents directory
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir;
  }

  /// Get public directory based on file type
  /// For Android: uses app documents directory (accessible without special permissions)
  /// For images/videos: uses gal package to save to gallery
  static Future<Directory> getPublicDirectory(String fileType) async {
    if (Platform.isAndroid) {
      // Use app documents directory for all file types
      // This is accessible via file manager without MANAGE_EXTERNAL_STORAGE permission
      return await getAndroidAppDocumentsDirectory();
    }

    // Fallback to app documents directory
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir;
  }

  /// Check if file already exists in public directory
  static Future<String?> getExistingFilePath(String fileName, String fileType) async {
    try {
      // Check app documents directory
      final publicDir = await getPublicDirectory(fileType);
      if (!await publicDir.exists()) {
        return null;
      }

      final file = File('${publicDir.path}/$fileName');
      if (await file.exists()) {
        print('✅ [PublicFileStorageService] File exists: ${file.path}');
        return file.path;
      }
      return null;
    } catch (e) {
      print('⚠️ [PublicFileStorageService] Error checking existing file: $e');
      return null;
    }
  }

  /// Save file to public directory
  /// For images/videos on Android, uses gal package to save to gallery
  /// For documents on Android, saves to Download directory
  static Future<String> saveToPublicDirectory(
    File sourceFile,
    String fileName,
    String fileType,
    String? mimeType,
  ) async {
    try {
      // For images on Android, use gal package to save directly to gallery
      if (Platform.isAndroid && fileType == 'image') {
        try {
          final bytes = await sourceFile.readAsBytes();
          await Gal.putImageBytes(
            bytes,
            name: fileName,
            album: appFolderName,
          );
          print('✅ [PublicFileStorageService] Saved image to gallery: $fileName');
          
          // Also save a copy to app documents directory for easy access
          final documentsDir = await getAndroidAppDocumentsDirectory();
          try {
            final documentsFile = File('${documentsDir.path}/$fileName');
            await sourceFile.copy(documentsFile.path);
            print('✅ [PublicFileStorageService] Also saved image to Documents: ${documentsFile.path}');
            return documentsFile.path;
          } catch (e) {
            print('⚠️ [PublicFileStorageService] Error saving image to Documents: $e');
          }
          
          // Return gallery path reference
          return sourceFile.path;
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving to gallery: $e');
          // Fall through to regular file save
        }
      }

      // For videos on Android, use gal package
      if (Platform.isAndroid && fileType == 'video') {
        try {
          final bytes = await sourceFile.readAsBytes();
          await Gal.putImageBytes(
            bytes,
            name: fileName,
            album: appFolderName,
          );
          print('✅ [PublicFileStorageService] Saved video to gallery: $fileName');
          
          // Also save to app documents directory
          final documentsDir = await getAndroidAppDocumentsDirectory();
          try {
            final documentsFile = File('${documentsDir.path}/$fileName');
            await sourceFile.copy(documentsFile.path);
            print('✅ [PublicFileStorageService] Also saved video to Documents: ${documentsFile.path}');
            return documentsFile.path;
          } catch (e) {
            print('⚠️ [PublicFileStorageService] Error saving video to Documents: $e');
          }
          
          return sourceFile.path;
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving video to gallery: $e');
          // Fall through to regular file save
        }
      }

      // For documents and audio files on Android, save to app documents directory
      // This is accessible via file manager without special permissions
      if (Platform.isAndroid && (fileType == 'document' || fileType == 'audio')) {
        final documentsDir = await getAndroidAppDocumentsDirectory();
        try {
          final documentsFile = File('${documentsDir.path}/$fileName');
          await sourceFile.copy(documentsFile.path);
          print('✅ [PublicFileStorageService] Saved $fileType to Documents: ${documentsFile.path}');
          return documentsFile.path;
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving $fileType to Documents: $e');
          // Fall through to app directory
        }
      }
      
      // Fallback: save to app-private directory
      final storageDir = await getPublicDirectory(fileType);
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      final targetFile = File('${storageDir.path}/$fileName');
      await sourceFile.copy(targetFile.path);
      print('✅ [PublicFileStorageService] Saved file to app directory: ${targetFile.path}');

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
    String? mimeType,
    Function(int received, int total)? onProgress,
  ) async {
    try {
      // Check if file already exists
      final existingPath = await getExistingFilePath(fileName, fileType);
      if (existingPath != null) {
        print('✅ [PublicFileStorageService] File already exists: $existingPath');
        return existingPath;
      }

      print('📥 [PublicFileStorageService] Downloading file: $fileName from $fileUrl');

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

      print('✅ [PublicFileStorageService] Downloaded file to temp: ${tempFile.path}');

      // Save to public directory
      final savedPath = await saveToPublicDirectory(tempFile, fileName, fileType, mimeType);

      // Delete temporary file
      try {
        await tempFile.delete();
      } catch (e) {
        print('⚠️ [PublicFileStorageService] Error deleting temp file: $e');
      }

      print('✅ [PublicFileStorageService] File saved to: $savedPath');
      return savedPath;
    } catch (e) {
      print('❌ [PublicFileStorageService] Error downloading and saving: $e');
      rethrow;
    }
  }
}
