import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import 'maintenance_request_service.dart';

class RepairRequestScreen extends StatefulWidget {
  const RepairRequestScreen({super.key});

  @override
  State<RepairRequestScreen> createState() => _RepairRequestScreenState();
}

class _AttachmentFile {
  _AttachmentFile({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.isVideo,
  });

  final List<int> bytes;
  final String mimeType;
  final String fileName;
  final bool isVideo;
}

class _RepairRequestScreenState extends State<RepairRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ApiClient _apiClient;
  late final MaintenanceRequestService _service;
  late final ProfileService _profileService;
  late final ContractService _contractService;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategory;
  DateTime? _preferredDate;
  TimeOfDay? _preferredTime;
  String? _preferredDateError;
  String? _preferredTimeError;

  final List<_AttachmentFile> _attachments = [];
  bool _loadingProfile = true;
  bool _loadingUnit = true;
  bool _submitting = false;
  UnitInfo? _selectedUnit;

  static const _selectedUnitPrefsKey = 'selected_unit_id';
  static const _maxAttachments = 5;
  // TEST MODE: Extended working hours for testing (6:00 AM - 23:30 PM)
  static const TimeOfDay _workingStart = TimeOfDay(hour: 6, minute: 0);
  static const TimeOfDay _workingEnd = TimeOfDay(hour: 23, minute: 30);

  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy');

  static const _categories = [
    'Điện',
    'Nước',
    'Máy lạnh',
    'Nội thất',
    'Khác',
  ];

  bool get _isLoading => _loadingProfile || _loadingUnit;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = MaintenanceRequestService(_apiClient);
    _profileService = ProfileService(_apiClient.dio);
    _contractService = ContractService(_apiClient);
    _loadUnitContext();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      if (!mounted) return;
      _contactNameController.text = profile['fullName']?.toString() ?? '';
      _contactPhoneController.text = profile['phoneNumber']?.toString() ?? '';
    } catch (_) {
      // allow manual overrides if needed
    } finally {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
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
        for (final candidate in units) {
          if (candidate.id == selectedUnitId) {
            unit = candidate;
            break;
          }
        }
      }
      unit ??= units.isNotEmpty ? units.first : null;

      if (unit != null) {
        _locationController.text = unit.displayName;
      }

      if (mounted) {
        setState(() => _selectedUnit = unit);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Không thể tải thông tin căn hộ. Vui lòng thử lại.', color: Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingUnit = false);
      }
    }
  }

  Future<void> _pickMedia({required bool isVideo, required ImageSource source}) async {
    if (_attachments.length >= _maxAttachments) {
      _showMessage('Chỉ được chọn tối đa $_maxAttachments tệp.', color: Colors.orange);
      return;
    }

    final picker = ImagePicker();
    final pickedFile = isVideo
        ? await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 2))
        : await picker.pickImage(source: source, imageQuality: 85);

    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    final mime = _detectMimeType(pickedFile.path, isVideo: isVideo);
    setState(() {
      _attachments.add(
        _AttachmentFile(
          bytes: bytes,
          mimeType: mime,
          fileName: pickedFile.name,
          isVideo: isVideo,
        ),
      );
    });
  }

  String _detectMimeType(String path, {required bool isVideo}) {
    final ext = path.split('.').last.toLowerCase();
    if (isVideo) {
      switch (ext) {
        case 'mp4':
        case 'm4v':
          return 'video/mp4';
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        default:
          return 'video/mp4';
      }
    }
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  void _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null) return;
    setState(() {
      _preferredDate = date;
      _preferredDateError = null;
      _preferredTimeError = _preferredTime == null
          ? 'Vui lòng chọn khung giờ xử lý'
          : _validatePreferredDateTime(_preferredDate, _preferredTime);
    });
  }

  void _pickTime() async {
    final initial = _preferredTime ?? const TimeOfDay(hour: 9, minute: 0);
    final time = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (time == null) return;
    setState(() {
      _preferredTime = time;
      _preferredTimeError = _validatePreferredDateTime(_preferredDate, time);
    });
    if (_preferredTimeError != null) {
      _showMessage(_preferredTimeError!, color: Colors.orange);
    }
  }

  String? _validatePreferredDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null) return 'Vui lòng chọn ngày xử lý';
    if (time == null) return 'Vui lòng chọn khung giờ xử lý';

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final now = DateTime.now();
    if (combined.isBefore(now)) {
      return 'Thời gian mong muốn không thể trước hiện tại';
    }
    if (!_isWithinWorkingHours(time)) {
      return 'Chỉ tiếp nhận từ ${_formatTimeOfDay(_workingStart)} đến ${_formatTimeOfDay(_workingEnd)}';
    }
    return null;
  }

  bool _isWithinWorkingHours(TimeOfDay time) {
    final minutes = time.hour * 60 + time.minute;
    return minutes >= _toMinutes(_workingStart) && minutes <= _toMinutes(_workingEnd);
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final scheduleError = _validatePreferredDateTime(_preferredDate, _preferredTime);
    setState(() {
      _preferredDateError = _preferredDate == null ? 'Vui lòng chọn ngày xử lý' : null;
      _preferredTimeError = scheduleError;
    });
    if (scheduleError != null) return;

    if (_selectedUnit == null) {
      _showMessage('Không tìm thấy thông tin căn hộ. Vui lòng thử lại.', color: Colors.red);
      return;
    }

    if (_submitting) return;
    final attachments = _attachments
        .map((file) => 'data:${file.mimeType};base64,${base64Encode(file.bytes)}')
        .toList();

    setState(() => _submitting = true);
    try {
      await _service.createRequest(
        unitId: _selectedUnit!.id,
        category: _selectedCategory!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        preferredDateTime: DateTime(
          _preferredDate!.year,
          _preferredDate!.month,
          _preferredDate!.day,
          _preferredTime!.hour,
          _preferredTime!.minute,
        ),
        attachments: attachments,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      );
      if (!mounted) return;
      _showMessage('Yêu cầu sửa chữa đã được gửi. Vui lòng chờ BQL liên hệ.', color: Colors.green);
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString().replaceFirst('Exception: ', ''), color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo yêu cầu sửa chữa'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUnitSection(theme),
                    _buildIssueDetailsSection(),
                    _buildScheduleSection(),
                    _buildContactSection(),
                    _buildAttachmentsSection(theme),
                    _buildNoteSection(),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: FilledButton.icon(
          onPressed: (_submitting || _isLoading) ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.handyman_outlined),
          label: const Text('Gửi yêu cầu sửa chữa'),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? subtitle,
    required Widget child,
    String? errorText,
  }) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surface.withValues(alpha: 
      theme.brightness == Brightness.dark ? 0.75 : 0.98,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.4 : 0.08),
            offset: const Offset(0, 14),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
          if (errorText != null) ...[
            const SizedBox(height: 12),
            Text(
              errorText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitSection(ThemeData theme) {
    final unit = _selectedUnit;
    return _buildSection(
      title: 'Căn hộ yêu cầu',
      subtitle: 'Tự đồng điền theo căn hộ bạn đang quản lý',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.apartment_outlined, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: unit == null
                    ? const Text('Không tìm thấy căn hộ phù hợp')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(unit.displayName, style: theme.textTheme.titleMedium),
                          if ((unit.buildingName ?? '').isNotEmpty)
                            Text(
                              unit.buildingName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Địa điểm sửa chữa',
              hintText: 'Hệ thống tự động điền theo căn hộ',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.lock_outline, size: 18),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Không xác định được địa điểm sửa chữa';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIssueDetailsSection() {
    return _buildSection(
      title: 'Thông tin sự cố',
      subtitle: 'Giúp ban quản lý hiểu vấn đề cụ thể',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Loại yêu cầu',
              border: OutlineInputBorder(),
            ),
            initialValue: _selectedCategory,
            items: _categories
                .map((category) => DropdownMenuItem(value: category, child: Text(category)))
                .toList(),
            onChanged: (value) => setState(() => _selectedCategory = value),
            validator: (value) => value == null || value.isEmpty ? 'Vui lòng chọn loại yêu cầu' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề yêu cầu',
              border: OutlineInputBorder(),
            ),
            maxLength: 200,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng nhập tiêu đề';
              }
              if (value.trim().length < 5) {
                return 'Tiêu đề cần tối thiểu 5 ký tự';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Mô tả chi tiết',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Vui lòng mô tả chi tiết vấn đề';
              }
              if (value.trim().length < 10) {
                return 'Mô tả cần tối thiểu 10 ký tự';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    final dateText =
        _preferredDate == null ? 'Chưa chọn' : _dateFormatter.format(_preferredDate!);
    final timeText = _preferredTime == null ? 'Chưa chọn' : _preferredTime!.format(context);

    return _buildSection(
      title: 'Thời gian mong muốn',
      subtitle: 'Khung giờ hỗ trợ 06:00 - 23:30 hằng ngày',
      errorText: _preferredTimeError,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ngày xử lý', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(dateText, style: Theme.of(context).textTheme.titleMedium),
                    if (_preferredDateError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _preferredDateError!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickDate,
                child: const Text('Chọn ngày'),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Khung giờ xử lý', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text(timeText, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
              TextButton(
                onPressed: _pickTime,
                child: const Text('Chọn giờ'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return _buildSection(
      title: 'Thông tin liên hệ',
      subtitle: 'Hệ thống tự động điền theo hồ sơ, bạn có thể chỉnh sửa nếu cần',
      child: Column(
        children: [
          TextFormField(
            controller: _contactNameController,
            decoration: const InputDecoration(
              labelText: 'Người liên hệ',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Không tìm thấy tên người liên hệ'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _contactPhoneController,
            decoration: const InputDecoration(
              labelText: 'Số điện thoại',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Không tìm thấy số điện thoại';
              }
              if (!RegExp(r'^0\d{9}$').hasMatch(value.trim())) {
                return 'Số điện thoại phải gồm 10 chữ số và bắt đầu bằng 0';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(ThemeData theme) {
    return _buildSection(
      title: 'Hình ảnh / Video minh họa',
      subtitle: 'Tùy chọn – tối đa $_maxAttachments tệp (ảnh hoặc video)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildAttachmentAction(
                icon: Icons.photo_camera_outlined,
                label: 'Chụp ảnh',
                onTap: () => _pickMedia(isVideo: false, source: ImageSource.camera),
              ),
              _buildAttachmentAction(
                icon: Icons.photo_library_outlined,
                label: 'Chọn ảnh',
                onTap: () => _pickMedia(isVideo: false, source: ImageSource.gallery),
              ),
              _buildAttachmentAction(
                icon: Icons.videocam_outlined,
                label: 'Quay video',
                onTap: () => _pickMedia(isVideo: true, source: ImageSource.camera),
              ),
              _buildAttachmentAction(
                icon: Icons.video_library_outlined,
                label: 'Chọn video',
                onTap: () => _pickMedia(isVideo: true, source: ImageSource.gallery),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_attachments.isEmpty)
            Text(
              'Chưa có tệp đính kèm',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(
                _attachments.length,
                (index) => _buildAttachmentPreview(index, theme),
              ),
            ),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Đã chọn ${_attachments.length}/$_maxAttachments tệp',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildAttachmentPreview(int index, ThemeData theme) {
    final attachment = _attachments[index];
    return Stack(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            image: attachment.isVideo
                ? null
                : DecorationImage(
                    image: MemoryImage(Uint8List.fromList(attachment.bytes)),
                    fit: BoxFit.cover,
                  ),
          ),
          child: attachment.isVideo
              ? Center(
                  child: Icon(
                    Icons.videocam_outlined,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                )
              : null,
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeAttachment(index),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoteSection() {
    return _buildSection(
      title: 'Ghi chú bổ sung',
      subtitle: 'Nhập hướng dẫn cho kỹ thuật viên (tùy chọn)',
      child: TextFormField(
        controller: _noteController,
        maxLines: 4,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Ví dụ: Liên hệ trước 15 phút, có thú cưng trong nhà...',
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
