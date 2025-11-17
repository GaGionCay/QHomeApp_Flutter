import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/api_client.dart';
import '../auth/auth_provider.dart';
import '../contracts/contract_list_screen.dart';
import '../core/event_bus.dart';
import '../login/change_password_screen.dart';
import '../notifications/notification_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/profile_service.dart';
import '../settings/settings_screen.dart';
import '../theme/app_colors.dart';
import 'layout_insets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  late Dio _dio;
  late ProfileService _profileService;

  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      final api = await ApiClient.create();
      _dio = api.dio;
      _profileService = ProfileService(_dio);
      await _loadProfile();
    } catch (e) {
      debugPrint('❌ Lỗi khởi tạo service: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _profileService.getProfile();
      setState(() {
        _profile = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Lỗi tải thông tin người dùng: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Xác nhận đăng xuất', style: theme.textTheme.titleMedium),
        content: Text(
          'Bạn chắc chắn muốn kết thúc phiên làm việc?\nBạn có thể đăng nhập lại bất cứ lúc nào.',
          style: theme.textTheme.bodyMedium,
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(CupertinoIcons.square_arrow_right),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4D67),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        final authProvider = context.read<AuthProvider>();
        await authProvider.logout(context);
        AppEventBus().clear();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đăng xuất thành công!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi đăng xuất: $e')),
          );
        }
      }
    }
  }

  Future<void> _openNotificationScreen(BuildContext context) async {
    final residentId = _profile?['residentId']?.toString();
    final buildingId = _profile?['buildingId']?.toString() ??
        _profile?['defaultBuildingId']?.toString();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationScreen(
          initialResidentId:
              (residentId != null && residentId.isNotEmpty) ? residentId : null,
          initialBuildingId:
              (buildingId != null && buildingId.isNotEmpty) ? buildingId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final double bottomInset = LayoutInsets.bottomNavContentPadding(
      context,
      extra: -LayoutInsets.navBarHeight + 100,
      minimumGap: 160,
    );

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF050F1F),
              Color(0xFF102240),
              Color(0xFF071117),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE9F4FF),
              Color(0xFFF7FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBody: true,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Không gian cư dân'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset),
                children: [
                  _buildProfileHeader(theme),
                  const SizedBox(height: 24),
                  _buildQuickActions(theme),
                  const SizedBox(height: 32),
                  Text(
                    'Tiện ích tài khoản',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MenuGlassTile(
                    icon: CupertinoIcons.person_crop_circle,
                    label: 'Hồ sơ cá nhân',
                    subtitle: 'Xem và chỉnh sửa thông tin cư dân',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _MenuGlassTile(
                    icon: CupertinoIcons.doc_text_fill,
                    label: 'Hợp đồng của tôi',
                    subtitle: 'Quản lý hợp đồng cư trú và tiện ích',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ContractListScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _MenuGlassTile(
                    icon: CupertinoIcons.gear_solid,
                    label: 'Cài đặt',
                    subtitle: 'Tùy chỉnh giao diện và trải nghiệm',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'An toàn tài khoản',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _MenuGlassTile(
                    icon: CupertinoIcons.lock_shield,
                    label: 'Đổi mật khẩu',
                    subtitle: 'Thiết lập mật khẩu mạnh hơn',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ChangePasswordScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _MenuGlassTile(
                    icon: CupertinoIcons.square_arrow_right,
                    label: 'Đăng xuất',
                    subtitle: 'Thoát khỏi tài khoản hiện tại',
                    iconColor: const Color(0xFFFF4D67),
                    onTap: () => _logout(context),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final avatarUrl = _profile?['avatarUrl'] as String?;
    final name = _profile?['fullName'] ?? 'Người dùng';
    final email = _profile?['email'] ?? '';
    final isDark = theme.brightness == Brightness.dark;

    return _ProfileGlassCard(
      child: Row(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              gradient: AppColors.heroBackdropGradient(isDark: isDark),
              shape: BoxShape.circle,
              boxShadow: AppColors.elevatedShadow,
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(avatarUrl, fit: BoxFit.cover)
                  : Image.asset(
                      'assets/images/avatar_placeholder.png',
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ProfilePill(
                      icon: CupertinoIcons.shield_lefthalf_fill,
                      label: 'Cư dân đã xác thực',
                    ),
                    _ProfilePill(
                      icon: CupertinoIcons.star_fill,
                      label: 'Thành viên Emerald',
                      gradient: const [Color(0xFF7EC8E3), Color(0xFF007AFF)],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return _ServiceGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tiện ích nổi bật',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickActionChip(
                  icon: CupertinoIcons.doc_text_fill,
                  label: 'Theo dõi hợp đồng',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ContractListScreen()),
                    );
                  },
                ),
                _QuickActionChip(
                  icon: CupertinoIcons.bell_circle_fill,
                  label: 'Thông báo mới',
                  onTap: () => _openNotificationScreen(context),
                ),
                _QuickActionChip(
                  icon: CupertinoIcons.lock_shield_fill,
                  label: 'Bảo mật tài khoản',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileGlassCard extends StatelessWidget {
  const _ProfileGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.08),
            ),
            boxShadow: AppColors.elevatedShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ServiceGlassCard extends StatelessWidget {
  const _ServiceGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.icon,
    required this.label,
    this.gradient,
  });

  final IconData icon;
  final String label;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasGradient = gradient != null;
    final bool useLightTreatment = hasGradient && !isDark;
    final Color backgroundColor = hasGradient
        ? Colors.transparent
        : theme.colorScheme.surface.withOpacity(isDark ? 0.28 : 0.92);
    final Color borderColor = hasGradient
        ? Colors.transparent
        : theme.colorScheme.outline.withOpacity(isDark ? 0.15 : 0.2);
    final Color textColor = hasGradient
        ? (useLightTreatment
            ? theme.colorScheme.onSurface.withOpacity(0.86)
            : Colors.white)
        : theme.colorScheme.onSurface;
    final Color iconColor = hasGradient
        ? (useLightTreatment
            ? theme.colorScheme.primary
            : Colors.white)
        : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: hasGradient ? LinearGradient(colors: gradient!) : null,
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: hasGradient ? null : Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuGlassTile extends StatelessWidget {
  const _MenuGlassTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = iconColor ?? colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.darkGlassLayerGradient()
                  : AppColors.glassLayerGradient(),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.outline.withOpacity(0.08),
              ),
              boxShadow: AppColors.subtleShadow,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: effectiveColor.withOpacity(isDark ? 0.22 : 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: effectiveColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_forward,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: colorScheme.surface.withOpacity(0.78),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
