import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../models/household_member_request.dart';
import '../models/unit_info.dart';
import 'household_member_request_service.dart';

class HouseholdMemberRequestStatusScreen extends StatefulWidget {
  const HouseholdMemberRequestStatusScreen({
    super.key,
    required this.unit,
  });

  final UnitInfo unit;

  @override
  State<HouseholdMemberRequestStatusScreen> createState() =>
      _HouseholdMemberRequestStatusScreenState();
}

class _HouseholdMemberRequestStatusScreenState
    extends State<HouseholdMemberRequestStatusScreen> {
  late final HouseholdMemberRequestService _service;
  List<HouseholdMemberRequest> _requests = [];
  bool _loading = true;
  late final String _unitId;
  String? _error;
  String? _cancellingId;

  @override
  void initState() {
    super.initState();
    _service = HouseholdMemberRequestService(ApiClient());
    _unitId = widget.unit.id;
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.getMyRequests();
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

  Future<void> _confirmCancel(HouseholdMemberRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hủy yêu cầu đăng ký?'),
        content: const Text(
            'Bạn có chắc chắn muốn hủy yêu cầu đăng ký thành viên này?'),
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

  Future<void> _cancelRequest(HouseholdMemberRequest request) async {
    setState(() {
      _cancellingId = request.id;
    });
    try {
      await _service.cancelRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy yêu cầu đăng ký thành viên.'),
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
          _cancellingId = null;
        });
      }
    }
  }

  List<HouseholdMemberRequest> get _filteredRequests {
    return _requests.where((request) => request.unitId == _unitId).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryText = theme.colorScheme.onSurface;
    final secondaryText = theme.colorScheme.onSurfaceVariant;
    final filtered = _filteredRequests;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi đăng ký thành viên'),
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
                                  'Bạn chưa gửi yêu cầu đăng ký thành viên nào.',
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
                                return _buildMemberCard(
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.25 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.home_work_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Căn hộ đang theo dõi',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.displayName,
                  style: theme.textTheme.titleMedium,
                ),
                if ((unit.buildingName ?? unit.buildingCode)?.isNotEmpty ??
                    false)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Tòa ${unit.buildingName ?? unit.buildingCode}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Muốn đổi căn hộ? Vào Cài đặt > Căn hộ của tôi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
    ThemeData theme,
    HouseholdMemberRequest request,
    Color primaryText,
    Color secondaryText,
  ) {
    final unitLabel = request.unitCode ?? 'Căn hộ';
    final cardBackground = theme.brightness == Brightness.dark
        ? Colors.white.withOpacity(0.05)
        : Colors.white;
    final cardBorderColor = theme.brightness == Brightness.dark
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
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    _memberStatusColor(request.status).withOpacity(0.18),
                child: Icon(
                  _memberStatusIcon(request.status),
                  color: _memberStatusColor(request.status),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.requestedResidentFullName ?? 'Thành viên',
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
                backgroundColor: _memberStatusColor(request.status),
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
          if ((request.requestedResidentPhone ?? '').isNotEmpty)
            Text(
              'Điện thoại: ${request.requestedResidentPhone}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
              ),
            ),
          if ((request.requestedResidentEmail ?? '').isNotEmpty)
            Text(
              'Email: ${request.requestedResidentEmail}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: secondaryText,
              ),
            ),
          const SizedBox(height: 8),
          if (request.formattedCreatedAt != null)
            Text(
              'Gửi lúc: ${request.formattedCreatedAt}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
          if (request.status == 'APPROVED' && request.approvedAt != null)
            Text(
              'Duyệt lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(request.approvedAt!.toLocal())}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
          if (request.status == 'REJECTED' && request.rejectedAt != null)
            Text(
              'Từ chối lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(request.rejectedAt!.toLocal())}',
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
          if ((request.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Ghi chú: ${request.note}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryText,
              ),
            ),
          ],
          if (request.isPending) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: _cancellingId == request.id
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close),
                label: Text(_cancellingId == request.id
                    ? 'Đang hủy...'
                    : 'Hủy yêu cầu'),
                onPressed: _cancellingId == request.id
                    ? null
                    : () => _confirmCancel(request),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _memberStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      case 'CANCELLED':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _memberStatusIcon(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return Icons.check_circle;
      case 'REJECTED':
        return Icons.cancel;
      case 'CANCELLED':
        return Icons.highlight_off;
      default:
        return Icons.pending_actions;
    }
  }
}
