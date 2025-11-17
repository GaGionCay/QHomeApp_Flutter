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
    required this.units,
    required this.initialUnitId,
  });

  final List<UnitInfo> units;
  final String initialUnitId;

  @override
  State<AccountRequestStatusScreen> createState() =>
      _AccountRequestStatusScreenState();
}

class _AccountRequestStatusScreenState
    extends State<AccountRequestStatusScreen> {
  late final ResidentAccountService _service;
  List<AccountCreationRequest> _requests = [];
  bool _loading = true;
  String? _selectedUnitFilter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ResidentAccountService(ApiClient());
    _selectedUnitFilter = widget.units.any((u) => u.id == widget.initialUnitId)
        ? widget.initialUnitId
        : (widget.units.isNotEmpty ? widget.units.first.id : null);
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

  Color _statusColor(AccountCreationRequest request) {
    if (request.isApproved) return Colors.green;
    if (request.isRejected) return Colors.red;
    return Colors.orange;
  }

  IconData _statusIcon(AccountCreationRequest request) {
    if (request.isApproved) return Icons.check_circle;
    if (request.isRejected) return Icons.cancel;
    return Icons.hourglass_top;
  }

  List<AccountCreationRequest> get _filteredRequests {
    if (_selectedUnitFilter == null) return _requests;
    return _requests
        .where((request) => request.unitId == _selectedUnitFilter)
        .toList();
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
          if (widget.units.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Căn hộ: ${widget.units.firstWhere(
                        (unit) =>
                            unit.id ==
                            (_selectedUnitFilter ?? widget.units.first.id),
                        orElse: () => widget.units.first,
                      ).displayName}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: primaryText,
                  ),
                ),
              ),
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
                                UnitInfo? matchedUnit;
                                if (request.unitId != null) {
                                  try {
                                    matchedUnit = widget.units.firstWhere(
                                        (unit) => unit.id == request.unitId);
                                  } catch (_) {
                                    matchedUnit = null;
                                  }
                                }
                                final unitLabel = request.unitCode ??
                                    matchedUnit?.displayName ??
                                    'Căn hộ';
                                final cardBackground =
                                    theme.brightness == Brightness.dark
                                        ? Colors.white.withOpacity(0.05)
                                        : Colors.white;
                                final cardBorderColor =
                                    theme.brightness == Brightness.dark
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.black.withOpacity(0.05);

                                return Container(
                                  decoration: BoxDecoration(
                                    color: cardBackground,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: cardBorderColor),
                                    boxShadow: [
                                      if (theme.brightness == Brightness.light)
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                    ],
                                  ),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor:
                                                _statusColor(request)
                                                    .withOpacity(0.18),
                                            child: Icon(
                                              _statusIcon(request),
                                              color: _statusColor(request),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  request.residentName ??
                                                      'Thành viên',
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: primaryText,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  unitLabel,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: secondaryText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              request.statusLabel,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            backgroundColor:
                                                _statusColor(request),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if ((request.relation ?? '').isNotEmpty)
                                        Text(
                                          'Quan hệ: ${request.relation}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if ((request.residentPhone ?? '')
                                          .isNotEmpty)
                                        Text(
                                          'Điện thoại: ${request.residentPhone}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if ((request.residentEmail ?? '')
                                          .isNotEmpty)
                                        Text(
                                          'Email: ${request.residentEmail}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Gửi lúc: ${request.formattedCreatedAt}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: secondaryText,
                                        ),
                                      ),
                                      if (request.isApproved)
                                        Text(
                                          'Duyệt lúc: ${request.formattedApprovedAt}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if (request.isRejected) ...[
                                        Text(
                                          'Từ chối lúc: ${request.formattedRejectedAt}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                        if ((request.rejectionReason ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Lý do: ${request.rejectionReason}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme.error,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                      if (request.hasProofImages) ...[
                                        const SizedBox(height: 12),
                                        Text(
                                          'Ảnh minh chứng:',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: secondaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: request
                                              .proofOfRelationImageUrls
                                              .map(_buildProofImage)
                                              .toList(),
                                        ),
                                      ],
                                      if (request.isApproved &&
                                          (request.username ?? '')
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        const Divider(),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tài khoản:',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: secondaryText,
                                          ),
                                        ),
                                        Text(
                                          'Username: ${request.username}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: primaryText,
                                          ),
                                        ),
                                        if ((request.email ?? '').isNotEmpty)
                                          Text(
                                            'Email: ${request.email}',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: primaryText,
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
