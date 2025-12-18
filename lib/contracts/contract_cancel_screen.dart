// ignore_for_file: use_build_context_synchronously
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/safe_state_mixin.dart';
import '../models/contract.dart';
import '../theme/app_colors.dart';
import '../auth/base_service_client.dart';
import 'contract_service.dart';

class ContractCancelScreen extends StatefulWidget {
  final ContractDto contract;
  final ContractService contractService;

  const ContractCancelScreen({
    Key? key,
    required this.contract,
    required this.contractService,
  }) : super(key: key);

  @override
  State<ContractCancelScreen> createState() => _ContractCancelScreenState();
}

class _ContractCancelScreenState extends State<ContractCancelScreen>
    with SafeStateMixin<ContractCancelScreen> {
  DateTime? _selectedDate;
  DateTime? _confirmedDate; // Ngày đã xác nhận (sau khi bấm xác nhận)
  bool _isLoading = false;
  String? _error;
  String? _inspectionId; // ID của inspection sau khi cancel contract

  // Tháng hủy hợp đồng (tháng hiện tại)
  late DateTime _cancelMonth;
  
  late final BaseServiceClient _baseServiceClient;

  @override
  void initState() {
    super.initState();
    // Tháng hủy hợp đồng là tháng hiện tại
    final now = DateTime.now();
    _cancelMonth = DateTime(now.year, now.month, 1);
    _baseServiceClient = BaseServiceClient();
  }

  // Lấy danh sách ngày trong tháng hủy hợp đồng
  List<DateTime> _getDaysInMonth() {
    final firstDay = _cancelMonth;
    final lastDay = DateTime(firstDay.year, firstDay.month + 1, 0);
    final daysInMonth = lastDay.day;
    
    List<DateTime> days = [];
    for (int day = 1; day <= daysInMonth; day++) {
      days.add(DateTime(firstDay.year, firstDay.month, day));
    }
    return days;
  }


  // Format tháng
  String _getMonthName() {
    return DateFormat('MM/yyyy').format(_cancelMonth);
  }

  // Format ngày
  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  // Lấy ngày cuối tháng
  DateTime _getLastDayOfMonth() {
    final lastDay = DateTime(_cancelMonth.year, _cancelMonth.month + 1, 0);
    return lastDay;
  }

  // Xác nhận ngày kiểm tra (cho phép xác nhận nhiều lần)
  Future<void> _confirmDate() async {
    if (_selectedDate == null) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Popup xác nhận ngày kiểm tra
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark
            ? AppColors.navySurfaceElevated
            : AppColors.neutralSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Xác nhận ngày kiểm tra',
          style: TextStyle(
            color: isDark ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn chọn ngày ${_formatDate(_selectedDate!)} để nhân viên tới kiểm tra?',
          style: TextStyle(
            color: isDark ? Colors.white70 : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Không',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Có',
              style: TextStyle(
                color: isDark ? Colors.blue[300] : Colors.blue[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Cho phép xác nhận nhiều lần - luôn update _confirmedDate
      setState(() {
        _confirmedDate = _selectedDate;
      });
      
      // Nếu đã có inspectionId (sau khi cancel contract), update scheduled date
      if (_inspectionId != null) {
        setState(() => _isLoading = true);
        try {
          await _baseServiceClient.updateInspectionScheduledDate(
            _inspectionId!,
            _selectedDate!,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Đã cập nhật ngày kiểm tra: ${_formatDate(_selectedDate!)}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Lỗi khi cập nhật ngày kiểm tra: ${e.toString()}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } else {
        // Chưa có inspectionId (chưa cancel contract), chỉ show message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xác nhận ngày kiểm tra: ${_formatDate(_selectedDate!)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmCancel() async {
    // Check permission before showing dialog
    if (widget.contract.isOwner == false) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      if (!mounted) return;
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
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Xác nhận hủy hợp đồng
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark
            ? AppColors.navySurfaceElevated
            : AppColors.neutralSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Xác nhận hủy hợp đồng',
          style: TextStyle(
            color: isDark ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn hủy hợp đồng ${widget.contract.contractNumber}?',
          style: TextStyle(
            color: isDark ? Colors.white70 : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Không',
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Có, hủy hợp đồng',
              style: TextStyle(
                color: isDark ? Colors.red[300] : Colors.red[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Nếu đã xác nhận ngày, dùng ngày đã xác nhận
      // Nếu không chọn ngày (chưa xác nhận), dùng ngày cuối tháng (tháng hủy hợp đồng)
      final scheduledDate = _confirmedDate ?? _getLastDayOfMonth();

      final result = await widget.contractService.cancelContract(
        widget.contract.id,
        scheduledDate: scheduledDate,
      );

      if (!mounted) return;

      if (result != null) {
          // Try to get inspection ID from result or fetch it
          // Inspection is created when contract is cancelled
          try {
            // Get inspection by contract ID to get inspectionId
            final inspectionResponse = await _baseServiceClient.dio.get(
              '/asset-inspections/contract/${widget.contract.id}',
            );
            if (inspectionResponse.statusCode == 200 && inspectionResponse.data is Map) {
              final inspectionData = Map<String, dynamic>.from(inspectionResponse.data as Map);
              _inspectionId = inspectionData['id']?.toString();
            }
          } catch (e) {
            // Inspection might not be created yet, that's okay
            print('Could not get inspection ID: $e');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Hủy hợp đồng thành công!',
                      style: TextStyle(
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
        Navigator.of(context).pop(true); 
      } else {
        setState(() {
          _error = 'Không thể hủy hợp đồng. Vui lòng thử lại.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      // Parse error message to show user-friendly message
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
      
      // Handle specific error messages from backend
      if (errorMessage.contains('Chỉ chủ căn hộ') || errorMessage.contains('OWNER') || errorMessage.contains('TENANT') || errorMessage.contains('không được phép')) {
        // Permission error - user is not OWNER/TENANT
        errorMessage = 'Chỉ chủ căn hộ (OWNER hoặc người thuê TENANT) mới được hủy gia hạn hợp đồng. Thành viên hộ gia đình không được phép hủy gia hạn.';
      }
      
      // Check permission before allowing cancel
      if (widget.contract.isOwner == false) {
        errorMessage = widget.contract.permissionMessage ?? 
            'Bạn không phải chủ căn hộ nên không thể gia hạn hay hủy hợp đồng.';
      }
      
      setState(() {
        _error = errorMessage;
        _isLoading = false;
      });
      
      // Show error in SnackBar as well
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final backgroundColor = isDark
        ? AppColors.navySurfaceElevated
        : AppColors.neutralSurface;
    final textPrimary = isDark
        ? Colors.white
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? Colors.white70
        : AppColors.textSecondary;

    final days = _getDaysInMonth();

    return Scaffold(
      backgroundColor: isDark ? AppColors.navySurface : Colors.white,
      appBar: AppBar(
        title: const Text('Chọn ngày kiểm tra'),
        backgroundColor: isDark ? AppColors.navySurface : Colors.white,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Đang xử lý...',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header info
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? colorScheme.outline.withValues(alpha: 0.3)
                              : AppColors.neutralOutline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hợp đồng: ${widget.contract.contractNumber}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          if (widget.contract.endDate != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Ngày hết hạn: ${_formatDate(widget.contract.endDate!)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    Text(
                      'Chọn ngày nhân viên tới kiểm tra',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tháng ${_getMonthName()}',
                      style: TextStyle(
                        fontSize: 14,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Calendar grid
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? colorScheme.outline.withValues(alpha: 0.3)
                              : AppColors.neutralOutline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: days.length,
                        itemBuilder: (context, index) {
                          final day = days[index];
                          final isSelected = _selectedDate != null &&
                              _selectedDate!.year == day.year &&
                              _selectedDate!.month == day.month &&
                              _selectedDate!.day == day.day;
                          final isToday = day.year == DateTime.now().year &&
                              day.month == DateTime.now().month &&
                              day.day == DateTime.now().day;
                          final isPast = day.isBefore(DateTime.now().subtract(const Duration(days: 1)));

                          return GestureDetector(
                            onTap: isPast
                                ? null
                                : () {
                                    setState(() {
                                      _selectedDate = day;
                                    });
                                  },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryBlue
                                    : isToday
                                        ? (isDark
                                            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                                            : AppColors.primaryBlue.withValues(alpha: 0.1))
                                        : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: isToday && !isSelected
                                    ? Border.all(
                                        color: AppColors.primaryBlue,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '${day.day}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected || isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isPast
                                        ? textSecondary.withValues(alpha: 0.3)
                                        : isSelected
                                            ? Colors.white
                                            : isToday
                                                ? AppColors.primaryBlue
                                                : textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Info message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blue.withValues(alpha: 0.15)
                            : Colors.blue[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.blue.withValues(alpha: 0.3)
                              : Colors.blue[200]!,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.info_circle,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              // Nếu đã xác nhận ngày, hiển thị ngày đã xác nhận
                              // Nếu chưa xác nhận, hiển thị ngày cuối tháng (mặc định)
                              _confirmedDate != null
                                  ? 'Nhân viên sẽ tới kiểm tra vào ngày ${_formatDate(_confirmedDate!)}'
                                  : 'Nếu không chọn ngày, nhân viên sẽ tới kiểm tra vào ngày cuối tháng (${_formatDate(_getLastDayOfMonth())})',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.blue[200] : Colors.blue[900],
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error message
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_circle,
                              color: Colors.red[600],
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Button xác nhận ngày (luôn hiển thị khi đã chọn ngày, cho phép xác nhận nhiều lần)
                    if (_selectedDate != null) ...[
                      FilledButton(
                        onPressed: _confirmDate,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _confirmedDate != null && _confirmedDate == _selectedDate
                              ? 'Xác nhận lại'
                              : 'Xác nhận',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Button xác nhận hủy hợp đồng (chỉ hiển thị khi đã xác nhận ngày hoặc không chọn ngày)
                    FilledButton(
                      onPressed: _confirmCancel,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Xác nhận hủy hợp đồng',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}


