import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'profile_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  late ProfileService _service;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final apiClient = await ApiClient.create();
    _service = ProfileService(apiClient.dio);
    final data = await _service.getProfile();
    setState(() {
      _profile = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hồ sơ của tôi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Chỉnh sửa hồ sơ",
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(initialData: _profile!),
                ),
              );
              if (updated == true) {
                await _loadProfile();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profile!['avatarUrl'] != null
                    ? NetworkImage(
                        "${_profile!['avatarUrl']}?v=${DateTime.now().millisecondsSinceEpoch}")
                    : null,
                child: _profile!['avatarUrl'] == null
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _profile!['fullName'] ?? "Chưa có tên",
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 30),
            _infoTile("Email", _profile!['email']),
            _infoTile("Số điện thoại", _profile!['phoneNumber']),
            _infoTile("Giới tính", _profile!['gender']),
            _infoTile("Ngày sinh", _profile!['dateOfBirth']),
            _infoTile("Căn hộ", _profile!['apartmentName']),
            _infoTile("Địa chỉ", _profile!['address']),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String title, dynamic value) {
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(value?.toString() ?? '—'),
    );
  }
}
