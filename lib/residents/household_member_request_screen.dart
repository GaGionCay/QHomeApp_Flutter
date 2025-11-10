import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../models/household.dart';
import '../models/unit_info.dart';
import 'household_member_request_service.dart';

class HouseholdMemberRequestScreen extends StatefulWidget {
  const HouseholdMemberRequestScreen({
    super.key,
    required this.units,
    required this.initialUnitId,
  });

  final List<UnitInfo> units;
  final String? initialUnitId;

  @override
  State<HouseholdMemberRequestScreen> createState() =>
      _HouseholdMemberRequestScreenState();
}

class _HouseholdMemberRequestScreenState
    extends State<HouseholdMemberRequestScreen> {
  late final HouseholdMemberRequestService _service;
  final _formKey = GlobalKey<FormState>();

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime? _dob;
  Household? _currentHousehold;
  bool _loadingHousehold = false;
  String? _householdError;

  Uint8List? _proofImageBytes;
  String? _proofImageMimeType;

  String? _selectedUnitId;
  bool _submitting = false;

  final _picker = ImagePicker();

  static const _relationSuggestions = [
    'Vợ/Chồng',
    'Con',
    'Bố',
    'Mẹ',
    'Anh/Chị/Em',
    'Ông/Bà',
    'Người thân',
  ];

  @override
  void initState() {
    super.initState();
    _service = HouseholdMemberRequestService(ApiClient());
    if (widget.units.isNotEmpty) {
      final initial = widget.initialUnitId ?? widget.units.first.id;
      _selectedUnitId = initial;
      _loadHousehold(initial);
    }
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nationalIdCtrl.dispose();
    _relationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHousehold(String unitId) async {
    setState(() {
      _loadingHousehold = true;
      _householdError = null;
      _currentHousehold = null;
    });
    try {
      final household = await _service.getCurrentHousehold(unitId);
      if (!mounted) return;
      setState(() {
        _currentHousehold = household;
        if (household == null) {
          _householdError =
              'Không tìm thấy thông tin hộ gia đình cho căn hộ đã chọn.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _householdError = 'Không thể tải thông tin hộ gia đình: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingHousehold = false;
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _proofImageBytes = bytes;
      _proofImageMimeType = _inferMimeType(picked.path);
    });
  }

  Future<void> _capturePhoto() async {
    final picked =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _proofImageBytes = bytes;
      _proofImageMimeType = _inferMimeType(picked.path);
    });
  }

  Future<void> _selectDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 18, now.month, now.day);
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (result == null) return;
    setState(() {
      _dob = result;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_currentHousehold == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Không xác định được hộ gia đình. Vui lòng chọn lại căn hộ.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
    });

    try {
      final proofImageDataUri = _proofImageBytes != null &&
              (_proofImageMimeType ?? '').isNotEmpty
          ? 'data:${_proofImageMimeType!};base64,${base64Encode(_proofImageBytes!)}'
          : null;

      await _service.createRequest(
        householdId: _currentHousehold!.id,
        residentFullName: _fullNameCtrl.text.trim(),
        residentPhone:
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        residentEmail:
            _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        residentNationalId: _nationalIdCtrl.text.trim().isEmpty
            ? null
            : _nationalIdCtrl.text.trim(),
        residentDob: _dob,
        relation: _relationCtrl.text.trim().isEmpty
            ? null
            : _relationCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        proofOfRelationImageUrl: proofImageDataUri,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi yêu cầu đăng ký thành viên thành công.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể gửi yêu cầu: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = widget.units;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng ký thành viên hộ gia đình'),
      ),
      body: units.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Bạn chưa là chủ hộ của căn hộ nào, nên không thể tạo yêu cầu.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedUnitId,
                        decoration: const InputDecoration(
                          labelText: 'Chọn căn hộ',
                        ),
                        items: units
                            .map(
                              (unit) => DropdownMenuItem<String>(
                                value: unit.id,
                                child: Text(unit.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedUnitId = value;
                          });
                          _loadHousehold(value);
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildHouseholdInfo(),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _fullNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Họ và tên thành viên',
                          hintText: 'Nhập họ tên đầy đủ',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập họ tên thành viên.';
                          }
                          if (value.trim().length < 3) {
                            return 'Họ tên phải từ 3 ký tự trở lên.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _relationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Quan hệ với chủ hộ',
                          hintText: 'Ví dụ: Con, Vợ/Chồng, Anh/Chị/Em',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _relationSuggestions
                            .map(
                              (suggestion) => ActionChip(
                                label: Text(suggestion),
                                onPressed: () {
                                  setState(() {
                                    _relationCtrl.text = suggestion;
                                  });
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Số điện thoại',
                          hintText: 'Nhập số điện thoại liên hệ',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email (nếu có)',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final emailRegex =
                              RegExp(r'^[\w\.\-+]+@[\w\.\-]+\.[A-Za-z]{2,}$');
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Email không hợp lệ.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nationalIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'CMND/CCCD (nếu có)',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildDobField(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú cho ban quản lý',
                          hintText:
                              'Ví dụ: Thời gian cư trú, mong muốn thời điểm kích hoạt...',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Ảnh minh chứng quan hệ (tùy chọn)',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickFromGallery,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Chọn ảnh'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _capturePhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Chụp ảnh'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_proofImageBytes != null)
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _proofImageBytes!,
                                height: 160,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Xóa ảnh',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withOpacity(0.6),
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _proofImageBytes = null;
                                  _proofImageMimeType = null;
                                });
                              },
                            ),
                          ],
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            _submitting ? 'Đang gửi...' : 'Gửi yêu cầu đăng ký',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildDobField() {
    final textTheme = Theme.of(context).textTheme;
    final dobText =
        _dob != null ? DateFormat('dd/MM/yyyy').format(_dob!) : 'Chưa chọn';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _selectDob,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Ngày sinh',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined, size: 20),
            const SizedBox(width: 12),
            Text(
              dobText,
              style: textTheme.bodyMedium,
            ),
            const Spacer(),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdInfo() {
    if (_loadingHousehold) {
      return Row(
        children: const [
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Đang tải thông tin hộ gia đình...'),
        ],
      );
    }

    if (_householdError != null) {
      return Text(
        _householdError!,
        style: const TextStyle(color: Colors.redAccent),
      );
    }

    if (_currentHousehold == null) {
      return const Text(
          'Chưa có dữ liệu hộ gia đình cho căn hộ này. Vui lòng liên hệ ban quản lý.');
    }

    final household = _currentHousehold!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  household.displayName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (household.primaryResidentName != null)
            Text('Chủ hộ: ${household.primaryResidentName}'),
          if (household.startDate != null)
            Text(
              'Hiệu lực từ: ${DateFormat('dd/MM/yyyy').format(household.startDate!)}',
            ),
        ],
      ),
    );
  }

  String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
