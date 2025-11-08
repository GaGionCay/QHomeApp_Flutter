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
  });

  final List<UnitInfo> units;

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
    _selectedUnitFilter =
        widget.units.isEmpty ? null : widget.units.first.id;
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
      final content = data.contains(',')
          ? data.split(',').last
          : data;
      return base64Decode(content);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMultipleUnits = widget.units.length > 1;
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
              child: DropdownButtonFormField<String?>(
                value: hasMultipleUnits ? _selectedUnitFilter : widget.units.first.id,
                decoration: const InputDecoration(
                  labelText: 'Lọc theo căn hộ',
                  border: OutlineInputBorder(),
                ),
                items: [
                  if (hasMultipleUnits)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tất cả căn hộ'),
                    ),
                  ...widget.units.map(
                    (unit) => DropdownMenuItem<String?>(
                      value: unit.id,
                      child: Text(unit.displayName),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedUnitFilter = hasMultipleUnits ? value : widget.units.first.id;
                  });
                },
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
                              children: const [
                                Text(
                                  'Bạn chưa gửi yêu cầu tạo tài khoản nào.',
                                  style: TextStyle(color: Colors.black54),
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
                                return Card(
                                  elevation: 2,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  _statusColor(request)
                                                      .withOpacity(0.1),
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
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    unitLabel,
                                                    style: const TextStyle(
                                                        color: Colors.black54),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Chip(
                                              label: Text(
                                                request.statusLabel,
                                                style: const TextStyle(
                                                    color: Colors.white),
                                              ),
                                              backgroundColor:
                                                  _statusColor(request),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        if ((request.relation ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Quan hệ: ${request.relation}',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                        if ((request.residentPhone ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Điện thoại: ${request.residentPhone}',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                        if ((request.residentEmail ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Email: ${request.residentEmail}',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Gửi lúc: ${request.formattedCreatedAt}',
                                          style: const TextStyle(
                                              color: Colors.black54),
                                        ),
                                        if (request.isApproved)
                                          Text(
                                            'Duyệt lúc: ${request.formattedApprovedAt}',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                        if (request.isRejected) ...[
                                          Text(
                                            'Từ chối lúc: ${request.formattedRejectedAt}',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                          if ((request.rejectionReason ?? '')
                                              .isNotEmpty)
                                            Text(
                                              'Lý do: ${request.rejectionReason}',
                                              style: const TextStyle(
                                                  color: Colors.redAccent),
                                            ),
                                        ],
                                        if (request.hasProofImages) ...[
                                          const SizedBox(height: 12),
                                          Text(
                                            'Ảnh minh chứng:',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
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
                                          const SizedBox(height: 8),
                                          const Divider(),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tài khoản:',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            'Username: ${request.username}',
                                            style: const TextStyle(
                                                color: Colors.black87),
                                          ),
                                          if ((request.email ?? '').isNotEmpty)
                                            Text(
                                              'Email: ${request.email}',
                                              style: const TextStyle(
                                                  color: Colors.black87),
                                            ),
                                        ],
                                      ],
                                    ),
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

