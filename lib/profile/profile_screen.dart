import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../theme/app_colors.dart';
import 'edit_profile_screen.dart';
import 'profile_service.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () async {
                  final updated = await Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          EditProfileScreen(initialData: _profile!),
                      transitionsBuilder: (_, animation, __, child) =>
                          FadeThroughTransition(
                        animation: animation,
                        secondaryAnimation:
                            Tween<double>(begin: 0.9, end: 1).animate(animation),
                        child: child,
                      ),
                    ),
                  );
                  if (updated == true) _loadProfile();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryEmerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Chỉnh sửa'),
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : FadeTransition(
                opacity: _fadeCtrl,
                child: RefreshIndicator(
                  color: theme.colorScheme.primary,
                  onRefresh: _loadProfile,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    children: [
                      _ProfileHeader(profile: _profile!),
                      const SizedBox(height: 24),
                      _ProfileInfoCard(profile: _profile!),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarUrl = profile['avatarUrl'] as String?;
    final name = profile['fullName'] ?? 'Chưa có tên';
    final email = profile['email'] ?? '—';

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient(),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.elevatedShadow,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Row(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(avatarUrl, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.neutralBackground.withValues(alpha: 0.3),
                      child: const Icon(Icons.person_outline,
                          size: 42, color: Colors.white),
                    ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  const _ProfileInfoCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final infoItems = [
      _InfoItem(Icons.phone_outlined, 'Số điện thoại',
          profile['phoneNumber'] ?? '—'),
      _InfoItem(Icons.person_outline, 'Giới tính',
          profile['gender'] ?? '—'),
      _InfoItem(Icons.cake_outlined, 'Ngày sinh',
          profile['dateOfBirth'] ?? '—'),
      _InfoItem(Icons.apartment_outlined, 'Căn hộ',
          profile['apartmentName'] ?? '—'),
      _InfoItem(Icons.location_on_outlined, 'Địa chỉ',
          profile['address'] ?? '—'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        boxShadow: AppColors.subtleShadow,
      ),
      child: Column(
        children: [
          for (final item in infoItems) ...[
            ListTile(
              leading: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(item.icon, color: theme.colorScheme.primary),
              ),
              title: Text(
                item.title,
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                item.value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
            if (item != infoItems.last)
              Divider(
                height: 4,
                indent: 72,
                endIndent: 16,
                color: theme.colorScheme.outline.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem(this.icon, this.title, this.value);
  final IconData icon;
  final String title;
  final String value;
}
