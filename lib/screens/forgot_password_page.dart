import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  int _step = 1;
  bool _isLoading = false;

  // --- Step 1: Request OTP via Email ---
  void _requestOtpEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Vui lòng nhập email')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.requestOtp(email);
    setState(() => _isLoading = false);

    if (result == null) {
      setState(() => _step = 2);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📩 OTP đã được gửi đến email')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $result')),
      );
    }
  }

  // --- Step 2: Verify OTP ---
  void _verifyOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Vui lòng nhập OTP')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.verifyOtp(email, otp);
    setState(() => _isLoading = false);

    if (result == null) {
      setState(() => _step = 3);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ OTP hợp lệ, hãy nhập mật khẩu mới')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $result')),
      );
    }
  }

  // --- Step 3: Reset Password ---
  void _resetPassword() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Mật khẩu nhập lại không khớp')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await _authService.confirmReset(email, otp, newPassword);
    setState(() => _isLoading = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Mật khẩu đã được cập nhật')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ $result')),
      );
    }
  }

  // --- UI Steps ---
  Widget _buildStepContent() {
    if (_step == 1) {
      // Step 1: Nhập Email
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Email', style: TextStyle(fontSize: 14, color: Colors.black87)),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(border: UnderlineInputBorder()),
          ),
          const SizedBox(height: 40),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _requestOtpEmail,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                ),
                child: const Text('📩 Gửi OTP qua Email'),
              ),
            ),
        ],
      );
    } else if (_step == 2) {
      // Step 2: Nhập OTP
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OTP', style: TextStyle(fontSize: 14, color: Colors.black87)),
          TextField(
            controller: _otpController,
            decoration: const InputDecoration(border: UnderlineInputBorder()),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xác minh OTP'),
            ),
          ),
        ],
      );
    } else {
      // Step 3: Reset Password
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mật khẩu mới', style: TextStyle(fontSize: 14)),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(border: UnderlineInputBorder()),
          ),
          const SizedBox(height: 20),
          const Text('Xác nhận mật khẩu', style: TextStyle(fontSize: 14)),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(border: UnderlineInputBorder()),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xác nhận đặt lại mật khẩu'),
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB8D4F1),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(150),
                    topRight: Radius.circular(150),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
