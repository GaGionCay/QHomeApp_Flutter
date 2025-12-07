import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../auth/api_client.dart';
import 'package:dio/dio.dart';
import '../models/contract.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'contract_detail_screen.dart';
import 'contract_service.dart';
import 'contract_renewal_screen.dart';
import 'contract_cancel_screen.dart';

class ContractListScreen extends StatefulWidget {
  const ContractListScreen({super.key});

  @override
  State<ContractListScreen> createState() => _ContractListScreenState();
}

class _ContractListScreenState extends State<ContractListScreen>
    with SingleTickerProviderStateMixin {
  ContractService? _contractService;
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  List<ContractDto> _contracts = [];
  bool _loadingUnits = true;
  bool _loadingContracts = false;
  String? _error;
  static const _selectedUnitPrefsKey = 'selected_unit_id';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Initialize TabController with 5 tabs: Cần gia hạn, Active, Inactive, Canceled, Expired
    _tabController = TabController(length: 5, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      
      // Store all contracts (will be filtered by tabs)
      setState(() {
        _contracts = data;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('❌ [ContractList] Lỗi khi load contracts: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải hợp đồng: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingContracts = false;
        });
      }
    }
  }

  /// Build tab content with filtered contracts
  Widget _buildTabContent(ThemeData theme, double bottomInset, List<ContractDto> filteredContracts) {
    if (_loadingContracts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filteredContracts.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset),
          child: _buildEmptyContracts(theme),
        ),
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final contract = filteredContracts[index];
                return _AnimatedContractCard(
                  key: ValueKey('contract_${contract.id}_${_tabController.index}'),
                  index: index,
                  contract: contract,
                  builder: _buildContractCard,
                );
              },
              childCount: filteredContracts.length,
            ),
          ),
        ),
      ],
    );
  }

  /// Get contracts that need renewal (sorted by startDate descending)
  List<ContractDto> _getRenewalContracts() {
    final filtered = _contracts.where((contract) => _needsRenewal(contract)).toList();
    return _sortByStartDate(filtered);
  }

  /// Get ACTIVE contracts (sorted by startDate descending)
  List<ContractDto> _getActiveContracts() {
    final filtered = _contracts.where((contract) => 
      contract.status.toUpperCase() == 'ACTIVE' && !_needsRenewal(contract)
    ).toList();
    return _sortByStartDate(filtered);
  }

  /// Get INACTIVE contracts (sorted by startDate descending)
  List<ContractDto> _getInactiveContracts() {
    final filtered = _contracts.where((contract) => 
      contract.status.toUpperCase() == 'INACTIVE'
    ).toList();
    return _sortByStartDate(filtered);
  }

  /// Get CANCELLED contracts (sorted by startDate descending)
  List<ContractDto> _getCanceledContracts() {
    final filtered = _contracts.where((contract) => 
      contract.status.toUpperCase() == 'CANCELLED'
    ).toList();
    return _sortByStartDate(filtered);
  }

  /// Get EXPIRED contracts (sorted by startDate descending)
  List<ContractDto> _getExpiredContracts() {
    final filtered = _contracts.where((contract) => 
      contract.status.toUpperCase() == 'EXPIRED'
    ).toList();
    return _sortByStartDate(filtered);
  }

  /// Sort contracts by startDate (most recent first, nulls last)
  List<ContractDto> _sortByStartDate(List<ContractDto> contracts) {
    final sorted = List<ContractDto>.from(contracts);
    sorted.sort((c1, c2) {
      // Sort by startDate (most recent first, nulls last)
      if (c1.startDate != null && c2.startDate != null) {
        return c2.startDate!.compareTo(c1.startDate!);
      }
      if (c1.startDate != null) return -1;
      if (c2.startDate != null) return 1;
      
      // If both null, sort by createdAt (most recent first)
      if (c1.createdAt != null && c2.createdAt != null) {
        return c2.createdAt!.compareTo(c1.createdAt!);
      }
      
      return 0;
    });
    return sorted;
  }

  /// Get priority for contract status sorting
  /// Lower number = higher priority
  /// ACTIVE = 1 (highest), INACTIVE = 2, CANCELLED = 3, EXPIRED = 4 (lowest)
  int _getStatusPriority(String status) {
    final upperStatus = status.toUpperCase();
    switch (upperStatus) {
      case 'ACTIVE':
        return 1;
      case 'INACTIVE':
        return 2;
      case 'CANCELLED':
        return 3;
      case 'EXPIRED':
        return 4;
      default:
        return 5;
    }
  }

  /// Get contract type text in Vietnamese
  String _getContractTypeText(String contractType) {
    switch (contractType.toUpperCase()) {
      case 'RENTAL':
        return 'Thuê';
      case 'PURCHASE':
        return 'Mua';
      default:
        return contractType;
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bạn chưa được gán vào căn hộ nào.\nLiên hệ quản lý để được cấp quyền.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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

    return Column(
      children: [
        // Unit Summary
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: _buildUnitSummary(selectedUnit),
        ),
        const SizedBox(height: 20),
        // Tab Bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            indicator: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            unselectedLabelStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Cần gia hạn'),
              Tab(text: 'Đang hoạt động'),
              Tab(text: 'Không hoạt động'),
              Tab(text: 'Đã hủy'),
              Tab(text: 'Đã hết hạn'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Tab Bar View
        Expanded(
          child: RefreshIndicator(
            color: theme.colorScheme.primary,
            onRefresh: _refresh,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(theme, bottomInset, _getRenewalContracts()),
                _buildTabContent(theme, bottomInset, _getActiveContracts()),
                _buildTabContent(theme, bottomInset, _getInactiveContracts()),
                _buildTabContent(theme, bottomInset, _getCanceledContracts()),
                _buildTabContent(theme, bottomInset, _getExpiredContracts()),
              ],
            ),
          ),
        ),
      ],
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
        color: theme.colorScheme.surface.withValues(alpha: 0.75),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.08),
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractCard(ContractDto contract) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('dd/MM/yyyy');
    final isActive = contract.status.toUpperCase() == 'ACTIVE';
    final needsRenewal = _needsRenewal(contract);

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
    late String statusText;
    switch (contract.status.toUpperCase()) {
      case 'ACTIVE':
        statusColor = const Color(0xFF34C759);
        statusIcon = CupertinoIcons.check_mark_circled_solid;
        statusText = 'Đang hoạt động';
        break;
      case 'INACTIVE':
        statusColor = const Color(0xFF5AC8FA);
        statusIcon = CupertinoIcons.pause_circle_fill;
        statusText = 'Không hoạt động';
        break;
      case 'CANCELLED':
        statusColor = const Color(0xFFFF3B30);
        statusIcon = CupertinoIcons.xmark_circle_fill;
        statusText = 'Đã hủy';
        break;
      case 'EXPIRED':
        statusColor = const Color(0xFFFF9500);
        statusIcon = CupertinoIcons.time_solid;
        statusText = 'Đã hết hạn';
        break;
      default:
        statusColor = theme.colorScheme.primary;
        statusIcon = CupertinoIcons.info_circle_fill;
        statusText = contract.status;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ContractDetailScreen(contractId: contract.id),
          ),
        );
      },
      child: _ContractCard(
        isActive: isActive,
        isDark: isDark,
        needsRenewal: needsRenewal,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Renewal banner - hiển thị nổi bật ở đầu card
              if (needsRenewal) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF9500).withValues(alpha: 0.15),
                        const Color(0xFFFF9500).withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFF9500).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          CupertinoIcons.bell_fill,
                          color: Color(0xFFFF9500),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cần gia hạn hợp đồng',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFF9500),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _getRenewalMessage(contract),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.arrow_right_circle_fill,
                        color: const Color(0xFFFF9500),
                        size: 20,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contract number - full width
                  Text(
                    contract.contractNumber,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive 
                          ? theme.colorScheme.onSurface 
                          : theme.colorScheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Contract type
                  Text(
                    'Loại: ${_getContractTypeText(contract.contractType)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 12),
                  // Status badge - "Đang hoạt động"
                  Row(
                    children: [
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive 
                              ? statusColor.withValues(alpha: 0.2)
                              : statusColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(18),
                          border: isActive 
                              ? Border.all(
                                  color: statusColor.withValues(alpha: 0.4),
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              statusIcon, 
                              size: isActive ? 18 : 16, 
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                                fontSize: isActive ? 11 : 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Renewal badge - below status if needs renewal
                  if (needsRenewal) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9500).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFFF9500).withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.arrow_clockwise,
                            size: 16,
                            color: const Color(0xFFFF9500),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Cần gia hạn',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFFF9500),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
              // Action buttons for RENTAL contracts that are ACTIVE and need renewal
              if (contract.contractType == 'RENTAL' && 
                  contract.status == 'ACTIVE') ...[
                const SizedBox(height: 20),
                // Check if contract is within 3 months before expiration
                Builder(
                  builder: (context) {
                    final canRenew = _canRenewContract(contract);
                    // Chỉ hiển thị button khi có thể gia hạn (trong vòng 3 tháng trước khi hết hạn)
                    // Không hiển thị nếu còn hơn 3 tháng, dù có renewalStatus là REMINDED hay PENDING
                    if (!canRenew) {
                      return const SizedBox.shrink();
                    }
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Thông báo nếu có reminder nhưng chưa đến thời điểm gia hạn (không nên xảy ra vì đã check canRenew)
                        if (contract.renewalStatus == 'REMINDED' || contract.renewalStatus == 'PENDING')
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.info_circle,
                                  size: 18,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Chỉ có thể gia hạn trong vòng 3 tháng trước khi hết hạn',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
            ],
          ),
        ),
                        if (contract.renewalStatus == 'REMINDED' || contract.renewalStatus == 'PENDING')
                          const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _handleCancelContract(contract),
                                icon: const Icon(CupertinoIcons.xmark_circle, size: 18),
                                label: const Text('Hủy hợp đồng'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(
                                    color: theme.colorScheme.error.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: canRenew ? () => _handleRenewContract(contract) : null,
                                icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                                label: const Text('Gia hạn hợp đồng'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: canRenew 
                                      ? AppColors.primaryBlue 
                                      : theme.colorScheme.surfaceContainerHighest,
                                  foregroundColor: canRenew 
                                      ? Colors.white 
                                      : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                  minimumSize: const Size(0, 48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: canRenew ? 2 : 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Check if contract needs renewal (can renew or has renewal status)
  bool _needsRenewal(ContractDto contract) {
    // Chỉ hợp đồng RENTAL và ACTIVE mới cần gia hạn
    if (contract.contractType != 'RENTAL' || contract.status != 'ACTIVE') {
      return false;
    }
    
    // Nếu có renewalStatus là REMINDED hoặc PENDING, cần gia hạn
    if (contract.renewalStatus == 'REMINDED' || contract.renewalStatus == 'PENDING') {
      return true;
    }
    
    // Nếu có thể gia hạn (trong vòng 3 tháng), cần gia hạn
    return _canRenewContract(contract);
  }

  /// Get renewal message based on contract state
  String _getRenewalMessage(ContractDto contract) {
    if (contract.renewalStatus == 'REMINDED') {
      if (contract.isFinalReminder == true) {
        return 'Nhắc nhở cuối cùng - Hợp đồng sắp hết hạn';
      }
      return 'Đã nhắc nhở gia hạn - Vui lòng xử lý sớm';
    }
    
    if (contract.renewalStatus == 'PENDING') {
      return 'Đang chờ gia hạn - Vui lòng hoàn tất thủ tục';
    }
    
    // Calculate days until expiry
    if (contract.endDate != null) {
      final now = DateTime.now();
      final endDate = contract.endDate!;
      final daysUntilExpiry = endDate.difference(now).inDays;
      
      if (daysUntilExpiry < 0) {
        return 'Hợp đồng đã hết hạn - Cần gia hạn ngay';
      } else if (daysUntilExpiry <= 30) {
        return 'Còn ${daysUntilExpiry} ngày - Cần gia hạn sớm';
      } else if (daysUntilExpiry <= 60) {
        final months = (daysUntilExpiry / 30).ceil();
        return 'Còn khoảng $months tháng - Nên gia hạn sớm';
      } else {
        final months = (daysUntilExpiry / 30).ceil();
        return 'Còn khoảng $months tháng - Có thể gia hạn';
      }
    }
    
    return 'Hợp đồng cần được gia hạn';
  }

  bool _canRenewContract(ContractDto contract) {
    // Chỉ cho phép gia hạn hợp đồng RENTAL và ACTIVE
    if (contract.contractType != 'RENTAL' || contract.status != 'ACTIVE') {
      return false;
    }
    
    if (contract.endDate == null) return false;
    
    final now = DateTime.now();
    final endDate = contract.endDate!;
    
    // If contract has already expired, cannot renew
    if (endDate.isBefore(now)) return false;
    
    // Tính số ngày từ hôm nay đến ngày hết hạn
    final daysUntilExpiry = endDate.difference(now).inDays;
    
    // Chỉ được gia hạn khi còn 3 tháng trước ngày hết hạn
    // 3 tháng = khoảng 90 ngày (30 ngày/tháng)
    // Cho phép gia hạn khi: 0 <= daysUntilExpiry <= 90 ngày
    // Không cho phép khi: daysUntilExpiry > 90 ngày (hơn 3 tháng)
    
    // Tính số tháng chính xác dựa trên số ngày
    // Nếu còn hơn 90 ngày (hơn 3 tháng), không cho phép
    if (daysUntilExpiry > 90) {
      return false;
    }
    
    // Nếu còn từ 0 đến 90 ngày (0 đến 3 tháng), cho phép gia hạn
    return daysUntilExpiry >= 0;
  }

  Future<void> _handleRenewContract(ContractDto contract) async {
    if (_contractService == null) return;
    
    // Kiểm tra: chỉ được gia hạn khi còn 3 tháng trước ngày hết hạn
    if (!_canRenewContract(contract)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Chỉ có thể gia hạn hợp đồng trong vòng 3 tháng trước khi hết hạn'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ContractRenewalScreen(
          contract: contract,
          contractService: _contractService!,
        ),
      ),
    );
    
    // Refresh contracts after returning
    if (_selectedUnitId != null) {
      await _loadContracts(_selectedUnitId!);
    }
  }

  Future<void> _handleCancelContract(ContractDto contract) async {
    if (_contractService == null) return;
    
    // Navigate to cancel screen to select inspection date
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContractCancelScreen(
          contract: contract,
          contractService: _contractService!,
        ),
      ),
    );
    
    // If cancellation was successful, refresh contracts
    if (result == true && mounted) {
      if (_selectedUnitId != null) {
        await _loadContracts(_selectedUnitId!);
      }
    }
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
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildFileChip(ContractFileDto file) {
    final theme = Theme.of(context);
    final isImage = file.contentType.toLowerCase().startsWith('image/');
    final isWord = file.contentType.toLowerCase().contains('word') || 
                  file.originalFileName.toLowerCase().endsWith('.doc') ||
                  file.originalFileName.toLowerCase().endsWith('.docx');
    
    IconData fileIcon = CupertinoIcons.doc_plaintext;
    if (isImage) {
      fileIcon = CupertinoIcons.photo;
    } else if (isWord) {
      fileIcon = CupertinoIcons.doc_text_fill;
    }

    return PopupMenuButton<String>(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface.withValues(alpha: 0.75),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIcon, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                file.originalFileName.isNotEmpty ? file.originalFileName : file.fileName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
      onSelected: (value) async {
        if (value == 'view') {
          await _viewFile(file);
        } else if (value == 'download') {
          await _downloadFile(file);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(CupertinoIcons.eye, size: 18),
              SizedBox(width: 8),
              Text('Xem'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(CupertinoIcons.arrow_down_circle, size: 18),
              SizedBox(width: 8),
              Text('Tải về'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _viewFile(ContractFileDto file) async {
    try {
      // Download file first, then open with system dialog
      final url = ApiClient.fileUrl(file.fileUrl);
      
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final uri = Uri.parse(url);
      final fileName = file.originalFileName.isNotEmpty 
          ? file.originalFileName 
          : file.fileName.isNotEmpty
              ? file.fileName
              : uri.pathSegments.last.isNotEmpty 
                  ? uri.pathSegments.last 
                  : 'contract_file';
      final filePath = '${tempDir.path}/$fileName';
      
      // Download file using Dio with authentication
      final apiClient = await ApiClient.create();
      final dio = apiClient.dio;
      
      await dio.download(
        url,
        filePath,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );
      
      // Open file with system dialog
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở tệp: ${result.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi mở tệp: $e')),
      );
    }
  }

  Future<void> _downloadFile(ContractFileDto file) async {
    if (_contractService == null) return;

    try {
      // Find contract ID from the file
      final contract = _contracts.firstWhere(
        (c) => c.files.any((f) => f.id == file.id),
        orElse: () => _contracts.first,
      );

      final filePath = await _contractService!.downloadContractFile(
        contract.id,
        file.id,
        file.originalFileName.isNotEmpty ? file.originalFileName : file.fileName,
        null, // No progress callback for list screen
      );

      if (!mounted) return;

      if (filePath != null) {
        final isImage = file.contentType.toLowerCase().startsWith('image/');
        final isWord = file.contentType.toLowerCase().contains('word') || 
                      file.originalFileName.toLowerCase().endsWith('.doc') ||
                      file.originalFileName.toLowerCase().endsWith('.docx');
        
        String fileTypeText = 'tài liệu';
        if (isImage) {
          fileTypeText = 'ảnh';
        } else if (isWord) {
          fileTypeText = 'file Word';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tải xuống $fileTypeText: ${file.originalFileName.isNotEmpty ? file.originalFileName : file.fileName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Mở',
              textColor: Colors.white,
              onPressed: () => _viewFile(file),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải xuống: ${file.originalFileName.isNotEmpty ? file.originalFileName : file.fileName}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Lỗi tải xuống: $e';
      if (e.toString().contains('quyền')) {
        errorMessage = 'Cần cấp quyền truy cập bộ nhớ để tải file. Vui lòng cấp quyền trong Cài đặt.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: AppColors.subtleShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Contract card with special styling for ACTIVE contracts and renewal needs
class _ContractCard extends StatelessWidget {
  const _ContractCard({
    required this.isActive,
    required this.isDark,
    required this.needsRenewal,
    required this.child,
  });

  final bool isActive;
  final bool isDark;
  final bool needsRenewal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Special styling for contracts that need renewal
    if (needsRenewal) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.darkGlassLayerGradient()
                  : AppColors.glassLayerGradient(),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                width: 2.5,
                color: const Color(0xFFFF9500).withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9500).withValues(alpha: 0.25),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
                if (isActive)
                  BoxShadow(
                    color: const Color(0xFF34C759).withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                ...AppColors.subtleShadow,
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    
    if (isActive) {
      // Special styling for ACTIVE contracts (without renewal need)
      return ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.darkGlassLayerGradient()
                  : AppColors.glassLayerGradient(),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                width: 2,
                color: const Color(0xFF34C759).withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF34C759).withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
                ...AppColors.subtleShadow,
              ],
            ),
            child: child,
          ),
        ),
      );
    }
    
    // Standard styling for other contracts
    return _ServiceGlassCard(child: child);
  }
}

/// Animated contract card with staggered entrance animation
class _AnimatedContractCard extends StatefulWidget {
  const _AnimatedContractCard({
    required super.key,
    required this.index,
    required this.contract,
    required this.builder,
  });

  final int index;
  final ContractDto contract;
  final Widget Function(ContractDto) builder;

  @override
  State<_AnimatedContractCard> createState() => _AnimatedContractCardState();
}

class _AnimatedContractCardState extends State<_AnimatedContractCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 300 + (widget.index * 50).clamp(0, 200)),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    
    // Start animation after a small delay based on index
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.index == 0 ? 0 : 16),
          child: widget.builder(widget.contract),
        ),
      ),
    );
  }
}
