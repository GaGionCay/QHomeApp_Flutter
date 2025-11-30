import 'package:flutter/foundation.dart';
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

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _service.getMessages(
        groupId: _groupId!,
        page: _currentPage,
        size: 50,
      );

      if (refresh) {
        _messages = response.content.reversed.toList();
      } else {
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
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi khi gửi tin nhắn: ${e.toString()}';
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

  @override
  void dispose() {
    super.dispose();
  }
}

