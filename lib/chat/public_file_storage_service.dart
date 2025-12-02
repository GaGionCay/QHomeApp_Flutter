import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as path;

/// Service to manage file storage in Android public directories
/// Uses MediaStore API to save files to public storage (Pictures, Movies, Music, Documents)
class PublicFileStorageService {
  static const String appFolderName = 'QHomeBase';
  static const MethodChannel _mediaStoreChannel = MethodChannel('com.qhome.resident/media_store');

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

  /// Check if file already exists in MediaStore public storage
  static Future<String?> getExistingFilePath(String fileName, String fileType, [String? mimeType]) async {
    try {
      if (Platform.isAndroid) {
        // Use MediaStore API to check if file exists
        try {
          final mime = mimeType ?? getMimeTypeFromFileName(fileName);
          final exists = await _mediaStoreChannel.invokeMethod<bool>(
            'checkFileExists',
            {
              'fileName': fileName,
              'mimeType': mime,
              'fileType': fileType,
            },
          );
          
          if (exists == true) {
            // Get the URI of the existing file
            final uriString = await _mediaStoreChannel.invokeMethod<String>(
              'getFileUri',
              {
                'fileName': fileName,
                'mimeType': mime,
                'fileType': fileType,
              },
            );
            
            if (uriString != null) {
              print('✅ [PublicFileStorageService] File exists in MediaStore: $fileName -> $uriString');
              return uriString;
            }
          }
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error checking MediaStore: $e');
          // Fall through to file system check
        }
      }
      
      // Fallback: Check app documents directory
      final publicDir = await getPublicDirectory(fileType);
      if (!await publicDir.exists()) {
        return null;
      }

      final file = File('${publicDir.path}/$fileName');
      if (await file.exists()) {
        print('✅ [PublicFileStorageService] File exists in file system: ${file.path}');
        return file.path;
      }
      return null;
    } catch (e) {
      print('⚠️ [PublicFileStorageService] Error checking existing file: $e');
      return null;
    }
  }
  
  /// Get MIME type from file name extension
  static String getMimeTypeFromFileName(String fileName) {
    final ext = path.extension(fileName).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.mp4':
        return 'video/mp4';
      case '.avi':
        return 'video/x-msvideo';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.webm':
        return 'video/webm';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.m4a':
        return 'audio/mp4';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.ppt':
        return 'application/vnd.ms-powerpoint';
      case '.pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case '.txt':
        return 'text/plain';
      case '.zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Save file to public directory using MediaStore API
  /// - Images -> Pictures/QHomeBase (via MediaStore)
  /// - Videos -> Movies/QHomeBase (via MediaStore)
  /// - Audio -> Music/Recordings (via MediaStore)
  /// - Documents -> Documents/QHomeBase (via MediaStore)
  static Future<String> saveToPublicDirectory(
    File sourceFile,
    String fileName,
    String fileType,
    String? mimeType,
  ) async {
    try {
      if (Platform.isAndroid) {
        // Use MediaStore API to save to public storage
        try {
          final mime = mimeType ?? getMimeTypeFromFileName(fileName);
          
          // Save to MediaStore using platform channel
          final uriString = await _mediaStoreChannel.invokeMethod<String>(
            'saveFileToMediaStore',
            {
              'filePath': sourceFile.path,
              'fileName': fileName,
              'mimeType': mime,
              'fileType': fileType,
            },
          );
          
          if (uriString != null && uriString.isNotEmpty) {
            print('✅ [PublicFileStorageService] Saved $fileType to MediaStore: $fileName -> $uriString');
            
            // For images, also use gal package as fallback/backup
            if (fileType == 'image') {
              try {
                final bytes = await sourceFile.readAsBytes();
                await Gal.putImageBytes(
                  bytes,
                  name: fileName,
                  album: appFolderName,
                );
                print('✅ [PublicFileStorageService] Also saved image via gal package');
              } catch (e) {
                print('⚠️ [PublicFileStorageService] Error saving image via gal: $e');
              }
            }
            
            // Return MediaStore URI as string (can be used to open file)
            return uriString;
          }
        } catch (e) {
          print('⚠️ [PublicFileStorageService] Error saving to MediaStore: $e');
          // Fall through to fallback methods
        }
        
        // Fallback for images: use gal package
        if (fileType == 'image') {
          try {
            final bytes = await sourceFile.readAsBytes();
            await Gal.putImageBytes(
              bytes,
              name: fileName,
              album: appFolderName,
            );
            print('✅ [PublicFileStorageService] Saved image via gal package (fallback): $fileName');
            return sourceFile.path;
          } catch (e) {
            print('⚠️ [PublicFileStorageService] Error saving image via gal: $e');
          }
        }
      }
      
      // Final fallback: save to app-private directory
      final storageDir = await getPublicDirectory(fileType);
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      final targetFile = File('${storageDir.path}/$fileName');
      await sourceFile.copy(targetFile.path);
      print('✅ [PublicFileStorageService] Saved file to app directory (fallback): ${targetFile.path}');

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
      final existingPath = await getExistingFilePath(fileName, fileType, mimeType);
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
