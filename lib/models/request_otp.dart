class RequestOtp {
  final String email;

  RequestOtp({required this.email});

  Map<String, dynamic> toJson() => {'email': email};
}
