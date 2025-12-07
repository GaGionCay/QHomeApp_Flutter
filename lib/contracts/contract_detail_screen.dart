import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../auth/api_client.dart';
import '../models/contract.dart';
import '../theme/app_colors.dart';
import 'contract_service.dart';

class ContractDetailScreen extends StatefulWidget {
  final String contractId;

  const ContractDetailScreen({
    super.key,
    required this.contractId,
  });

  @override
  State<ContractDetailScreen> createState() => _ContractDetailScreenState();
}

class _ContractDetailScreenState extends State<ContractDetailScreen> {
  ContractService? _contractService;
  ContractDto? _contract;
  bool _loading = true;
  String? _error;
  final Map<String, bool> _downloadingFiles = {}; // fileId -> isDownloading
  final Map<String, int> _downloadProgress = {}; // fileId -> progress percentage
  bool _downloadingAll = false; // Flag for downloading all files

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final apiClient = await ApiClient.create();
      _contractService = ContractService(apiClient);
      await _loadContractDetail();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể khởi tạo dịch vụ: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadContractDetail() async {
    final service = _contractService;
    if (service == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final contract = await service.getContractById(widget.contractId);
      if (!mounted) return;
      setState(() {
        _contract = contract;
        _loading = false;
        if (contract == null) {
          _error = 'Không tìm thấy hợp đồng';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi tải chi tiết hợp đồng: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Không xác định';
    return DateFormat('dd/MM/yyyy').format(date.toLocal());
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'Không xác định';
    return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  String _formatCurrency(double? value) {
    if (value == null) return '-';
    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    return formatter.format(value);
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return const Color(0xFF34C759);
      case 'INACTIVE':
        return const Color(0xFF5AC8FA);
      case 'CANCELLED':
      case 'TERMINATED':
        return const Color(0xFFFF3B30);
      case 'EXPIRED':
        return const Color(0xFFFF9500);
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return CupertinoIcons.check_mark_circled_solid;
      case 'INACTIVE':
        return CupertinoIcons.pause_circle_fill;
      case 'CANCELLED':
      case 'TERMINATED':
        return CupertinoIcons.xmark_circle_fill;
      case 'EXPIRED':
        return CupertinoIcons.time_solid;
      default:
        return CupertinoIcons.info_circle_fill;
    }
  }

  String _getStatusText(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return 'Đang hoạt động';
      case 'INACTIVE':
        return 'Không hoạt động';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'TERMINATED':
        return 'Đã chấm dứt';
      case 'EXPIRED':
        return 'Đã hết hạn';
      default:
        return status;
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

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
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: backgroundGradient),
        ),
        title: const Text('Chi tiết hợp đồng'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (_contract != null && _contract!.files.isNotEmpty)
            IconButton(
              onPressed: _downloadingAll ? null : _downloadAllFiles,
              icon: _downloadingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.arrow_down_circle),
              tooltip: 'Tải tất cả tài liệu',
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          top: true,
          bottom: false,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                )
              : _error != null
                  ? _buildErrorState(theme)
                  : _contract == null
                      ? _buildNotFoundState(theme)
                      : _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: _DetailGlassCard(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 56,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Lỗi',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'Không thể tải chi tiết hợp đồng',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadContractDetail,
                icon: const Icon(CupertinoIcons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotFoundState(ThemeData theme) {
    return Center(
      child: _DetailGlassCard(
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
                'Không tìm thấy hợp đồng',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hợp đồng này không tồn tại hoặc đã bị xóa.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final contract = _contract!;
    final statusColor = _getStatusColor(contract.status);
    final statusIcon = _getStatusIcon(contract.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          _DetailGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 56,
                        width: 56,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient(),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          CupertinoIcons.doc_text_fill,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              contract.contractNumber,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Loại: ${_getContractTypeText(contract.contractType)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
                          color: statusColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 16, color: statusColor),
                            const SizedBox(width: 6),
                            Text(
                              _getStatusText(contract.status),
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
                  // Download button row
                  if (contract.files.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _downloadingAll ? null : _downloadAllFiles,
                            icon: _downloadingAll
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(CupertinoIcons.arrow_down_circle, size: 20),
                            label: Text(_downloadingAll ? 'Đang tải...' : 'Tải tất cả tài liệu'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.info_circle,
                            size: 20,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Hợp đồng này không có tài liệu đính kèm',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Contract Information
          _DetailGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thông tin hợp đồng',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildInfoRow(
                    theme,
                    'Ngày bắt đầu',
                    _formatDate(contract.startDate),
                    CupertinoIcons.calendar,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    theme,
                    'Ngày kết thúc',
                    _formatDate(contract.endDate),
                    CupertinoIcons.calendar_badge_minus,
                  ),
                  if (contract.monthlyRent != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      theme,
                      'Tiền thuê hàng tháng',
                      _formatCurrency(contract.monthlyRent),
                      CupertinoIcons.creditcard,
                    ),
                  ],
                  if (contract.purchasePrice != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      theme,
                      'Giá mua',
                      _formatCurrency(contract.purchasePrice),
                      CupertinoIcons.money_dollar_circle,
                    ),
                  ],
                  if (contract.purchaseDate != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      theme,
                      'Ngày mua',
                      _formatDate(contract.purchaseDate),
                      CupertinoIcons.calendar_today,
                    ),
                  ],
                  if (contract.paymentMethod != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      theme,
                      'Phương thức thanh toán',
                      contract.paymentMethod!,
                      CupertinoIcons.creditcard_fill,
                    ),
                  ],
                  if (contract.paymentTerms != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      theme,
                      'Điều khoản thanh toán',
                      contract.paymentTerms!,
                      CupertinoIcons.doc_text_fill,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Notes
          if (contract.notes != null && contract.notes!.isNotEmpty) ...[
            _DetailGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.doc_plaintext,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ghi chú',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      contract.notes!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Files
          if (contract.files.isNotEmpty) ...[
            _DetailGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.folder_fill,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tài liệu đính kèm',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...contract.files.map((file) => _buildFileItem(theme, file)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Metadata
          _DetailGlassCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Thông tin hệ thống',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (contract.createdAt != null)
                    _buildInfoRow(
                      theme,
                      'Ngày tạo',
                      _formatDateTime(contract.createdAt),
                      CupertinoIcons.time,
                    ),
                  if (contract.updatedAt != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      theme,
                      'Cập nhật lần cuối',
                      _formatDateTime(contract.updatedAt),
                      CupertinoIcons.arrow_clockwise,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileItem(ThemeData theme, ContractFileDto file) {
    final isDownloading = _downloadingFiles[file.id] ?? false;
    final progress = _downloadProgress[file.id] ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface.withValues(alpha: 0.75),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
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
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.doc_plaintext,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.originalFileName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (file.fileSize != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _formatFileSize(file.fileSize!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Download button
                if (isDownloading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress > 0 ? progress / 100 : null,
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(CupertinoIcons.arrow_down_circle),
                    color: theme.colorScheme.primary,
                    onPressed: () => _downloadFile(file),
                    tooltip: 'Tải về máy',
                  ),
                // View button
                IconButton(
                  icon: const Icon(CupertinoIcons.eye),
                  color: theme.colorScheme.primary,
                  onPressed: () => _viewFile(file),
                  tooltip: 'Xem file',
                ),
              ],
            ),
            // Download progress bar
            if (isDownloading && progress > 0) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.3),
                minHeight: 2,
              ),
              const SizedBox(height: 4),
              Text(
                'Đang tải: $progress%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
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
          : uri.pathSegments.last.isNotEmpty 
              ? uri.pathSegments.last 
              : 'contract_file';
      final filePath = '${tempDir.path}/$fileName';
      
      // Download file using Dio with authentication
      if (_contractService == null) return;
      final apiClient = _contractService!.apiClient;
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
    if (_contract == null || _contractService == null) return;
    if (_downloadingFiles[file.id] == true) return; // Already downloading

    setState(() {
      _downloadingFiles[file.id] = true;
      _downloadProgress[file.id] = 0;
    });

    try {
      final filePath = await _contractService!.downloadContractFile(
        _contract!.id,
        file.id,
        file.originalFileName,
        (received, total) {
          if (mounted && total > 0) {
            final progress = ((received / total) * 100).round();
            setState(() {
              _downloadProgress[file.id] = progress;
            });
          }
        },
      );

      if (!mounted) return;

      if (filePath != null) {
        setState(() {
          _downloadingFiles[file.id] = false;
          _downloadProgress[file.id] = 100;
        });

        // Determine file type for better message
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
            content: Text('Đã tải xuống $fileTypeText: ${file.originalFileName}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Mở',
              textColor: Colors.white,
              onPressed: () => _viewFile(file),
            ),
          ),
        );

        // Clear progress after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _downloadProgress.remove(file.id);
            });
          }
        });
      } else {
        setState(() {
          _downloadingFiles[file.id] = false;
          _downloadProgress.remove(file.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải xuống: ${file.originalFileName}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingFiles[file.id] = false;
        _downloadProgress.remove(file.id);
      });

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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadAllFiles() async {
    if (_contract == null || _contractService == null) return;
    if (_contract!.files.isEmpty) return;
    if (_downloadingAll) return;

    setState(() {
      _downloadingAll = true;
    });

    int successCount = 0;
    int failCount = 0;

    try {
      // Download all files sequentially
      for (final file in _contract!.files) {
        // Skip if already downloading
        if (_downloadingFiles[file.id] == true) continue;

        setState(() {
          _downloadingFiles[file.id] = true;
          _downloadProgress[file.id] = 0;
        });

        try {
          final filePath = await _contractService!.downloadContractFile(
            _contract!.id,
            file.id,
            file.originalFileName,
            (received, total) {
              if (mounted && total > 0) {
                final progress = ((received / total) * 100).round();
                setState(() {
                  _downloadProgress[file.id] = progress;
                });
              }
            },
          );

          if (filePath != null) {
            successCount++;
            setState(() {
              _downloadingFiles[file.id] = false;
              _downloadProgress[file.id] = 100;
            });
          } else {
            failCount++;
            setState(() {
              _downloadingFiles[file.id] = false;
              _downloadProgress.remove(file.id);
            });
          }
        } catch (e) {
          failCount++;
          if (mounted) {
            setState(() {
              _downloadingFiles[file.id] = false;
              _downloadProgress.remove(file.id);
            });
          }
        }

        // Small delay between downloads
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!mounted) return;

      setState(() {
        _downloadingAll = false;
      });

      // Show summary
      String message;
      if (successCount > 0 && failCount == 0) {
        message = 'Đã tải xuống thành công $successCount tài liệu';
      } else if (successCount > 0 && failCount > 0) {
        message = 'Đã tải xuống $successCount/${_contract!.files.length} tài liệu ($failCount thất bại)';
      } else {
        message = 'Không thể tải xuống tài liệu';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      // Clear progress after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _downloadProgress.clear();
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingAll = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi tải xuống: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _DetailGlassCard extends StatelessWidget {
  const _DetailGlassCard({required this.child});

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

