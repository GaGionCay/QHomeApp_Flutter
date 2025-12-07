import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage local file paths for sent messages
class MessageLocalPathService {
  static const String _keyPrefix = 'message_local_path_';
  static const String _fileTypePrefix = 'message_file_type_';
  static const String _fileExtensionPrefix = 'message_file_extension_';

  /// Save local path for a message (when user sends a file)
  static Future<void> saveLocalPath(
    String messageId,
    String localPath,
    String? fileType,
    String? fileExtension,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$messageId', localPath);
      if (fileType != null) {
        await prefs.setString('$_fileTypePrefix$messageId', fileType);
      }
      if (fileExtension != null) {
        await prefs.setString('$_fileExtensionPrefix$messageId', fileExtension);
      }
    } catch (e) {
      print('⚠️ [MessageLocalPathService] Error saving local path: $e');
    }
  }

  /// Get local path for a message
  static Future<String?> getLocalPath(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_keyPrefix$messageId');
    } catch (e) {
      print('⚠️ [MessageLocalPathService] Error getting local path: $e');
      return null;
    }
  }

  /// Get file type for a message
  static Future<String?> getFileType(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_fileTypePrefix$messageId');
    } catch (e) {
      return null;
    }
  }

  /// Get file extension for a message
  static Future<String?> getFileExtension(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_fileExtensionPrefix$messageId');
    } catch (e) {
      return null;
    }
  }

  /// Check if message has local path (file was sent by current user)
  static Future<bool> hasLocalPath(String messageId) async {
    final path = await getLocalPath(messageId);
    return path != null;
  }
}


