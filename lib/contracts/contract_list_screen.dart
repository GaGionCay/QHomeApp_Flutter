import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../models/contract.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'contract_service.dart';

class ContractListScreen extends StatefulWidget {
  const ContractListScreen({super.key});

  @override
  State<ContractListScreen> createState() => _ContractListScreenState();
}

class _ContractListScreenState extends State<ContractListScreen> {
  ContractService? _contractService;
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  List<ContractDto> _contracts = [];
  bool _loadingUnits = true;
  bool _loadingContracts = false;
  String? _error;
  static const _selectedUnitPrefsKey = 'selected_unit_id';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loadingUnits = true;
      _error = null;
    });

    try {
      final apiClient = await ApiClient.create();
      _contractService = ContractService(apiClient);
      await _loadUnits();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể khởi tạo dịch vụ: $e';
        _loadingUnits = false;
      });
    }
  }

  Future<void> _loadUnits() async {
    final service = _contractService;
    if (service == null) return;

    try {
      final units = await service.getMyUnits();
      final prefs = await SharedPreferences.getInstance();
      final savedUnit = prefs.getString(_selectedUnitPrefsKey);
      String? nextSelected = savedUnit;

      if (nextSelected == null && units.isNotEmpty) {
        nextSelected = units.first.id;
      }

      if (!mounted) return;
      setState(() {
        _units = units;
        _selectedUnitId = nextSelected;
        _loadingUnits = false;
      });

      if (_selectedUnitId != null) {
        await _loadContracts(_selectedUnitId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Lỗi tải danh sách căn hộ: $e';
        _loadingUnits = false;
      });
    }
  }

  Future<void> _loadContracts(String unitId) async {
    final service = _contractService;
    if (service == null) return;

    setState(() {
      _loadingContracts = true;
    });

    try {
      final data = await service.getContractsByUnit(unitId);
      if (!mounted) return;
      setState(() {
        _contracts = data;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải hợp đồng: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingContracts = false;
      });
    }
  }

  Future<void> _refresh() async {
    final unitId = _selectedUnitId;
    if (unitId != null) {
      await _loadContracts(unitId);
    } else {
      await _loadUnits();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    const double navHeight = 72;
    const double navVerticalPadding = 18;
    final double bottomInset = navHeight +
        (navVerticalPadding * 2) +
        MediaQuery.of(context).padding.bottom;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B1728),
              Color(0xFF0F213A),
              Color(0xFF071117),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE7F3FF),
              Color(0xFFF5FAFF),
              Colors.white,
            ],
          );

    return Scaffold(
      extendBody: true,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Hợp đồng của tôi'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: _buildBody(theme, bottomInset),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, double bottomInset) {
    if (_loadingUnits) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: _ServiceGlassCard(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.74),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _init,
                  icon: const Icon(CupertinoIcons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_units.isEmpty) {
      return Center(
        child: _ServiceGlassCard(
          child: Padding(
            padding: EdgeInsets.fromLTRB(28, 28, 28, bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.person_crop_square,
                  size: 56,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bạn chưa được gán vào căn hộ nào.\nLiên hệ quản lý để được cấp quyền.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedUnit = _units.firstWhere(
      (unit) => unit.id == _selectedUnitId,
      orElse: () => _units.first,
    );

    return RefreshIndicator(
      color: theme.colorScheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 24, 20, bottomInset),
        children: [
          _buildUnitSummary(selectedUnit),
          const SizedBox(height: 20),
          if (_loadingContracts)
            const Center(child: CircularProgressIndicator())
          else if (_contracts.isEmpty)
            _buildEmptyContracts(theme)
          else
            ..._contracts.map(_buildContractCard),
        ],
      ),
    );
  }

  Widget _buildUnitSummary(UnitInfo selectedUnit) {
    final theme = Theme.of(context);
    return _ServiceGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    CupertinoIcons.house_fill,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedUnit.displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tòa ${selectedUnit.buildingName ?? selectedUnit.buildingCode ?? '-'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(CupertinoIcons.chevron_down),
                  onSelected: (value) async {
                    if (_selectedUnitId == value) return;
                    setState(() => _selectedUnitId = value);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(_selectedUnitPrefsKey, value);
                    await _loadContracts(value);
                  },
                  itemBuilder: (_) => _units
                      .map(
                        (unit) => PopupMenuItem<String>(
                          value: unit.id,
                          child: Text(unit.displayName),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                if (selectedUnit.floor != null)
                  _buildUnitChip(
                    icon: CupertinoIcons.layers,
                    label: 'Tầng ${selectedUnit.floor}',
                  ),
                if (selectedUnit.areaM2 != null)
                  _buildUnitChip(
                    icon: CupertinoIcons.square_stack_3d_down_right,
                    label:
                        'Diện tích ${selectedUnit.areaM2!.toStringAsFixed(1)} m²',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitChip({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surface.withOpacity(0.75),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContracts(ThemeData theme) {
    return _ServiceGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.doc_text_search,
              size: 56,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có hợp đồng nào cho căn hộ này.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn sẽ nhận thông báo khi hợp đồng được ban quản lý cập nhật.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractCard(ContractDto contract) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');

    String formatDate(DateTime? date) {
      if (date == null) return 'Không xác định';
      return dateFormat.format(date);
    }

    String formatCurrency(double? value) {
      if (value == null) return '-';
      final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
      return formatter.format(value);
    }

    late Color statusColor;
    late IconData statusIcon;
    switch (contract.status.toUpperCase()) {
      case 'ACTIVE':
        statusColor = const Color(0xFF34C759);
        statusIcon = CupertinoIcons.check_mark_circled_solid;
        break;
      case 'TERMINATED':
        statusColor = const Color(0xFFFF3B30);
        statusIcon = CupertinoIcons.xmark_circle_fill;
        break;
      case 'EXPIRED':
        statusColor = const Color(0xFFFF9500);
        statusIcon = CupertinoIcons.time_solid;
        break;
      default:
        statusColor = theme.colorScheme.primary;
        statusIcon = CupertinoIcons.info_circle_fill;
    }

    return _ServiceGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contract.contractNumber,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Loại: ${contract.contractType}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        contract.status.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              icon: CupertinoIcons.calendar,
              label: 'Bắt đầu',
              value: formatDate(contract.startDate),
            ),
            const SizedBox(height: 6),
            _buildInfoRow(
              icon: CupertinoIcons.calendar_badge_minus,
              label: 'Kết thúc',
              value: formatDate(contract.endDate),
            ),
            if (contract.monthlyRent != null) ...[
              const SizedBox(height: 6),
              _buildInfoRow(
                icon: CupertinoIcons.creditcard,
                label: 'Tiền thuê',
                value: formatCurrency(contract.monthlyRent),
              ),
            ],
            if (contract.notes != null && contract.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                contract.notes!,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (contract.files.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Tài liệu đính kèm',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: contract.files.map(_buildFileChip).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _buildFileChip(ContractFileDto file) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final url = ApiClient.fileUrl(file.fileUrl);
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url));
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể mở tệp ${file.fileName}')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface.withOpacity(0.75),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.doc_plaintext, size: 16),
            const SizedBox(width: 8),
            Text(
              file.fileName,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
