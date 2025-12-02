import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat/direct_message.dart';
import '../models/chat/conversation.dart';
import 'chat_service.dart';

class DirectChatViewModel extends ChangeNotifier {
  final ChatService _service;
  
  List<DirectMessage> _messages = [];
  Conversation? _conversation;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _currentPage = 0;
  final int _pageSize = 25;

  DirectChatViewModel(this._service);

  List<DirectMessage> get messages => _messages;
  Conversation? get conversation => _conversation;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _hasMore;

  Future<void> initialize(String conversationId) async {
    _isLoading = true;
    _error = null;
    _currentPage = 0;
    _hasMore = true;
    _messages = [];
    notifyListeners();

    try {
      print('📤 [DirectChatViewModel] Initializing conversation: $conversationId');
      
      // Load conversation
      _conversation = await _service.getConversation(conversationId);
      
      print('✅ [DirectChatViewModel] Conversation loaded:');
      print('   ID: ${_conversation?.id}');
      print('   Status: ${_conversation?.status}');
      print('   Participant1: ${_conversation?.participant1Id}');
      print('   Participant2: ${_conversation?.participant2Id}');
      
      if (_conversation != null && _conversation!.status != 'ACTIVE') {
        print('⚠️ [DirectChatViewModel] Conversation status is not ACTIVE: ${_conversation!.status}');
      }
      
      // Load initial messages
      await loadMessages(conversationId, refresh: true);
    } catch (e) {
      _error = 'Lỗi khi khởi tạo: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error initializing: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMessages(String conversationId, {bool refresh = false}) async {
    if (refresh) {
      _currentPage = 0;
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    if (refresh) {
      _isLoading = true;
    } else {
      _isLoadingMore = true;
    }
    _error = null;
    notifyListeners();

    try {
      final response = await _service.getDirectMessages(
        conversationId: conversationId,
        page: _currentPage,
        size: _pageSize,
      );

      if (refresh) {
        _messages = response.content.reversed.toList(); // Reverse to show oldest first
      } else {
        _messages.insertAll(0, response.content.reversed.toList());
      }

      _currentPage++;
      _hasMore = response.hasNext;

      _isLoading = false;
      _isLoadingMore = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _isLoadingMore = false;
      _error = 'Lỗi khi tải tin nhắn: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error loading messages: $e');
      notifyListeners();
    }
  }

  Future<void> sendMessage({
    required String conversationId,
    String? content,
    String? messageType,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyToMessageId,
  }) async {
    print('🔵 [DirectChatViewModel] sendMessage called');
    print('   Conversation ID: $conversationId');
    print('   Message type: ${messageType ?? "TEXT"}');
    if (content != null && content.isNotEmpty) {
      print('   Content preview: ${content.substring(0, content.length > 50 ? 50 : content.length)}...');
    } else {
      print('   Content: null or empty');
    }
    print('   Current conversation status: ${_conversation?.status}');
    
    try {
      print('📤 [DirectChatViewModel] Calling _service.sendDirectMessage...');
      final message = await _service.sendDirectMessage(
        conversationId: conversationId,
        content: content,
        messageType: messageType,
        imageUrl: imageUrl,
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        replyToMessageId: replyToMessageId,
      );

      print('✅ [DirectChatViewModel] Message received from service');
      print('   Message ID: ${message.id}');
      print('   Message type: ${message.messageType}');
      
      _messages.add(message);
      
      // Refresh conversation to ensure status is up-to-date
      try {
        print('🔄 [DirectChatViewModel] Refreshing conversation after sending message...');
        _conversation = await _service.getConversation(conversationId);
        print('✅ [DirectChatViewModel] Conversation refreshed. Status: ${_conversation?.status}');
      } catch (e) {
        print('⚠️ [DirectChatViewModel] Failed to refresh conversation after sending: $e');
        // Don't fail the send operation if refresh fails
      }
      
      notifyListeners();
      print('✅ [DirectChatViewModel] Message added to list and listeners notified');
    } catch (e, stackTrace) {
      _error = 'Lỗi khi gửi tin nhắn: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error sending message: $e');
      print('❌ [DirectChatViewModel] Stack trace: $stackTrace');
      notifyListeners();
      rethrow;
    }
  }

  void addIncomingMessage(DirectMessage message) {
    if (!_messages.any((m) => m.id == message.id)) {
      _messages.add(message);
      notifyListeners();
    }
  }

  Future<void> uploadImage(String conversationId, XFile image) async {
    try {
      final imageUrl = await _service.uploadDirectImage(
        conversationId: conversationId,
        image: image,
      );
      await sendMessage(
        conversationId: conversationId,
        messageType: 'IMAGE',
        imageUrl: imageUrl,
      );
    } catch (e) {
      _error = 'Lỗi khi upload ảnh: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error uploading image: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uploadImages(String conversationId, List<XFile> images) async {
    try {
      final imageUrls = await _service.uploadDirectImages(
        conversationId: conversationId,
        images: images,
      );
      
      // Send each image as a separate message
      for (final imageUrl in imageUrls) {
        await sendMessage(
          conversationId: conversationId,
          messageType: 'IMAGE',
          imageUrl: imageUrl,
        );
      }
    } catch (e) {
      _error = 'Lỗi khi upload ảnh: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error uploading images: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uploadAudio(String conversationId, File audioFile) async {
    try {
      final result = await _service.uploadDirectAudio(
        conversationId: conversationId,
        audioFile: audioFile,
      );
      
      await sendMessage(
        conversationId: conversationId,
        messageType: 'AUDIO',
        fileUrl: result['fileUrl'],
        fileName: result['fileName'] ?? 'audio.m4a',
        fileSize: int.tryParse(result['fileSize']?.toString() ?? '0'),
        mimeType: result['mimeType'] ?? 'audio/m4a',
      );
    } catch (e) {
      _error = 'Lỗi khi upload audio: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error uploading audio: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uploadFile(String conversationId, File file) async {
    try {
      final result = await _service.uploadDirectFile(
        conversationId: conversationId,
        file: file,
      );
      
      await sendMessage(
        conversationId: conversationId,
        messageType: 'FILE',
        fileUrl: result['fileUrl'],
        fileName: result['fileName'] ?? 'file',
        fileSize: int.tryParse(result['fileSize']?.toString() ?? '0'),
        mimeType: result['mimeType'] ?? 'application/octet-stream',
      );
    } catch (e) {
      _error = 'Lỗi khi upload file: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error uploading file: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uploadVideo(String conversationId, File videoFile) async {
    try {
      final result = await _service.uploadDirectVideo(
        conversationId: conversationId,
        videoFile: videoFile,
      );
      
      await sendMessage(
        conversationId: conversationId,
        messageType: 'VIDEO',
        fileUrl: result['fileUrl'],
        fileName: result['fileName'] ?? 'video.mp4',
        fileSize: int.tryParse(result['fileSize']?.toString() ?? '0'),
        mimeType: result['mimeType'] ?? 'video/mp4',
      );
    } catch (e) {
      _error = 'Lỗi khi upload video: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error uploading video: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> blockUser(String blockedId) async {
    try {
      await _service.blockUser(blockedId);
      // Refresh conversation to get updated status
      if (_conversation != null) {
        _conversation = await _service.getConversation(_conversation!.id);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Lỗi khi chặn người dùng: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error blocking user: $e');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> unblockUser(String blockedId) async {
    try {
      await _service.unblockUser(blockedId);
      // Refresh conversation to get updated status
      if (_conversation != null) {
        _conversation = await _service.getConversation(_conversation!.id);
        notifyListeners();
      }
    } catch (e) {
      _error = 'Lỗi khi bỏ chặn người dùng: ${e.toString()}';
      print('❌ [DirectChatViewModel] Error unblocking user: $e');
      notifyListeners();
      rethrow;
    }
  }
}

