class JwtResponse {
  final String accessToken;
  final String refreshToken;
  final int userId;
  final String username;
  final String role;

  JwtResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.role,
  });

  factory JwtResponse.fromJson(Map<String, dynamic> json) {
    return JwtResponse(
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      userId: json['userId'],
      username: json['username'],
      role: json['role'],
    );
  }
}

