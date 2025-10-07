import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/news_service.dart';
import 'home_screen.dart';
import 'request_reset_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  const LoginScreen({super.key, required this.authService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;

  void login() async {
    setState(() => loading = true);

    // Thực hiện login
    final success = await widget.authService.login(
      emailController.text.trim(),
      passwordController.text.trim(),
    );

    setState(() => loading = false);

    if (success != null) {
      // Khởi tạo NewsService sau khi login thành công
      final newsService = NewsService(apiClient: widget.authService.apiClient);

      // Chuyển sang HomeScreen và truyền cả authService + newsService
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            authService: widget.authService,
            newsService: newsService,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : login,
              child: loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RequestResetScreen(authService: widget.authService),
                ),
              ),
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ),
    );
  }
}
