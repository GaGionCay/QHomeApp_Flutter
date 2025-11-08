import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import 'cleaning_request_service.dart';

class CleaningRequestScreen extends StatefulWidget {
  const CleaningRequestScreen({super.key});

  @override
  State<CleaningRequestScreen> createState() => _CleaningRequestScreenState();
}

class _CleaningRequestScreenState extends State<CleaningRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiClient _apiClient;
  late final CleaningRequestService _service;
  late final ProfileService _profileService;
  late final ContractService _contractService;

  UnitInfo? _selectedUnit;
  bool _loadingUnit = true;
  bool _loadingProfile = true;
  bool _submitting = false;

  final _locationController = TextEditingController();
  final _noteController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _durationController = TextEditingController();

  String? _selectedCleaningType;
  DateTime? _cleaningDate;
  TimeOfDay? _startTime;
  final Set<String> _selectedExtras = {};
  String? _paymentMethod;

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  static const _cleaningTypes = [
    'Dọn dẹp cơ bản',
    'Dọn dẹp tổng thể',
    'Dọn bếp',
    'Dọn phòng khách',
    'Giặt rèm',
    'Khử mùi toàn căn',
    'Vệ sinh thiết bị',
  ];

  static const _extraServices = [
    'Giặt rèm',
    'Lau kính',
    'Khử mùi',
    'Giặt thảm',
    'Khử khuẩn',
  ];

  static const Map<String, double> _defaultDurations = {
    'Dọn dẹp cơ bản': 1,
    'Dọn dẹp tổng thể': 2,
    'Dọn bếp': 1.5,
    'Dọn phòng khách': 1.5,
    'Giặt rèm': 2,
    'Khử mùi toàn căn': 1.5,
    'Vệ sinh thiết bị': 1,
  };

  String _formatDuration(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
  }

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = CleaningRequestService(_apiClient);
    _profileService = ProfileService(_apiClient.dio);
    _contractService = ContractService(_apiClient);
    _loadUnitContext();
    _loadProfile();
  }

  Future<void> _loadUnitContext() async {
    try {
      final units = await _contractService.getMyUnits();
      String? selectedUnitId;
      try {
        final prefs = await SharedPreferences.getInstance();
        selectedUnitId = prefs.getString(_selectedUnitPrefsKey);
      } catch (_) {
        selectedUnitId = null;
      }

      UnitInfo? unit;
      if (selectedUnitId != null) {
        for (final item in units) {
          if (item.id == selectedUnitId) {
            unit = item;
            break;
          }
        }
      }

      unit ??= units.isNotEmpty ? units.first : null;

      if (unit != null && unit.id.isNotEmpty) {
        _locationController.text = unit.displayName;
      }

      if (mounted) {
        setState(() {
          _selectedUnit = unit;
        });
      }
    } catch (e) {
      _showMessage(
        'Không thể tải thông tin căn hộ. Vui lòng thử lại.',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingUnit = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      final phone = profile['phoneNumber']?.toString() ?? '';
      if (mounted) {
        _contactPhoneController.text = phone;
      }
    } catch (_) {
      // allow manual input
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
      }
    }
  }

  Future<void> _pickCleaningDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) {
      setState(() {
        _cleaningDate = picked;
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }

  double? _parseDuration() {
    final type = _selectedCleaningType;
    if (type == null) return null;
    return _defaultDurations[type];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedUnit == null) {
      _showMessage(
        'Không tìm thấy thông tin căn hộ. Vui lòng thử lại.',
        color: Colors.red,
      );
      return;
    }
    if (_cleaningDate == null) {
      _showMessage('Vui lòng chọn ngày dọn dẹp', color: Colors.orange);
      return;
    }
    if (_startTime == null) {
      _showMessage('Vui lòng chọn khung giờ bắt đầu', color: Colors.orange);
      return;
    }
    final duration = _parseDuration();
    if (duration == null || duration <= 0) {
      _showMessage('Thời lượng phải là số lớn hơn 0', color: Colors.orange);
      return;
    }
    if (_submitting) return;

    setState(() {
      _submitting = true;
    });

    final startDuration = Duration(
      hours: _startTime!.hour,
      minutes: _startTime!.minute,
    );

    try {
      await _service.createRequest(
        unitId: _selectedUnit!.id,
        cleaningType: _selectedCleaningType!,
        cleaningDate: _cleaningDate!,
        startTime: startDuration,
        durationHours: duration,
        location: _locationController.text.trim(),
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        extraServices: _selectedExtras.toList(),
        paymentMethod: _paymentMethod,
      );
      if (!mounted) return;
      _showMessage(
        'Yêu cầu dọn dẹp đã được gửi, đang chờ xử lý.',
        color: Colors.green,
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showMessage(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _locationController.dispose();
    _noteController.dispose();
    _contactPhoneController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _loadingUnit || _loadingProfile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo yêu cầu dọn dẹp'),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCleaningTypeField(),
                  const SizedBox(height: 16),
                  _buildDatePicker(),
                  const SizedBox(height: 16),
                  _buildTimePicker(),
                  const SizedBox(height: 16),
                  _buildDurationField(),
                  const SizedBox(height: 16),
                  _buildLocationField(),
                  const SizedBox(height: 16),
                  _buildContactPhoneField(),
                  const SizedBox(height: 16),
                  _buildExtrasSection(),
                  const SizedBox(height: 16),
                  _buildPaymentMethod(),
                  const SizedBox(height: 16),
                  _buildNoteField(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_submitting || isLoading) ? null : _submit,
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Gửi yêu cầu'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.05),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCleaningTypeField() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Loại hình dọn dẹp',
        border: OutlineInputBorder(),
      ),
      value: _selectedCleaningType,
      items: _cleaningTypes
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(type),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedCleaningType = value;
          if (value != null) {
            final duration = _defaultDurations[value] ?? 1;
            _durationController.text = _formatDuration(duration);
          } else {
            _durationController.clear();
          }
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Vui lòng chọn loại hình dọn dẹp';
        }
        return null;
      },
    );
  }

  Widget _buildDatePicker() {
    final text = _cleaningDate == null
        ? 'Chưa chọn'
        : '${_cleaningDate!.day.toString().padLeft(2, '0')}/'
            '${_cleaningDate!.month.toString().padLeft(2, '0')}/'
            '${_cleaningDate!.year}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Ngày dọn dẹp',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(text),
      trailing: ElevatedButton(
        onPressed: _pickCleaningDate,
        child: const Text('Chọn ngày'),
      ),
    );
  }

  Widget _buildTimePicker() {
    final text = _startTime == null
        ? 'Chưa chọn'
        : '${_startTime!.hour.toString().padLeft(2, '0')}:'
            '${_startTime!.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Khung giờ bắt đầu',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(text),
      trailing: ElevatedButton(
        onPressed: _pickStartTime,
        child: const Text('Chọn giờ'),
      ),
    );
  }

  Widget _buildDurationField() {
    return TextFormField(
      controller: _durationController,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Thời lượng ước tính (giờ)',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        final parsed = _parseDuration();
        if (parsed == null || parsed <= 0) {
          return 'Vui lòng nhập thời lượng hợp lệ';
        }
        return null;
      },
    );
  }

  Widget _buildLocationField() {
    return TextFormField(
      controller: _locationController,
      decoration: const InputDecoration(
        labelText: 'Địa điểm thực hiện',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vui lòng nhập địa điểm';
        }
        return null;
      },
    );
  }

  Widget _buildContactPhoneField() {
    return TextFormField(
      controller: _contactPhoneController,
      decoration: const InputDecoration(
        labelText: 'Số điện thoại liên hệ',
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.phone,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vui lòng nhập số điện thoại liên hệ';
        }
        return null;
      },
    );
  }

  Widget _buildExtrasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dịch vụ bổ sung (tùy chọn)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _extraServices
              .map(
                (extra) => FilterChip(
                  label: Text(extra),
                  selected: _selectedExtras.contains(extra),
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedExtras.add(extra);
                      } else {
                        _selectedExtras.remove(extra);
                      }
                    });
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPaymentMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phương thức thanh toán (tùy chọn)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        RadioListTile<String?>(
          value: 'PAY_LATER',
          groupValue: _paymentMethod,
          onChanged: (value) {
            setState(() {
              _paymentMethod = value;
            });
          },
          title: const Text('Trả sau'),
        ),
        RadioListTile<String?>(
          value: 'VNPAY',
          groupValue: _paymentMethod,
          onChanged: (value) {
            setState(() {
              _paymentMethod = value;
            });
          },
          title: const Text('Thanh toán VNPAY'),
        ),
        RadioListTile<String?>(
          value: null,
          groupValue: _paymentMethod,
          onChanged: (value) {
            setState(() {
              _paymentMethod = null;
            });
          },
          title: const Text('Chưa chọn'),
        ),
      ],
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Ghi chú / yêu cầu đặc biệt (tùy chọn)',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
    );
  }
}

