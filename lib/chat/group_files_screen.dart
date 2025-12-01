import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import '../models/chat/group_file.dart';
import '../chat/chat_service.dart';
import '../chat/file_cache_service.dart';
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

class _GroupFilesScreenState extends State<GroupFilesScreen> {
  final ChatService _chatService = ChatService();
  final FileCacheService _fileCacheService = FileCacheService();
  final ScrollController _scrollController = ScrollController();

  List<GroupFile> _files = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 20;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  Future<void> _loadFiles({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _currentPage = 0;
        _files = [];
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

      setState(() {
        if (refresh) {
          _files = response.content;
        } else {
          _files.addAll(response.content);
        }
        _hasMore = response.hasNext;
        _currentPage++;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _error = 'Lỗi khi tải danh sách file: ${e.toString()}';
      });
    }
  }

  Future<void> _downloadAndOpenFile(GroupFile file) async {
    try {
      // Check if file is already cached
      final cachedPath = await _fileCacheService.getCachedFilePath(file.fileUrl);
      if (cachedPath != null) {
        await _openFile(cachedPath, file.fileType);
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
      final fileExtension = file.fileName.split('.').last;
      final localFile = File('${cacheDir.path}/${file.id}.$fileExtension');

      await dio.download(
        _buildFullUrl(file.fileUrl),
        localFile.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toInt();
            if (progress % 10 == 0) {
              // Update every 10%
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
      await _openFile(localFile.path, file.fileType);
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

      final result = await OpenFile.open(filePath, type: mimeType ?? 'application/octet-stream');
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở file: ${result.message}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi mở file: ${e.toString()}')),
      );
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

  IconData _getFileIcon(String? mimeType, String fileName) {
    if (mimeType == null || mimeType.isEmpty) {
      final ext = fileName.split('.').last.toLowerCase();
      return _getIconByExtension(ext);
    }

    if (mimeType.startsWith('image/')) {
      return CupertinoIcons.photo;
    } else if (mimeType.startsWith('video/')) {
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
      case 'pdf':
        return CupertinoIcons.doc_text;
      case 'doc':
      case 'docx':
        return CupertinoIcons.doc;
      case 'xls':
      case 'xlsx':
        return CupertinoIcons.table;
      case 'zip':
      case 'rar':
        return CupertinoIcons.archivebox;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return CupertinoIcons.photo;
      case 'mp4':
      case 'avi':
      case 'mov':
        return CupertinoIcons.videocam;
      case 'mp3':
      case 'wav':
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
      ),
      body: _isLoading && _files.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _files.isEmpty
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
              : _files.isEmpty
                  ? Center(
                      child: Text(
                        'Chưa có file nào',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadFiles(refresh: true),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _files.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _files.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }

                          final file = _files[index];
                          return _buildFileItem(file, theme);
                        },
                      ),
                    ),
    );
  }

  Widget _buildFileItem(GroupFile file, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _downloadAndOpenFile(file),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                _getFileIcon(file.fileType, file.fileName),
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

