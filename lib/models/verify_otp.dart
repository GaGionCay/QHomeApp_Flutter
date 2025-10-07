class VerifyOtp {
  final String email;
  final String otp;

  VerifyOtp({required this.email, required this.otp});

  Map<String, dynamic> toJson() => {
        'email': email,
        'otp': otp,
      };
}
