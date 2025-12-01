import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import '../models/chat/group_file.dart';
import '../chat/chat_service.dart';
import '../chat/file_cache_service.dart';
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
  final FileCacheService _fileCacheService = FileCacheService();
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

  /// Check if file is an image based on mimeType
  bool _isImageFile(GroupFile file) {
    // First check mimeType (preferred)
    if (file.mimeType != null && file.mimeType!.isNotEmpty) {
      final mimeType = file.mimeType!.toLowerCase();
      // Check mime-type: image/jpeg, image/png, image/jpg, image/heic, image/webp
      if (mimeType.startsWith('image/')) {
        print('✅ [GroupFilesScreen] File ${file.fileName} is IMAGE (mimeType: $mimeType)');
        return true;
      }
    }
    
    // Fallback to fileType if mimeType is not available
    if (file.fileType != null && file.fileType!.isNotEmpty) {
      final fileType = file.fileType!.toUpperCase();
      if (fileType == 'IMAGE') {
        print('✅ [GroupFilesScreen] File ${file.fileName} is IMAGE (fileType: $fileType)');
        return true;
      }
    }
    
    print('❌ [GroupFilesScreen] File ${file.fileName} is NOT IMAGE (mimeType: ${file.mimeType}, fileType: ${file.fileType})');
    return false;
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
      // Check if file is already cached
      final cachedPath = await _fileCacheService.getCachedFilePath(file.fileUrl);
      if (cachedPath != null) {
        await _openFile(cachedPath, file.mimeType ?? file.fileType);
        return;
      }

      // Show downloading snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đang tải file...'),
          duration: Duration(seconds: 2),
        ),
      );

      // Download file
      final dio = Dio();
      final cacheDir = await _fileCacheService.getCacheDirectory();
      final fileExtension = path.extension(file.fileName);
      final localFile = File('${cacheDir.path}/${file.id}$fileExtension');

      await dio.download(
        _buildFullUrl(file.fileUrl),
        localFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
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

      // Save to cache
      await _fileCacheService.saveToCache(file.fileUrl, localFile, file.fileName);

      // Hide snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Open file
      await _openFile(localFile.path, file.mimeType ?? file.fileType);
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tải file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFile(String filePath, String? mimeType) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File không tồn tại')),
        );
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
      
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở file: ${result.message.isNotEmpty ? result.message : "Không tìm thấy app phù hợp"}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('❌ [GroupFilesScreen] Error opening file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi mở file: ${e.toString()}')),
      );
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
            color: theme.colorScheme.onSurface.withOpacity(0.6),
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
            color: theme.colorScheme.onSurface.withOpacity(0.6),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _downloadAndOpenFile(file),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                _getFileIcon(file.mimeType ?? file.fileType, file.fileName),
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatFileSize(file.fileSize),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
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
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (file.senderName != null)
                          Text(
                            ' • ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        Text(
                          _formatDate(file.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
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
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
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
              color: Colors.black.withOpacity(0.7),
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
