import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat/message.dart';
import '../models/chat/group.dart';
import '../profile/profile_service.dart';
import '../auth/api_client.dart';
import 'chat_service.dart';

class ChatMessageViewModel extends ChangeNotifier {
  final ChatService _service;

  ChatMessageViewModel(this._service);

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  int _currentPage = 0;
  bool _hasMore = true;
  String? _groupId;
  String? _groupName;
  String? _currentUserId;
  String? _currentResidentId;
  ChatGroup? _group;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String? get groupName => _groupName;
  String? get currentUserId => _currentUserId;
  String? get currentResidentId => _currentResidentId;
  ChatGroup? get group => _group;
  
  bool get isCreator => _group != null && _currentResidentId != null && 
      _group!.createdBy == _currentResidentId;

  Future<void> initialize(String groupId) async {
    _groupId = groupId;
    _isLoading = true;
    notifyListeners();
    await _loadCurrentUser();
    await loadGroupInfo(); // Load group info first to show name immediately
    _isLoading = false;
    notifyListeners();
    await loadMessages(refresh: true);
    await markAsRead();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final profileService = ProfileService(ApiClient().dio);
      final profile = await profileService.getProfile();
      _currentUserId = profile['id']?.toString();
      _currentResidentId = profile['residentId']?.toString();
    } catch (e) {
      debugPrint('Error loading current user: $e');
    }
  }

  Future<void> markAsRead() async {
    try {
      await _service.markMessagesAsRead(_groupId!);
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  Future<void> loadGroupInfo() async {
    try {
      final group = await _service.getGroupById(_groupId!);
      _group = group;
      _groupName = group.name;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading group info: $e');
    }
  }

  Future<void> updateGroupName(String newName) async {
    try {
      final updatedGroup = await _service.updateGroup(
        groupId: _groupId!,
        name: newName,
      );
      _group = updatedGroup;
      _groupName = updatedGroup.name;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi đổi tên nhóm: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> leaveGroup() async {
    try {
      await _service.leaveGroup(_groupId!);
    } catch (e) {
      _error = 'Lỗi khi rời nhóm: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteGroup() async {
    try {
      await _service.deleteGroup(_groupId!);
    } catch (e) {
      _error = 'Lỗi khi xóa nhóm: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadMessages({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 0;
      _messages = [];
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;
    if (_isLoading && !refresh) return; // Prevent multiple simultaneous loads

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load only 25 messages per page for better performance
      final response = await _service.getMessages(
        groupId: _groupId!,
        page: _currentPage,
        size: 25,
      );

      if (refresh) {
        // When refreshing, replace all messages with newest ones
        _messages = response.content.reversed.toList();
      } else {
        // When loading more, insert older messages at the beginning
        // Messages are returned in descending order (newest first), so we reverse them
        _messages.insertAll(0, response.content.reversed);
      }

      _currentPage++;
      _hasMore = response.hasNext;

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Lỗi khi tải tin nhắn: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<void> sendMessage(String content) async {
    try {
      final message = await _service.sendMessage(
        groupId: _groupId!,
        content: content,
      );
      // Append new message to the end (newest messages are at the end)
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi gửi tin nhắn: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<String> uploadImage(XFile image) async {
    try {
      print('📤 [ChatMessageViewModel] Bắt đầu upload ảnh, groupId: $_groupId');
      final imageUrl = await _service.uploadImage(
        groupId: _groupId!,
        image: image,
      );
      print('✅ [ChatMessageViewModel] Upload ảnh thành công, imageUrl: $imageUrl');
      return imageUrl;
    } catch (e, stackTrace) {
      print('❌ [ChatMessageViewModel] Lỗi khi upload ảnh: $e');
      print('📋 [ChatMessageViewModel] Stack trace: $stackTrace');
      _error = 'Lỗi khi upload ảnh: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendImageMessage(String imageUrl) async {
    try {
      print('📨 [ChatMessageViewModel] Bắt đầu gửi message ảnh, imageUrl: $imageUrl');
      final message = await _service.sendMessage(
        groupId: _groupId!,
        messageType: 'IMAGE',
        imageUrl: imageUrl,
      );
      print('✅ [ChatMessageViewModel] Gửi message thành công!');
      print('📋 [ChatMessageViewModel] Message ID: ${message.id}');
      print('📋 [ChatMessageViewModel] Message type: ${message.messageType}');
      print('📋 [ChatMessageViewModel] Message imageUrl: ${message.imageUrl}');
      print('📋 [ChatMessageViewModel] Tổng số messages hiện tại: ${_messages.length}');
      
      _messages.add(message);
      print('✅ [ChatMessageViewModel] Đã thêm message vào list, tổng số: ${_messages.length}');
      notifyListeners();
      print('✅ [ChatMessageViewModel] Đã notify listeners');
    } catch (e, stackTrace) {
      print('❌ [ChatMessageViewModel] Lỗi khi gửi ảnh: $e');
      print('📋 [ChatMessageViewModel] Stack trace: $stackTrace');
      _error = 'Lỗi khi gửi ảnh: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  /// Upload multiple images and send each as a separate message
  Future<void> uploadAndSendMultipleImages(List<XFile> images) async {
    try {
      print('📤 [ChatMessageViewModel] Bắt đầu upload ${images.length} ảnh');
      
      // Upload all images in parallel
      final imageUrls = await _service.uploadImages(
        groupId: _groupId!,
        images: images,
      );
      
      print('✅ [ChatMessageViewModel] Upload ${imageUrls.length} ảnh thành công');
      
      // Send each image as a separate message (sequentially to maintain order)
      for (var imageUrl in imageUrls) {
        await sendImageMessage(imageUrl);
        // Small delay to ensure messages are sent in order
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      print('✅ [ChatMessageViewModel] Đã gửi ${imageUrls.length} ảnh thành công');
    } catch (e, stackTrace) {
      print('❌ [ChatMessageViewModel] Lỗi khi upload/gửi nhiều ảnh: $e');
      print('📋 [ChatMessageViewModel] Stack trace: $stackTrace');
      _error = 'Lỗi khi gửi ảnh: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadAudio(File audioFile) async {
    try {
      return await _service.uploadAudio(
        groupId: _groupId!,
        audioFile: audioFile,
      );
    } catch (e) {
      _error = 'Lỗi khi upload audio: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendAudioMessage(String audioUrl, int fileSize) async {
    try {
      final message = await _service.sendMessage(
        groupId: _groupId!,
        messageType: 'AUDIO',
        fileUrl: audioUrl,
        fileSize: fileSize,
      );
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi gửi ghi âm: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadFile(File file) async {
    try {
      return await _service.uploadFile(
        groupId: _groupId!,
        file: file,
      );
    } catch (e) {
      _error = 'Lỗi khi upload file: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> sendFileMessage(String fileUrl, String fileName, int fileSize, String? mimeType) async {
    try {
      final message = await _service.sendMessage(
        groupId: _groupId!,
        messageType: 'FILE',
        fileUrl: fileUrl,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
      );
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi gửi file: ${e.toString()}';
      notifyListeners();
      rethrow;
    }
  }

  /// Add a new incoming message (from WebSocket or real-time updates)
  void addIncomingMessage(ChatMessage message) {
    // Check if message already exists to avoid duplicates
    if (!_messages.any((m) => m.id == message.id)) {
      _messages.add(message);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadMessages(refresh: true);
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await loadMessages();
  }
}

