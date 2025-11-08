import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/api_client.dart';
import '../models/contract.dart';
import '../models/unit_info.dart';
import 'contract_service.dart';

class ContractListScreen extends StatefulWidget {
  const ContractListScreen({super.key});

  @override
  State<ContractListScreen> createState() => _ContractListScreenState();
}

class _ContractListScreenState extends State<ContractListScreen> {
  ContractService? _contractService;
  List<UnitInfo> _units = [];
  String? _selectedUnitId;
  List<ContractDto> _contracts = [];
  bool _loadingUnits = true;
  bool _loadingContracts = false;
  String? _error;
  static const _selectedUnitPrefsKey = 'selected_unit_id';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loadingUnits = true;
      _error = null;
    });

    try {
      final apiClient = await ApiClient.create();
      _contractService = ContractService(apiClient);
      await _loadUnits();
    } catch (e) {
      setState(() {
        _error = 'Không thể khởi tạo dịch vụ: $e';
        _loadingUnits = false;
      });
    }
  }

  Future<void> _loadUnits() async {
    final service = _contractService;
    if (service == null) return;

    try {
      final units = await service.getMyUnits();
      final prefs = await SharedPreferences.getInstance();
      final savedUnit = prefs.getString(_selectedUnitPrefsKey);
      String? nextSelected = savedUnit;

      if (nextSelected == null && units.isNotEmpty) {
        nextSelected = units.first.id;
      }

      if (!mounted) return;
      setState(() {
        _units = units;
        _selectedUnitId = nextSelected;
        _loadingUnits = false;
      });

      if (_selectedUnitId != null) {
        await _loadContracts(_selectedUnitId!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Lỗi tải danh sách căn hộ: $e';
        _loadingUnits = false;
      });
    }
  }

  Future<void> _loadContracts(String unitId) async {
    final service = _contractService;
    if (service == null) return;

    setState(() {
      _loadingContracts = true;
    });

    try {
      final data = await service.getContractsByUnit(unitId);
      if (!mounted) return;
      setState(() {
        _contracts = data;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi tải hợp đồng: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingContracts = false;
      });
    }
  }

  Future<void> _refresh() async {
    final unitId = _selectedUnitId;
    if (unitId != null) {
      await _loadContracts(unitId);
    } else {
      await _loadUnits();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hợp đồng của tôi'),
        backgroundColor: const Color(0xFF26A69A),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingUnits) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _init,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (_units.isEmpty) {
      return const Center(
        child: Text(
          'Bạn chưa được gắn vào căn hộ nào.\nLiên hệ quản lý để được cấp quyền.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    final selectedUnit = _units.firstWhere(
      (unit) => unit.id == _selectedUnitId,
      orElse: () => _units.first,
    );

    return RefreshIndicator(
      color: const Color(0xFF26A69A),
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildUnitSummary(selectedUnit),
          const SizedBox(height: 16),
          if (_loadingContracts)
            const Center(child: CircularProgressIndicator())
          else if (_contracts.isEmpty)
            _buildEmptyContracts()
          else
            ..._contracts.map(_buildContractCard),
        ],
      ),
    );
  }

  Widget _buildUnitSummary(UnitInfo selectedUnit) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Căn hộ đang xem',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              selectedUnit.displayName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Tòa nhà: ${selectedUnit.buildingName ?? selectedUnit.buildingCode ?? '-'}',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (selectedUnit.floor != null)
              Text(
                'Tầng: ${selectedUnit.floor}',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            if (selectedUnit.areaM2 != null)
              Text(
                'Diện tích: ${selectedUnit.areaM2!.toStringAsFixed(1)} m²',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyContracts() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.description_outlined, size: 36, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Chưa có hợp đồng nào cho căn hộ này.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractCard(ContractDto contract) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy');

    String formatDate(DateTime? date) {
      if (date == null) return 'Không xác định';
      return dateFormat.format(date);
    }

    String formatCurrency(double? value) {
      if (value == null) return '-';
      final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
      return formatter.format(value);
    }

    Color statusColor;
    switch (contract.status.toUpperCase()) {
      case 'ACTIVE':
        statusColor = Colors.green;
        break;
      case 'TERMINATED':
        statusColor = Colors.red;
        break;
      case 'EXPIRED':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = theme.colorScheme.primary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contract.contractNumber,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Loại: ${contract.contractType}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    contract.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Bắt đầu: ${formatDate(contract.startDate)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event_busy, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  'Kết thúc: ${formatDate(contract.endDate)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            if (contract.monthlyRent != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Tiền thuê: ${formatCurrency(contract.monthlyRent)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
            if (contract.notes != null && contract.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                contract.notes!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (contract.files.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Tài liệu đính kèm',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: contract.files.map(_buildFileChip).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileChip(ContractFileDto file) {
    final label = file.originalFileName.isNotEmpty
        ? file.originalFileName
        : file.fileName;
    return ActionChip(
      avatar: const Icon(Icons.attach_file, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: () => _openFile(file.fileUrl),
    );
  }

  Future<void> _openFile(String url) async {
    final normalized = _resolveFileUrl(url);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đường dẫn tải không hợp lệ.')),
      );
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở file.')),
      );
    }
  }

  String _resolveFileUrl(String url) {
    if (url.startsWith('http')) return url;
    return 'http://${ApiClient.HOST_IP}:8082$url';
  }
}
