import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import 'profile_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  late AnimationController _fadeCtrl;
  late ProfileService _service;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
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
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _profile!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Chỉnh sửa hồ sơ',
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) =>
                      EditProfileScreen(initialData: profile),
                  transitionsBuilder: (_, a, __, child) =>
                      FadeTransition(opacity: a, child: child),
                ),
              );
              if (updated == true) _loadProfile();
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            children: [
              // Avatar + Name
              Center(
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withOpacity(0.25),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundImage: profile['avatarUrl'] != null
                            ? NetworkImage(profile['avatarUrl'])
                            : null,
                        backgroundColor: Colors.grey.shade100,
                        child: profile['avatarUrl'] == null
                            ? const Icon(Icons.person,
                                size: 60, color: Colors.grey)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile['fullName'] ?? "Chưa có tên",
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile['email'] ?? "",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Info card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoTile(
                        Icons.phone, "Số điện thoại", profile['phoneNumber']),
                    _buildDivider(),
                    _buildInfoTile(Icons.male, "Giới tính", profile['gender']),
                    _buildDivider(),
                    _buildInfoTile(
                        Icons.cake, "Ngày sinh", profile['dateOfBirth']),
                    _buildDivider(),
                    _buildInfoTile(
                        Icons.home, "Căn hộ", profile['apartmentName']),
                    _buildDivider(),
                    _buildInfoTile(
                        Icons.location_on, "Địa chỉ", profile['address']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String? value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        decoration: BoxDecoration(
          color: Colors.teal.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.teal),
      ),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(value ?? "—", style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildDivider() => Divider(height: 4, color: Colors.grey.shade200);
}
