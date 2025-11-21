import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import '../models/account_creation_request.dart';
import '../models/unit_info.dart';
import 'resident_account_service.dart';

class AccountRequestStatusScreen extends StatefulWidget {
  const AccountRequestStatusScreen({
    super.key,
    required this.unit,
  });

  final UnitInfo unit;

  @override
  State<AccountRequestStatusScreen> createState() =>
      _AccountRequestStatusScreenState();
}

class _AccountRequestStatusScreenState
    extends State<AccountRequestStatusScreen> {
  late final ResidentAccountService _service;
  List<AccountCreationRequest> _requests = [];
  bool _loading = true;
  late final String _unitId;
  String? _error;
  String? _cancellingRequestId;

  @override
  void initState() {
    super.initState();
    _service = ResidentAccountService(ApiClient());
    _unitId = widget.unit.id;
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getMyAccountRequests();
      if (mounted) {
        setState(() {
          _requests = data;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirmCancel(AccountCreationRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hủy yêu cầu?'),
        content:
            const Text('Bạn có chắc chắn muốn hủy yêu cầu tạo tài khoản này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hủy yêu cầu'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _cancelRequest(request);
    }
  }

  Future<void> _cancelRequest(AccountCreationRequest request) async {
    setState(() {
      _cancellingRequestId = request.id;
    });
    try {
      await _service.cancelAccountRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy yêu cầu thành công.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể hủy yêu cầu: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancellingRequestId = null;
        });
      }
    }
  }

  Color _statusColor(AccountCreationRequest request) {
    if (request.isApproved) return Colors.green;
    if (request.isRejected) return Colors.red;
    if (request.isCancelled) return Colors.grey;
    return Colors.orange;
  }

  IconData _statusIcon(AccountCreationRequest request) {
    if (request.isApproved) return Icons.check_circle;
    if (request.isRejected) return Icons.cancel;
    if (request.isCancelled) return Icons.highlight_off;
    return Icons.hourglass_top;
  }

  List<AccountCreationRequest> get _filteredRequests {
    return _requests.where((request) => request.unitId == _unitId).toList();
  }

  Widget _buildProofImage(String data) {
    final uri = data.trim();
    if (uri.isEmpty) return const SizedBox.shrink();

    if (uri.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          uri,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.broken_image_outlined),
          ),
        ),
      );
    }

    final bytes = _decodeBase64Image(uri);
    if (bytes == null) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        width: 80,
        height: 80,
        fit: BoxFit.cover,
      ),
    );
  }

  Uint8List? _decodeBase64Image(String data) {
    try {
      final content = data.contains(',') ? data.split(',').last : data;
      return base64Decode(content);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryText = theme.colorScheme.onSurface;
    final secondaryText = theme.colorScheme.onSurfaceVariant;

    final filtered = _filteredRequests;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi yêu cầu tạo tài khoản'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildUnitHeader(context),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadRequests,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'Không thể tải danh sách yêu cầu.\n$_error',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        )
                      : filtered.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                Text(
                                  'Bạn chưa gửi yêu cầu tạo tài khoản nào.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: secondaryText,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final request = filtered[index];
                                return _buildAccountCard(
                                  theme,
                                  request,
                                  primaryText,
                                  secondaryText,
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitHeader(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.unit;
    final buildingLabel = unit.buildingName ?? unit.buildingCode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 
          theme.brightness == Brightness.dark ? 0.25 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.person_search_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang xem yêu cầu của',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((buildingLabel ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Tòa $buildingLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Muốn đổi căn hộ? Vào Cài đặt > Căn hộ của tôi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(
    ThemeData theme,
    AccountCreationRequest request,
    Color primaryText,
    Color secondaryText,
  ) {
    final isCurrentUnit = request.unitId == _unitId || request.unitId == null;
    final unitLabel = request.unitCode ??
        (isCurrentUnit ? widget.unit.displayName : 'Căn hộ');
    final cardBackground = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;
    final cardBorderColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardBorderColor),
        boxShadow: [
          if (theme.brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _statusColor(request).withValues(alpha: 0.18),
                child: Icon(
                  _statusIcon(request),
                  color: _statusColor(request),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.residentName ?? 'Thành viên',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      unitLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  request.statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: _statusColor(request),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if ((request.relation ?? '').isNotEmpty)
            Text(
              'Quan hệ: ${request.relation}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
              ),
            ),
          if ((request.residentPhone ?? '').isNotEmpty)
            Text(
              'Điện thoại: ${request.residentPhone}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
              ),
            ),
          if ((request.residentEmail ?? '').isNotEmpty)
            Text(
              'Email: ${request.residentEmail}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Gửi lúc: ${request.formattedCreatedAt}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: secondaryText,
            ),
          ),
          if (request.isApproved)
            Text(
              'Duyệt lúc: ${request.formattedApprovedAt}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
          if (request.isRejected) ...[
            Text(
              'Từ chối lúc: ${request.formattedRejectedAt}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
            if ((request.rejectionReason ?? '').isNotEmpty)
              Text(
                'Lý do: ${request.rejectionReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ] else if (request.isCancelled) ...[
            Text(
              'Hủy lúc: ${request.formattedRejectedAt}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
            Text(
              'Bạn đã hủy yêu cầu này.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (request.hasProofImages) ...[
            const SizedBox(height: 12),
            Text(
              'Ảnh minh chứng:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: request.proofOfRelationImageUrls
                  .map(_buildProofImage)
                  .toList(),
            ),
          ],
          if (request.isApproved && (request.username ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Tài khoản:',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: secondaryText,
              ),
            ),
            Text(
              'Username: ${request.username}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: primaryText,
              ),
            ),
            if ((request.email ?? '').isNotEmpty)
              Text(
                'Email: ${request.email}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: primaryText,
                ),
              ),
          ],
          if (request.isPending) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: _cancellingRequestId == request.id
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close),
                label: Text(
                  _cancellingRequestId == request.id
                      ? 'Đang hủy...'
                      : 'Hủy yêu cầu',
                ),
                onPressed: _cancellingRequestId == request.id
                    ? null
                    : () => _confirmCancel(request),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


