import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat/group.dart';
import '../models/chat/message.dart';
import '../models/chat/invitation.dart';
import '../models/chat/invite_members_response.dart';
import 'chat_api_client.dart';

class ChatService {
  final ChatApiClient _apiClient;

  ChatService() : _apiClient = ChatApiClient();

  /// Get my groups
  Future<GroupPagedResponse> getMyGroups({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/groups',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return GroupPagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy danh sách nhóm: ${e.toString()}');
    }
  }

  /// Get group by ID
  Future<ChatGroup> getGroupById(String groupId) async {
    try {
      final response = await _apiClient.dio.get('/groups/$groupId');
      return ChatGroup.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy thông tin nhóm: ${e.toString()}');
    }
  }

  /// Create group
  Future<ChatGroup> createGroup({
    required String name,
    String? description,
    String? buildingId,
    List<String>? memberIds,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/groups',
        data: {
          'name': name,
          'description': description,
          'buildingId': buildingId,
          'memberIds': memberIds,
        },
      );
      return ChatGroup.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi tạo nhóm: ${e.toString()}');
    }
  }

  /// Update group
  Future<ChatGroup> updateGroup({
    required String groupId,
    String? name,
    String? description,
    String? avatarUrl,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/groups/$groupId',
        data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        },
      );
      return ChatGroup.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi cập nhật nhóm: ${e.toString()}');
    }
  }

  /// Add members to group
  Future<void> addMembers({
    required String groupId,
    required List<String> memberIds,
  }) async {
    try {
      await _apiClient.dio.post(
        '/groups/$groupId/members',
        data: {
          'memberIds': memberIds,
        },
      );
    } catch (e) {
      throw Exception('Lỗi khi thêm thành viên: ${e.toString()}');
    }
  }

  /// Remove member from group
  Future<void> removeMember({
    required String groupId,
    required String memberId,
  }) async {
    try {
      await _apiClient.dio.delete('/groups/$groupId/members/$memberId');
    } catch (e) {
      throw Exception('Lỗi khi xóa thành viên: ${e.toString()}');
    }
  }

  /// Leave group
  Future<void> leaveGroup(String groupId) async {
    try {
      await _apiClient.dio.post('/groups/$groupId/leave');
    } catch (e) {
      throw Exception('Lỗi khi rời nhóm: ${e.toString()}');
    }
  }

  /// Delete group (only creator can delete)
  Future<void> deleteGroup(String groupId) async {
    try {
      await _apiClient.dio.delete('/groups/$groupId');
    } catch (e) {
      throw Exception('Lỗi khi xóa nhóm: ${e.toString()}');
    }
  }

  /// Invite members by phone number
  Future<InviteMembersResponse> inviteMembersByPhone({
    required String groupId,
    required List<String> phoneNumbers,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/groups/$groupId/invite',
        data: {
          'phoneNumbers': phoneNumbers,
        },
      );
      return InviteMembersResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi mời thành viên: ${e.toString()}');
    }
  }

  /// Get my pending invitations
  Future<List<GroupInvitationResponse>> getMyPendingInvitations() async {
    try {
      final response = await _apiClient.dio.get('/groups/invitations/my');
      return (response.data as List<dynamic>)
          .map((json) => GroupInvitationResponse.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Lỗi khi lấy lời mời: ${e.toString()}');
    }
  }

  /// Accept invitation
  Future<void> acceptInvitation(String invitationId) async {
    try {
      await _apiClient.dio.post('/groups/invitations/$invitationId/accept');
    } catch (e) {
      throw Exception('Lỗi khi chấp nhận lời mời: ${e.toString()}');
    }
  }

  /// Decline invitation
  Future<void> declineInvitation(String invitationId) async {
    try {
      await _apiClient.dio.post('/groups/invitations/$invitationId/decline');
    } catch (e) {
      throw Exception('Lỗi khi từ chối lời mời: ${e.toString()}');
    }
  }

  /// Get messages
  Future<MessagePagedResponse> getMessages({
    required String groupId,
    int page = 0,
    int size = 50,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/groups/$groupId/messages',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return MessagePagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy tin nhắn: ${e.toString()}');
    }
  }

  /// Send message
  Future<ChatMessage> sendMessage({
    required String groupId,
    String? content,
    String? messageType,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? replyToMessageId,
  }) async {
    try {
      final requestData = {
        'content': content,
        'messageType': messageType ?? 'TEXT',
        'imageUrl': imageUrl,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'replyToMessageId': replyToMessageId,
      };
      
      print('📨 [ChatService] Gửi message, groupId: $groupId');
      print('📨 [ChatService] Request data: $requestData');
      
      final response = await _apiClient.dio.post(
        '/groups/$groupId/messages',
        data: requestData,
      );

      print('📥 [ChatService] Response status: ${response.statusCode}');
      print('📥 [ChatService] Response data: ${response.data}');
      
      final message = ChatMessage.fromJson(response.data);
      print('✅ [ChatService] Parse message thành công!');
      print('📋 [ChatService] Message ID: ${message.id}');
      print('📋 [ChatService] Message type: ${message.messageType}');
      print('📋 [ChatService] Message imageUrl: ${message.imageUrl}');
      print('📋 [ChatService] Message content: ${message.content}');
      
      return message;
    } catch (e, stackTrace) {
      print('❌ [ChatService] Lỗi khi gửi tin nhắn: $e');
      print('📋 [ChatService] Stack trace: $stackTrace');
      if (e is DioException) {
        print('📋 [ChatService] DioException response: ${e.response?.data}');
        print('📋 [ChatService] DioException statusCode: ${e.response?.statusCode}');
      }
      throw Exception('Lỗi khi gửi tin nhắn: ${e.toString()}');
    }
  }

  /// Edit message
  Future<ChatMessage> editMessage({
    required String groupId,
    required String messageId,
    required String content,
  }) async {
    try {
      final response = await _apiClient.dio.put(
        '/groups/$groupId/messages/$messageId',
        data: content,
      );
      return ChatMessage.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi chỉnh sửa tin nhắn: ${e.toString()}');
    }
  }

  /// Delete message
  Future<void> deleteMessage({
    required String groupId,
    required String messageId,
  }) async {
    try {
      await _apiClient.dio.delete('/groups/$groupId/messages/$messageId');
    } catch (e) {
      throw Exception('Lỗi khi xóa tin nhắn: ${e.toString()}');
    }
  }

  /// Mark messages as read
  Future<void> markMessagesAsRead(String groupId) async {
    try {
      await _apiClient.dio.post('/groups/$groupId/messages/mark-read');
    } catch (e) {
      throw Exception('Lỗi khi đánh dấu đã đọc: ${e.toString()}');
    }
  }

  /// Get unread message count
  Future<int> getUnreadCount(String groupId) async {
    try {
      final response = await _apiClient.dio.get('/groups/$groupId/messages/unread-count');
      return response.data['unreadCount'] ?? 0;
    } catch (e) {
      throw Exception('Lỗi khi lấy số tin nhắn chưa đọc: ${e.toString()}');
    }
  }

  /// Upload image
  Future<String> uploadImage({
    required String groupId,
    required XFile image,
  }) async {
    try {
      print('📤 [ChatService] Bắt đầu upload ảnh cho groupId: $groupId');
      print('📤 [ChatService] Image path: ${image.path}');
      print('📤 [ChatService] Image name: ${image.name}');
      
      final fileSize = await image.length();
      print('📤 [ChatService] Image size: $fileSize bytes');
      
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(image.path, filename: image.name),
      });

      print('📤 [ChatService] Gửi request POST /uploads/chat/$groupId/image');
      final response = await _apiClient.dio.post(
        '/uploads/chat/$groupId/image',
        data: formData,
      );

      print('📥 [ChatService] Response status: ${response.statusCode}');
      print('📥 [ChatService] Response data: ${response.data}');
      
      final imageUrl = response.data['imageUrl'] as String?;
      if (imageUrl == null) {
        print('❌ [ChatService] Response không có imageUrl! Response: ${response.data}');
        throw Exception('Response không có imageUrl: ${response.data}');
      }
      
      print('✅ [ChatService] Upload thành công! imageUrl: $imageUrl');
      return imageUrl;
    } catch (e, stackTrace) {
      print('❌ [ChatService] Lỗi khi upload ảnh: $e');
      print('📋 [ChatService] Stack trace: $stackTrace');
      if (e is DioException) {
        print('📋 [ChatService] DioException response: ${e.response?.data}');
        print('📋 [ChatService] DioException statusCode: ${e.response?.statusCode}');
      }
      throw Exception('Lỗi khi upload ảnh: ${e.toString()}');
    }
  }

  /// Upload audio (voice message)
  Future<Map<String, dynamic>> uploadAudio({
    required String groupId,
    required File audioFile,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          audioFile.path,
          filename: audioFile.path.split('/').last,
        ),
      });

      final response = await _apiClient.dio.post(
        '/uploads/chat/$groupId/audio',
        data: formData,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Lỗi khi upload audio: ${e.toString()}');
    }
  }

  /// Upload file (document, PDF, zip, etc.)
  Future<Map<String, dynamic>> uploadFile({
    required String groupId,
    required File file,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
        ),
      });

      final response = await _apiClient.dio.post(
        '/uploads/chat/$groupId/file',
        data: formData,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Lỗi khi upload file: ${e.toString()}');
    }
  }
}

