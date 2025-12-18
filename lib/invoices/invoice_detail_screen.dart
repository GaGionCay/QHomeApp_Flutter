import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/invoice_line.dart';
import '../theme/app_colors.dart';
import 'invoice_service.dart';

import '../core/safe_state_mixin.dart';
class InvoiceDetailScreen extends StatefulWidget {
  final InvoiceLineResponseDto invoiceLine;
  final InvoiceService invoiceService;

  const InvoiceDetailScreen({
    super.key,
    required this.invoiceLine,
    required this.invoiceService,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> with SafeStateMixin<InvoiceDetailScreen> {
  Map<String, dynamic>? _invoiceDetail;
  List<dynamic>? _allLines;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetail();
  }

  Future<void> _loadInvoiceDetail() async {
    try {
      safeSetState(() {
        _isLoading = true;
        _error = null;
      });

      final invoiceData = await widget.invoiceService.getInvoiceDetailById(widget.invoiceLine.invoiceId);
      if (invoiceData != null) {
        safeSetState(() {
          _invoiceDetail = invoiceData;
          _allLines = invoiceData['lines'] as List<dynamic>?;
          _isLoading = false;
        });
      } else {
        safeSetState(() {
          _error = 'Không tìm thấy chi tiết hóa đơn';
          _isLoading = false;
        });
      }
    } catch (e) {
      safeSetState(() {
        _error = 'Lỗi khi tải chi tiết hóa đơn: $e';
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy', 'vi_VN').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _formatMoney(double amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0)
        .format(amount);
  }

  Color _getServiceColor(String? serviceCode) {
    final code = serviceCode?.toUpperCase() ?? '';
    if (code.contains('ELECTRIC') || code.contains('DIEN')) {
      return Colors.orangeAccent;
    } else if (code.contains('WATER') || code.contains('NUOC')) {
      return AppColors.primaryBlue;
    }
    return AppColors.primaryEmerald;
  }

  IconData _getServiceIcon(String? serviceCode) {
    final code = serviceCode?.toUpperCase() ?? '';
    if (code.contains('ELECTRIC') || code.contains('DIEN')) {
      return Icons.flash_on;
    } else if (code.contains('WATER') || code.contains('NUOC')) {
      return Icons.water_drop;
    }
    return Icons.receipt_long;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết hóa đơn'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadInvoiceDetail,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        colorScheme.surface,
                        colorScheme.surfaceContainerHighest,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Invoice Line Header Card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: _getServiceColor(widget.invoiceLine.serviceCode)
                                              .withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          _getServiceIcon(widget.invoiceLine.serviceCode),
                                          color: _getServiceColor(widget.invoiceLine.serviceCode),
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.invoiceLine.serviceCodeDisplay,
                                              style: theme.textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (_invoiceDetail?['code'] != null)
                                              Text(
                                                _invoiceDetail!['code'].toString(),
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: widget.invoiceLine.isPaid
                                              ? AppColors.success.withValues(alpha: 0.1)
                                              : AppColors.warning.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          widget.invoiceLine.isPaid ? 'Đã thanh toán' : 'Chưa thanh toán',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: widget.invoiceLine.isPaid
                                                ? AppColors.success
                                                : AppColors.warning,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _formatMoney(widget.invoiceLine.lineTotal),
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _getServiceColor(widget.invoiceLine.serviceCode),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Invoice Information
                          Text(
                            'Thông tin hóa đơn',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  if (_invoiceDetail?['code'] != null) ...[
                                    _buildInfoRow(
                                      theme,
                                      'Mã hóa đơn',
                                      _invoiceDetail!['code'].toString(),
                                    ),
                                    const Divider(height: 24),
                                  ],
                                  _buildInfoRow(
                                    theme,
                                    'Ngày dịch vụ',
                                    _formatDate(widget.invoiceLine.serviceDate),
                                  ),
                                  if (_invoiceDetail?['issuedAt'] != null) ...[
                                    const Divider(height: 24),
                                    _buildInfoRow(
                                      theme,
                                      'Ngày phát hành',
                                      _formatDate(_invoiceDetail!['issuedAt']?.toString()),
                                    ),
                                  ],
                                  if (_invoiceDetail?['dueDate'] != null) ...[
                                    const Divider(height: 24),
                                    _buildInfoRow(
                                      theme,
                                      'Hạn thanh toán',
                                      _formatDate(_invoiceDetail!['dueDate']?.toString()),
                                    ),
                                  ],
                                  const Divider(height: 24),
                                  _buildInfoRow(
                                    theme,
                                    'Trạng thái',
                                    widget.invoiceLine.isPaid ? 'Đã thanh toán' : 'Chưa thanh toán',
                                  ),
                                  if (_invoiceDetail?['billToName'] != null) ...[
                                    const Divider(height: 24),
                                    _buildInfoRow(
                                      theme,
                                      'Người nhận',
                                      _invoiceDetail!['billToName'].toString(),
                                    ),
                                  ],
                                  if (_invoiceDetail?['billToContact'] != null) ...[
                                    const Divider(height: 24),
                                    _buildInfoRow(
                                      theme,
                                      'Liên hệ',
                                      _invoiceDetail!['billToContact'].toString(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Current Invoice Line Details
                          Text(
                            'Chi tiết dịch vụ',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.invoiceLine.description,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Số lượng',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      Text(
                                        '${widget.invoiceLine.quantity} ${widget.invoiceLine.unit}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Đơn giá',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      Text(
                                        _formatMoney(widget.invoiceLine.unitPrice),
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.invoiceLine.taxAmount > 0) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Thuế VAT',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                                          ),
                                        ),
                                        Text(
                                          _formatMoney(widget.invoiceLine.taxAmount),
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Thành tiền',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        _formatMoney(widget.invoiceLine.lineTotal),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _getServiceColor(widget.invoiceLine.serviceCode),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Other Lines in Same Invoice
                          if (_allLines != null && _allLines!.isNotEmpty) ...[
                            Builder(
                              builder: (context) {
                                // Filter out current line by comparing description and serviceDate
                                final otherLines = _allLines!.where((line) {
                                  final lineDesc = line['description']?.toString() ?? '';
                                  final lineDate = line['serviceDate']?.toString() ?? '';
                                  // Exclude current line by comparing description and serviceDate
                                  return lineDesc != widget.invoiceLine.description ||
                                      lineDate != widget.invoiceLine.serviceDate;
                                }).toList();
                                
                                if (otherLines.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 24),
                                    Text(
                                      'Các dịch vụ khác trong hóa đơn',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ...otherLines.map((line) {
                                      final lineTotal = (line['lineTotal'] is num) 
                                          ? line['lineTotal'].toDouble() 
                                          : 0.0;
                                      final description = line['description']?.toString() ?? '';
                                      final serviceCode = line['serviceCode']?.toString() ?? '';
                                      
                                      return Card(
                                        elevation: 1,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      description,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      serviceCode,
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                _formatMoney(lineTotal),
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: _getServiceColor(serviceCode),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

