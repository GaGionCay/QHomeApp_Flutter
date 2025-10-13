import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';
import 'reset_password_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String email;
  const VerifyOtpScreen({required this.email, super.key});
  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final otpCtrl = TextEditingController();
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực OTP')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: otpCtrl, decoration: const InputDecoration(labelText: 'Mã OTP')),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: loading ? null : () async {
              setState(() => loading = true);
              try {
                await auth.verifyOtp(widget.email, otpCtrl.text.trim());
                if (!mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: widget.email, otp: otpCtrl.text.trim())));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP không hợp lệ')));
              } finally {
                setState(() => loading = false);
              }
            },
            child: loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Xác thực'),
          )
        ]),
      ),
    );
  }
}
