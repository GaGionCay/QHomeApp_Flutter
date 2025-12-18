import 'package:flutter/material.dart';
import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../core/safe_state_mixin.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, SafeStateMixin<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<UnitInfo> _units = const [];
  bool _loadingUnits = true;
  bool _loading = true;
  late AnimationController _fadeCtrl;
  late ProfileService _service;
  ContractService? _contractService;
  Map<String, dynamic>? _householdInfo;
  bool _loadingHousehold = false;

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
    
    // Load household info và danh sách thành viên
    Map<String, dynamic>? householdInfo;
    final residentId = data['residentId']?.toString();
    if (residentId != null && residentId.isNotEmpty) {
      try {
        setState(() => _loadingHousehold = true);
        householdInfo = await _service.getHouseholdInfoWithMembers(residentId);
      } catch (e) {
        debugPrint('⚠️ Lỗi tải thông tin household: $e');
      } finally {
        if (mounted) {
          setState(() => _loadingHousehold = false);
        }
      }
    }
    
    if (!mounted) return;
    setState(() {
      _profile = data;
      _units = units;
      _householdInfo = householdInfo;
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
                      if (_householdInfo != null && 
                          (_householdInfo!['unitCode'] != null || 
                           (_householdInfo!['members'] as List?)?.isNotEmpty == true)) ...[
                        const SizedBox(height: 20),
                        _HouseholdMembersCard(
                          householdInfo: _householdInfo!,
                          currentResidentId: _profile!['residentId']?.toString(),
                        ),
                      ],
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

class _HouseholdMembersCard extends StatelessWidget {
  const _HouseholdMembersCard({
    required this.householdInfo,
    required this.currentResidentId,
  });

  final Map<String, dynamic> householdInfo;
  final String? currentResidentId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitCode = householdInfo['unitCode']?.toString() ?? '';
    final primaryResidentName = householdInfo['primaryResidentName']?.toString() ?? '';
    final primaryResidentId = householdInfo['primaryResidentId']?.toString();
    final members = (householdInfo['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (members.isEmpty && unitCode.isEmpty) {
      return const SizedBox.shrink();
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
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.people_outline, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Thành viên trong căn hộ',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    if (unitCode.isNotEmpty)
                      Text(
                        'Căn hộ: $unitCode',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (primaryResidentName.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.home_outlined,
                    color: AppColors.primaryEmerald,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chủ hộ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              TextSpan(
                                text: primaryResidentName,
                              ),
                              // Nếu user hiện tại là chủ hộ, thêm "(tôi)"
                              if (primaryResidentId != null &&
                                  currentResidentId != null &&
                                  primaryResidentId!.toLowerCase() == currentResidentId!.toLowerCase())
                                TextSpan(
                                  text: ' (tôi)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (members.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Thành viên:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            ...members.map((member) {
              final memberName = member['residentName']?.toString() ?? '—';
              final memberResidentId = member['residentId']?.toString();
              final relation = member['relation']?.toString() ?? '—';
              final isPrimary = member['isPrimary'] == true;
              final isCurrentUser = memberResidentId != null &&
                  currentResidentId != null &&
                  memberResidentId!.toLowerCase() == currentResidentId!.toLowerCase();
              
              // Bỏ qua primary resident vì đã hiển thị ở trên
              if (isPrimary && primaryResidentId != null && 
                  memberResidentId != null &&
                  memberResidentId!.toLowerCase() == primaryResidentId!.toLowerCase()) {
                return const SizedBox.shrink();
              }
              
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.08)),
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.05),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodyMedium,
                          children: [
                            TextSpan(
                              text: memberName,
                              style: TextStyle(
                                fontWeight: isCurrentUser ? FontWeight.w600 : FontWeight.normal,
                                color: isCurrentUser 
                                    ? theme.colorScheme.primary 
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: ' — $relation',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                            if (isCurrentUser)
                              TextSpan(
                                text: ' (Tôi)',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
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
    final dob = profile['dateOfBirth'] ?? profile['birthDate'] ?? '—';
    final citizenId = profile['citizenId'] ?? profile['identityNumber'] ?? '—';
    final residentId = profile['residentId'] ?? profile['residentCode'] ?? '—';
 
    final infoItems = [
      _InfoItem(Icons.badge_outlined, 'Mã cư dân', residentId),
      _InfoItem(Icons.phone_outlined, 'Số điện thoại', phone),
      _InfoItem(Icons.credit_card_outlined, 'CMND/CCCD', citizenId),
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
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

