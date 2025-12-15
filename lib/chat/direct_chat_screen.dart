// ignore_for_file: use_build_context_synchronously
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
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import '../models/chat/direct_message.dart';
import '../auth/api_client.dart';
import '../auth/token_storage.dart';
import '../core/event_bus.dart';
import 'chat_service.dart';
import 'direct_chat_view_model.dart';
import 'direct_chat_websocket_service.dart';
import 'public_file_storage_service.dart';
import 'message_local_path_service.dart';
import 'direct_files_screen.dart';
import '../marketplace/post_detail_screen.dart';
import '../marketplace/marketplace_service.dart';
import 'linkable_text_widget.dart';
import '../widgets/animations/smooth_animations.dart';
import 'package:dio/dio.dart';
// Reuse widgets from ChatScreen - import only what we need

class DirectChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherParticipantName;

  const DirectChatScreen({
    super.key,
    required this.conversationId,
    required this.otherParticipantName,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  late final DirectChatViewModel _viewModel;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final _audioRecorder = FlutterSoundRecorder();
  final _audioPlayer = AudioPlayer();
  final _tokenStorage = TokenStorage();
  
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  DateTime? _recordingStartTime;
  
  bool _isLoadingMore = false;
  bool _isUserScrolling = false;
  Timer? _scrollEndTimer;
  int _lastMessageCount = 0;
  String? _currentResidentId;
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    final service = ChatService();
    _viewModel = DirectChatViewModel(service);
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.initialize(widget.conversationId);
    _loadCurrentResidentId();
    _loadBlockedUsers();
    _setupBlockedUsersListener();
    
    _scrollController.addListener(_onScroll);
    
    // Subscribe to WebSocket for real-time notifications
    _subscribeToWebSocket();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastMessageCount = _viewModel.messages.length;
      }
    });
  }
  
  Future<void> _subscribeToWebSocket() async {
    try {
      final token = await _tokenStorage.readAccessToken();
      final userId = await ApiClient().storage.readUserId();
      
      if (token != null && userId != null) {
        await directChatWebSocketService.subscribeToConversation(
          conversationId: widget.conversationId,
          token: token,
          userId: userId,
          onMessage: (message) {
            // Handle incoming message from WebSocket
            if (mounted) {
              _viewModel.addIncomingMessage(message);
              // Scroll to bottom if user is at bottom
              if (_scrollController.hasClients) {
                final maxScroll = _scrollController.position.maxScrollExtent;
                final currentScroll = _scrollController.position.pixels;
                // If user is near bottom (within 100px), auto-scroll
                if (maxScroll - currentScroll < 100) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.maxScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                }
              }
            }
          },
        );
        print('✅ [DirectChatScreen] Subscribed to WebSocket for conversation: ${widget.conversationId}');
      } else {
        print('⚠️ [DirectChatScreen] Cannot subscribe to WebSocket - missing token or userId');
      }
    } catch (e) {
      print('❌ [DirectChatScreen] Error subscribing to WebSocket: $e');
    }
  }

  void _onViewModelChanged() {
    // Check if conversation is hidden
    if (_viewModel.error != null && 
        (_viewModel.error!.contains('hidden') || _viewModel.error!.contains('Hidden'))) {
      // Conversation is hidden, navigate back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cuộc trò chuyện đã bị xóa. Tin nhắn mới sẽ xuất hiện lại khi có tin nhắn mới.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    // Unsubscribe from WebSocket
    directChatWebSocketService.unsubscribeFromConversation(widget.conversationId);
    print('✅ [DirectChatScreen] Unsubscribed from WebSocket for conversation: ${widget.conversationId}');
    
    _viewModel.removeListener(_onViewModelChanged);
    _scrollController.removeListener(_onScroll);
    _scrollEndTimer?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.closeRecorder().catchError((e) {
      print('⚠️ [DirectChatScreen] Error closing audio recorder: $e');
    });
    _audioPlayer.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    
    // Emit event to refresh conversation list when leaving the screen
    // This ensures unread count is updated after messages are marked as read
    print('📢 [DirectChatScreen] dispose() called - emitting direct_chat_activity_updated event');
    AppEventBus().emit('direct_chat_activity_updated');
    print('✅ [DirectChatScreen] Event emitted in dispose()');
    
    super.dispose();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      await _chatService.getBlockedUsers();
      // Blocked users are now loaded but not stored locally
    } catch (e) {
      print('⚠️ [DirectChatScreen] Error loading blocked users: $e');
    }
  }

  void _setupBlockedUsersListener() {
    AppEventBus().on('blocked_users_updated', (_) async {
      await _loadBlockedUsers();
      // Refresh conversation to update isBlockedByOther status
      if (mounted && _viewModel.conversation != null) {
        await _viewModel.initialize(widget.conversationId);
        if (mounted) {
          setState(() {
            // Trigger rebuild to update UI
          });
        }
      }
    });
  }

  /// Check if conversation input should be disabled
  /// Returns true if either party has blocked the other OR they are not friends
  bool _isConversationBlocked() {
    if (_currentResidentId == null || _viewModel.conversation == null) {
      return false;
    }
    
    try {
      // Disable input if either party has blocked the other
      // If A blocks B: A sees "Bạn đã chặn người dùng này", B sees "Người dùng hiện không hoạt động"
      final isBlockedByOther = _viewModel.conversation?.isBlockedByOther == true;
      final isBlockedByMe = _viewModel.conversation?.isBlockedByMe == true;
      
      // Also disable if they are not friends
      final areFriends = _viewModel.conversation?.areFriends == true;
      
      return isBlockedByOther || isBlockedByMe || !areFriends;
    } catch (e) {
      return false;
    }
  }

  /// Get the appropriate placeholder text for blocked conversation
  String _getBlockedPlaceholderText() {
    if (_viewModel.conversation == null) {
      return 'Nhập tin nhắn...';
    }
    
    final isBlockedByMe = _viewModel.conversation?.isBlockedByMe == true;
    final isBlockedByOther = _viewModel.conversation?.isBlockedByOther == true;
    final areFriends = _viewModel.conversation?.areFriends == true;
    
    // Priority: block status > friendship status
    if (isBlockedByMe) {
      return 'Bạn đã chặn người dùng này';
    } else if (isBlockedByOther) {
      return 'Người dùng hiện không hoạt động';
    } else if (!areFriends) {
      return 'Bạn chưa gửi lời mời trò chuyện';
    }
    
    return 'Nhập tin nhắn...';
  }

  Future<void> _loadCurrentResidentId() async {
    _currentResidentId = await _tokenStorage.readResidentId();
    if (mounted) setState(() {});
  }

  void _onScroll() {
    _isUserScrolling = true;
    _scrollEndTimer?.cancel();
    _scrollEndTimer = Timer(const Duration(milliseconds: 150), () {
      _isUserScrolling = false;
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 100;
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_viewModel.hasMore || _viewModel.isLoading) return;
    
    setState(() {
      _isLoadingMore = true;
    });

    try {
      await _viewModel.loadMessages(widget.conversationId);
    } catch (e) {
      print('❌ [DirectChatScreen] Lỗi khi load more messages: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }


  Future<void> _sendMessage() async {
    print('🔵 [DirectChatScreen] _sendMessage called');
    
    final content = _messageController.text.trim();
    print('🔵 [DirectChatScreen] Content: "$content"');
    
    if (content.isEmpty) {
      print('⚠️ [DirectChatScreen] Content is empty, returning');
      return;
    }

    // Check conversation status
    final conversation = _viewModel.conversation;
    
    print('📤 [DirectChatScreen] Attempting to send message:');
    print('   Conversation ID: ${widget.conversationId}');
    print('   Conversation: ${conversation != null ? "exists" : "NULL"}');
    print('   Conversation status: ${conversation?.status ?? "unknown"}');
    print('   Content length: ${content.length}');
    print('   Content preview: ${content.substring(0, content.length > 50 ? 50 : content.length)}...');
    
    if (conversation == null) {
      print('⚠️ [DirectChatScreen] Conversation is null, trying to load...');
      try {
        await _viewModel.initialize(widget.conversationId);
        final loadedConversation = _viewModel.conversation;
        print('✅ [DirectChatScreen] Conversation loaded. Status: ${loadedConversation?.status}');
        
        if (loadedConversation == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể tải thông tin cuộc trò chuyện'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('❌ [DirectChatScreen] Error loading conversation: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi tải cuộc trò chuyện: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    
    final finalConversation = _viewModel.conversation;
    if (finalConversation == null) {
      print('❌ [DirectChatScreen] Conversation is still null after loading');
      return;
    }
    
    if (finalConversation.status == 'BLOCKED') {
      print('🚫 [DirectChatScreen] Conversation is BLOCKED');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gửi tin nhắn: Cuộc trò chuyện đã bị chặn'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    if (finalConversation.status != 'ACTIVE') {
      print('⚠️ [DirectChatScreen] Conversation is not ACTIVE: ${finalConversation.status}');
      // Try to refresh conversation status
      try {
        print('🔄 [DirectChatScreen] Refreshing conversation...');
        await _viewModel.initialize(widget.conversationId);
        final refreshedConversation = _viewModel.conversation;
        print('✅ [DirectChatScreen] Conversation refreshed. New status: ${refreshedConversation?.status}');
        
        if (refreshedConversation == null) {
          print('❌ [DirectChatScreen] Conversation is null after refresh');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể tải thông tin cuộc trò chuyện'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        // Update finalConversation reference
        final updatedConversation = refreshedConversation;
        
        if (updatedConversation.status != 'ACTIVE') {
          print('⚠️ [DirectChatScreen] Conversation status is still not ACTIVE: ${updatedConversation.status}');
          // For now, allow sending if status is not BLOCKED (might be PENDING, etc.)
          if (updatedConversation.status == 'BLOCKED') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cuộc trò chuyện đã bị chặn'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          // Allow sending even if status is not ACTIVE (might be a timing issue)
          print('⚠️ [DirectChatScreen] Allowing message send despite non-ACTIVE status: ${updatedConversation.status}');
        }
      } catch (e, stackTrace) {
        print('❌ [DirectChatScreen] Error refreshing conversation: $e');
        print('❌ [DirectChatScreen] Stack trace: $stackTrace');
        // Don't block sending if refresh fails - might be a network issue
        print('⚠️ [DirectChatScreen] Continuing despite refresh error...');
      }
    }

    print('✅ [DirectChatScreen] All checks passed, calling sendMessage...');
    try {
      // Clear controller BEFORE sending to prevent double-send
      final messageContent = content;
      _messageController.clear();
      
      await _viewModel.sendMessage(
        conversationId: widget.conversationId,
        content: messageContent,
      );
      print('✅ [DirectChatScreen] sendMessage completed successfully');
      _scrollToBottomIfNeeded();
    } catch (e, stackTrace) {
      print('❌ [DirectChatScreen] Error sending message: $e');
      print('❌ [DirectChatScreen] Stack trace: $stackTrace');
      // Restore message content if send failed
      if (content.isNotEmpty) {
        _messageController.text = content;
      }
      if (mounted) {
        final errorMessage = e.toString();
        // Check if error is about blocked user
        final isBlockedError = errorMessage.contains('Người dùng hiện không tìm thấy') ||
                               errorMessage.contains('người dùng hiện không tìm thấy') ||
                               errorMessage.contains('không tìm thấy người dùng');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBlockedError 
                ? 'Người dùng hiện không tìm thấy'
                : 'Lỗi khi gửi tin nhắn: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _scrollToBottomIfNeeded() {
    if (!_scrollController.hasClients) return;
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
    // Check if conversation is blocked
    final conversation = _viewModel.conversation;
    if (conversation != null && conversation.status == 'BLOCKED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gửi ảnh: Cuộc trò chuyện đã bị chặn'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      if (source == ImageSource.gallery) {
        final images = await _imagePicker.pickMultiImage(
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (images.isEmpty) return;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đang upload ${images.length} ảnh...'),
              duration: const Duration(days: 1),
            ),
          );

          try {
            await _viewModel.uploadImages(widget.conversationId, images);
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Đã gửi ${images.length} ảnh thành công!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
              _scrollToBottomIfNeeded();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Lỗi khi gửi ảnh: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      } else {
        final image = await _imagePicker.pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (image == null) return;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đang upload ảnh...')),
          );

          try {
            await _viewModel.uploadImage(widget.conversationId, image);
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Đã gửi ảnh thành công!'),
                  backgroundColor: Colors.green,
                ),
              );
              _scrollToBottomIfNeeded();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Lỗi khi gửi ảnh: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi chọn ảnh: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    // Check if conversation is blocked
    final conversation = _viewModel.conversation;
    if (conversation != null && conversation.status == 'BLOCKED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gửi video: Cuộc trò chuyện đã bị chặn'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      print('🎥 [DirectChatScreen] Bắt đầu chọn video từ ${source == ImageSource.gallery ? "gallery" : "camera"}');
      
      // Request camera permission if needed
      if (source == ImageSource.camera) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cần quyền truy cập camera để quay video'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Pick video with max duration 10 seconds
      final video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 10),
      );

      if (video == null) {
        print('⚠️ [DirectChatScreen] Người dùng hủy chọn video');
        return;
      }

      print('✅ [DirectChatScreen] Đã chọn video: ${video.path}');

      // Check video duration BEFORE compression to avoid unnecessary processing
      final originalMediaInfo = await VideoCompress.getMediaInfo(video.path);
      final originalDuration = originalMediaInfo.duration ?? 0;
      print('📹 [DirectChatScreen] Video gốc duration: ${originalDuration}ms (${(originalDuration / 1000).toStringAsFixed(2)}s)');

      // Check if video is longer than 10.5 seconds (add 0.5s buffer for encoding tolerance)
      if (originalDuration > 10500) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Video có thời lượng quá dài. Vui lòng chọn video ngắn hơn 10 giây.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      if (mounted) {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang xử lý video...'),
            duration: Duration(days: 1),
          ),
        );

        try {
          // Compress video
          print('🎬 [DirectChatScreen] Bắt đầu compress video...');
          final compressedVideo = await VideoCompress.compressVideo(
            video.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
            frameRate: 30,
          );

          if (compressedVideo == null) {
            throw Exception('Không thể compress video');
          }

          print('✅ [DirectChatScreen] Video đã được compress: ${compressedVideo.path}');

          // Double-check duration after compression (with buffer)
          final compressedMediaInfo = await VideoCompress.getMediaInfo(compressedVideo.path!);
          final compressedDuration = compressedMediaInfo.duration ?? 0;
          print('📹 [DirectChatScreen] Video sau compress duration: ${compressedDuration}ms (${(compressedDuration / 1000).toStringAsFixed(2)}s)');

          // Check again with buffer (10.5 seconds) to account for encoding variations
          if (compressedDuration > 10500) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Video có thời lượng quá dài sau khi xử lý. Vui lòng chọn video ngắn hơn 10 giây.'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 4),
                ),
              );
            }
            return;
          }

          final finalVideoFile = File(compressedVideo.path!);

          // Upload video first (from original file path)
          print('📤 [DirectChatScreen] Bắt đầu upload video...');
          await _viewModel.uploadVideo(widget.conversationId, finalVideoFile);
          print('✅ [DirectChatScreen] Upload và gửi video thành công!');

          // Save to public storage after successful upload
          try {
            final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
            final savedPath = await PublicFileStorageService.saveToPublicDirectory(
              finalVideoFile,
              fileName,
              'video',
              'video/mp4',
            );
            print('✅ [DirectChatScreen] Video đã được lưu vào public storage: $savedPath');
          } catch (e) {
            print('⚠️ [DirectChatScreen] Lỗi khi lưu video vào public storage: $e');
            // Don't fail the whole operation if saving to gallery fails
          }

          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Đã gửi video thành công!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            _scrollToBottomIfNeeded();
          }
        } catch (e, stackTrace) {
          print('❌ [DirectChatScreen] Lỗi khi xử lý video: $e');
          print('📋 [DirectChatScreen] Stack trace: $stackTrace');
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Lỗi khi gửi video: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ [DirectChatScreen] Lỗi khi chọn video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    // Check if conversation is blocked
    final conversation = _viewModel.conversation;
    if (conversation != null && conversation.status == 'BLOCKED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể ghi âm: Cuộc trò chuyện đã bị chặn'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần quyền truy cập microphone')),
          );
        }
        return;
      }

      await _audioRecorder.openRecorder();
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.startRecorder(
        toFile: path,
        codec: Codec.aacMP4,
        bitRate: 128000,
        sampleRate: 44100,
      );

      _recordingStartTime = DateTime.now();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording && _recordingStartTime != null) {
          setState(() {
            _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          });
        } else {
          timer.cancel();
        }
      });
    } catch (e) {
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
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      final path = await _audioRecorder.stopRecorder();
      
      setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });

      if (send && path != null && mounted) {
        // Check if conversation is blocked
        final conversation = _viewModel.conversation;
        if (conversation != null && conversation.status == 'BLOCKED') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể gửi ghi âm: Cuộc trò chuyện đã bị chặn'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final audioFile = File(path);
        if (!await audioFile.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File ghi âm không tồn tại')),
            );
          }
          return;
        }
        
        // Save audio file to public storage before uploading
        try {
          final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          final savedPath = await PublicFileStorageService.saveToPublicDirectory(
            audioFile,
            fileName,
            'audio',
            'audio/m4a',
          );
          print('✅ [DirectChatScreen] Audio file saved to public storage: $savedPath');
          
          // Save local path for message
          await MessageLocalPathService.saveLocalPath(
            'temp_${DateTime.now().millisecondsSinceEpoch}',
            savedPath,
            'audio',
            'm4a',
          );
        } catch (e) {
          print('⚠️ [DirectChatScreen] Failed to save audio to public storage: $e');
          // Continue with upload even if saving to public storage fails
        }
        
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          const SnackBar(content: Text('Đang upload ghi âm...')),
        );

        try {
          await _viewModel.uploadAudio(widget.conversationId, audioFile);
          if (mounted) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✅ Đã gửi ghi âm thành công!'),
                backgroundColor: Colors.green,
              ),
            );
            _scrollToBottomIfNeeded();
          }
        } catch (e) {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(content: Text('Lỗi khi gửi ghi âm: ${e.toString()}')),
            );
          }
        }
      }

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
    // Check if conversation is blocked
    final conversation = _viewModel.conversation;
    if (conversation != null && conversation.status == 'BLOCKED') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể gửi file: Cuộc trò chuyện đã bị chặn'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final messenger = ScaffoldMessenger.of(context);
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null && mounted) {
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;

        messenger.showSnackBar(
          const SnackBar(content: Text('Đang upload file...')),
        );

        try {
          await _viewModel.uploadFile(widget.conversationId, file);
          
          if (_viewModel.messages.isNotEmpty) {
            final lastMessage = _viewModel.messages.last;
            await MessageLocalPathService.saveLocalPath(
              lastMessage.id,
              file.path,
              PublicFileStorageService.getFileType(result.files.single.extension, fileName),
              PublicFileStorageService.getFileExtension(fileName),
            );
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  String _buildFullUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '${ApiClient.activeFileBaseUrl}$url';
  }

  void _showFullScreenImage(BuildContext context, DirectMessage message) {
    if (message.imageUrl == null) return;
    
    Navigator.of(context).push(
      SmoothPageRoute(
        page:
 _FullScreenImageViewer(
          imageUrl: _buildFullUrl(message.imageUrl!),
          message: message,
          onLongPress: () {
            Navigator.pop(context);
            _showImageOptionsBottomSheet(context, message);
          },
        ),
      ),
    );
  }

  Future<void> _showImageOptionsBottomSheet(BuildContext context, DirectMessage message) async {
    if (message.imageUrl == null) return;

    // Only allow delete for messages sent by current user
    final isMyMessage = _currentResidentId != null && message.senderId == _currentResidentId;

    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_circle),
              title: const Text('Tải ảnh về máy'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
            if (isMyMessage) ...[
              const Divider(),
              ListTile(
                leading: const Icon(CupertinoIcons.delete, color: Colors.red),
                title: const Text('Xóa ở phía tôi', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Chỉ bạn không thấy tin nhắn này'),
                onTap: () => Navigator.pop(context, 'delete_for_me'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.delete_simple, color: Colors.red),
                title: const Text('Xóa ở phía mọi người', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Mọi người đều không thấy tin nhắn này'),
                onTap: () => Navigator.pop(context, 'delete_for_everyone'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'download' && context.mounted) {
      await _downloadImageToGallery(context, message);
    } else if (result == 'delete_for_me' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_ME');
    } else if (result == 'delete_for_everyone' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_EVERYONE');
    }
  }

  Future<void> _showVideoOptionsBottomSheet(BuildContext context, DirectMessage message) async {
    if (message.fileUrl == null) return;

    // Only allow delete for messages sent by current user
    final isMyMessage = _currentResidentId != null && message.senderId == _currentResidentId;

    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_circle),
              title: const Text('Tải video về máy'),
              onTap: () => Navigator.pop(context, 'download'),
            ),
            if (isMyMessage) ...[
              const Divider(),
              ListTile(
                leading: const Icon(CupertinoIcons.delete, color: Colors.red),
                title: const Text('Xóa ở phía tôi', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Chỉ bạn không thấy tin nhắn này'),
                onTap: () => Navigator.pop(context, 'delete_for_me'),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.delete_simple, color: Colors.red),
                title: const Text('Xóa ở phía mọi người', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Mọi người đều không thấy tin nhắn này'),
                onTap: () => Navigator.pop(context, 'delete_for_everyone'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'delete_for_me' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_ME');
    } else if (result == 'delete_for_everyone' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_EVERYONE');
    }
    // Note: Download video is handled by the video widget itself
  }

  Future<void> _downloadImageToGallery(BuildContext context, DirectMessage message) async {
    if (message.imageUrl == null) return;

    try {
      final imageUrl = message.imageUrl!;
      final fullImageUrl = _buildFullUrl(imageUrl);
      
      String fileName = message.fileName ?? 
                       (imageUrl.split('/').isNotEmpty 
                        ? imageUrl.split('/').last.split('?').first 
                        : null) ??
                       'image_${message.id}.jpg';
      
      if (!fileName.contains('.')) {
        fileName = '$fileName.jpg';
      }
      
      final fileType = PublicFileStorageService.getFileType('image', fileName);
      final mimeType = PublicFileStorageService.getMimeTypeFromFileName(fileName);
      final existingPath = await PublicFileStorageService.getExistingFilePath(fileName, fileType, mimeType);
      
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang tải ảnh...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      await PublicFileStorageService.downloadAndSave(
        fullImageUrl,
        fileName,
        'image',
        'image/jpeg',
        (received, total) {},
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
          ),
        );
      }
    }
  }

  Future<void> _showMessageOptionsBottomSheet(BuildContext context, DirectMessage message) async {
    // Only allow edit/delete for messages sent by current user
    final isMyMessage = _currentResidentId != null && message.senderId == _currentResidentId;
    
    if (!isMyMessage) {
      // Don't show options for messages from other users
      return;
    }

    // Only allow edit for TEXT messages
    final canEdit = message.messageType == 'TEXT' && 
                    message.content != null && 
                    message.content!.isNotEmpty &&
                    !message.isDeleted;

    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit)
              ListTile(
                leading: const Icon(CupertinoIcons.pencil, color: Colors.blue),
                title: const Text('Chỉnh sửa', style: TextStyle(color: Colors.blue)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (canEdit)
              const Divider(),
            ListTile(
              leading: const Icon(CupertinoIcons.delete, color: Colors.red),
              title: const Text('Xóa ở phía tôi', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Chỉ bạn không thấy tin nhắn này'),
              onTap: () => Navigator.pop(context, 'delete_for_me'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.delete_simple, color: Colors.red),
              title: const Text('Xóa ở phía mọi người', style: TextStyle(color: Colors.red)),
              subtitle: const Text('Mọi người đều không thấy tin nhắn này'),
              onTap: () => Navigator.pop(context, 'delete_for_everyone'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == 'edit' && context.mounted) {
      await _editMessage(context, message);
    } else if (result == 'delete_for_me' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_ME');
    } else if (result == 'delete_for_everyone' && context.mounted) {
      await _deleteMessage(context, message, 'FOR_EVERYONE');
    }
  }

  Future<void> _editMessage(BuildContext context, DirectMessage message) async {
    final textController = TextEditingController(text: message.content ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh sửa tin nhắn'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Nhập nội dung tin nhắn...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final newContent = textController.text.trim();
              if (newContent.isNotEmpty) {
                Navigator.pop(context, newContent);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && context.mounted) {
      try {
        await _viewModel.editMessage(message.id, result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã chỉnh sửa tin nhắn'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi chỉnh sửa tin nhắn: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteMessage(BuildContext context, DirectMessage message, String deleteType) async {
    final deleteTypeText = deleteType == 'FOR_ME' 
        ? 'Xóa ở phía tôi (chỉ bạn không thấy tin nhắn này)'
        : 'Xóa ở phía mọi người (mọi người đều không thấy tin nhắn này)';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tin nhắn'),
        content: Text('Bạn có chắc chắn muốn $deleteTypeText?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Optimistic update: mark as deleted immediately
        _viewModel.markMessageAsDeleted(message.id, deleteType);
        
        await _chatService.deleteDirectMessage(
          conversationId: widget.conversationId,
          messageId: message.id,
          deleteType: deleteType,
        );
        
        // Refresh messages to ensure consistency with backend
        await _viewModel.loadMessages(widget.conversationId, refresh: true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(deleteType == 'FOR_ME' 
                  ? '✅ Đã xóa tin nhắn (chỉ bạn không thấy)'
                  : '✅ Đã xóa tin nhắn (mọi người đều không thấy)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        print('❌ [DirectChatScreen] Error deleting message: $e');
        // Revert optimistic update on error
        await _viewModel.loadMessages(widget.conversationId, refresh: true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi xóa tin nhắn: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showBlockConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chặn người dùng'),
        content: const Text(
          'Bạn có chắc chắn muốn chặn người dùng này? Sau khi chặn, bạn sẽ không thể gửi hoặc nhận tin nhắn từ người này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Chặn'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        if (_currentResidentId == null || _viewModel.conversation == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Không thể xác định người dùng để chặn'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final otherParticipantId = _viewModel.conversation!.getOtherParticipantId(_currentResidentId!);
        await _viewModel.blockUser(otherParticipantId);
        
        // Refresh conversation status
        await _viewModel.initialize(widget.conversationId);
        
        // Emit event to update badges and refresh blocked users list
        AppEventBus().emit('direct_chat_activity_updated');
        AppEventBus().emit('blocked_users_updated');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Đã chặn người dùng'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi khi chặn người dùng: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _unblockUser(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gỡ chặn'),
        content: const Text('Bạn có chắc chắn muốn gỡ chặn người dùng này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gỡ chặn'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (_currentResidentId == null || _viewModel.conversation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể xác định người dùng để bỏ chặn'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final otherParticipantId = _viewModel.conversation!.getOtherParticipantId(_currentResidentId!);
      await _viewModel.unblockUser(otherParticipantId);
      
      // Reload blocked users list
      await _loadBlockedUsers();
      
      // Refresh conversation status and messages
      await _viewModel.initialize(widget.conversationId);
      
      // Emit event to update badges and refresh blocked users list
      AppEventBus().emit('direct_chat_activity_updated');
      AppEventBus().emit('blocked_users_updated');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã bỏ chặn người dùng'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi bỏ chặn người dùng: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
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
          title: Text(
            widget.otherParticipantName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Consumer<DirectChatViewModel>(
              builder: (context, viewModel, child) {
                return PopupMenuButton<String>(
                  icon: const Icon(CupertinoIcons.ellipsis),
                  onSelected: (value) async {
                    if (value == 'block') {
                      await _showBlockConfirmation(context);
                    } else if (value == 'unblock') {
                      await _unblockUser(context);
                    } else if (value == 'files') {
                      Navigator.of(context).push(
                        SmoothPageRoute(
        page:
 DirectFilesScreen(
                            conversationId: widget.conversationId,
                            otherParticipantName: widget.otherParticipantName,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) {
                    // Check if current user has blocked the other participant
                    // Use isBlockedByMe instead of status == 'BLOCKED' to accurately detect if A has blocked B
                    final isBlockedByMe = _viewModel.conversation?.isBlockedByMe == true;
                    return [
                      const PopupMenuItem(
                        value: 'files',
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.folder, size: 20),
                            SizedBox(width: 8),
                            Text('Files & Ảnh'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      if (isBlockedByMe)
                        const PopupMenuItem(
                          value: 'unblock',
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.check_mark_circled, size: 20, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Bỏ chặn người dùng', style: TextStyle(color: Colors.green)),
                            ],
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'block',
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.xmark_circle, size: 20, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Chặn người dùng', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ];
                  },
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Consumer<DirectChatViewModel>(
                builder: (context, viewModel, child) {
                  final currentMessageCount = viewModel.messages.length;
                  final hasNewMessages = currentMessageCount > _lastMessageCount;
                  
                  if (hasNewMessages && mounted) {
                    _lastMessageCount = currentMessageCount;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_isUserScrolling) {
                        _scrollToBottomIfNeeded();
                      }
                    });
                  } else if (!hasNewMessages && currentMessageCount != _lastMessageCount) {
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
                    cacheExtent: 500,
                    key: const PageStorageKey<String>('direct_chat_messages_list'),
                    itemCount: viewModel.messages.length + (viewModel.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == viewModel.messages.length) {
                        return _DirectLoadMoreButton(
                          key: const ValueKey('load_more_button'),
                          isLoading: _isLoadingMore || viewModel.isLoading,
                          hasMore: viewModel.hasMore,
                          onLoadMore: _loadMoreMessages,
                        );
                      }

                      final message = viewModel.messages[viewModel.messages.length - 1 - index];
                      final messageKey = ValueKey<String>('message_${message.id}');
                      
                      if (message.messageType == 'SYSTEM') {
                        return _DirectSystemMessageBubble(
                          key: messageKey,
                          message: message,
                        );
                      }
                      
                      return SmoothAnimations.staggeredItem(
                        index: index,
                        child: _DirectMessageBubble(
                        key: messageKey,
                        message: message,
                        currentResidentId: _currentResidentId,
                        onImageTap: (msg) {
                          _showFullScreenImage(context, msg);
                        },
                        onDeepLinkTap: (deepLink) {
                          _handleDeepLink(deepLink);
                        },
                        onImageLongPress: (msg) {
                          _showImageOptionsBottomSheet(context, msg);
                        },
                        onVideoLongPress: (msg) {
                          _showVideoOptionsBottomSheet(context, msg);
                        },
                        onMessageLongPress: () {
                          _showMessageOptionsBottomSheet(context, message);
                        },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Consumer<DirectChatViewModel>(
              builder: (context, viewModel, child) {
                final isBlocked = _isConversationBlocked();
                final placeholderText = isBlocked ? _getBlockedPlaceholderText() : null;
                return _DirectMessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                  onPickImage: _pickImage,
                  onPickVideo: _pickVideo,
                  onStartRecording: _startRecording,
                  onStopRecording: _stopRecording,
                  onPickFile: _pickFile,
                  isRecording: _isRecording,
                  recordingDuration: _recordingDuration,
                  enabled: !isBlocked,
                  placeholderText: placeholderText,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleDeepLink(String deepLink) {
    // Parse deep-link: app://marketplace/post/{id}
    final uri = Uri.parse(deepLink);
    if (uri.scheme == 'app' && uri.host == 'marketplace' && uri.pathSegments.length >= 2) {
      final postId = uri.pathSegments[1];
      _navigateToPostDetail(postId);
    }
  }

  Future<void> _navigateToPostDetail(String postId) async {
    try {
      final marketplaceService = MarketplaceService();
      final post = await marketplaceService.getPostById(postId);
      if (mounted) {
        Navigator.push(
          context,
          SmoothPageRoute(
            page: PostDetailScreen(post: post),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // Check if error is 404 or post not found
        bool isPostDeleted = false;
        if (e is DioException) {
          // Check HTTP status code (404, 400, or 500 if backend throws RuntimeException)
          final statusCode = e.response?.statusCode;
          isPostDeleted = statusCode == 404 || statusCode == 400 || statusCode == 500;
          
          // Check error message in response data
          if (e.response?.data != null) {
            try {
              final responseData = e.response!.data;
              String errorMessage = '';
              if (responseData is Map) {
                errorMessage = (responseData['error']?.toString() ?? '').toLowerCase();
              } else {
                errorMessage = responseData.toString().toLowerCase();
              }
              if (errorMessage.contains('post not found') ||
                  errorMessage.contains('bài viết không tồn tại')) {
                isPostDeleted = true;
              }
            } catch (_) {
              // Ignore parsing errors
            }
          }
          
          // Check error message in DioException
          final errorMessage = (e.message?.toLowerCase() ?? '') + 
                              (e.toString().toLowerCase());
          if (errorMessage.contains('post not found') ||
              errorMessage.contains('bài viết không tồn tại')) {
            isPostDeleted = true;
          }
        } else {
          // Check exception message for "Post not found"
          final errorMessage = e.toString().toLowerCase();
          isPostDeleted = errorMessage.contains('post not found') ||
                         errorMessage.contains('404') || 
                         errorMessage.contains('not found') ||
                         errorMessage.contains('không tìm thấy') ||
                         errorMessage.contains('bài viết không tồn tại');
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPostDeleted 
                ? 'Bài viết đã bị xóa' 
                : 'Không thể tải bài viết: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

class _DirectLoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _DirectLoadMoreButton({
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

class _DirectSystemMessageBubble extends StatelessWidget {
  final DirectMessage message;

  const _DirectSystemMessageBubble({super.key, required this.message});

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
                      color: const Color(0xFF6B7280),
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

class _DirectMessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(ImageSource) onPickImage;
  final Function(ImageSource) onPickVideo;
  final VoidCallback onStartRecording;
  final Function({bool send}) onStopRecording;
  final VoidCallback onPickFile;
  final bool isRecording;
  final Duration recordingDuration;
  final bool enabled;
  final String? placeholderText;

  const _DirectMessageInput({
    required this.controller,
    required this.onSend,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPickFile,
    this.isRecording = false,
    this.recordingDuration = Duration.zero,
    this.enabled = true,
    this.placeholderText,
  });

  @override
  State<_DirectMessageInput> createState() => _DirectMessageInputState();
}

class _DirectMessageInputState extends State<_DirectMessageInput> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final newHasText = widget.controller.text.trim().isNotEmpty;
    if (newHasText != _hasText) {
      setState(() {
        _hasText = newHasText;
      });
    }
  }

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
          if (widget.isRecording)
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
                    _formatDuration(widget.recordingDuration),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => widget.onStopRecording(send: false),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => widget.onStopRecording(send: true),
                    child: const Text('Gửi'),
                  ),
                ],
              ),
            ),
          if (!widget.enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.person_crop_circle_badge_xmark,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.placeholderText ?? 'Hiện tại không tìm thấy người dùng',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                PopupMenuButton<String>(
                  icon: Icon(
                    widget.isRecording ? CupertinoIcons.mic_fill : CupertinoIcons.plus_circle,
                    color: widget.isRecording ? Colors.red : theme.colorScheme.primary,
                  ),
                  onSelected: (value) {
                    if (value == 'image_gallery') {
                      widget.onPickImage(ImageSource.gallery);
                    } else if (value == 'image_camera') {
                      widget.onPickImage(ImageSource.camera);
                    } else if (value == 'video_gallery') {
                      widget.onPickVideo(ImageSource.gallery);
                    } else if (value == 'video_camera') {
                      widget.onPickVideo(ImageSource.camera);
                    } else if (value == 'file') {
                      widget.onPickFile();
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
                      value: 'video_gallery',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.videocam, size: 20),
                          SizedBox(width: 8),
                          Text('Chọn video (10s)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'video_camera',
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.videocam_fill, size: 20),
                          SizedBox(width: 8),
                          Text('Quay video (10s)'),
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
                GestureDetector(
                  onLongPress: widget.isRecording ? null : widget.onStartRecording,
                  onLongPressEnd: (details) {
                    if (widget.isRecording) {
                      widget.onStopRecording(send: true);
                    }
                  },
                  child: IconButton(
                    icon: Icon(
                      widget.isRecording ? CupertinoIcons.mic_fill : CupertinoIcons.mic,
                      color: widget.isRecording ? Colors.red : theme.colorScheme.primary,
                    ),
                    onPressed: () {
                      if (widget.isRecording) {
                        widget.onStopRecording(send: true);
                      } else {
                        widget.onStartRecording();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    enabled: widget.enabled && !widget.isRecording,
                    decoration: InputDecoration(
                      hintText: widget.isRecording 
                          ? 'Đang ghi âm...' 
                          : (widget.placeholderText ?? 'Nhập tin nhắn...'),
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
                    widget.isRecording ? CupertinoIcons.stop_circle_fill : CupertinoIcons.paperplane_fill,
                    color: widget.isRecording ? Colors.red : Colors.white,
                  ),
                  onPressed: widget.isRecording
                      ? () {
                          print('🔵 [DirectMessageInput] Stop recording button pressed');
                          widget.onStopRecording(send: true);
                        }
                      : (!_hasText || !widget.enabled
                          ? null
                          : () {
                              print('🔵 [DirectMessageInput] Send button pressed');
                              print('   Controller text: "${widget.controller.text}"');
                              print('   Controller text trimmed: "${widget.controller.text.trim()}"');
                              print('   Is empty: ${widget.controller.text.trim().isEmpty}');
                              print('   _hasText: $_hasText');
                              try {
                                widget.onSend();
                                print('✅ [DirectMessageInput] onSend callback executed');
                              } catch (e, stackTrace) {
                                print('❌ [DirectMessageInput] Error in onSend callback: $e');
                                print('❌ [DirectMessageInput] Stack trace: $stackTrace');
                              }
                            }),
                  style: IconButton.styleFrom(
                    backgroundColor: widget.isRecording
                        ? Colors.red.withValues(alpha: 0.1)
                        : (_hasText && widget.enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                    foregroundColor: widget.isRecording ? Colors.red : Colors.white,
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

class _DirectMessageBubble extends StatelessWidget {
  final DirectMessage message;
  final String? currentResidentId;
  final Function(DirectMessage)? onImageTap;
  final Function(DirectMessage)? onImageLongPress;
  final Function(DirectMessage)? onVideoLongPress;
  final Function(String)? onDeepLinkTap;
  final VoidCallback? onMessageLongPress;

  const _DirectMessageBubble({
    super.key,
    required this.message,
    this.currentResidentId,
    this.onImageTap,
    this.onImageLongPress,
    this.onVideoLongPress,
    this.onDeepLinkTap,
    this.onMessageLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMe = currentResidentId != null && message.senderId == currentResidentId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onMessageLongPress,
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
            if (message.isDeleted == true)
              Text(
                message.deleteType == 'FOR_ME' 
                    ? 'Đã xóa ở phía tôi'
                    : message.deleteType == 'FOR_EVERYONE'
                        ? 'Đã xóa ở phía mọi người'
                        : 'Đã xóa',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isMe
                      ? Colors.white.withValues(alpha: 0.6)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
              )
            else if (message.messageType == 'IMAGE' && message.imageUrl != null)
              Builder(
                builder: (context) {
                  final fullImageUrl = _buildFullUrl(message.imageUrl!);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () => onImageTap?.call(message),
                      onLongPress: () => onImageLongPress?.call(message),
                      child: CachedNetworkImage(
                        imageUrl: fullImageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 200,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
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
                        ),
                      ),
                    ),
                  );
                },
              )
            else if (message.messageType == 'AUDIO' && message.fileUrl != null)
              _DirectAudioMessageWidget(
                audioUrl: _buildFullUrl(message.fileUrl!),
                isMe: isMe,
                theme: theme,
              )
            else if (message.messageType == 'VIDEO' && message.fileUrl != null)
              _DirectVideoMessageWidget(
                messageId: message.id,
                videoUrl: _buildFullUrl(message.fileUrl!),
                fileName: message.fileName ?? 'video.mp4',
                fileSize: message.fileSize ?? 0,
                senderId: message.senderId ?? '',
                currentResidentId: currentResidentId,
                isMe: isMe,
                theme: theme,
                onLongPress: () => onVideoLongPress?.call(message),
              )
            else if (message.messageType == 'FILE' && message.fileUrl != null)
              _DirectFileMessageWidget(
                messageId: message.id,
                fileUrl: _buildFullUrl(message.fileUrl!),
                fileName: message.fileName ?? 'File',
                fileSize: message.fileSize ?? 0,
                mimeType: message.mimeType,
                senderId: message.senderId ?? '',
                currentResidentId: currentResidentId,
                isMe: isMe,
                theme: theme,
              )
            else if (message.messageType == 'MARKETPLACE_POST' && message.content != null)
              _MarketplacePostCard(
                postStatus: message.postStatus,
                postId: message.postId ?? '',
                postTitle: message.postTitle ?? '',
                postThumbnailUrl: message.postThumbnailUrl,
                postPrice: message.postPrice,
                deepLink: message.deepLink ?? '',
                theme: theme,
                onTap: () {
                  // Handle deep-link navigation - only if post is not deleted
                  if (message.postStatus != 'DELETED' &&
                      message.deepLink != null && 
                      message.deepLink!.isNotEmpty && 
                      onDeepLinkTap != null) {
                    onDeepLinkTap!(message.deepLink!);
                  }
                },
              )
            else if (message.content != null && message.content!.isNotEmpty)
              LinkableText(
                text: message.content!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isMe ? Colors.white : theme.colorScheme.onSurface,
                ),
                linkColor: isMe ? Colors.blue.shade300 : Colors.blue.shade700,
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
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '${ApiClient.activeFileBaseUrl}$url';
  }
}

class _DirectAudioMessageWidget extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final ThemeData theme;

  const _DirectAudioMessageWidget({
    required this.audioUrl,
    required this.isMe,
    required this.theme,
  });

  @override
  State<_DirectAudioMessageWidget> createState() => _DirectAudioMessageWidgetState();
}

class _DirectAudioMessageWidgetState extends State<_DirectAudioMessageWidget> {
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
        if (state.processingState == ProcessingState.completed) {
          // Reset to 00:00 and change button to Play when finished
          _resetAudioState();
          _audioPlayer.seek(Duration.zero);
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
      await _audioPlayer.pause();
      await _audioPlayer.seek(Duration.zero);
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    } catch (e) {
      print('⚠️ [DirectAudioMessageWidget] Error resetting audio state: $e');
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
        if (_position >= _duration && _duration > Duration.zero) {
          await _audioPlayer.seek(Duration.zero);
          setState(() {
            _position = Duration.zero;
          });
        }
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

class _DirectFileMessageWidget extends StatefulWidget {
  final String messageId;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final String senderId;
  final String? currentResidentId;
  final bool isMe;
  final ThemeData theme;

  const _DirectFileMessageWidget({
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
  State<_DirectFileMessageWidget> createState() => _DirectFileMessageWidgetState();
}

class _DirectFileMessageWidgetState extends State<_DirectFileMessageWidget> {
  String? _cachedFilePath;
  bool _isCheckingCache = true;
  bool _isDownloading = false;
  int _lastProgressPercent = -1;

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
      
      final fileType = PublicFileStorageService.getFileType(widget.mimeType, widget.fileName);
      final existingPath = await PublicFileStorageService.getExistingFilePath(
        widget.fileName,
        fileType,
        widget.mimeType,
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
      
      if (mounted) {
        setState(() {
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
    if (mimeType != null) {
      if (mimeType.startsWith('image/')) return CupertinoIcons.photo_fill;
      if (mimeType.startsWith('video/')) return CupertinoIcons.videocam_fill;
      if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
      if (mimeType == 'application/pdf') return CupertinoIcons.doc_text_fill;
      if (mimeType.contains('word') || mimeType.contains('document')) return CupertinoIcons.doc_fill;
      if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return CupertinoIcons.table_fill;
      if (mimeType.contains('zip') || mimeType.contains('archive')) return CupertinoIcons.archivebox_fill;
    }
    
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf': return CupertinoIcons.doc_text_fill;
      case 'doc':
      case 'docx': return CupertinoIcons.doc_fill;
      case 'xls':
      case 'xlsx': return CupertinoIcons.table_fill;
      case 'zip':
      case 'rar': return CupertinoIcons.archivebox_fill;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif': return CupertinoIcons.photo_fill;
      case 'mp4':
      case 'avi':
      case 'mov': return CupertinoIcons.videocam_fill;
      default: return CupertinoIcons.doc_fill;
    }
  }

  Future<void> _downloadAndOpenFile(BuildContext context) async {
    if (_isDownloading) return;

    if (_cachedFilePath != null) {
      await _openFile(context, _cachedFilePath!);
      return;
    }

    setState(() {
      _isDownloading = true;
      _lastProgressPercent = -1;
    });
    
    try {
      final messenger = ScaffoldMessenger.of(context);
      final fileType = PublicFileStorageService.getFileType(widget.mimeType, widget.fileName);
      
      // Check if file already exists before downloading
      final existingPath = await PublicFileStorageService.getExistingFilePath(
        widget.fileName,
        fileType,
        widget.mimeType,
      );
      
      if (existingPath != null) {
        if (mounted) {
          setState(() {
            _cachedFilePath = existingPath;
            _isDownloading = false;
          });
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('File đã có trong máy, đang mở...'),
            duration: Duration(seconds: 1),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await _openFile(context, existingPath);
        return;
      }
      
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đang tải file: ${widget.fileName}'),
          duration: const Duration(days: 1),
        ),
      );

      final savedPath = await PublicFileStorageService.downloadAndSave(
        widget.fileUrl.startsWith('http') 
            ? widget.fileUrl 
            : '${ApiClient.activeFileBaseUrl}${widget.fileUrl}',
        widget.fileName,
        fileType,
        widget.mimeType,
        (received, total) {
          if (total > 0 && context.mounted) {
            final progressPercent = ((received / total) * 100).toInt();
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

      if (context.mounted) {
        messenger.hideCurrentSnackBar();
      }

      if (mounted) {
        setState(() {
          _cachedFilePath = savedPath;
          _isDownloading = false;
        });
      }

      await _openFile(context, savedPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
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
      // Check if filePath is a MediaStore URI (content://) or a file path
      final isMediaStoreUri = filePath.startsWith('content://');
      
      if (!isMediaStoreUri) {
        // Check if file exists (for regular file paths)
        final file = File(filePath);
        if (!await file.exists()) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File không tồn tại')),
            );
          }
          return;
        }
      }

      String? mimeType = widget.mimeType;
      if (mimeType == null || mimeType.isEmpty) {
        mimeType = _getMimeTypeFromFileName(widget.fileName);
      }

      // Open file with mimeType (OpenFile supports both file paths and content URIs)
      final result = await OpenFile.open(
        filePath,
        type: mimeType ?? 'application/octet-stream',
      );
      
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
      }
    } catch (e) {
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
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'zip': return 'application/zip';
      case 'jpg':
      case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      default: return null;
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
  final DirectMessage message;
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

class _DirectVideoMessageWidget extends StatefulWidget {
  final String messageId;
  final String videoUrl;
  final String fileName;
  final int fileSize;
  final String senderId;
  final String? currentResidentId;
  final bool isMe;
  final ThemeData theme;
  final VoidCallback? onLongPress;

  const _DirectVideoMessageWidget({
    required this.messageId,
    required this.videoUrl,
    required this.fileName,
    required this.fileSize,
    required this.senderId,
    this.currentResidentId,
    required this.isMe,
    required this.theme,
    this.onLongPress,
  });

  @override
  State<_DirectVideoMessageWidget> createState() => _DirectVideoMessageWidgetState();
}

class _DirectVideoMessageWidgetState extends State<_DirectVideoMessageWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isLoading = true;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Skip ImageKit videos - ImageKit is out of storage and blocking requests
      String videoUrl = widget.videoUrl;
      if (_isImageKitUrl(videoUrl)) {
        debugPrint('⚠️ [DirectChatVideo] Skipping ImageKit video (out of storage): $videoUrl');
        if (mounted) {
          setState(() {
            _error = 'Video ImageKit không khả dụng do hết dung lượng';
            _isLoading = false;
          });
        }
        return;
      }
      
      // Use database video URL directly
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );

      await _controller!.initialize();
      
      // Add listener to update position and duration
      _controller!.addListener(_videoListener);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
          _duration = _controller!.value.duration;
          _position = _controller!.value.position;
        });
      }
    } catch (e) {
      debugPrint('❌ [DirectVideoMessageWidget] Lỗi khởi tạo video: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _videoListener() {
    if (mounted && _controller != null) {
      setState(() {
        _isPlaying = _controller!.value.isPlaying;
        _duration = _controller!.value.duration;
        _position = _controller!.value.position;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  /// Check if URL is from ImageKit
  bool _isImageKitUrl(String url) {
    if (url.isEmpty) return false;
    return url.contains('ik.imagekit.io') || url.contains('imagekit.io');
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadVideo(BuildContext context) async {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đang tải video: ${widget.fileName}'),
          duration: const Duration(days: 1),
        ),
      );

      final fileType = PublicFileStorageService.getFileType('video/mp4', widget.fileName);
      await PublicFileStorageService.downloadAndSave(
        widget.videoUrl,
        widget.fileName,
        fileType,
        'video/mp4',
        (received, total) {
          if (total > 0 && context.mounted) {
            final progressPercent = ((received / total) * 100).toInt();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đang tải: $progressPercent%'),
                duration: const Duration(days: 1),
              ),
            );
          }
        },
      );

      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Đã tải video thành công!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi tải video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  void _showVideoOptions(BuildContext context) {
    showSmoothBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.arrow_down_circle,
                color: widget.theme.colorScheme.primary,
              ),
              title: const Text('Tải video về máy'),
              onTap: () {
                Navigator.pop(context);
                _downloadVideo(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenVideo() {
    if (_controller == null || !_isInitialized) return;
    
    final context = this.context;
    Navigator.push(
      context,
      SmoothPageRoute(
        page:
 _FullScreenVideoViewer(
          controller: _controller!,
          videoUrl: widget.videoUrl,
          fileName: widget.fileName,
          fileSize: widget.fileSize,
          theme: widget.theme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Đang tải video...',
                style: widget.theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null || !_isInitialized || _controller == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: widget.theme.colorScheme.onErrorContainer,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'Không thể tải video',
              style: widget.theme.textTheme.bodySmall?.copyWith(
                color: widget.theme.colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _showFullScreenVideo,
      onLongPress: widget.onLongPress ?? () => _showVideoOptions(context),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 300,
          maxWidth: 250,
        ),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            // Video player - fill container
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            ),
            // Play/Pause overlay
            Center(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            // Duration and file size (bottom)
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Duration (current / total)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // File size
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatFileSize(widget.fileSize),
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Full screen icon (top right)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  CupertinoIcons.fullscreen,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenVideoViewer extends StatefulWidget {
  final VideoPlayerController controller;
  final String videoUrl;
  final String fileName;
  final int fileSize;
  final ThemeData theme;

  const _FullScreenVideoViewer({
    required this.controller,
    required this.videoUrl,
    required this.fileName,
    required this.fileSize,
    required this.theme,
  });

  @override
  State<_FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<_FullScreenVideoViewer> {
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.controller.value.isPlaying;
    _duration = widget.controller.value.duration;
    _position = widget.controller.value.position;
    widget.controller.addListener(_videoListener);
  }

  void _videoListener() {
    if (mounted && !_isDragging) {
      setState(() {
        _isPlaying = widget.controller.value.isPlaying;
        _duration = widget.controller.value.duration;
        _position = widget.controller.value.position;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      if (_isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _seekTo(Duration position) async {
    await widget.controller.seekTo(position);
    if (mounted) {
      setState(() {
        _position = position;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadVideo() async {
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đang tải video: ${widget.fileName}'),
          duration: const Duration(days: 1),
        ),
      );

      final fileType = PublicFileStorageService.getFileType('video/mp4', widget.fileName);
      await PublicFileStorageService.downloadAndSave(
        widget.videoUrl,
        widget.fileName,
        fileType,
        'video/mp4',
        (received, total) {
          if (total > 0 && context.mounted) {
            final progressPercent = ((received / total) * 100).toInt();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đang tải: $progressPercent%'),
                duration: const Duration(days: 1),
              ),
            );
          }
        },
      );

      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Đã tải video thành công!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi khi tải video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showVideoOptions() {
    showSmoothBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: widget.theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: widget.theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(
                CupertinoIcons.arrow_down_circle,
                color: widget.theme.colorScheme.primary,
              ),
              title: const Text('Tải video về máy'),
              onTap: () {
                Navigator.pop(context);
                _downloadVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_videoListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video player
            Center(
              child: AspectRatio(
                aspectRatio: widget.controller.value.aspectRatio,
                child: VideoPlayer(widget.controller),
              ),
            ),
            // Controls overlay
            if (_showControls)
              Stack(
                children: [
                  // Top bar with back button
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                CupertinoIcons.back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.fileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatFileSize(widget.fileSize),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                CupertinoIcons.ellipsis,
                                color: Colors.white,
                              ),
                              onPressed: _showVideoOptions,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Center play/pause button
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Icon(
                          _isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                  // Bottom controls with seek bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Seek slider
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                thumbColor: Colors.white,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              ),
                              child: Slider(
                                value: _duration.inMilliseconds > 0
                                    ? _position.inMilliseconds.toDouble()
                                    : 0.0,
                                max: _duration.inMilliseconds > 0
                                    ? _duration.inMilliseconds.toDouble()
                                    : 1.0,
                                onChanged: (value) {
                                  setState(() {
                                    _isDragging = true;
                                    _position = Duration(milliseconds: value.toInt());
                                  });
                                },
                                onChangeEnd: (value) {
                                  _seekTo(Duration(milliseconds: value.toInt()));
                                  setState(() {
                                    _isDragging = false;
                                  });
                                },
                              ),
                            ),
                            // Duration text
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(_position),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _formatDuration(_duration),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MarketplacePostCard extends StatelessWidget {
  final String postId;
  final String postTitle;
  final String? postThumbnailUrl;
  final double? postPrice;
  final String deepLink;
  final String? postStatus; // ACTIVE, SOLD, DELETED
  final ThemeData theme;
  final VoidCallback onTap;

  const _MarketplacePostCard({
    required this.postId,
    required this.postTitle,
    this.postThumbnailUrl,
    this.postPrice,
    required this.deepLink,
    this.postStatus,
    required this.theme,
    required this.onTap,
  });

  String _formatPrice(double? price) {
    if (price == null) return 'Thỏa thuận';
    return '${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} đ';
  }

  @override
  Widget build(BuildContext context) {
    final isDeleted = postStatus == 'DELETED';
    
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: isDeleted 
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDeleted
              ? theme.colorScheme.error.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: isDeleted
          ? // Deleted post UI
          Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.delete,
                    color: theme.colorScheme.error.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bài viết này đã bị xoá',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : // Active post UI
          GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thumbnail
                  if (postThumbnailUrl != null && postThumbnailUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: CachedNetworkImage(
                        imageUrl: postThumbnailUrl!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 150,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 150,
                          color: theme.colorScheme.errorContainer,
                          child: Icon(
                            CupertinoIcons.photo,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          postTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        // Price
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.money_dollar,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatPrice(postPrice),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Link indicator
                        Row(
                          children: [
                            Icon(
                              CupertinoIcons.link,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Xem bài viết',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}


