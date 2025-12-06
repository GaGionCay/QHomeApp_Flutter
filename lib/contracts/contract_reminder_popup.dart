import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contract.dart';
import '../theme/app_colors.dart';
import 'contract_service.dart';
import 'contract_renewal_screen.dart';

class ContractReminderPopup extends StatefulWidget {
  final ContractDto contract;
  final ContractService contractService;
  final VoidCallback? onDismiss;

  const ContractReminderPopup({
    Key? key,
    required this.contract,
    required this.contractService,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<ContractReminderPopup> createState() => _ContractReminderPopupState();
}

class _ContractReminderPopupState extends State<ContractReminderPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _dismissDialog() async {
    await _animationController.reverse();
    if (mounted) {
      Navigator.of(context).pop();
      // Mark popup as shown when dismissed
      await _markPopupAsShown();
    }
  }

  /// Mark popup as shown in SharedPreferences
  Future<void> _markPopupAsShown() async {
    if (widget.contract.renewalReminderSentAt == null) {
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'contract_reminder_shown_${widget.contract.id}_${widget.contract.renewalReminderSentAt!.millisecondsSinceEpoch}';
      await prefs.setString(key, DateTime.now().toIso8601String());
      debugPrint('✅ [ContractReminderPopup] Marked popup as shown for contract: ${widget.contract.contractNumber}');
    } catch (e) {
      debugPrint('⚠️ [ContractReminderPopup] Error marking popup as shown: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('dd/MM/yyyy');
    final isFinalReminder = widget.contract.isFinalReminder == true;

    // Colors based on theme
    final backgroundColor = isDark
        ? AppColors.navySurfaceElevated
        : AppColors.neutralSurface;
    final textPrimary = isDark
        ? Colors.white
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? Colors.white70
        : AppColors.textSecondary;
    
    // Warning colors (adapt to theme)
    final warningColor = isFinalReminder
        ? (isDark ? Colors.red[300] : Colors.red[600])
        : (isDark ? Colors.orange[300] : Colors.orange[600]);
    final warningBackground = isFinalReminder
        ? (isDark ? Colors.red.withValues(alpha: 0.15) : Colors.red[50])
        : (isDark ? Colors.orange.withValues(alpha: 0.15) : Colors.orange[50]);
    final warningBorder = isFinalReminder
        ? (isDark ? Colors.red.withValues(alpha: 0.3) : Colors.red[200]!)
        : (isDark ? Colors.orange.withValues(alpha: 0.3) : Colors.orange[200]!);
    final warningText = isFinalReminder
        ? (isDark ? Colors.red[200] : Colors.red[900])
        : (isDark ? Colors.orange[200] : Colors.orange[900]);

    return PopScope(
      canPop: !isFinalReminder,
      onPopInvoked: (didPop) {
        if (!didPop && isFinalReminder) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Bạn BẮT BUỘC phải chọn gia hạn hoặc hủy hợp đồng'),
              backgroundColor: warningColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        } else if (didPop) {
          widget.onDismiss?.call();
        }
      },
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 0,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : AppColors.elevatedShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with icon and title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: warningBackground,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                CupertinoIcons.bell_solid,
                                color: warningColor,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                isFinalReminder
                                    ? 'Thông báo cuối cùng'
                                    : widget.contract.reminderCount == 2
                                        ? 'Nhắc nhở gia hạn hợp đồng (Lần 2)'
                                        : 'Nhắc nhở gia hạn hợp đồng',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textPrimary,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        // Content card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: warningBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: warningBorder,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hợp đồng: ${widget.contract.contractNumber}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textPrimary,
                                ),
                              ),
                              if (widget.contract.endDate != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Ngày hết hạn: ${dateFormat.format(widget.contract.endDate!)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textSecondary,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Text(
                                isFinalReminder
                                    ? 'Hợp đồng của bạn sắp hết hạn. Bạn BẮT BUỘC phải gia hạn hoặc hủy hợp đồng ngay hôm nay.'
                                    : widget.contract.reminderCount == 2
                                        ? 'Hợp đồng của bạn sắp hết hạn. Vui lòng gia hạn hoặc hủy hợp đồng ngay.'
                                        : 'Hợp đồng của bạn sắp hết hạn trong vòng 1 tháng. Vui lòng gia hạn hoặc hủy hợp đồng.',
                                style: TextStyle(
                                  color: warningText,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Buttons
                        if (isFinalReminder)
                          // Final reminder: Only 2 buttons
                          Row(
                            children: [
                              Expanded(
                                child: _buildCancelButton(
                                  context,
                                  theme,
                                  isDark,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: _buildRenewButton(
                                  context,
                                  theme,
                                  isDark,
                                ),
                              ),
                            ],
                          )
                        else
                          // Normal reminder: 3 buttons
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDismissButton(
                                      context,
                                      theme,
                                      isDark,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildCancelButton(
                                      context,
                                      theme,
                                      isDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: _buildRenewButton(
                                  context,
                                  theme,
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDismissButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return OutlinedButton(
      onPressed: () => _dismissDialog().then((_) => widget.onDismiss?.call()),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(
          color: isDark
              ? theme.colorScheme.outline
              : AppColors.neutralOutline,
          width: 1.5,
        ),
      ),
      child: Text(
        'Đóng',
        style: TextStyle(
          color: isDark
              ? theme.colorScheme.onSurface
              : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildCancelButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return OutlinedButton(
      onPressed: () => _handleCancel(context),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(
          color: isDark ? Colors.red[400]! : Colors.red[600]!,
          width: 1.5,
        ),
      ),
      child: Text(
        'Hủy hợp đồng',
        style: TextStyle(
          color: isDark ? Colors.red[300] : Colors.red[600],
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildRenewButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    return FilledButton(
      onPressed: () => _handleRenew(context),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      child: const Text(
        'Gia hạn hợp đồng',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Future<void> _handleRenew(BuildContext context) async {
    // Mark popup as shown before navigating
    await _markPopupAsShown();
    await _dismissDialog();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContractRenewalScreen(
            contract: widget.contract,
            contractService: widget.contractService,
          ),
        ),
      );
    }
  }

  void _handleCancel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
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
            onPressed: () => Navigator.pop(dialogContext),
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
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Mark popup as shown before canceling
              await _markPopupAsShown();
              await _dismissDialog();
              
              try {
                await widget.contractService.cancelContract(widget.contract.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Đã hủy hợp đồng thành công'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
                widget.onDismiss?.call();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi khi hủy hợp đồng: $e'),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }
              }
            },
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
  }
}
