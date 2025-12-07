import 'package:flutter/foundation.dart';
import '../models/chat/group.dart';
import 'chat_service.dart';

class ChatViewModel extends ChangeNotifier {
  final ChatService _service;

  ChatViewModel(this._service);

  List<ChatGroup> _groups = [];
  bool _isLoading = false;
  String? _error;
  int _currentPage = 0;
  bool _hasMore = true;

  List<ChatGroup> get groups => _groups;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasMore => _hasMore;

  Future<void> initialize() async {
    await loadGroups(refresh: true);
  }

  Future<void> loadGroups({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 0;
      _groups = [];
      _hasMore = true;
    }

    if (!_hasMore && !refresh) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _service.getMyGroups(
        page: _currentPage,
        size: 20,
      );

      if (refresh) {
        _groups = response.content;
      } else {
        _groups.addAll(response.content);
      }

      _currentPage++;
      _hasMore = response.hasNext;

      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // Only show error if it's not a 404 (404 might mean no groups, which is normal)
      final errorStr = e.toString();
      if (errorStr.contains('404') || errorStr.contains('not found')) {
        // 404 is handled gracefully in service, return empty list
        _groups = refresh ? [] : _groups;
        _hasMore = false;
        _error = null; // Don't show error for 404
      } else {
        _error = 'Lỗi khi tải danh sách nhóm: ${e.toString()}';
      }
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadGroups(refresh: true);
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await loadGroups();
  }
}

