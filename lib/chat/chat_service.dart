import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../models/chat/group.dart';
import '../models/chat/message.dart';
import '../models/chat/invitation.dart';
import '../models/chat/invite_members_response.dart';
import '../models/chat/group_file.dart';
import '../models/chat/conversation.dart';
import '../models/chat/direct_message.dart';
import '../models/chat/direct_invitation.dart';
import '../models/chat/direct_chat_file.dart';
import '../models/chat/friend.dart';
import '../models/marketplace_post.dart';
import '../auth/api_client.dart';
import '../services/imagekit_service.dart';
import 'chat_api_client.dart';

class ChatService {
  final ChatApiClient _apiClient;
  final ImageKitService _imageKitService;

  ChatService() 
      : _apiClient = ChatApiClient(),
        _imageKitService = ImageKitService(ApiClient());

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

  /// Get group files with pagination
  Future<GroupFilePagedResponse> getGroupFiles({
    required String groupId,
    int page = 0,
    int size = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/groups/$groupId/files',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return GroupFilePagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy danh sách file: ${e.toString()}');
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
    String? mimeType,
    String? replyToMessageId,
    // Marketplace post fields
    String? postId,
    String? postTitle,
    String? postThumbnailUrl,
    double? postPrice,
    String? deepLink,
  }) async {
    try {
      final requestData = {
        'content': content,
        'messageType': messageType ?? 'TEXT',
        'imageUrl': imageUrl,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'replyToMessageId': replyToMessageId,
        // Marketplace post fields
        if (postId != null) 'postId': postId,
        if (postTitle != null) 'postTitle': postTitle,
        if (postThumbnailUrl != null) 'postThumbnailUrl': postThumbnailUrl,
        if (postPrice != null) 'postPrice': postPrice,
        if (deepLink != null) 'deepLink': deepLink,
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

  /// Upload image to ImageKit
  Future<String> uploadImage({
    required String groupId,
    required XFile image,
  }) async {
    try {
      // Upload to ImageKit with folder "chat/group/{groupId}"
      final imageUrl = await _imageKitService.uploadImage(
        file: image,
        folder: 'chat/group/$groupId',
      );
      return imageUrl;
    } catch (e) {
      throw Exception('Lỗi khi upload ảnh: ${e.toString()}');
    }
  }

  /// Upload multiple images to ImageKit
  Future<List<String>> uploadImages({
    required String groupId,
    required List<XFile> images,
  }) async {
    try {
      // Upload to ImageKit with folder "chat/group/{groupId}"
      final imageUrls = await _imageKitService.uploadImages(
        files: images,
        folder: 'chat/group/$groupId',
      );
      return imageUrls;
    } catch (e) {
      throw Exception('Lỗi khi upload nhiều ảnh: ${e.toString()}');
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

  /// Upload video
  Future<Map<String, dynamic>> uploadVideo({
    required String groupId,
    required File videoFile,
  }) async {
    try {
      print('📤 [ChatService] Bắt đầu upload video cho groupId: $groupId');
      print('📤 [ChatService] Video path: ${videoFile.path}');
      print('📤 [ChatService] Video size: ${await videoFile.length()} bytes');
      
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          videoFile.path,
          filename: videoFile.path.split('/').last,
        ),
      });

      print('📤 [ChatService] Gửi request POST /uploads/chat/$groupId/video');
      final response = await _apiClient.dio.post(
        '/uploads/chat/$groupId/video',
        data: formData,
      );

      print('✅ [ChatService] Upload video thành công!');
      return response.data as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('❌ [ChatService] Lỗi khi upload video: $e');
      print('📋 [ChatService] Stack trace: $stackTrace');
      throw Exception('Lỗi khi upload video: ${e.toString()}');
    }
  }

  // ==================== DIRECT CHAT 1-1 METHODS ====================

  /// Get all conversations
  Future<List<Conversation>> getConversations() async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final url = '/direct-chat/conversations';
      
      print('📤 [ChatService] Getting conversations...');
      print('   Base URL: ${apiClient.dio.options.baseUrl}');
      print('   Full URL: ${apiClient.dio.options.baseUrl}$url');
      
      final response = await apiClient.dio.get(url);
      
      print('✅ [ChatService] Got conversations:');
      print('   Status: ${response.statusCode}');
      print('   Count: ${(response.data as List).length}');
      
      // Log unread counts for debugging
      if (response.data is List) {
        final conversations = response.data as List;
        print('📊 [ChatService] Unread counts per conversation:');
        for (var i = 0; i < conversations.length; i++) {
          final conv = conversations[i];
          final unreadCount = conv['unreadCount'] ?? 0;
          final convId = conv['id']?.toString() ?? 'unknown';
          print('   [$i] Conversation id=$convId, unreadCount=$unreadCount');
        }
      }
      
      final result = (response.data as List<dynamic>)
          .map((json) => Conversation.fromJson(json))
          .toList();
      
      print('✅ [ChatService] Parsed ${result.length} conversations');
      return result;
    } on DioException catch (e) {
      print('❌ [ChatService] Error getting conversations:');
      print('   Status code: ${e.response?.statusCode}');
      print('   Response data: ${e.response?.data}');
      print('   Request URL: ${e.requestOptions.uri}');
      throw Exception('Lỗi khi lấy danh sách cuộc trò chuyện: ${e.message ?? e.toString()}');
    } catch (e) {
      print('❌ [ChatService] Unexpected error getting conversations: $e');
      throw Exception('Lỗi khi lấy danh sách cuộc trò chuyện: ${e.toString()}');
    }
  }

  /// Get conversation by ID
  Future<Conversation> getConversation(String conversationId) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.get('/direct-chat/conversations/$conversationId');
      return Conversation.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy thông tin cuộc trò chuyện: ${e.toString()}');
    }
  }

  /// Get messages in a conversation
  Future<DirectMessagePagedResponse> getDirectMessages({
    required String conversationId,
    int page = 0,
    int size = 25,
  }) async {
    try {
      print('📡 [ChatService] getDirectMessages - conversationId: $conversationId, page: $page, size: $size');
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final url = '/direct-chat/conversations/$conversationId/messages';
      print('🌐 [ChatService] Calling API: $url');
      final response = await apiClient.dio.get(
        url,
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      print('✅ [ChatService] API response received - status: ${response.statusCode}');
      print('📦 [ChatService] Response data keys: ${response.data.keys}');
      final result = DirectMessagePagedResponse.fromJson(response.data);
      print('✅ [ChatService] Parsed response - content length: ${result.content.length}, hasNext: ${result.hasNext}');
      print('📝 [ChatService] Note: Backend should have marked messages as read (lastReadAt updated)');
      return result;
    } catch (e, stackTrace) {
      print('❌ [ChatService] Error in getDirectMessages: $e');
      print('❌ [ChatService] Stack trace: $stackTrace');
      throw Exception('Lỗi khi lấy tin nhắn: ${e.toString()}');
    }
  }

  /// Send direct message
  Future<DirectMessage> sendDirectMessage({
    required String conversationId,
    String? content,
    String? messageType,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? replyToMessageId,
    // Marketplace post fields
    String? postId,
    String? postTitle,
    String? postThumbnailUrl,
    double? postPrice,
    String? deepLink,
  }) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final requestData = {
        'content': content,
        'messageType': messageType ?? 'TEXT',
        'imageUrl': imageUrl,
        'fileUrl': fileUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'replyToMessageId': replyToMessageId,
        // Marketplace post fields
        if (postId != null) 'postId': postId,
        if (postTitle != null) 'postTitle': postTitle,
        if (postThumbnailUrl != null) 'postThumbnailUrl': postThumbnailUrl,
        if (postPrice != null) 'postPrice': postPrice,
        if (deepLink != null) 'deepLink': deepLink,
      };
      
      print('📤 [ChatService] Sending direct message:');
      print('   Conversation ID: $conversationId');
      print('   Message type: ${messageType ?? 'TEXT'}');
      print('   Content: ${content?.substring(0, content.length > 50 ? 50 : content.length)}...');
      
      final response = await apiClient.dio.post(
        '/direct-chat/conversations/$conversationId/messages',
        data: requestData,
      );
      
      print('✅ [ChatService] Message sent successfully');
      print('   Status: ${response.statusCode}');
      
      return DirectMessage.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ [ChatService] Error sending message:');
      print('   Status code: ${e.response?.statusCode}');
      print('   Response data: ${e.response?.data}');
      print('   Request URL: ${e.requestOptions.uri}');
      
      if (e.response?.statusCode == 400 || e.response?.statusCode == 403) {
        final errorMessage = e.response?.data?.toString() ?? e.message ?? 'Lỗi không xác định';
        throw Exception(errorMessage);
      }
      
      throw Exception('Lỗi khi gửi tin nhắn: ${e.message ?? e.toString()}');
    } catch (e) {
      print('❌ [ChatService] Unexpected error sending message: $e');
      throw Exception('Lỗi khi gửi tin nhắn: ${e.toString()}');
    }
  }

  /// Delete direct message
  /// deleteType: 'FOR_ME' (only for current user) or 'FOR_EVERYONE' (for everyone)
  Future<void> deleteDirectMessage({
    required String conversationId,
    required String messageId,
    String deleteType = 'FOR_ME',
  }) async {
    try {
      print('🗑️ [ChatService] Deleting direct message: conversationId=$conversationId, messageId=$messageId, deleteType=$deleteType');
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.delete(
        '/direct-chat/conversations/$conversationId/messages/$messageId',
        queryParameters: {'deleteType': deleteType},
      );
      print('✅ [ChatService] Message deleted successfully: statusCode=${response.statusCode}');
    } catch (e) {
      print('❌ [ChatService] Error deleting message: $e');
      throw Exception('Lỗi khi xóa tin nhắn: ${e.toString()}');
    }
  }

  /// Get unread count for a conversation
  Future<int> getDirectUnreadCount(String conversationId) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.get(
        '/direct-chat/conversations/$conversationId/unread-count',
      );
      return response.data ?? 0;
    } catch (e) {
      throw Exception('Lỗi khi lấy số tin nhắn chưa đọc: ${e.toString()}');
    }
  }

  // Direct Chat Invitations
  /// Create direct invitation
  Future<DirectInvitation> createDirectInvitation({
    String? inviteeId,
    String? phoneNumber,
    String? initialMessage,
  }) async {
    try {
      if (inviteeId == null && phoneNumber == null) {
        throw Exception('Either inviteeId or phoneNumber must be provided');
      }
      
      // Use ApiClient.activeBaseUrl directly since /api/direct-invitations is not under /api/chat
      final apiClient = ApiClient();
      final url = '/direct-invitations';
      final requestData = {
        if (inviteeId != null) 'inviteeId': inviteeId,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (initialMessage != null) 'initialMessage': initialMessage,
      };
      
      print('📤 [ChatService] Creating direct invitation:');
      print('   Base URL: ${apiClient.dio.options.baseUrl}');
      print('   Full URL: ${apiClient.dio.options.baseUrl}$url');
      print('   Data: $requestData');
      
      final response = await apiClient.dio.post(
        url,
        data: requestData,
      );
      
      print('✅ [ChatService] Direct invitation created successfully');
      print('   Response status: ${response.statusCode}');
      print('   Response data: ${response.data}');
      
      return DirectInvitation.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ [ChatService] Error creating direct invitation:');
      print('   Type: ${e.type}');
      print('   Status code: ${e.response?.statusCode}');
      print('   Response data: ${e.response?.data}');
      print('   Request URL: ${e.requestOptions.uri}');
      print('   Request headers: ${e.requestOptions.headers}');
      
      if (e.response?.statusCode == 403) {
        throw Exception('Không có quyền tạo lời mời. Vui lòng kiểm tra quyền truy cập của bạn.');
      }
      
      throw Exception('Lỗi khi tạo lời mời: ${e.message ?? e.toString()}');
    } catch (e) {
      print('❌ [ChatService] Unexpected error creating direct invitation: $e');
      throw Exception('Lỗi khi tạo lời mời: ${e.toString()}');
    }
  }

  /// Accept direct invitation
  Future<DirectInvitation> acceptDirectInvitation(String invitationId) async {
    try {
      // Use ApiClient directly since /api/direct-invitations is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.post(
        '/direct-invitations/$invitationId/accept',
      );
      return DirectInvitation.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi chấp nhận lời mời: ${e.toString()}');
    }
  }

  /// Decline direct invitation
  Future<void> declineDirectInvitation(String invitationId) async {
    try {
      // Use ApiClient directly since /api/direct-invitations is not under /api/chat
      final apiClient = ApiClient();
      await apiClient.dio.post('/direct-invitations/$invitationId/decline');
    } catch (e) {
      throw Exception('Lỗi khi từ chối lời mời: ${e.toString()}');
    }
  }

  /// Get pending direct invitations
  Future<List<DirectInvitation>> getPendingDirectInvitations() async {
    try {
      // Use ApiClient directly since /api/direct-invitations is not under /api/chat
      final apiClient = ApiClient();
      final url = '/direct-invitations/pending';
      
      print('📤 [ChatService] Getting pending direct invitations...');
      print('   Base URL: ${apiClient.dio.options.baseUrl}');
      print('   Full URL: ${apiClient.dio.options.baseUrl}$url');
      
      final response = await apiClient.dio.get(url);
      
      print('✅ [ChatService] Got response:');
      print('   Status: ${response.statusCode}');
      print('   Data: ${response.data}');
      print('   Data type: ${response.data.runtimeType}');
      
      final invitations = (response.data as List<dynamic>)
          .map((json) => DirectInvitation.fromJson(json))
          .toList();
      
      print('✅ [ChatService] Parsed ${invitations.length} invitations');
      for (var inv in invitations) {
        print('   - Invitation ID: ${inv.id}, Inviter: ${inv.inviterId}, Invitee: ${inv.inviteeId}, Status: ${inv.status}');
      }
      
      return invitations;
    } catch (e) {
      print('❌ [ChatService] Error getting pending invitations: $e');
      if (e is DioException) {
        print('   Status code: ${e.response?.statusCode}');
        print('   Response data: ${e.response?.data}');
        print('   Request URL: ${e.requestOptions.uri}');
      }
      throw Exception('Lỗi khi lấy danh sách lời mời: ${e.toString()}');
    }
  }

  /// Count pending direct invitations
  Future<int> countPendingDirectInvitations() async {
    try {
      // Use ApiClient directly since /api/direct-invitations is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.get('/direct-invitations/pending/count');
      return response.data ?? 0;
    } catch (e) {
      throw Exception('Lỗi khi đếm lời mời: ${e.toString()}');
    }
  }

  // Direct Chat File Uploads
  /// Upload image for direct chat to ImageKit
  Future<String> uploadDirectImage({
    required String conversationId,
    required XFile image,
  }) async {
    try {
      // Upload to ImageKit with folder "chat/direct/{conversationId}"
      final imageUrl = await _imageKitService.uploadImage(
        file: image,
        folder: 'chat/direct/$conversationId',
      );
      return imageUrl;
    } catch (e) {
      throw Exception('Lỗi khi upload ảnh: ${e.toString()}');
    }
  }

  /// Upload multiple images for direct chat
  Future<List<String>> uploadDirectImages({
    required String conversationId,
    required List<XFile> images,
  }) async {
    try {
      final formData = FormData();
      for (var image in images) {
        formData.files.add(
          MapEntry(
            'files',
            await MultipartFile.fromFile(image.path, filename: image.name),
          ),
        );
      }

      final response = await _apiClient.dio.post(
        '/uploads/chat/direct/$conversationId/images',
        data: formData,
      );

      final imageUrls = (response.data['imageUrls'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();
      
      return imageUrls ?? [];
    } catch (e) {
      throw Exception('Lỗi khi upload nhiều ảnh: ${e.toString()}');
    }
  }

  /// Upload audio for direct chat
  Future<Map<String, dynamic>> uploadDirectAudio({
    required String conversationId,
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
        '/uploads/chat/direct/$conversationId/audio',
        data: formData,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Lỗi khi upload audio: ${e.toString()}');
    }
  }

  /// Upload video for direct chat
  Future<Map<String, dynamic>> uploadDirectVideo({
    required String conversationId,
    required File videoFile,
  }) async {
    try {
      print('📤 [ChatService] Bắt đầu upload video cho conversationId: $conversationId');
      print('📤 [ChatService] Video path: ${videoFile.path}');
      print('📤 [ChatService] Video size: ${await videoFile.length()} bytes');
      
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          videoFile.path,
          filename: videoFile.path.split('/').last,
        ),
      });

      print('📤 [ChatService] Gửi request POST /uploads/chat/direct/$conversationId/video');
      final response = await _apiClient.dio.post(
        '/uploads/chat/direct/$conversationId/video',
        data: formData,
      );

      print('✅ [ChatService] Upload video thành công!');
      return response.data as Map<String, dynamic>;
    } catch (e, stackTrace) {
      print('❌ [ChatService] Lỗi khi upload video: $e');
      print('📋 [ChatService] Stack trace: $stackTrace');
      throw Exception('Lỗi khi upload video: ${e.toString()}');
    }
  }

  /// Upload file for direct chat
  Future<Map<String, dynamic>> uploadDirectFile({
    required String conversationId,
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
        '/uploads/chat/direct/$conversationId/file',
        data: formData,
      );

      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Lỗi khi upload file: ${e.toString()}');
    }
  }

  // Blocking
  /// Block user
  Future<void> blockUser(String blockedId) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      await apiClient.dio.post('/direct-chat/block/$blockedId');
    } catch (e) {
      throw Exception('Lỗi khi chặn người dùng: ${e.toString()}');
    }
  }

  /// Unblock user
  Future<void> unblockUser(String blockedId) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      await apiClient.dio.delete('/direct-chat/block/$blockedId');
    } catch (e) {
      throw Exception('Lỗi khi bỏ chặn người dùng: ${e.toString()}');
    }
  }

  /// Get list of blocked user IDs
  Future<List<String>> getBlockedUsers() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.dio.get('/direct-chat/blocked-users');
      final List<dynamic> blockedUserIds = response.data ?? [];
      return blockedUserIds.map((id) => id.toString()).toList();
    } catch (e) {
      print('❌ [ChatService] Error getting blocked users: $e');
      throw Exception('Lỗi khi lấy danh sách người dùng đã chặn: ${e.toString()}');
    }
  }

  /// Check if a user is blocked
  Future<bool> isBlocked(String userId) async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.dio.get('/direct-chat/is-blocked/$userId');
      return response.data as bool? ?? false;
    } catch (e) {
      print('❌ [ChatService] Error checking if user is blocked: $e');
      return false; // Default to not blocked if check fails
    }
  }

  /// Get direct chat files with pagination
  Future<DirectChatFilePagedResponse> getDirectFiles({
    required String conversationId,
    int page = 0,
    int size = 20,
  }) async {
    try {
      // Use ApiClient directly since /api/direct-chat is not under /api/chat
      final apiClient = ApiClient();
      final response = await apiClient.dio.get(
        '/direct-chat/conversations/$conversationId/files',
        queryParameters: {
          'page': page,
          'size': size,
        },
      );
      return DirectChatFilePagedResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Lỗi khi lấy danh sách file: ${e.toString()}');
    }
  }

  /// Mute group chat
  /// durationHours: 1, 2, 24, or null (indefinitely)
  Future<void> muteGroupChat({
    required String groupId,
    int? durationHours,
  }) async {
    try {
      final apiClient = ApiClient();
      await apiClient.dio.post(
        '/groups/$groupId/messages/mute',
        queryParameters: durationHours != null ? {'durationHours': durationHours} : null,
      );
    } catch (e) {
      throw Exception('Lỗi khi tắt thông báo nhóm: ${e.toString()}');
    }
  }

  /// Unmute group chat
  Future<void> unmuteGroupChat(String groupId) async {
    try {
      final apiClient = ApiClient();
      await apiClient.dio.delete('/groups/$groupId/messages/mute');
    } catch (e) {
      throw Exception('Lỗi khi bật lại thông báo nhóm: ${e.toString()}');
    }
  }

  /// Mute direct conversation
  /// durationHours: 1, 2, 24, or null (indefinitely)
  Future<void> muteDirectConversation({
    required String conversationId,
    int? durationHours,
  }) async {
    try {
      final apiClient = ApiClient();
      await apiClient.dio.post(
        '/direct-chat/conversations/$conversationId/mute',
        queryParameters: durationHours != null ? {'durationHours': durationHours} : null,
      );
    } catch (e) {
      throw Exception('Lỗi khi tắt thông báo cuộc trò chuyện: ${e.toString()}');
    }
  }

  /// Unmute direct conversation
  Future<void> unmuteDirectConversation(String conversationId) async {
    try {
      final apiClient = ApiClient();
      await apiClient.dio.delete('/direct-chat/conversations/$conversationId/mute');
    } catch (e) {
      throw Exception('Lỗi khi bật lại thông báo cuộc trò chuyện: ${e.toString()}');
    }
  }

  /// Hide direct conversation (client-side only)
  Future<void> hideDirectConversation(String conversationId) async {
    try {
      final apiClient = ApiClient();
      await apiClient.dio.post('/direct-chat/conversations/$conversationId/hide');
    } catch (e) {
      throw Exception('Lỗi khi ẩn cuộc trò chuyện: ${e.toString()}');
    }
  }

  /// Share marketplace post to group chat
  Future<ChatMessage> shareMarketplacePostToGroup({
    required String groupId,
    required MarketplacePost post,
  }) async {
    try {
      // Validate required fields
      if (post.id.isEmpty) {
        throw Exception('Post ID không được để trống');
      }
      if (post.title.isEmpty) {
        throw Exception('Post title không được để trống');
      }
      
      final deepLink = 'app://marketplace/post/${post.id}';
      final thumbnailUrl = post.images.isNotEmpty ? post.images.first.imageUrl : null;
      
      return await sendMessage(
        groupId: groupId,
        messageType: 'MARKETPLACE_POST',
        content: null, // Will be set by backend from postId, postTitle, etc.
        imageUrl: thumbnailUrl,
        fileUrl: null,
        fileName: null,
        fileSize: null,
        mimeType: null,
        replyToMessageId: null,
        // Marketplace post fields
        postId: post.id,
        postTitle: post.title,
        postThumbnailUrl: thumbnailUrl,
        postPrice: post.price,
        deepLink: deepLink,
      );
    } catch (e) {
      throw Exception('Lỗi khi chia sẻ bài viết: ${e.toString()}');
    }
  }

  /// Get friends list
  Future<List<Friend>> getFriends() async {
    try {
      final apiClient = ApiClient();
      final response = await apiClient.dio.get('/direct-chat/friends');
      final List<dynamic> friendsJson = response.data ?? [];
      return friendsJson.map((json) => Friend.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('❌ [ChatService] Error getting friends: $e');
      throw Exception('Lỗi khi lấy danh sách bạn bè: ${e.toString()}');
    }
  }

  /// Share marketplace post to direct chat
  Future<DirectMessage> shareMarketplacePostToDirect({
    required String conversationId,
    required MarketplacePost post,
  }) async {
    try {
      // Validate required fields
      if (post.id.isEmpty) {
        throw Exception('Post ID không được để trống');
      }
      if (post.title.isEmpty) {
        throw Exception('Post title không được để trống');
      }
      
      final deepLink = 'app://marketplace/post/${post.id}';
      final thumbnailUrl = post.images.isNotEmpty ? post.images.first.imageUrl : null;
      
      return await sendDirectMessage(
        conversationId: conversationId,
        messageType: 'MARKETPLACE_POST',
        content: null, // Will be set by backend from postId, postTitle, etc.
        imageUrl: thumbnailUrl,
        fileUrl: null,
        fileName: null,
        fileSize: null,
        mimeType: null,
        replyToMessageId: null,
        // Marketplace post fields
        postId: post.id,
        postTitle: post.title,
        postThumbnailUrl: thumbnailUrl,
        postPrice: post.price,
        deepLink: deepLink,
      );
    } catch (e) {
      throw Exception('Lỗi khi chia sẻ bài viết: ${e.toString()}');
    }
  }
}

