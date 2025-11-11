import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_provider.dart';
import '../auth/api_client.dart';
import '../common/layout_insets.dart';
import '../contracts/contract_service.dart';
import '../core/event_bus.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

const _selectedUnitPrefsKey = 'selected_unit_id';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final bottomInset = LayoutInsets.bottomNavContentPadding(
      context,
      minimumGap: 32,
    );

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF040C17),
              Color(0xFF0F1B2F),
              Color(0xFF04080C),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE7F1FF),
              Color(0xFFF7FBFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBody: true,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Cài đặt'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset),
          children: const [
            _ThemeModeSection(),
            SizedBox(height: 24),
            _BiometricSettingsSection(),
            SizedBox(height: 24),
            _UnitSwitcherSection(),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSection extends StatelessWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<ThemeController>();
    final mode = controller.themeMode;

    return _SettingsGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chế độ hiển thị',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cá nhân hóa giao diện với màu sắc sáng hoặc tối. Bạn cũng có thể mặc định theo thiết lập hệ thống.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.72),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _ThemeModeOption(
                icon: CupertinoIcons.sun_max_fill,
                label: 'Sáng',
                description: 'Nền sáng, phù hợp ban ngày',
                isSelected: mode == ThemeMode.light,
                onTap: () => controller.setThemeMode(ThemeMode.light),
              ),
              _ThemeModeOption(
                icon: CupertinoIcons.moon_stars_fill,
                label: 'Tối',
                description: 'Nền tối, dịu mắt khi thiếu sáng',
                isSelected: mode == ThemeMode.dark,
                onTap: () => controller.setThemeMode(ThemeMode.dark),
              ),
              _ThemeModeOption(
                icon: CupertinoIcons.device_laptop,
                label: 'Theo hệ thống',
                description: 'Đồng bộ với thiết lập của thiết bị',
                isSelected: mode == ThemeMode.system,
                onTap: () => controller.setThemeMode(ThemeMode.system),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeModeOption extends StatelessWidget {
  const _ThemeModeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final LinearGradient background = isSelected
        ? AppColors.primaryGradient()
        : (isDark
            ? AppColors.darkGlassLayerGradient()
            : AppColors.glassLayerGradient());

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: 260,
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              gradient: background,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isSelected
                    ? Colors.white.withOpacity(0.35)
                    : colorScheme.outline.withOpacity(0.08),
              ),
              boxShadow:
                  isSelected ? AppColors.elevatedShadow : AppColors.subtleShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(isSelected ? 0.22 : 0.18),
                        borderRadius: BorderRadius.circular(16),
                        border: isSelected
                            ? Border.all(color: Colors.white.withOpacity(0.4))
                            : null,
                      ),
                      child: Icon(
                        icon,
                        color: isSelected ? Colors.white : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isSelected
                              ? Colors.white
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: isSelected ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isSelected
                        ? Colors.white.withOpacity(0.85)
                        : colorScheme.onSurface.withOpacity(0.6),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitSwitcherSection extends StatefulWidget {
  const _UnitSwitcherSection();

  @override
  State<_UnitSwitcherSection> createState() => _UnitSwitcherSectionState();
}

class _BiometricSettingsSection extends StatefulWidget {
  const _BiometricSettingsSection();

  @override
  State<_BiometricSettingsSection> createState() =>
      _BiometricSettingsSectionState();
}

class _BiometricSettingsSectionState extends State<_BiometricSettingsSection> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _loading = true;
  bool _supportsBiometrics = false;
  bool _biometricEnabled = false;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final auth = context.read<AuthProvider>();
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();
      final enabled = await auth.isBiometricLoginEnabled();
      if (!mounted) return;
      setState(() {
        _supportsBiometrics = supported && (canCheck || available.isNotEmpty);
        _biometricEnabled = enabled;
        _loading = false;
      });
    } on PlatformException catch (_) {
      if (!mounted) return;
      setState(() {
        _supportsBiometrics = false;
        _biometricEnabled = false;
        _loading = false;
      });
    }
  }

  Future<void> _registerBiometric() async {
    if (_processing) return;
    final auth = context.read<AuthProvider>();
    final username = await auth.getStoredUsername();
    if (username == null) {
      _showSnack('Không tìm thấy tên đăng nhập. Vui lòng đăng nhập lại.');
      return;
    }
    final password = await _promptPassword();
    if (password == null || password.isEmpty) {
      return;
    }

    setState(() => _processing = true);

    final supported = await _localAuth.isDeviceSupported();
    final canCheck = await _localAuth.canCheckBiometrics;
    final available = await _localAuth.getAvailableBiometrics();
    if (!(supported && (canCheck || available.isNotEmpty))) {
      setState(() => _processing = false);
      _showSnack('Thiết bị của bạn không hỗ trợ đăng nhập bằng vân tay.');
      return;
    }

    final reauthOk = await auth.reauthenticateForBiometrics(password);
    if (!reauthOk) {
      setState(() => _processing = false);
      _showSnack('Mật khẩu không chính xác. Vui lòng thử lại.');
      return;
    }

    try {
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Xác thực vân tay để hoàn tất đăng ký',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!didAuthenticate) {
        setState(() => _processing = false);
        return;
      }
    } on PlatformException catch (e) {
      setState(() => _processing = false);
      _showSnack('Không thể xác thực vân tay: ${e.message ?? e.code}');
      return;
    }

    await auth.enableBiometricLogin(username, password);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = true;
      _processing = false;
    });
    _showSnack('Đã bật đăng nhập bằng vân tay.');
  }

  Future<void> _disableBiometric() async {
    if (_processing) return;
    final auth = context.read<AuthProvider>();
    setState(() => _processing = true);
    await auth.disableBiometricLogin();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = false;
      _processing = false;
    });
    _showSnack('Đã tắt đăng nhập bằng vân tay.');
  }

  Future<String?> _promptPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận mật khẩu'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mật khẩu hiện tại',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return const _SettingsGlassCard(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: SizedBox(
            height: 36,
            width: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }

    if (!_supportsBiometrics) {
      return _SettingsGlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient(),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.subtleShadow,
                  ),
                  child: const Icon(
                    Icons.block,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Thiết bị không hỗ trợ vân tay',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Thiết bị của bạn không có cảm biến sinh trắc học được hỗ trợ. Bạn vẫn có thể đăng nhập bằng mật khẩu thông thường.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return _SettingsGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient(),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Đăng nhập bằng vân tay',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: _biometricEnabled
                    ? Chip(
                        key: const ValueKey('enabled'),
                        avatar: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          'Đang bật',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: colorScheme.primary,
                      )
                    : Chip(
                        key: const ValueKey('disabled'),
                        label: Text(
                          'Đang tắt',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.8),
                          ),
                        ),
                        backgroundColor:
                            colorScheme.surfaceVariant.withOpacity(0.5),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _biometricEnabled
                ? 'Bạn đã kích hoạt đăng nhập bằng vân tay. Lần sau có thể dùng vân tay ngay tại màn hình đăng nhập.'
                : 'Đăng ký vân tay để lần sau có thể đăng nhập nhanh mà không cần nhập mật khẩu.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          if (_processing)
            const Center(
              child: SizedBox(
                height: 32,
                width: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else if (_biometricEnabled)
            OutlinedButton.icon(
              onPressed: _disableBiometric,
              icon: const Icon(Icons.block),
              label: const Text('Tắt đăng nhập vân tay'),
            )
          else
            FilledButton.icon(
              onPressed: _registerBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Đăng ký vân tay'),
            ),
        ],
      ),
    );
  }
}

class _UnitSwitcherSectionState extends State<_UnitSwitcherSection> {
  late final ContractService _contractService;
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _contractService = ContractService(ApiClient());
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final units = await _contractService.getMyUnits();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_selectedUnitPrefsKey);

      String? selected;
      if (units.isNotEmpty) {
        if (saved != null && units.any((unit) => unit.id == saved)) {
          selected = saved;
        } else {
          selected = units.first.id;
        }
      }

      if (!mounted) return;
      setState(() {
        _units = units;
        _selectedUnitId = selected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Không thể tải danh sách căn hộ. Vui lòng thử lại sau.';
        _loading = false;
      });
    }
  }

  Future<void> _onUnitChanged(String? unitId) async {
    if (unitId == null || unitId == _selectedUnitId) return;

    setState(() {
      _saving = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedUnitPrefsKey, unitId);
    AppEventBus().emit('unit_context_changed', unitId);

    if (!mounted) return;
    setState(() {
      _selectedUnitId = unitId;
      _saving = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đổi căn hộ mặc định.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return _SettingsGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient(),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: const Icon(
                  CupertinoIcons.house_alt_fill,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Căn hộ đang quản lý',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lựa chọn căn hộ mặc định để đồng bộ với toàn bộ tiện ích và dữ liệu hiển thị.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Center(
              child: SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else if (_errorMessage != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _loadUnits,
                  icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                  label: const Text('Thử lại'),
                ),
              ],
            )
          else if (_units.isEmpty)
            Text(
              'Bạn chưa được gán vào căn hộ nào. Vui lòng liên hệ ban quản lý để được hỗ trợ.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUnitDropdown(theme, isDark),
                if (_saving) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Đang cập nhật căn hộ...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _saving ? null : _loadUnits,
                  icon: const Icon(CupertinoIcons.refresh),
                  label: const Text('Đồng bộ lại danh sách căn hộ'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildUnitDropdown(ThemeData theme, bool isDark) {
    final outlineColor =
        isDark ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.28);
    final gradient =
        isDark ? AppColors.darkGlassLayerGradient() : AppColors.glassLayerGradient();
    final textColor =
        isDark ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.9);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: outlineColor, width: 1.2),
            boxShadow: AppColors.subtleShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedUnitId,
                dropdownColor: isDark
                    ? AppColors.navySurfaceElevated
                    : Colors.white.withOpacity(0.98),
                icon: Icon(
                  CupertinoIcons.chevron_down,
                  color: isDark ? Colors.white : theme.colorScheme.primary,
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
                items: _units
                    .map(
                      (unit) => DropdownMenuItem<String>(
                        value: unit.id,
                        child: Text(
                          unit.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving ? null : _onUnitChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsGlassCard extends StatelessWidget {
  const _SettingsGlassCard({
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

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
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}


