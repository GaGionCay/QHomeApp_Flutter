// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:ui';
import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/safe_state_mixin.dart';
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

class _ContractRenewalScreenState extends State<ContractRenewalScreen> 
    with SafeStateMixin<ContractRenewalScreen> {
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<Uri>? _appLinkSubscription;
  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    // Set default start date to first day of next month (realtime)
    final now = DateTime.now();
    _selectedStartDate = DateTime(now.year, now.month + 1, 1);
    // Set default end date to last day of start month (same month as start)
    _updateEndDate();
    
    // Listen for VNPay callback deep links
    _initAppLinksListener();
  }

  @override
  void dispose() {
    _appLinkSubscription?.cancel();
    super.dispose();
  }

  void _initAppLinksListener() {
    _appLinkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 [ContractRenewal] Nhận deep link: $uri');
        
        if (uri.scheme == 'qhomeapp' && uri.host == 'vnpay-result') {
          final success = uri.queryParameters['success'] == 'true';
          final contractId = uri.queryParameters['contractId'];
          final message = uri.queryParameters['message'];
          
          if (success && contractId != null && mounted) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message != null && message.isNotEmpty
                            ? Uri.decodeComponent(message)
                            : 'Gia hạn hợp đồng thành công!',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
            
            // Pop back to contract list screen
            // The contract list will refresh automatically when navigated back
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                Navigator.of(context).pop(true); // Return true to indicate success
              }
            });
          } else if (!success && mounted) {
            // Show error message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message != null && message.isNotEmpty
                            ? Uri.decodeComponent(message)
                            : 'Thanh toán không thành công',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
          }
        }
      },
      onError: (err) {
        debugPrint('❌ [ContractRenewal] Lỗi khi nhận deep link: $err');
      },
    );
  }

  void _updateEndDate() {
    if (_selectedStartDate != null) {
      // Set end date to last day of the month that is 3 months after start date
      // Example: Start date = 01/2026 -> End date = 31/03/2026 (last day of March 2026)
      final startYear = _selectedStartDate!.year;
      final startMonth = _selectedStartDate!.month;
      final endMonth = startMonth + 3;
      final endYear = endMonth > 12 ? startYear + 1 : startYear;
      final adjustedEndMonth = endMonth > 12 ? endMonth - 12 : endMonth;
      
      // Get last day of the end month
      final lastDayOfMonth = DateTime(endYear, adjustedEndMonth + 1, 0);
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
    
    // Extract start date components for validation
    final startYear = _selectedStartDate!.year;
    final startMonth = _selectedStartDate!.month;
    
    // Minimum date: 3 months after start date (gia hạn tối thiểu 3 tháng)
    final minYear = startYear;
    final minMonth = startMonth + 3; // Ít nhất 3 tháng sau ngày bắt đầu
    final minYearAdjusted = minMonth > 12 ? minYear + 1 : minYear;
    final minMonthAdjusted = minMonth > 12 ? minMonth - 12 : minMonth;
    
    // Maximum date: 3 years from now
    final maxYear = now.year + 3;

    // Show year picker first, then month picker
    int? selectedYear;
    int? selectedMonth;

    // Step 1: Select year (all years are selectable, validation happens in month picker)
    final yearResult = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Chọn năm kết thúc'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: maxYear - minYearAdjusted + 1,
              itemBuilder: (context, index) {
                final year = minYearAdjusted + index;
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
                      
                      // Calculate if this month/year combination is at least 3 months after start date
                      final monthsDiff = (selectedYear! - startYear) * 12 + (month - startMonth);
                      final isDisabled = monthsDiff < 3;
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

    // Validate: End month must be at least 3 months after start month
    final endYear = selectedYear!;
    final endMonth = selectedMonth!;
    
    // Calculate months difference
    final monthsDiff = (endYear - startYear) * 12 + (endMonth - startMonth);
    
    if (monthsDiff < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Gia hạn hợp đồng phải ít nhất 3 tháng. Vui lòng chọn tháng kết thúc cách tháng bắt đầu ít nhất 3 tháng.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

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
    // Check permission before proceeding
    if (widget.contract.isOwner == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.contract.permissionMessage ?? 
                'Bạn không phải chủ căn hộ nên không thể gia hạn hay hủy hợp đồng.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    
    if (_selectedStartDate == null || _selectedEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn đầy đủ ngày bắt đầu và kết thúc')),
      );
      return;
    }

    // Validate: Ngày kết thúc phải sau ngày bắt đầu và không được trùng nhau
    if (_selectedEndDate!.isBefore(_selectedStartDate!) || 
        _selectedEndDate!.isAtSameMomentAs(_selectedStartDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ngày kết thúc phải sau ngày bắt đầu và không được trùng nhau'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Validate: Gia hạn phải ít nhất 3 tháng
    final startDate = _selectedStartDate!;
    final endDate = _selectedEndDate!;
    
    // Calculate months difference accurately
    // Start date is first day of month, end date is last day of month
    // So we calculate from start of start month to start of end month
    final startOfStartMonth = DateTime(startDate.year, startDate.month, 1);
    final startOfEndMonth = DateTime(endDate.year, endDate.month, 1);
    
    // Calculate difference in months
    final monthsDifference = (endDate.year - startDate.year) * 12 + (endDate.month - startDate.month);
    
    // Check if at least 3 months
    // Since startDate is first day of month and endDate is last day of month,
    // if monthsDifference is 2, it means we have 2 full months + partial month = less than 3 months
    // We need at least 3 months difference (e.g., Jan -> Apr = 3 months)
    if (monthsDifference < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Gia hạn hợp đồng phải ít nhất 3 tháng. Ngày kết thúc phải cách ngày bắt đầu ít nhất 3 tháng.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
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
        // Parse error message to show user-friendly message
        // Try to get message from Exception first, fallback to toString()
        String errorMessage = '';
        if (e is Exception) {
          errorMessage = e.toString();
          // Remove "Exception: " prefix if present
          if (errorMessage.startsWith('Exception: ')) {
            errorMessage = errorMessage.substring(11);
          }
        } else {
          errorMessage = e.toString();
        }
        
        debugPrint('🔍 [ContractRenewal] Error message: $errorMessage');
        
        // Handle specific error messages from backend
        if (errorMessage.contains('Chỉ chủ căn hộ') || errorMessage.contains('OWNER') || errorMessage.contains('TENANT') || errorMessage.contains('không được phép')) {
          // Permission error - user is not OWNER/TENANT
          errorMessage = 'Chỉ chủ căn hộ (OWNER hoặc người thuê TENANT) mới được gia hạn hợp đồng. Thành viên hộ gia đình không được phép gia hạn.';
        }
        
        // Check permission before allowing renewal
        if (widget.contract.isOwner == false) {
          errorMessage = widget.contract.permissionMessage ?? 
              'Bạn không phải chủ căn hộ nên không thể gia hạn hay hủy hợp đồng.';
        } else if (errorMessage.contains('ít nhất 3 tháng') || errorMessage.contains('3 tháng')) {
          errorMessage = 'Gia hạn hợp đồng phải ít nhất 3 tháng. Vui lòng chọn ngày kết thúc cách ngày bắt đầu ít nhất 3 tháng.';
        } else if (errorMessage.contains('trùng thời gian') || errorMessage.contains('trùng')) {
          // Extract contract number and date range from error message if available
          // Format: "Hợp đồng mới trùng thời gian với hợp đồng hiện có (Số hợp đồng: XXX, từ YYYY-MM-DD đến YYYY-MM-DD). Vui lòng chọn khoảng thời gian khác."
          String displayMessage = errorMessage;
          
          // Try to extract and format the information more clearly
          // Updated regex to be more flexible with whitespace
          final contractMatch = RegExp(r'Số hợp đồng:\s*([^,)]+)').firstMatch(errorMessage);
          final dateMatch = RegExp(r'từ\s*(\d{4}-\d{2}-\d{2})\s*đến\s*(\d{4}-\d{2}-\d{2})').firstMatch(errorMessage);
          
          debugPrint('🔍 [ContractRenewal] Contract match: ${contractMatch?.group(1)}');
          debugPrint('🔍 [ContractRenewal] Date match: ${dateMatch?.group(1)} - ${dateMatch?.group(2)}');
          
          if (contractMatch != null && dateMatch != null) {
            final contractNumber = contractMatch.group(1)?.trim() ?? '';
            final startDate = dateMatch.group(1) ?? '';
            final endDate = dateMatch.group(2) ?? '';
            
            // Format dates to DD/MM/YYYY
            try {
              final startParts = startDate.split('-');
              final endParts = endDate.split('-');
              if (startParts.length == 3 && endParts.length == 3) {
                final formattedStart = '${startParts[2]}/${startParts[1]}/${startParts[0]}';
                final formattedEnd = '${endParts[2]}/${endParts[1]}/${endParts[0]}';
                
                displayMessage = 'Hợp đồng mới trùng thời gian với hợp đồng đã được gia hạn trước đó.\n\n'
                    'Số hợp đồng trùng: $contractNumber\n'
                    'Thời gian: Từ $formattedStart đến $formattedEnd\n\n'
                    'Vui lòng chọn khoảng thời gian khác để gia hạn hợp đồng.';
              }
            } catch (ex) {
              debugPrint('⚠️ [ContractRenewal] Date parsing failed: $ex');
              // If date parsing fails, use original message
            }
          } else {
            // If regex doesn't match, still show a formatted message
            displayMessage = 'Hợp đồng mới trùng thời gian với hợp đồng đã được gia hạn trước đó.\n\n'
                'Vui lòng chọn khoảng thời gian khác để gia hạn hợp đồng.';
          }
          
          errorMessage = displayMessage;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(fontSize: 14),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
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
              helperText: 'Chọn tháng và năm kết thúc hợp đồng (tối thiểu 3 tháng từ ngày bắt đầu)',
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

