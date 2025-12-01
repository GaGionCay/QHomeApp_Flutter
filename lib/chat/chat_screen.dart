import 'dart:async';
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
import '../models/chat/message.dart';
import '../auth/api_client.dart';
import 'chat_service.dart';
import 'chat_message_view_model.dart';
import 'file_cache_service.dart';
import 'public_file_storage_service.dart';
import 'message_local_path_service.dart';
import 'invite_members_dialog.dart';
import 'group_members_screen.dart';
import 'group_files_screen.dart';

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
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;

  bool _isLoadingMore = false;
  int _previousMessageCount = 0;
  bool _isUserScrolling = false; // Track if user is manually scrolling
  Timer? _scrollEndTimer;
  int _lastMessageCount = 0; // Track message count to detect new messages

  @override
  void initState() {
    super.initState();
    final service = ChatService();
    _viewModel = ChatMessageViewModel(service);
    _viewModel.initialize(widget.groupId);
    
    // Add scroll listener for manual scroll detection (no auto-load on scroll)
    _scrollController.addListener(_onScroll);
    
    // Initialize message count after first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastMessageCount = _viewModel.messages.length;
      }
    });
  }

  void _onScroll() {
    // Mark that user is scrolling
    _isUserScrolling = true;
    
    // Reset scroll end timer
    _scrollEndTimer?.cancel();
    _scrollEndTimer = Timer(const Duration(milliseconds: 150), () {
      _isUserScrolling = false;
    });

    // NOTE: Removed auto-load on scroll - only load when user clicks "Hiển thị thêm tin nhắn" button
  }

  /// Check if user is near the bottom of the list (within 100px)
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 100;
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_viewModel.hasMore || _viewModel.isLoading) return;
    
    setState(() {
      _isLoadingMore = true;
      _previousMessageCount = _viewModel.messages.length;
    });

    try {
      // Store current scroll position and maxScrollExtent before loading
      double? previousScrollPosition;
      double? previousMaxScrollExtent;
      if (_scrollController.hasClients) {
        previousScrollPosition = _scrollController.position.pixels;
        previousMaxScrollExtent = _scrollController.position.maxScrollExtent;
      }

      await _viewModel.loadMore();
      
      // Maintain scroll position after loading more messages
      // Since ListView is reversed, new messages are inserted at index 0 (top)
      // We need to adjust scroll position to maintain the visual position of the item user was viewing
      if (mounted && _scrollController.hasClients && 
          previousScrollPosition != null && previousMaxScrollExtent != null) {
        final newMessageCount = _viewModel.messages.length;
        final addedCount = newMessageCount - _previousMessageCount;
        
        if (addedCount > 0) {
          // Wait for frames to ensure new items are fully rendered and maxScrollExtent is updated
          // Use double postFrameCallback to ensure ListView has completed layout
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Wait one more frame to ensure all items are laid out
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scrollController.hasClients) {
                final newMaxScrollExtent = _scrollController.position.maxScrollExtent;
                
                // Calculate the height difference (new messages added at top)
                // The scroll extent increased by the height of new messages
                final heightDifference = newMaxScrollExtent - previousMaxScrollExtent!;
                
                // Calculate new position: add the height difference to maintain visual position
                final newPosition = previousScrollPosition! + heightDifference;
                
                // Only adjust if we're not at the bottom (pixels = 0 in reversed list)
                // and the new position is valid
                if (previousScrollPosition > 0 && 
                    newPosition <= newMaxScrollExtent && 
                    newPosition >= 0 &&
                    newMaxScrollExtent > previousMaxScrollExtent) {
                  // Use jumpTo (not animateTo) to instantly set position without animation
                  // This prevents any visual jumps or glitches
                  _scrollController.jumpTo(newPosition);
                }
              }
            });
          });
        }
      }
    } catch (e) {
      print('❌ [ChatScreen] Lỗi khi load more messages: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Cancel timers first
    _scrollEndTimer?.cancel();
    _recordingTimer?.cancel();
    _recordingTimer = null;
    
    // Dispose controllers
    _messageController.dispose();
    _scrollController.dispose();
    
    // Dispose audio resources (async operations should be handled separately)
    _audioRecorder.closeRecorder().catchError((e) {
      print('⚠️ [ChatScreen] Error closing audio recorder: $e');
    });
    _audioPlayer.dispose();
    
    // Dispose view model
    _viewModel.dispose();
    
    // Always call super.dispose() last
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    await _viewModel.sendMessage(content);
    _messageController.clear();
    
    // Auto-scroll to bottom only if user was near bottom
    _scrollToBottomIfNeeded();
  }

  /// Scroll to bottom only if user is near bottom (not manually scrolling)
  void _scrollToBottomIfNeeded() {
    if (!_scrollController.hasClients) return;
    
    // Only auto-scroll if user is near bottom and not manually scrolling
    if (_isNearBottom() && !_isUserScrolling) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      print('📸 [ChatScreen] Bắt đầu chọn ảnh từ ${source == ImageSource.gallery ? "gallery" : "camera"}');
      
      if (source == ImageSource.gallery) {
        // Allow multiple image selection from gallery
        final images = await _imagePicker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (images.isEmpty) {
          print('⚠️ [ChatScreen] Người dùng hủy chọn ảnh');
          return;
        }

        print('✅ [ChatScreen] Đã chọn ${images.length} ảnh từ gallery');

        if (mounted) {
          // Show loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đang upload ${images.length} ảnh...'),
              duration: const Duration(days: 1), // Long duration, will be dismissed manually
            ),
          );

          try {
            print('📤 [ChatScreen] Bắt đầu upload ${images.length} ảnh...');
            await _viewModel.uploadAndSendMultipleImages(images);
            print('✅ [ChatScreen] Đã gửi ${images.length} ảnh thành công!');
            
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Đã gửi ${images.length} ảnh thành công!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
              // Auto-scroll to bottom only if needed
              _scrollToBottomIfNeeded();
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
      } else {
        // Camera: single image only
        final image = await _imagePicker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (image == null) {
          print('⚠️ [ChatScreen] Người dùng hủy chụp ảnh');
          return;
        }

        print('✅ [ChatScreen] Đã chụp ảnh: ${image.path}, size: ${await image.length()} bytes');

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
              // Auto-scroll to bottom only if needed
              _scrollToBottomIfNeeded();
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
      print('🎤 [ChatScreen] Bắt đầu ghi âm...');
      
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        print('❌ [ChatScreen] Không có quyền microphone');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần quyền truy cập microphone')),
          );
        }
        return;
      }
      print('✅ [ChatScreen] Đã có quyền microphone');

      // Open recorder
      print('🔧 [ChatScreen] Đang mở recorder...');
      await _audioRecorder.openRecorder();
      print('✅ [ChatScreen] Recorder đã mở');

      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      print('📁 [ChatScreen] File path: $path');
      
      print('▶️ [ChatScreen] Đang bắt đầu ghi âm với codec aacMP4...');
      await _audioRecorder.startRecorder(
        toFile: path,
        codec: Codec.aacMP4, // Changed from aacADTS to aacMP4 for better Android support
        bitRate: 128000,
        sampleRate: 44100,
      );
      print('✅ [ChatScreen] Đã bắt đầu ghi âm thành công!');

      // Start recording timer to update duration
      _recordingStartTime = DateTime.now();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // Update duration every second using Timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording && _recordingStartTime != null) {
          setState(() {
            _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          });
        } else {
          timer.cancel();
        }
      });
    } catch (e, stackTrace) {
      print('❌ [ChatScreen] Lỗi khi bắt đầu ghi âm: $e');
      print('📋 [ChatScreen] Stack trace: $stackTrace');
      
      // Clean up on error
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _recordingStartTime = null;
      
      if (mounted) {
        setState(() {
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bắt đầu ghi âm: ${e.toString()}')),
        );
      }
      
      try {
        await _audioRecorder.closeRecorder();
      } catch (_) {}
    }
  }

  Future<void> _stopRecording({bool send = true}) async {
    try {
      print('⏹️ [ChatScreen] Đang dừng ghi âm...');
      
      // Capture messenger before any async gaps if we're going to send
      final messenger = send ? ScaffoldMessenger.of(context) : null;
      
      // Stop the timer first
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      final path = await _audioRecorder.stopRecorder();
      print('✅ [ChatScreen] Đã dừng ghi âm, path: $path');
      
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });

      if (send && path != null && mounted) {
        // Verify file exists
        final audioFile = File(path);
        if (!await audioFile.exists()) {
          print('❌ [ChatScreen] File ghi âm không tồn tại: $path');
          if (mounted && messenger != null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('File ghi âm không tồn tại')),
            );
          }
          return;
        }
        
        final fileSize = await audioFile.length();
        print('📊 [ChatScreen] File size: $fileSize bytes');
        
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Đang upload ghi âm...')),
          );
        }

        try {
          print('📤 [ChatScreen] Đang upload audio...');
          final result = await _viewModel.uploadAudio(audioFile);
          print('✅ [ChatScreen] Upload audio thành công: ${result['audioUrl']}');
          
          // Parse fileSize (backend returns it as String)
          final fileSizeValue = result['fileSize'];
          final fileSizeInt = fileSizeValue is int 
              ? fileSizeValue 
              : int.parse(fileSizeValue.toString());
          
          print('📨 [ChatScreen] Đang gửi audio message...');
          await _viewModel.sendAudioMessage(
            result['audioUrl'] as String,
            fileSizeInt,
          );
          print('✅ [ChatScreen] Đã gửi audio message thành công!');
          
          if (mounted && messenger != null) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✅ Đã gửi ghi âm thành công!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            // Auto-scroll to bottom only if needed
            _scrollToBottomIfNeeded();
          }
        } catch (e, stackTrace) {
          print('❌ [ChatScreen] Lỗi khi gửi ghi âm: $e');
          print('📋 [ChatScreen] Stack trace: $stackTrace');
          if (mounted && messenger != null) {
            messenger.showSnackBar(
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
          print('🗑️ [ChatScreen] Đã xóa file tạm: $path');
        }
      }
    } catch (e, stackTrace) {
      print('❌ [ChatScreen] Lỗi khi dừng ghi âm: $e');
      print('📋 [ChatScreen] Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi dừng ghi âm: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      // Capture messenger before any async gaps
      final messenger = ScaffoldMessenger.of(context);
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;
        final fileSize = await file.length();

        messenger.showSnackBar(
          const SnackBar(content: Text('Đang upload file...')),
        );

        try {
          final uploadResult = await _viewModel.uploadFile(file);
          
          // Parse fileSize (backend returns it as String)
          final fileSizeValue = uploadResult['fileSize'];
          final fileSizeInt = fileSizeValue is int 
              ? fileSizeValue 
              : (fileSizeValue != null ? int.parse(fileSizeValue.toString()) : fileSize);
          
          // Get mimeType from upload result
          final mimeType = uploadResult['mimeType'] as String?;
          
          // Determine file type and extension
          final fileType = PublicFileStorageService.getFileType(mimeType, fileName);
          final fileExtension = PublicFileStorageService.getFileExtension(fileName);
          
          // Send message
          await _viewModel.sendFileMessage(
            uploadResult['fileUrl'] as String,
            uploadResult['fileName'] as String? ?? fileName,
            fileSizeInt,
            mimeType,
          );
          
          // Get the last message (the one we just sent) and save local path
          if (_viewModel.messages.isNotEmpty) {
            final lastMessage = _viewModel.messages.last;
            await MessageLocalPathService.saveLocalPath(
              lastMessage.id,
              file.path, // Local path of the uploaded file
              fileType,
              fileExtension,
            );
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            // Auto-scroll to bottom only if needed
            _scrollToBottomIfNeeded();
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
    final messenger = ScaffoldMessenger.of(context);
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
          messenger.showSnackBar(
            const SnackBar(content: Text('Đã đổi tên nhóm thành công')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showLeaveConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
          navigator.pop();
          messenger.showSnackBar(
            const SnackBar(content: Text('Đã rời nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Lỗi: ${e.toString()}')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context, ChatMessageViewModel viewModel) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
          navigator.pop();
          messenger.showSnackBar(
            const SnackBar(content: Text('Đã xóa nhóm')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
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
            // Files button
            Consumer<ChatMessageViewModel>(
              builder: (context, viewModel, child) {
                return IconButton(
                  icon: const Icon(CupertinoIcons.folder),
                  tooltip: 'Files',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupFilesScreen(
                          groupId: widget.groupId,
                          groupName: viewModel.groupName ?? 'Nhóm chat',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
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
                  // Only auto-scroll when NEW messages arrive (not on every rebuild)
                  final currentMessageCount = viewModel.messages.length;
                  final hasNewMessages = currentMessageCount > _lastMessageCount;
                  
                  if (hasNewMessages && mounted) {
                    _lastMessageCount = currentMessageCount;
                    
                    // Only auto-scroll if user is at bottom and not manually scrolling
                    // Use postFrameCallback to avoid interfering with current scroll
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_isUserScrolling) {
                        _scrollToBottomIfNeeded();
                      }
                    });
                  } else if (!hasNewMessages && currentMessageCount != _lastMessageCount) {
                    // Update count even if messages decreased (e.g., refresh)
                    _lastMessageCount = currentMessageCount;
                  }

                  if (viewModel.isLoading && viewModel.messages.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (viewModel.messages.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có tin nhắn nào',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                    // Add key to preserve scroll position during rebuilds
                    key: const PageStorageKey<String>('chat_messages_list'),
                    itemCount: viewModel.messages.length + (viewModel.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Load more button/indicator at the top (oldest messages)
                      if (index == viewModel.messages.length) {
                        return _LoadMoreButton(
                          key: const ValueKey('load_more_button'),
                          isLoading: _isLoadingMore || viewModel.isLoading,
                          hasMore: viewModel.hasMore,
                          onLoadMore: _loadMoreMessages,
                        );
                      }

                      final message = viewModel.messages[viewModel.messages.length - 1 - index];
                      // Use stable key for each message to prevent unnecessary rebuilds
                      final messageKey = ValueKey<String>('message_${message.id}');
                      
                      // Check if this is a system message
                      if (message.messageType == 'SYSTEM') {
                        return _SystemMessageBubble(
                          key: messageKey,
                          message: message,
                        );
                      }
                      return _MessageBubble(
                        key: messageKey,
                        message: message,
                        currentResidentId: viewModel.currentResidentId,
                        onImageTap: (msg) {
                          _showFullScreenImage(context, msg);
                        },
                        onImageLongPress: (msg) {
                          _showImageOptionsBottomSheet(context, msg);
                        },
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

  void _showFullScreenImage(BuildContext context, ChatMessage message) {
    if (message.imageUrl == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenImageViewer(
          imageUrl: _buildFullUrl(message.imageUrl!),
          message: message,
          onLongPress: () {
            Navigator.pop(context); // Close full screen viewer
            _showImageOptionsBottomSheet(context, message);
          },
        ),
      ),
    );
  }

  Future<void> _showImageOptionsBottomSheet(BuildContext context, ChatMessage message) async {
    if (message.imageUrl == null) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_circle),
              title: const Text('Tải ảnh về máy'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.xmark_circle),
              title: const Text('Hủy'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );

    if (result == 'download' && context.mounted) {
      await _downloadImageToGallery(context, message);
    }
  }

  Future<void> _downloadImageToGallery(BuildContext context, ChatMessage message) async {
    if (message.imageUrl == null) return;

    try {
      final imageUrl = message.imageUrl!;
      final fullImageUrl = _buildFullUrl(imageUrl);
      
      // Extract file name from URL or use message ID
      String fileName = message.fileName ?? 
                       (imageUrl.split('/').isNotEmpty 
                        ? imageUrl.split('/').last.split('?').first 
                        : null) ??
                       'image_${message.id}.jpg';
      
      // Ensure fileName has extension
      if (!fileName.contains('.')) {
        fileName = '$fileName.jpg';
      }
      
      // Check if image already exists in gallery
      final fileType = PublicFileStorageService.getFileType('image', fileName);
      final existingPath = await PublicFileStorageService.getExistingFilePath(fileName, fileType);
      
      if (existingPath != null) {
        if (context.mounted) {
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang tải ảnh...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Download and save image (PublicFileStorageService will handle gallery save via gal)
      await PublicFileStorageService.downloadAndSave(
        fullImageUrl,
        fileName,
        'image',
        'image/jpeg', // mimeType
        (received, total) {
          // Progress callback - but we won't show it to avoid interrupting
        },
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tải ảnh vào thư viện'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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

  String _buildFullUrl(String url) {
    // If URL already starts with http:// or https://, return as is
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // Otherwise, build full URL from base URL
    return '${ApiClient.activeFileBaseUrl}$url';
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? currentResidentId;
  final Function(ChatMessage)? onImageTap;
  final Function(ChatMessage)? onImageLongPress;

  const _MessageBubble({
    super.key,
    required this.message,
    this.currentResidentId,
    this.onImageTap,
    this.onImageLongPress,
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
                      ? Colors.white.withValues(alpha: 0.8)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                        if (onImageTap != null) {
                          onImageTap!(message);
                        }
                      },
                      onLongPress: () {
                        print('👆 [MessageBubble] Long press vào ảnh, hiển thị menu');
                        if (onImageLongPress != null) {
                          onImageLongPress!(message);
                        }
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
                messageId: message.id,
                fileUrl: _buildFullUrl(message.fileUrl!),
                fileName: message.fileName ?? 'File',
                fileSize: message.fileSize ?? 0,
                mimeType: message.mimeType,
                senderId: message.senderId,
                currentResidentId: currentResidentId,
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
                    ? Colors.white.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
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
        
        // Reset when audio completes
        if (state.processingState == ProcessingState.completed) {
          _resetAudioState();
        }
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

  Future<void> _resetAudioState() async {
    try {
      // Pause the player
      await _audioPlayer.pause();
      
      // Seek to the beginning
      await _audioPlayer.seek(Duration.zero);
      
      // Update state to reflect reset
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    } catch (e) {
      // Ignore errors during reset
      print('⚠️ [AudioMessageWidget] Error resetting audio state: $e');
    }
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
        // If audio has finished playing, reset to beginning
        if (_position >= _duration && _duration > Duration.zero) {
          await _audioPlayer.seek(Duration.zero);
          setState(() {
            _position = Duration.zero;
          });
        }
        
        // Load audio if not already loaded or if position is at zero
        if (_position == Duration.zero || _duration == Duration.zero) {
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
        setState(() {
          _isLoading = false;
        });
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
                        ? Colors.white.withValues(alpha: 0.3)
                        : widget.theme.colorScheme.primary.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: widget.theme.textTheme.bodySmall?.copyWith(
                    color: widget.isMe
                        ? Colors.white.withValues(alpha: 0.8)
                        : widget.theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

class _FileMessageWidget extends StatefulWidget {
  final String messageId;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final String senderId;
  final String? currentResidentId;
  final bool isMe;
  final ThemeData theme;

  const _FileMessageWidget({
    required this.messageId,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
    required this.senderId,
    this.currentResidentId,
    required this.isMe,
    required this.theme,
  });

  @override
  State<_FileMessageWidget> createState() => _FileMessageWidgetState();
}

class _FileMessageWidgetState extends State<_FileMessageWidget> {
  final FileCacheService _fileCacheService = FileCacheService();
  String? _cachedFilePath;
  bool _isCheckingCache = true;
  bool _isDownloading = false;
  int _lastProgressPercent = -1; // Track last progress to avoid too frequent updates

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    setState(() {
      _isCheckingCache = true;
    });
    
    try {
      // First, check if this is a file sent by current user (has localPath)
      final isSender = widget.currentResidentId != null && 
                       widget.senderId == widget.currentResidentId;
      
      if (isSender) {
        final localPath = await MessageLocalPathService.getLocalPath(widget.messageId);
        if (localPath != null) {
          final file = File(localPath);
          if (await file.exists()) {
            if (mounted) {
              setState(() {
                _cachedFilePath = localPath;
                _isCheckingCache = false;
              });
            }
            return;
          }
        }
      }
      
      // Check if file exists in public directory
      final fileType = PublicFileStorageService.getFileType(widget.mimeType, widget.fileName);
      final existingPath = await PublicFileStorageService.getExistingFilePath(
        widget.fileName,
        fileType,
      );
      
      if (existingPath != null) {
        if (mounted) {
          setState(() {
            _cachedFilePath = existingPath;
            _isCheckingCache = false;
          });
        }
        return;
      }
      
      // Fallback to old cache service
      final cachedPath = await _fileCacheService.getCachedFilePath(widget.fileUrl);
      if (mounted) {
        setState(() {
          _cachedFilePath = cachedPath;
          _isCheckingCache = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingCache = false;
        });
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _getFileIcon(String? mimeType, String fileName) {
    // Use mimeType if available, otherwise fall back to file extension
    if (mimeType != null) {
      if (mimeType.startsWith('image/')) {
        return CupertinoIcons.photo_fill;
      } else if (mimeType.startsWith('video/')) {
        return CupertinoIcons.videocam_fill;
      } else if (mimeType.startsWith('audio/')) {
        return CupertinoIcons.music_note;
      } else if (mimeType == 'application/pdf') {
        return CupertinoIcons.doc_text_fill;
      } else if (mimeType.contains('word') || mimeType.contains('document')) {
        return CupertinoIcons.doc_fill;
      } else if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
        return CupertinoIcons.table_fill;
      } else if (mimeType.contains('zip') || mimeType.contains('archive')) {
        return CupertinoIcons.archivebox_fill;
      }
    }
    
    // Fallback to file extension
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
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return CupertinoIcons.photo_fill;
      case 'mp4':
      case 'avi':
      case 'mov':
        return CupertinoIcons.videocam_fill;
      default:
        return CupertinoIcons.doc_fill;
    }
  }

  Future<void> _downloadAndOpenFile(BuildContext context) async {
    // Capture all context-dependent objects before any async gaps
    final openFileContext = context;
    
    // Prevent multiple simultaneous downloads
    if (_isDownloading) {
      return;
    }

    // If file is already cached, just open it
    if (_cachedFilePath != null) {
      await _openFile(openFileContext, _cachedFilePath!);
      return;
    }

    setState(() {
      _isDownloading = true;
      _lastProgressPercent = -1;
    });
    
    try {
      // Capture messenger before any async gaps
      final messenger = ScaffoldMessenger.of(context);
      
      // Determine file type
      final fileType = PublicFileStorageService.getFileType(widget.mimeType, widget.fileName);
      
      // Show initial loading message
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đang tải file: ${widget.fileName}'),
          duration: const Duration(days: 1),
        ),
      );

      // Download and save to public directory
      final savedPath = await PublicFileStorageService.downloadAndSave(
        widget.fileUrl.startsWith('http') 
            ? widget.fileUrl 
            : '${ApiClient.activeFileBaseUrl}${widget.fileUrl}',
        widget.fileName,
        fileType,
        widget.mimeType, // mimeType
        (received, total) {
          if (total > 0 && context.mounted) {
            final progressPercent = ((received / total) * 100).toInt();
            // Only update every 5% to avoid too frequent updates
            if (progressPercent != _lastProgressPercent && 
                (progressPercent % 5 == 0 || progressPercent == 100)) {
              _lastProgressPercent = progressPercent;
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Đang tải: $progressPercent%'),
                  duration: const Duration(days: 1),
                ),
              );
            }
          }
        },
      );

      // Hide progress snackbar after download completes
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
      }

      // Update state
      if (mounted) {
        setState(() {
          _cachedFilePath = savedPath;
          _isDownloading = false;
        });
      }

      // Open file
      // ignore: use_build_context_synchronously
      await _openFile(openFileContext, savedPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
      
      // Check if context is still valid before using UI operations
      if (openFileContext.mounted) {
        ScaffoldMessenger.of(openFileContext).hideCurrentSnackBar();
        ScaffoldMessenger.of(openFileContext).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tải file: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _openFile(BuildContext context, String filePath) async {
    try {
      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File không tồn tại')),
          );
        }
        return;
      }

      print('📂 [FileMessageWidget] Mở file: $filePath');
      print('📂 [FileMessageWidget] MimeType: ${widget.mimeType}');
      print('📂 [FileMessageWidget] FileName: ${widget.fileName}');

      // Detect mimeType from file extension if not provided
      String? mimeType = widget.mimeType;
      if (mimeType == null || mimeType.isEmpty) {
        mimeType = _getMimeTypeFromFileName(widget.fileName);
        print('📂 [FileMessageWidget] Detected mimeType: $mimeType');
      }

      // Open file with mimeType
      final result = await OpenFile.open(
        filePath,
        type: mimeType ?? 'application/octet-stream',
      );
      
      print('📂 [FileMessageWidget] Open result: ${result.type}, message: ${result.message}');
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (result.type != ResultType.done) {
          final errorMessage = result.message.isNotEmpty 
              ? result.message 
              : 'Không tìm thấy app phù hợp để mở file này';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể mở file: $errorMessage'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        // Don't show success message as it's annoying
      }
    } catch (e, stackTrace) {
      print('❌ [FileMessageWidget] Lỗi khi mở file: $e');
      print('📋 [FileMessageWidget] Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi mở file: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String? _getMimeTypeFromFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'txt':
        return 'text/plain';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCachedFile = _cachedFilePath != null && !_isCheckingCache;
    final isLoading = _isCheckingCache || _isDownloading;

    return InkWell(
      onTap: isLoading ? null : () => _downloadAndOpenFile(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.2)
              : widget.theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (isLoading)
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
                ),
              )
            else
              Icon(
                _getFileIcon(widget.mimeType, widget.fileName),
                size: 32,
                color: widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    style: widget.theme.textTheme.bodyMedium?.copyWith(
                      color: widget.isMe ? Colors.white : widget.theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(widget.fileSize),
                    style: widget.theme.textTheme.bodySmall?.copyWith(
                      color: widget.isMe
                          ? Colors.white.withValues(alpha: 0.7)
                          : widget.theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              hasCachedFile 
                  ? CupertinoIcons.arrow_right_circle_fill
                  : CupertinoIcons.arrow_down_circle,
              color: widget.isMe ? Colors.white : widget.theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final ChatMessage message;
  final VoidCallback? onLongPress;

  const _FullScreenImageViewer({
    required this.imageUrl,
    required this.message,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: GestureDetector(
          onLongPress: onLongPress,
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
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _LoadMoreButton({
    super.key,
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

  const _SystemMessageBubble({super.key, required this.message});

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
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
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
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
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
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
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
                        Text('Chọn nhiều ảnh'),
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
                      ? Colors.red.withValues(alpha: 0.1)
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


