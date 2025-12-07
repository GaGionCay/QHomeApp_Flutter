// ignore_for_file: use_build_context_synchronously
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/contract.dart';
import '../models/unit_info.dart';
import '../theme/app_colors.dart';
import 'contract_service.dart';

class ContractRenewalScreen extends StatefulWidget {
  final ContractDto contract;
  final ContractService contractService;
  final UnitInfo? unit;

  const ContractRenewalScreen({
    Key? key,
    required this.contract,
    required this.contractService,
    this.unit,
  }) : super(key: key);

  @override
  State<ContractRenewalScreen> createState() => _ContractRenewalScreenState();
}

class _ContractRenewalScreenState extends State<ContractRenewalScreen> {
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Set default start date to first day of next month (realtime)
    final now = DateTime.now();
    _selectedStartDate = DateTime(now.year, now.month + 1, 1);
    // Set default end date to last day of start month (same month as start)
    _updateEndDate();
  }

  void _updateEndDate() {
    if (_selectedStartDate != null) {
      // Get last day of the selected month
      final lastDayOfMonth = DateTime(_selectedStartDate!.year, _selectedStartDate!.month + 1, 0);
      setState(() {
        _selectedEndDate = lastDayOfMonth;
      });
    }
  }

  // Start date is auto-set to first day of next month (not selectable)
  // This method is kept for potential future use but won't be called
  Future<void> _selectStartDate() async {
    // Start date is automatically set to first day of next month
    // No user selection needed
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ngày bắt đầu được tự động đặt là ngày đầu tháng sau'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectEndDate() async {
    if (_selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chờ hệ thống khởi tạo ngày bắt đầu')),
      );
      return;
    }

    // Show month/year picker only
    final now = DateTime.now();
    final initialYear = _selectedEndDate?.year ?? _selectedStartDate!.year;
    final initialMonth = _selectedEndDate?.month ?? _selectedStartDate!.month;
    
    // Minimum date: same month as start date or later
    final minYear = _selectedStartDate!.year;
    final minMonth = _selectedStartDate!.month;
    
    // Maximum date: 3 years from now
    final maxYear = now.year + 3;

    // Show year picker first, then month picker
    int? selectedYear;
    int? selectedMonth;

    // Step 1: Select year
    final yearResult = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Chọn năm kết thúc'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: maxYear - minYear + 1,
              itemBuilder: (context, index) {
                final year = minYear + index;
                return ListTile(
                  title: Text(year.toString()),
                  onTap: () => Navigator.of(context).pop(year),
                  selected: year == initialYear,
                );
              },
            ),
          ),
        );
      },
    );

    if (yearResult == null) return;
    selectedYear = yearResult;

    // Step 2: Select month
    final monthResult = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Chọn tháng kết thúc',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Năm: $selectedYear',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      final month = index + 1;
                      final isDisabled = selectedYear == minYear && month < minMonth;
                      final isSelected = !isDisabled && month == initialMonth;
                      
                      return InkWell(
                        onTap: isDisabled
                            ? null
                            : () => Navigator.of(context).pop(month),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                          decoration: BoxDecoration(
                            color: isDisabled
                                ? Theme.of(context).colorScheme.surfaceContainerHighest
                                : isSelected
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                              width: isSelected ? 2.5 : 1.5,
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    month.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                      color: isDisabled
                                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                                          : isSelected
                                              ? Theme.of(context).colorScheme.onPrimaryContainer
                                              : Theme.of(context).colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Flexible(
                                  child: Text(
                                    'Tháng $month',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      height: 1.0,
                                      color: isDisabled
                                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                                          : isSelected
                                              ? Theme.of(context).colorScheme.onPrimaryContainer
                                              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (monthResult == null) return;
    selectedMonth = monthResult;

    // Set to last day of selected month
    final lastDayOfMonth = DateTime(selectedYear, selectedMonth + 1, 0);
    setState(() {
      _selectedEndDate = lastDayOfMonth;
    });
  }

  double? _calculateTotalRent() {
    if (_selectedStartDate == null || _selectedEndDate == null || widget.contract.monthlyRent == null) {
      return null;
    }

    final startDate = _selectedStartDate!;
    final endDate = _selectedEndDate!;
    final monthlyRent = widget.contract.monthlyRent!;

    // Calculate months between dates
    int months = (endDate.year - startDate.year) * 12 + (endDate.month - startDate.month) + 1;

    if (months <= 0) return 0;

    double totalRent = 0;

    // First month: if start day <= 15, charge full month, else half month
    if (startDate.day <= 15) {
      totalRent += monthlyRent;
    } else {
      totalRent += monthlyRent / 2;
    }

    // Middle months: full month each
    if (months > 1) {
      totalRent += monthlyRent * (months - 1);
    }

    return totalRent;
  }

  Future<void> _proceedToPayment() async {
    if (_selectedStartDate == null || _selectedEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn đầy đủ ngày bắt đầu và kết thúc')),
      );
      return;
    }

    if (_selectedEndDate!.isBefore(_selectedStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ngày kết thúc phải sau ngày bắt đầu')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.contractService.createRenewalPaymentUrl(
        contractId: widget.contract.id,
        startDate: _selectedStartDate!,
        endDate: _selectedEndDate!,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        if (response != null && response['paymentUrl'] != null) {
          // Open VNPay payment URL
          final uri = Uri.parse(response['paymentUrl'] as String);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            throw Exception('Không thể mở URL thanh toán');
          }
        } else {
          throw Exception('Không nhận được payment URL từ server');
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Format số tiền với dấu phẩy ngăn cách hàng nghìn, không có phần thập phân
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final totalRent = _calculateTotalRent();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gia hạn hợp đồng'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thông tin hợp đồng hiện tại',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Số hợp đồng: ${widget.contract.contractNumber}'),
                    if (widget.contract.monthlyRent != null)
                      Text('Tiền thuê/tháng: ${currencyFormat.format(widget.contract.monthlyRent!)} VND'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Thông tin hợp đồng mới',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDateField(
              label: 'Ngày bắt đầu (tự động)',
              value: _selectedStartDate != null
                  ? '${DateFormat('MM/yyyy').format(_selectedStartDate!)} (ngày đầu tháng)'
                  : 'Đang tải...',
              onTap: _selectStartDate,
              icon: CupertinoIcons.calendar_today,
              isReadOnly: true,
              helperText: 'Tự động đặt là ngày đầu tháng sau',
            ),
            const SizedBox(height: 16),
            _buildDateField(
              label: 'Ngày kết thúc (chọn tháng/năm)',
              value: _selectedEndDate != null
                  ? '${DateFormat('MM/yyyy').format(_selectedEndDate!)} (ngày cuối tháng)'
                  : 'Chọn tháng/năm',
              onTap: _selectEndDate,
              icon: CupertinoIcons.calendar,
              helperText: 'Chọn tháng và năm kết thúc hợp đồng',
            ),
            if (totalRent != null) ...[
              const SizedBox(height: 24),
              _buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tổng tiền cần thanh toán:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              currencyFormat.format(totalRent),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.visible,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'VND',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isLoading ? null : _proceedToPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Thanh toán VNPay',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(20),
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

  Widget _buildDateField({
    required String label,
    required String value,
    required VoidCallback onTap,
    required IconData icon,
    bool isReadOnly = false,
    String? helperText,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: isReadOnly ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isReadOnly
              ? theme.colorScheme.surface.withValues(alpha: 0.5)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isReadOnly
                ? theme.colorScheme.outline.withValues(alpha: 0.1)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isReadOnly
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isReadOnly
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isReadOnly)
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
              ],
            ),
            if (helperText != null) ...[
              const SizedBox(height: 8),
              Text(
                helperText,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

