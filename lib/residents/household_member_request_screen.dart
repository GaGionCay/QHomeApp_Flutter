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
    required this.unit,
  });

  final UnitInfo unit;

  @override
  State<HouseholdMemberRequestScreen> createState() =>
      _HouseholdMemberRequestScreenState();
}

class _HouseholdMemberRequestScreenState
    extends State<HouseholdMemberRequestScreen> {
  late final HouseholdMemberRequestService _service;
  final _formKey = GlobalKey<FormState>();
  final _fullNameFieldKey = GlobalKey<FormFieldState<String>>();
  final _relationFieldKey = GlobalKey<FormFieldState<String>>();
  final _phoneFieldKey = GlobalKey<FormFieldState<String>>();
  final _emailFieldKey = GlobalKey<FormFieldState<String>>();
  final _nationalIdFieldKey = GlobalKey<FormFieldState<String>>();

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _relationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  final _fullNameFocus = FocusNode();
  final _relationFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _nationalIdFocus = FocusNode();

  DateTime? _dob;
  Household? _currentHousehold;
  bool _loadingHousehold = false;
  String? _householdError;

  // Tối đa 2 ảnh minh chứng
  final List<Uint8List> _proofImages = [];
  final List<String> _proofImageMimeTypes = [];

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
    _loadHousehold(widget.unit.id);
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nationalIdCtrl.dispose();
    _relationCtrl.dispose();
    _noteCtrl.dispose();
    _fullNameFocus.dispose();
    _relationFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _nationalIdFocus.dispose();
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
    if (_proofImages.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ được chọn tối đa 2 ảnh minh chứng.')),
      );
      return;
    }
    setState(() {
      _proofImages.add(bytes);
      _proofImageMimeTypes.add(_inferMimeType(picked.path));
    });
  }

  Future<void> _capturePhoto() async {
    final picked =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (_proofImages.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ được chụp tối đa 2 ảnh minh chứng.')),
      );
      return;
    }
    setState(() {
      _proofImages.add(bytes);
      _proofImageMimeTypes.add(_inferMimeType(picked.path));
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
    // Không quá 100 tuổi
    final hundredYearsAgo = DateTime(now.year - 100, now.month, now.day);
    if (result.isBefore(hundredYearsAgo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ngày sinh không được quá 100 tuổi.')),
      );
      return;
    }
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
              'Không xác định được hộ gia đình. Vui lòng kiểm tra lại căn hộ trong phần Cài đặt.'),
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
      // Backend hiện nhận một ảnh: gửi ảnh đầu tiên nếu có
      final proofImageDataUri = _proofImages.isNotEmpty
          ? 'data:${_proofImageMimeTypes.first};base64,${base64Encode(_proofImages.first)}'
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
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isNotEmpty
                ? 'Không thể gửi yêu cầu: $message'
                : 'Không thể gửi yêu cầu. Vui lòng thử lại.',
          ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng ký thành viên hộ gia đình'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSelectedUnitBanner(context),
                const SizedBox(height: 16),
                _buildHouseholdInfo(),
                const SizedBox(height: 24),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      _fullNameFieldKey.currentState?.validate();
                    }
                  },
                  child: TextFormField(
                    key: _fullNameFieldKey,
                    focusNode: _fullNameFocus,
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
                      final v = value.trim();
                      if (v.length > 100) {
                        return 'Họ và tên không được quá 100 ký tự.';
                      }
                      // Cho phép chữ cái tiếng Việt, khoảng trắng đơn, dấu gạch nối
                      final nameRegex = RegExp(r"^[A-Za-zÀ-ỹà-ỹĐđ\s\-]+$");
                      if (!nameRegex.hasMatch(v)) {
                        return 'Họ và tên không được chứa ký tự đặc biệt hoặc số.';
                      }
                      // Không được sử dụng khoảng trắng quá 2 lần trong chuỗi
                      final spaceCount = ' '.allMatches(v).length;
                      if (spaceCount > 2) {
                        return 'Họ và tên không được dùng quá 2 khoảng trắng.';
                      }
                      // Không cho phép khoảng trắng lặp (nhiều dấu cách liền nhau)
                      if (RegExp(r'\s{2,}').hasMatch(v)) {
                        return 'Không dùng nhiều dấu cách liên tiếp.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      _relationFieldKey.currentState?.validate();
                    }
                  },
                  child: TextFormField(
                    key: _relationFieldKey,
                    focusNode: _relationFocus,
                    controller: _relationCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Quan hệ với chủ hộ',
                      hintText: 'Ví dụ: Con, Vợ/Chồng, Anh/Chị/Em',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng cho biết quan hệ với chủ hộ.';
                      }
                      return null;
                    },
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Chọn quan hệ bằng các tùy chọn phía dưới.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
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
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      _phoneFieldKey.currentState?.validate();
                    }
                  },
                  child: TextFormField(
                    key: _phoneFieldKey,
                    focusNode: _phoneFocus,
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: 'Nhập số điện thoại liên hệ',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập số điện thoại.';
                      }
                      final v = value.trim();
                      // Chỉ cho phép số, không khoảng trắng, không ký tự đặc biệt
                      if (!RegExp(r'^[0-9]+$').hasMatch(v)) {
                        return 'Số điện thoại chỉ gồm chữ số, không có khoảng trắng/ký tự đặc biệt.';
                      }
                      if (v.length > 10) {
                        return 'Số điện thoại không được quá 10 số.';
                      }
                      if (v.length < 9) {
                        return 'Số điện thoại tối thiểu 9 số.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      _emailFieldKey.currentState?.validate();
                    }
                  },
                  child: TextFormField(
                    key: _emailFieldKey,
                    focusNode: _emailFocus,
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Nhập email liên hệ',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Vui lòng nhập email.';
                      }
                      final v = value.trim();
                      if (v.length > 100) {
                        return 'Email không được quá 100 ký tự.';
                      }
                      final emailRegex = RegExp(
                          r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
                      if (!emailRegex.hasMatch(v)) {
                        return 'Email không hợp lệ.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) {
                      _nationalIdFieldKey.currentState?.validate();
                    }
                  },
                  child: TextFormField(
                    key: _nationalIdFieldKey,
                    focusNode: _nationalIdFocus,
                    controller: _nationalIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CMND/CCCD (nếu có)',
                    ),
                    validator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return null;
                      if (!RegExp(r'^[0-9]+$').hasMatch(v)) {
                        return 'CMND/CCCD chỉ gồm chữ số, không có khoảng trắng/ký tự đặc biệt.';
                      }
                      if (!(v.length == 9 || v.length == 12)) {
                        return 'CMND 9 số hoặc CCCD 12 số.';
                      }
                      return null;
                    },
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
                        onPressed:
                            _proofImages.length >= 2 ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Chọn ảnh'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _proofImages.length >= 2 ? null : _capturePhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Chụp ảnh'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_proofImages.isNotEmpty)
                  Column(
                    children: List.generate(_proofImages.length, (index) {
                      final bytes = _proofImages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                bytes,
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
                                  _proofImages.removeAt(index);
                                  _proofImageMimeTypes.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
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

  Widget _buildSelectedUnitBanner(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.unit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(
          theme.brightness == Brightness.dark ? 0.3 : 0.6,
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
                  'Căn hộ đang thao tác',
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
