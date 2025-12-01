import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Service to manage local file cache for downloaded chat files
class FileCacheService {
  static const String _cacheKeyPrefix = 'file_cache_';
  static const String _cacheIndexKey = 'file_cache_index';

  /// Get the cache directory for downloaded files
  Future<Directory> getCacheDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${directory.path}/chat_files');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Generate a cache key from file URL
  String _getCacheKey(String fileUrl) {
    final bytes = utf8.encode(fileUrl);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Get local file path if file is cached
  Future<String?> getCachedFilePath(String fileUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = _getCacheKey(fileUrl);
      final localPath = prefs.getString('$_cacheKeyPrefix$cacheKey');
      
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          return localPath;
        } else {
          // File was deleted, remove from cache
          await prefs.remove('$_cacheKeyPrefix$cacheKey');
        }
      }
      return null;
    } catch (e) {
      print('⚠️ [FileCacheService] Error getting cached file path: $e');
      return null;
    }
  }

  /// Save file to cache and store the path
  Future<String> saveToCache(String fileUrl, File downloadedFile, String? originalFileName) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheKey = _getCacheKey(fileUrl);
      
      // Generate file name with extension
      final extension = originalFileName?.split('.').last ?? 'file';
      final cachedFileName = '$cacheKey.$extension';
      final cachedFilePath = '${cacheDir.path}/$cachedFileName';
      
      // Copy file to cache directory
      final cachedFile = await downloadedFile.copy(cachedFilePath);
      
      // Save cache mapping
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cacheKeyPrefix$cacheKey', cachedFile.path);
      
      // Update cache index
      final index = prefs.getStringList(_cacheIndexKey) ?? [];
      if (!index.contains(cacheKey)) {
        index.add(cacheKey);
        await prefs.setStringList(_cacheIndexKey, index);
      }
      
      print('✅ [FileCacheService] File cached: ${cachedFile.path}');
      return cachedFile.path;
    } catch (e) {
      print('❌ [FileCacheService] Error saving to cache: $e');
      rethrow;
    }
  }

  /// Check if file is cached
  Future<bool> isCached(String fileUrl) async {
    final cachedPath = await getCachedFilePath(fileUrl);
    return cachedPath != null;
  }

  /// Clear all cached files
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getStringList(_cacheIndexKey) ?? [];
      
      // Delete all cached files
      for (final cacheKey in index) {
        final cachedPath = prefs.getString('$_cacheKeyPrefix$cacheKey');
        if (cachedPath != null) {
          final file = File(cachedPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        await prefs.remove('$_cacheKeyPrefix$cacheKey');
      }
      
      await prefs.remove(_cacheIndexKey);
      print('✅ [FileCacheService] Cache cleared');
    } catch (e) {
      print('❌ [FileCacheService] Error clearing cache: $e');
    }
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getCacheDirectory();
      int totalSize = 0;
      
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      print('⚠️ [FileCacheService] Error calculating cache size: $e');
      return 0;
    }
  }
}

