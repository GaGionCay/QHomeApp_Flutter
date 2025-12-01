import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:dio/dio.dart';
import '../models/chat/message.dart';
import '../auth/api_client.dart';
import '../auth/token_storage.dart';
import 'chat_service.dart';
import 'chat_message_view_model.dart';
import 'invite_members_dialog.dart';
import 'group_members_screen.dart';

class ChatScreen extends StatefulWidget {
  final String groupId;

  const ChatScreen({super.key, required this.groupId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatMessageViewModel _viewModel;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final _audioRecorder = FlutterSoundRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;

  bool _isLoadingMore = false;
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    final service = ChatService();
    _viewModel = ChatMessageViewModel(service);
    _viewModel.initialize(widget.groupId);
    
    // Add scroll listener for infinite scroll
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // When scrolling near the top (old messages), load more
    if (_scrollController.position.pixels < 200 && 
        !_isLoadingMore && 
        _viewModel.hasMore &&
        !_viewModel.isLoading) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_viewModel.hasMore || _viewModel.isLoading) return;
    
    setState(() {
      _isLoadingMore = true;
      _previousMessageCount = _viewModel.messages.length;
    });

    try {
      // Store current scroll position before loading
      double? previousScrollPosition;
      if (_scrollController.hasClients) {
        previousScrollPosition = _scrollController.position.pixels;
      }

      await _viewModel.loadMore();
      
      // Maintain scroll position after loading more messages
      // Since ListView is reversed, new messages are inserted at index 0
      // We need to adjust scroll position to maintain visual position
      if (mounted && _scrollController.hasClients && previousScrollPosition != null) {
        final newMessageCount = _viewModel.messages.length;
        final addedCount = newMessageCount - _previousMessageCount;
        
        if (addedCount > 0) {
          // Wait for next frame to ensure new items are rendered
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              // Estimate height of added messages (average message height ~60-80px)
              // This is approximate but works well for most cases
              final estimatedHeight = addedCount * 70.0;
              final newPosition = previousScrollPosition! + estimatedHeight;
              
              // Only adjust if we're not at the bottom
              if (previousScrollPosition > 0) {
                _scrollController.jumpTo(newPosition.clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                ));
              }
            }
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() async {
    _messageController.dispose();
    _scrollController.dispose();
    await _audioRecorder.closeRecorder();
    _audioPlayer.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    await _viewModel.sendMessage(content);
    _messageController.clear();
    
    // Auto-scroll to bottom after sending message (since ListView is reversed)
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      print('📸 [ChatScreen] Bắt đầu chọn ảnh từ ${source == ImageSource.gallery ? "gallery" : "camera"}');
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image == null) {
        print('⚠️ [ChatScreen] Người dùng hủy chọn ảnh');
        return;
      }

      print('✅ [ChatScreen] Đã chọn ảnh: ${image.path}, size: ${await image.length()} bytes');

      if (mounted) {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang upload ảnh...')),
        );

        try {
          print('📤 [ChatScreen] Bắt đầu upload ảnh...');
          final imageUrl = await _viewModel.uploadImage(image);
          print('✅ [ChatScreen] Upload ảnh thành công! imageUrl: $imageUrl');
          
          print('📨 [ChatScreen] Bắt đầu gửi message với ảnh...');
          await _viewModel.sendImageMessage(imageUrl);
          print('✅ [ChatScreen] Gửi message ảnh thành công!');
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Đã gửi ảnh thành công!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            // Auto-scroll to bottom
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        } catch (e, stackTrace) {
          print('❌ [ChatScreen] Lỗi khi gửi ảnh: $e');
          print('📋 [ChatScreen] Stack trace: $stackTrace');
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Lỗi khi gửi ảnh: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ [ChatScreen] Lỗi khi chọn ảnh: $e');
      print('📋 [ChatScreen] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi chọn ảnh: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần quyền truy cập microphone')),
          );
        }
        return;
      }

      // Open recorder
      await _audioRecorder.openRecorder();

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordingPath = path;
      
      await _audioRecorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        bitRate: 128000,
        sampleRate: 44100,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Update duration
      _audioRecorder.onProgress!.listen((recording) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingDuration = recording.duration;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bắt đầu ghi âm: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    try {
      final path = await _audioRecorder.stopRecorder();
      
      setState(() {
        _isRecording = false;
      });

      if (send && path != null && mounted) {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang upload ghi âm...')),
        );

        try {
          final audioFile = File(path);
          final result = await _viewModel.uploadAudio(audioFile);
          await _viewModel.sendAudioMessage(
            result['audioUrl'] as String,
            result['fileSize'] as int,
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            // Auto-scroll to bottom
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi gửi ghi âm: ${e.toString()}')),
            );
          }
        }
      }

      // Clean up
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi dừng ghi âm: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = await file.length();

        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đang upload file...')),
        );

        try {
          final uploadResult = await _viewModel.uploadFile(file);
          await _viewModel.sendFileMessage(
            uploadResult['fileUrl'] as String,
            uploadResult['fileName'] as String? ?? fileName,
            uploadResult['fileSize'] as int? ?? fileSize,
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            // Auto-scroll to bottom
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi gửi file: ${e.toString()}')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chọn file: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _showRenameDialog(BuildContext context, ChatMessageViewModel viewModel) async {
    final controller = TextEditingController(text: viewModel.groupName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đổi tên nhóm'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Nhập tên nhóm mới',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(context, newName);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      try {
        await viewModel.updateGroupName(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã đổi tên nhóm thành công')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showLeaveConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rời nhóm'),
        content: const Text('Bạn có chắc chắn muốn rời nhóm này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await viewModel.leaveGroup();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã rời nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa nhóm'),
        content: const Text('Bạn có chắc chắn muốn xóa nhóm này không? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa nhóm'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await viewModel.deleteGroup();
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: Consumer<ChatMessageViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isLoading && viewModel.groupName == null) {
                return const Text('Đang tải...');
              }
              return Text(
                viewModel.groupName ?? 'Nhóm chat',
                style: const TextStyle(fontWeight: FontWeight.bold),
              );
            },
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.person_add),
              onPressed: () async {
                final result = await showDialog(
                  context: context,
                  builder: (_) => InviteMembersDialog(groupId: widget.groupId),
                );
                if (result == true && mounted) {
                  // Refresh group info if needed
                }
              },
            ),
            Consumer<ChatMessageViewModel>(
              builder: (context, viewModel, child) {
                return PopupMenuButton<String>(
                  icon: const Icon(CupertinoIcons.ellipsis),
                  onSelected: (value) async {
                    if (value == 'members') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupMembersScreen(groupId: widget.groupId),
                        ),
                      );
                    } else if (value == 'rename') {
                      await _showRenameDialog(context, viewModel);
                    } else if (value == 'leave') {
                      await _showLeaveConfirmation(context, viewModel);
                    } else if (value == 'delete') {
                      await _showDeleteConfirmation(context, viewModel);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'members',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.person_2, size: 20),
                          SizedBox(width: 8),
                          Text('Xem thành viên'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.pencil, size: 20),
                          SizedBox(width: 8),
                          Text('Đổi tên nhóm'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.arrow_right_square, size: 20),
                          SizedBox(width: 8),
                          Text('Rời nhóm'),
                        ],
                      ),
                    ),
                    if (viewModel.isCreator)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Xóa nhóm', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Consumer<ChatMessageViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isLoading && viewModel.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (viewModel.messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có tin nhắn nào',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    // Optimize for performance: only render visible items + small cache
                    cacheExtent: 500, // Cache 500px above/below viewport
                    itemCount: viewModel.messages.length + (viewModel.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Load more button/indicator at the top (oldest messages)
                      if (index == viewModel.messages.length) {
                        return _LoadMoreButton(
                          isLoading: _isLoadingMore || viewModel.isLoading,
                          hasMore: viewModel.hasMore,
                          onLoadMore: _loadMoreMessages,
                        );
                      }

                      final message = viewModel.messages[viewModel.messages.length - 1 - index];
                      // Check if this is a system message
                      if (message.messageType == 'SYSTEM') {
                        return _SystemMessageBubble(message: message);
                      }
                      return _MessageBubble(
                        message: message,
                        currentResidentId: viewModel.currentResidentId,
                      );
                    },
                  );
                },
              ),
            ),
            _MessageInput(
              controller: _messageController,
              onSend: _sendMessage,
              onPickImage: _pickImage,
              onStartRecording: _startRecording,
              onStopRecording: _stopRecording,
              onPickFile: _pickFile,
              isRecording: _isRecording,
              recordingDuration: _recordingDuration,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? currentResidentId;

  const _MessageBubble({
    required this.message,
    this.currentResidentId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = currentResidentId != null && message.senderId == currentResidentId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.senderName ?? 'Người dùng',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isMe
                      ? Colors.white.withOpacity(0.8)
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            // Display based on message type
            if (message.messageType == 'IMAGE' && message.imageUrl != null)
              Builder(
                builder: (context) {
                  final fullImageUrl = _buildFullUrl(message.imageUrl!);
                  print('🖼️ [MessageBubble] Hiển thị ảnh, messageId: ${message.id}');
                  print('🖼️ [MessageBubble] Original imageUrl: ${message.imageUrl}');
                  print('🖼️ [MessageBubble] Full imageUrl: $fullImageUrl');
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () {
                        print('👆 [MessageBubble] Tap vào ảnh, mở full screen');
                        _showFullScreenImage(context, message.imageUrl!);
                      },
                      child: CachedNetworkImage(
                        imageUrl: fullImageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) {
                          print('⏳ [MessageBubble] Đang load ảnh: $url');
                          return Container(
                            height: 200,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(child: CircularProgressIndicator()),
                          );
                        },
                        errorWidget: (context, url, error) {
                          print('❌ [MessageBubble] Lỗi load ảnh: $url, error: $error');
                          return Container(
                            height: 200,
                            color: theme.colorScheme.errorContainer,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(CupertinoIcons.exclamationmark_triangle),
                                const SizedBox(height: 8),
                                Text(
                                  'Lỗi tải ảnh',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              )
            else if (message.messageType == 'AUDIO' && message.fileUrl != null)
              _AudioMessageWidget(
                audioUrl: _buildFullUrl(message.fileUrl!),
                isMe: isMe,
                theme: theme,
              )
            else if (message.messageType == 'FILE' && message.fileUrl != null)
              _FileMessageWidget(
                fileUrl: _buildFullUrl(message.fileUrl!),
                fileName: message.fileName ?? 'File',
                fileSize: message.fileSize ?? 0,
                isMe: isMe,
                theme: theme,
              )
            else if (message.content != null && message.content!.isNotEmpty)
              Text(
                message.content!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: isMe
                    ? Colors.white.withOpacity(0.7)
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inHours < 1) return '${diff.inMinutes} phút trước';
    if (diff.inDays < 1) return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${time.day}/${time.month}/${time.year}';
  }

  String _buildFullUrl(String url) {
    // If URL already starts with http:// or https://, return as is
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // Otherwise, build full URL from base URL
    return '${ApiClient.activeFileBaseUrl}$url';
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          imageUrl: _buildFullUrl(imageUrl),
        ),
      ),
    );
  }
}

class _AudioMessageWidget extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final ThemeData theme;

  const _AudioMessageWidget({
    required this.audioUrl,
    required this.isMe,
    required this.theme,
  });

  @override
  State<_AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<_AudioMessageWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
    _audioPlayer.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _duration = duration ?? Duration.zero;
        });
      }
    });
    _audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _position = position;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_position == Duration.zero || _position >= _duration) {
          setState(() {
            _isLoading = true;
          });
          await _audioPlayer.setUrl(widget.audioUrl);
          setState(() {
            _isLoading = false;
          });
        }
        await _audioPlayer.play();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi phát audio: ${e.toString()}')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                    color: widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
                  ),
            onPressed: _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: LinearProgressIndicator(
                    value: _duration.inMilliseconds > 0
                        ? _position.inMilliseconds / _duration.inMilliseconds
                        : 0,
                    backgroundColor: widget.isMe
                        ? Colors.white.withOpacity(0.3)
                        : widget.theme.colorScheme.primary.withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_position) + ' / ' + _formatDuration(_duration),
                  style: widget.theme.textTheme.bodySmall?.copyWith(
                    color: widget.isMe
                        ? Colors.white.withOpacity(0.8)
                        : widget.theme.colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileMessageWidget extends StatelessWidget {
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final bool isMe;
  final ThemeData theme;

  const _FileMessageWidget({
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.isMe,
    required this.theme,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return CupertinoIcons.doc_text_fill;
      case 'doc':
      case 'docx':
        return CupertinoIcons.doc_fill;
      case 'xls':
      case 'xlsx':
        return CupertinoIcons.table_fill;
      case 'zip':
      case 'rar':
        return CupertinoIcons.archivebox_fill;
      default:
        return CupertinoIcons.doc_fill;
    }
  }

  Future<void> _downloadAndOpenFile(BuildContext context) async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang tải file: $fileName')),
      );

      // Request storage permission
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cần quyền truy cập bộ nhớ để tải file')),
            );
          }
          return;
        }
      }

      // Get download directory
      final directory = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();
      
      if (directory == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể truy cập thư mục tải xuống')),
          );
        }
        return;
      }

      final filePath = '${directory.path}/$fileName';

      // Download file
      final dio = Dio();
      final token = await TokenStorage().readAccessToken();
      if (token != null) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }

      await dio.download(
        fileUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            if (context.mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đang tải: $progress%')),
              );
            }
          }
        },
      );

      // Open file
      final result = await OpenFile.open(filePath);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể mở file: ${result.message}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã mở file thành công')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải file: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _downloadAndOpenFile(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withOpacity(0.2)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _getFileIcon(fileName),
              size: 32,
              color: isMe ? Colors.white : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fileName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isMe ? Colors.white : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(fileSize),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isMe
                          ? Colors.white.withOpacity(0.7)
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.arrow_down_circle,
              color: isMe ? Colors.white : theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
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
  }
}

class _LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _LoadMoreButton({
    required this.isLoading,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            : OutlinedButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(CupertinoIcons.arrow_up, size: 16),
                label: const Text('Hiển thị thêm tin nhắn'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
      ),
    );
  }
}

class _SystemMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _SystemMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    message.content ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280), // Gray color
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outline.withOpacity(0.3),
                    thickness: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(ImageSource) onPickImage;
  final VoidCallback onStartRecording;
  final Function({bool send}) onStopRecording;
  final VoidCallback onPickFile;
  final bool isRecording;
  final Duration recordingDuration;

  const _MessageInput({
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPickFile,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Recording indicator
          if (isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(recordingDuration),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => onStopRecording(send: false),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onStopRecording(send: true),
                    child: const Text('Gửi'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // Attachment button
              PopupMenuButton<String>(
                icon: Icon(
                  isRecording ? CupertinoIcons.mic_fill : CupertinoIcons.plus_circle,
                  color: isRecording ? Colors.red : theme.colorScheme.primary,
                ),
                onSelected: (value) {
                  if (value == 'image_gallery') {
                    onPickImage(ImageSource.gallery);
                  } else if (value == 'image_camera') {
                    onPickImage(ImageSource.camera);
                  } else if (value == 'file') {
                    onPickFile();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'image_gallery',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.photo, size: 20),
                        SizedBox(width: 8),
                        Text('Chọn ảnh'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'image_camera',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.camera, size: 20),
                        SizedBox(width: 8),
                        Text('Chụp ảnh'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'file',
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.doc, size: 20),
                        SizedBox(width: 8),
                        Text('Chọn file'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Voice message button
              GestureDetector(
                onLongPress: isRecording ? null : onStartRecording,
                onLongPressEnd: (details) {
                  if (isRecording) {
                    onStopRecording(send: true);
                  }
                },
                child: IconButton(
                  icon: Icon(
                    isRecording ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                    color: isRecording ? Colors.red : theme.colorScheme.primary,
                  ),
                  onPressed: () {
                    if (isRecording) {
                      onStopRecording(send: true);
                    } else {
                      onStartRecording();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isRecording,
                  decoration: InputDecoration(
                    hintText: isRecording ? 'Đang ghi âm...' : 'Nhập tin nhắn...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isRecording ? CupertinoIcons.stop_circle_fill : CupertinoIcons.paperplane_fill,
                  color: isRecording ? Colors.red : Colors.white,
                ),
                onPressed: isRecording
                    ? () => onStopRecording(send: true)
                    : (controller.text.trim().isEmpty ? null : onSend),
                style: IconButton.styleFrom(
                  backgroundColor: isRecording
                      ? Colors.red.withOpacity(0.1)
                      : theme.colorScheme.primary,
                  foregroundColor: isRecording ? Colors.red : Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

