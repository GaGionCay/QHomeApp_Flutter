// import 'package:flutter/material.dart';
// import '../services/auth_service.dart';
// import 'login_screen.dart';

// class DashboardScreen extends StatelessWidget {
//   DashboardScreen({super.key});
//   final _authService = AuthService();

//   void _logout(BuildContext context) async {
//     await _authService.logout();
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(builder: (_) => const LoginScreen()),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Dashboard'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.logout),
//             onPressed: () => _logout(context),
//           ),
//         ],
//       ),
//       body: const Center(child: Text('Welcome, Resident!')),
//     );
//   }
// }
