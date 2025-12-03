class Friend {
  final String friendId;
  final String friendName;
  final String friendPhone;
  final String? conversationId;
  final bool hasActiveConversation;

  Friend({
    required this.friendId,
    required this.friendName,
    required this.friendPhone,
    this.conversationId,
    required this.hasActiveConversation,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      friendId: json['friendId']?.toString() ?? '',
      friendName: json['friendName'] ?? 'Unknown',
      friendPhone: json['friendPhone'] ?? '',
      conversationId: json['conversationId']?.toString(),
      hasActiveConversation: json['hasActiveConversation'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'friendId': friendId,
      'friendName': friendName,
      'friendPhone': friendPhone,
      'conversationId': conversationId,
      'hasActiveConversation': hasActiveConversation,
    };
  }
}

