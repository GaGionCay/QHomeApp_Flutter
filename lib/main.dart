import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_page.dart';
import 'screens/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<Widget> _getInitialPage() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('id');
    final email = prefs.getString('email');

    if (id != null && email != null) {
      return HomePage(id: id, email: email);
    } else {
      return const LoginPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QHome Auth',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: FutureBuilder(
        future: _getInitialPage(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          } else {
            return snapshot.data as Widget;
          }
        },
      ),
    );
  }
}