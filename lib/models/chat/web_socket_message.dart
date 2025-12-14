import 'direct_message.dart';

class WebSocketMessage {
  final String type;
  final String? conversationId;
  final String? groupId;
  final DirectMessage? directMessage;
  final DateTime? timestamp;

  WebSocketMessage({
    required this.type,
    this.conversationId,
    this.groupId,
    this.directMessage,
    this.timestamp,
  });

  factory WebSocketMessage.fromJson(Map<String, dynamic> json) {
    return WebSocketMessage(
      type: json['type'] ?? '',
      conversationId: json['conversationId'],
      groupId: json['groupId'],
      directMessage: json['directMessage'] != null
          ? DirectMessage.fromJson(json['directMessage'])
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : null,
    );
  }
}
