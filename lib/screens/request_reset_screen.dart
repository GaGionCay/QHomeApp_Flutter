import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'verify_otp_screen.dart';

class RequestResetScreen extends StatefulWidget {
  final AuthService authService;

  const RequestResetScreen({super.key, required this.authService});

  @override
  State<RequestResetScreen> createState() => _RequestResetScreenState();
}

class _RequestResetScreenState extends State<RequestResetScreen> {
  final TextEditingController emailController = TextEditingController();
  bool loading = false;

  void requestReset() async {
    setState(() => loading = true);
    final success = await widget.authService.requestReset(emailController.text.trim());
    setState(() => loading = false);

    if (success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(authService: widget.authService, email: emailController.text.trim()),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to request OTP')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Password Reset')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : requestReset,
              child: loading ? const CircularProgressIndicator() : const Text('Send OTP'),
            ),
          ],
        ),
      ),
    );
  }
}
