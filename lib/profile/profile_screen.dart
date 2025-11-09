import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  List<UnitInfo> _units = const [];
  bool _loadingUnits = true;
  bool _loading = true;
  late AnimationController _fadeCtrl;
  late ProfileService _service;
  ContractService? _contractService;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingUnits = true;
      });
    }
    final apiClient = await ApiClient.create();
    _service = ProfileService(apiClient.dio);
    _contractService = ContractService(apiClient);
    final data = await _service.getProfile();
    List<UnitInfo> units = const [];
    try {
      units = await _contractService!.getMyUnits();
    } catch (e) {
      debugPrint('⚠️ Lỗi tải danh sách căn hộ: $e');
    }
    if (!mounted) return;
    setState(() {
      _profile = data;
      _units = units;
      _loadingUnits = false;
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
                      const SizedBox(height: 20),
                      if (_loadingUnits)
                        const Center(child: CircularProgressIndicator())
                      else
                        _OwnedUnitsCard(units: _units),
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
    final phone = profile['phoneNumber'] ?? profile['phone'] ?? '—';
    final gender = profile['gender'] ?? '—';
    final dob = profile['dateOfBirth'] ?? profile['birthDate'] ?? '—';
    final citizenId = profile['citizenId'] ?? profile['identityNumber'] ?? '—';
    final residentId = profile['residentId'] ?? profile['residentCode'] ?? '—';
 
    final infoItems = [
      _InfoItem(Icons.badge_outlined, 'Mã cư dân', residentId),
      _InfoItem(Icons.phone_outlined, 'Số điện thoại', phone),
      _InfoItem(Icons.credit_card_outlined, 'CMND/CCCD', citizenId),
      _InfoItem(Icons.person_outline, 'Giới tính', gender),
      _InfoItem(Icons.cake_outlined, 'Ngày sinh', dob),
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

class _OwnedUnitsCard extends StatelessWidget {
  const _OwnedUnitsCard({required this.units});

  final List<UnitInfo> units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (units.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
          boxShadow: AppColors.subtleShadow,
        ),
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(Icons.home_outlined, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Bạn chưa có căn hộ nào được gán trong hệ thống.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
        boxShadow: AppColors.subtleShadow,
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.apartment_rounded, color: AppColors.primaryEmerald),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Căn hộ của bạn',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${units.length} căn hộ đang sở hữu/quản lý',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...units.map((unit) => _UnitTile(unit: unit, theme: theme)).toList(),
        ],
      ),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.theme});

  final UnitInfo unit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final buildingLabel = unit.buildingName?.isNotEmpty == true
        ? unit.buildingName
        : unit.buildingCode;
    final title = [buildingLabel, unit.code].where((e) => e != null && e.isNotEmpty).join(' • ');
    final details = <String>[
      if (unit.floor != null) 'Tầng ${unit.floor}',
      if (unit.areaM2 != null) '${unit.areaM2!.toStringAsFixed(1)} m²',
      if (unit.bedrooms != null) '${unit.bedrooms} phòng ngủ',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.key_outlined, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isNotEmpty ? title : unit.code,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  details.isNotEmpty ? details : 'Thông tin chi tiết đang cập nhật',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                if (unit.status?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryEmerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unit.status!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.primaryEmerald,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
