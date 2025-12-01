import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import '../models/chat/group_file.dart';
import '../chat/chat_service.dart';
import '../chat/public_file_storage_service.dart';
import '../auth/api_client.dart';

class GroupFilesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupFilesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupFilesScreen> createState() => _GroupFilesScreenState();
}

class _GroupFilesScreenState extends State<GroupFilesScreen> with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  List<GroupFile> _allFiles = [];
  List<GroupFile> _imageFiles = [];
  List<GroupFile> _documentFiles = [];
  
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFiles(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadFiles();
    }
  }

  /// Check if file is an image based on mimeType, fileType, or file extension
  bool _isImageFile(GroupFile file) {
    // First check mimeType (preferred)
    if (file.mimeType != null && file.mimeType!.isNotEmpty) {
      final mimeType = file.mimeType!.toLowerCase();
      // Check mime-type: image/jpeg, image/png, image/jpg, image/heic, image/webp
      if (mimeType.startsWith('image/')) {
        return true;
      }
      // If mimeType is application/octet-stream, check file extension
      if (mimeType == 'application/octet-stream') {
        if (_isImageExtension(file.fileName)) {
          return true;
        }
      }
    }
    
    // Fallback to fileType if mimeType is not available
    if (file.fileType != null && file.fileType!.isNotEmpty) {
      final fileType = file.fileType!.toUpperCase();
      if (fileType == 'IMAGE') {
        return true;
      }
      // If fileType looks like a mime type and is image
      if (file.fileType!.toLowerCase().startsWith('image/')) {
        return true;
      }
    }
    
    // Last resort: check file extension
    if (_isImageExtension(file.fileName)) {
      return true;
    }
    
    return false;
  }

  /// Check if file has image extension
  bool _isImageExtension(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    return extension == '.jpg' || 
           extension == '.jpeg' || 
           extension == '.png' || 
           extension == '.gif' || 
           extension == '.webp' || 
           extension == '.heic' ||
           extension == '.bmp' ||
           extension == '.svg';
  }

  /// Categorize files into images and documents
  void _categorizeFiles() {
    _imageFiles = _allFiles.where((file) => _isImageFile(file)).toList();
    _documentFiles = _allFiles.where((file) => !_isImageFile(file)).toList();
  }

  Future<void> _loadFiles({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 0;
        _allFiles = [];
        _imageFiles = [];
        _documentFiles = [];
        _hasMore = true;
        _isLoading = true;
        _error = null;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final response = await _chatService.getGroupFiles(
        groupId: widget.groupId,
        page: _currentPage,
        size: _pageSize,
      );

      // Debug: Print file information
      print('📋 [GroupFilesScreen] Loaded ${response.content.length} files');
      for (var file in response.content) {
        print('📄 [GroupFilesScreen] File: ${file.fileName}, mimeType: ${file.mimeType}, fileType: ${file.fileType}, size: ${file.fileSize}');
      }

      setState(() {
        if (refresh) {
          _allFiles = response.content;
        } else {
          _allFiles.addAll(response.content);
        }
        _categorizeFiles();
        _hasMore = response.hasNext;
        _currentPage++;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
      
      // Debug: Print categorized files
      print('🖼️ [GroupFilesScreen] Images: ${_imageFiles.length}, Documents: ${_documentFiles.length}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = 'Lỗi khi tải danh sách file: ${e.toString()}';
      });
    }
  }

  String _buildFullUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final baseUrl = ApiClient.activeFileBaseUrl;
    if (baseUrl.isEmpty) return url;
    return '$baseUrl$url';
  }

  /// Download image to Pictures/<AppName> directory
  Future<void> _downloadImage(GroupFile file) async {
    try {
      // Check if image already exists
      final fileType = PublicFileStorageService.getFileType(file.mimeType ?? file.fileType, file.fileName);
      final existingPath = await PublicFileStorageService.getExistingFilePath(file.fileName, fileType);
      
      if (existingPath != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ảnh đã có trong máy'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang tải ảnh...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Download and save image
      await PublicFileStorageService.downloadAndSave(
        _buildFullUrl(file.fileUrl),
        file.fileName,
        'image',
        file.mimeType ?? file.fileType,
        (received, total) {
          // Progress callback
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tải ảnh vào thư viện'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải ảnh: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Open image in full-screen viewer
  void _openImageViewer(GroupFile file, List<GroupFile> allImages) {
    final initialIndex = allImages.indexOf(file);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          images: allImages,
          initialIndex: initialIndex >= 0 ? initialIndex : 0,
          onDownload: (file) => _downloadImage(file),
        ),
      ),
    );
  }

  /// Download and open document file
  Future<void> _downloadAndOpenFile(GroupFile file) async {
    try {
      // Determine file type and mime type
      final fileType = PublicFileStorageService.getFileType(
        file.mimeType ?? file.fileType,
        file.fileName,
      );
      final mimeType = file.mimeType ?? file.fileType;

      // Check if file already exists in public directory
      final existingPath = await PublicFileStorageService.getExistingFilePath(
        file.fileName,
        fileType,
      );
      
      if (existingPath != null) {
        print('✅ [GroupFilesScreen] File already exists: $existingPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File đã có trong máy, đang mở...'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        await _openFile(existingPath, mimeType);
        return;
      }

      // Show downloading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang tải file...'),
            duration: Duration(days: 1), // Long duration, will be dismissed manually
          ),
        );
      }

      // Download and save to public directory
      final savedPath = await PublicFileStorageService.downloadAndSave(
        _buildFullUrl(file.fileUrl),
        file.fileName,
        fileType,
        mimeType,
        (received, total) {
          if (total > 0 && mounted) {
            final progress = (received / total * 100).toInt();
            if (progress % 10 == 0) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đang tải: $progress%'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          }
        },
      );

      // Hide snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã tải file thành công'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Open file
      await _openFile(savedPath, mimeType);
    } catch (e) {
      print('❌ [GroupFilesScreen] Error downloading file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải file: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _openFile(String filePath, String? mimeType) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File không tồn tại')),
          );
        }
        return;
      }

      // Detect mimeType from file extension if not provided
      String? detectedMimeType = mimeType;
      if (detectedMimeType == null || detectedMimeType.isEmpty || detectedMimeType == 'IMAGE' || detectedMimeType == 'DOCUMENT') {
        detectedMimeType = _getMimeTypeFromFileName(filePath);
        print('📂 [GroupFilesScreen] Detected mimeType: $detectedMimeType for file: $filePath');
      }

      print('📂 [GroupFilesScreen] Opening file: $filePath with mimeType: $detectedMimeType');
      final result = await OpenFile.open(
        filePath, 
        type: detectedMimeType ?? 'application/octet-stream',
      );
      
      print('📂 [GroupFilesScreen] Open result: ${result.type}, message: ${result.message}');
      
      // If permission denied and file is in Download directory, try to copy to app documents directory
      if (result.type == ResultType.permissionDenied && filePath.contains('/Download/')) {
        print('⚠️ [GroupFilesScreen] Permission denied for Download directory, copying to app documents directory');
        try {
          // Get file name from path
          final fileName = filePath.split('/').last;
          
          // Copy file to app documents directory
          final documentsDir = await PublicFileStorageService.getAndroidAppDocumentsDirectory();
          final newFilePath = '${documentsDir.path}/$fileName';
          await file.copy(newFilePath);
          
          print('✅ [GroupFilesScreen] Copied file to app documents directory: $newFilePath');
          
          // Try to open from new location
          final newResult = await OpenFile.open(
            newFilePath,
            type: detectedMimeType ?? 'application/octet-stream',
          );
          
          if (newResult.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Không thể mở file: ${newResult.message.isNotEmpty ? newResult.message : "Không tìm thấy app phù hợp"}'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        } catch (e) {
          print('❌ [GroupFilesScreen] Error copying file: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi sao chép file: ${e.toString()}'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
      
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở file: ${result.message.isNotEmpty ? result.message : "Không tìm thấy app phù hợp"}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('❌ [GroupFilesScreen] Error opening file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi mở file: ${e.toString()}')),
        );
      }
    }
  }

  String? _getMimeTypeFromFileName(String filePath) {
    final extension = path.extension(filePath).toLowerCase();
    switch (extension) {
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
      case '.zip':
        return 'application/zip';
      case '.rar':
        return 'application/x-rar-compressed';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.txt':
        return 'text/plain';
      default:
        return null;
    }
  }

  IconData _getFileIcon(String? mimeType, String fileName) {
    if (mimeType == null || mimeType.isEmpty) {
      final ext = path.extension(fileName).toLowerCase();
      return _getIconByExtension(ext);
    }

    if (mimeType.startsWith('video/')) {
      return CupertinoIcons.videocam;
    } else if (mimeType.startsWith('audio/')) {
      return CupertinoIcons.music_note;
    } else if (mimeType == 'application/pdf') {
      return CupertinoIcons.doc_text;
    } else if (mimeType.contains('word') || mimeType.contains('document')) {
      return CupertinoIcons.doc;
    } else if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return CupertinoIcons.table;
    } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return CupertinoIcons.archivebox;
    } else {
      return CupertinoIcons.doc;
    }
  }

  IconData _getIconByExtension(String ext) {
    switch (ext.toLowerCase()) {
      case '.pdf':
        return CupertinoIcons.doc_text;
      case '.doc':
      case '.docx':
        return CupertinoIcons.doc;
      case '.xls':
      case '.xlsx':
        return CupertinoIcons.table;
      case '.zip':
      case '.rar':
        return CupertinoIcons.archivebox;
      case '.mp4':
      case '.avi':
      case '.mov':
        return CupertinoIcons.videocam;
      case '.mp3':
      case '.wav':
        return CupertinoIcons.music_note;
      default:
        return CupertinoIcons.doc;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Vừa xong';
        }
        return '${difference.inMinutes} phút trước';
      }
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays == 1) {
      return 'Hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Files - ${widget.groupName}'),
        backgroundColor: theme.colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(CupertinoIcons.photo),
              text: 'Images',
            ),
            Tab(
              icon: Icon(CupertinoIcons.doc),
              text: 'Documents',
            ),
          ],
        ),
      ),
      body: _isLoading && _allFiles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _allFiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _loadFiles(refresh: true),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Images Tab
                    _buildImagesTab(theme),
                    // Documents Tab
                    _buildDocumentsTab(theme),
                  ],
                ),
    );
  }

  Widget _buildImagesTab(ThemeData theme) {
    if (_imageFiles.isEmpty) {
      return Center(
        child: Text(
          'Chưa có ảnh nào',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFiles(refresh: true),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: _imageFiles.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _imageFiles.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final file = _imageFiles[index];
          return _buildImageThumbnail(file, theme);
        },
      ),
    );
  }

  Widget _buildImageThumbnail(GroupFile file, ThemeData theme) {
    return GestureDetector(
      onTap: () => _openImageViewer(file, _imageFiles),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: _buildFullUrl(file.fileUrl),
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: theme.colorScheme.errorContainer,
                child: const Icon(CupertinoIcons.exclamationmark_triangle),
              ),
            ),
          ),
          // Badge to indicate this is an image
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                CupertinoIcons.photo,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsTab(ThemeData theme) {
    if (_documentFiles.isEmpty) {
      return Center(
        child: Text(
          'Chưa có file nào',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFiles(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _documentFiles.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _documentFiles.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final file = _documentFiles[index];
          return _buildDocumentItem(file, theme);
        },
      ),
    );
  }

  Widget _buildDocumentItem(GroupFile file, ThemeData theme) {
    // Determine file category for badge
    String fileCategory = _getFileCategory(file);
    Color categoryColor = _getCategoryColor(fileCategory);
    IconData categoryIcon = _getCategoryIcon(fileCategory);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _downloadAndOpenFile(file),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // File icon with category badge
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getFileIcon(file.mimeType ?? file.fileType, file.fileName),
                      size: 28,
                      color: categoryColor,
                    ),
                  ),
                  // Category badge
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: categoryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 2),
                      ),
                      child: Icon(
                        categoryIcon,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            file.fileName,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Category label
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: categoryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            fileCategory,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: categoryColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatFileSize(file.fileSize),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (file.senderName != null)
                          Flexible(
                            child: Text(
                              file.senderName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (file.senderName != null)
                          Text(
                            ' • ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        Text(
                          _formatDate(file.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                CupertinoIcons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get file category for display
  String _getFileCategory(GroupFile file) {
    final mimeType = file.mimeType ?? file.fileType ?? '';
    final lowerMimeType = mimeType.toLowerCase();
    
    if (lowerMimeType.startsWith('image/') || file.fileType == 'IMAGE') {
      return 'ẢNH';
    } else if (lowerMimeType.startsWith('video/') || file.fileType == 'VIDEO') {
      return 'VIDEO';
    } else if (lowerMimeType.startsWith('audio/') || file.fileType == 'AUDIO') {
      return 'AUDIO';
    } else if (lowerMimeType == 'application/pdf' || path.extension(file.fileName).toLowerCase() == '.pdf') {
      return 'PDF';
    } else if (lowerMimeType.contains('word') || lowerMimeType.contains('document') || 
               path.extension(file.fileName).toLowerCase() == '.doc' || 
               path.extension(file.fileName).toLowerCase() == '.docx') {
      return 'DOC';
    } else if (lowerMimeType.contains('excel') || lowerMimeType.contains('spreadsheet') ||
               path.extension(file.fileName).toLowerCase() == '.xls' || 
               path.extension(file.fileName).toLowerCase() == '.xlsx') {
      return 'EXCEL';
    } else if (lowerMimeType.contains('zip') || lowerMimeType.contains('archive') ||
               path.extension(file.fileName).toLowerCase() == '.zip' || 
               path.extension(file.fileName).toLowerCase() == '.rar') {
      return 'ZIP';
    } else {
      return 'FILE';
    }
  }

  /// Get color for file category
  Color _getCategoryColor(String category) {
    switch (category) {
      case 'ẢNH':
        return Colors.blue;
      case 'VIDEO':
        return Colors.red;
      case 'AUDIO':
        return Colors.purple;
      case 'PDF':
        return Colors.red.shade700;
      case 'DOC':
        return Colors.blue.shade700;
      case 'EXCEL':
        return Colors.green.shade700;
      case 'ZIP':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Get icon for file category
  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'ẢNH':
        return CupertinoIcons.photo;
      case 'VIDEO':
        return CupertinoIcons.videocam;
      case 'AUDIO':
        return CupertinoIcons.music_note;
      case 'PDF':
        return CupertinoIcons.doc_text;
      case 'DOC':
        return CupertinoIcons.doc;
      case 'EXCEL':
        return CupertinoIcons.table;
      case 'ZIP':
        return CupertinoIcons.archivebox;
      default:
        return CupertinoIcons.doc;
    }
  }
}

/// Full-screen image viewer with zoom, swipe to close, and download
class _FullScreenImageViewer extends StatefulWidget {
  final List<GroupFile> images;
  final int initialIndex;
  final Function(GroupFile) onDownload;

  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
    required this.onDownload,
  });

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _buildFullUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final baseUrl = ApiClient.activeFileBaseUrl;
    if (baseUrl.isEmpty) return url;
    return '$baseUrl$url';
  }

  @override
  Widget build(BuildContext context) {
    final currentImage = widget.images[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.arrow_down_circle),
            onPressed: () => widget.onDownload(currentImage),
            tooltip: 'Tải ảnh về máy',
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.images.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final image = widget.images[index];
          return GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: _buildFullUrl(image.fileUrl),
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => const Center(
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: widget.images.length > 1
          ? Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.all(16),
              child: Text(
                '${_currentIndex + 1} / ${widget.images.length}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }
}

