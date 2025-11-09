import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/api_client.dart';
import '../contracts/contract_service.dart';
import '../models/unit_info.dart';
import '../profile/profile_service.dart';
import 'maintenance_request_service.dart';

class RepairRequestScreen extends StatefulWidget {
  const RepairRequestScreen({
    super.key,
  });

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
  late final MaintenanceRequestService _service;
  late final ProfileService _profileService;
  late final ContractService _contractService;
  late final ApiClient _apiClient;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategory;
  DateTime? _preferredDateTime;
  final List<_AttachmentFile> _attachments = [];
  bool _loadingProfile = true;
  bool _loadingUnit = true;
  bool _submitting = false;
  UnitInfo? _selectedUnit;

  static const _selectedUnitPrefsKey = 'selected_unit_id';

  static const _categories = [
    'Điện',
    'Nước',
    'Máy lạnh',
    'Nội thất',
    'Khác',
  ];

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
      final fullName = profile['fullName']?.toString() ?? '';
      final phone = profile['phoneNumber']?.toString() ?? '';
      _contactNameController.text = fullName;
      _contactPhoneController.text = phone;
    } catch (e) {
      // ignore profile errors, allow manual input
    } finally {
      if (mounted) {
        setState(() {
          _loadingProfile = false;
        });
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
      if (mounted) {
        _showMessage(
          'Không thể tải thông tin căn hộ. Vui lòng thử lại.',
          color: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingUnit = false;
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_attachments.length >= 3) {
      _showMessage(
        'Chỉ được chọn tối đa 3 tệp đính kèm',
        color: Colors.orange,
      );
      return;
    }
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    final mimeType = _detectMimeType(pickedFile.path, isVideo: false);
    setState(() {
      _attachments.add(
        _AttachmentFile(
          bytes: bytes,
          mimeType: mimeType,
          fileName: pickedFile.name,
          isVideo: false,
        ),
      );
    });
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_attachments.length >= 3) {
      _showMessage(
        'Chỉ được chọn tối đa 3 tệp đính kèm',
        color: Colors.orange,
      );
      return;
    }
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 2));
    if (pickedFile == null) return;

    final bytes = await pickedFile.readAsBytes();
    final mimeType = _detectMimeType(pickedFile.path, isVideo: true);
    setState(() {
      _attachments.add(
        _AttachmentFile(
          bytes: bytes,
          mimeType: mimeType,
          fileName: pickedFile.name,
          isVideo: true,
        ),
      );
    });
  }

  String _detectMimeType(String path, {required bool isVideo}) {
    final extension = path.split('.').last.toLowerCase();
    if (isVideo) {
      switch (extension) {
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

    switch (extension) {
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

  Future<void> _pickPreferredDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    final preferred = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _preferredDateTime = preferred;
    });
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

    if (_submitting) return;

    final attachments = _attachments
        .map(
          (file) =>
              'data:${file.mimeType};base64,${base64Encode(file.bytes)}',
        )
        .toList();

    setState(() {
      _submitting = true;
    });

    try {
      await _service.createRequest(
        unitId: _selectedUnit!.id,
        category: _selectedCategory!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        location: _locationController.text.trim(),
        contactName: _contactNameController.text.trim(),
        contactPhone: _contactPhoneController.text.trim(),
        attachments: attachments,
        preferredDateTime: _preferredDateTime,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (!mounted) return;
      _showMessage(
        'Yêu cầu sửa chữa đã được gửi và đang chờ duyệt.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo yêu cầu sửa chữa'),
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
                  _buildCategoryField(),
                  const SizedBox(height: 16),
                  _buildTitleField(),
                  const SizedBox(height: 16),
                  _buildDescriptionField(),
                  const SizedBox(height: 16),
                  _buildLocationField(),
                  const SizedBox(height: 16),
                  _buildPreferredTimeField(),
                  const SizedBox(height: 16),
                  _buildContactFields(),
                  const SizedBox(height: 16),
                  _buildAttachmentsSection(),
                  const SizedBox(height: 16),
                  _buildNoteField(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitting || _loadingUnit ? null : _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Gửi yêu cầu'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loadingProfile || _loadingUnit)
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

  Widget _buildCategoryField() {
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Loại yêu cầu',
        border: OutlineInputBorder(),
      ),
      initialValue: _selectedCategory,
      items: _categories
          .map(
            (category) => DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Vui lòng chọn loại yêu cầu';
        }
        return null;
      },
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      decoration: const InputDecoration(
        labelText: 'Tiêu đề yêu cầu',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vui lòng nhập tiêu đề yêu cầu';
        }
        return null;
      },
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: 'Mô tả chi tiết',
        border: OutlineInputBorder(),
        alignLabelWithHint: true,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vui lòng mô tả chi tiết vấn đề';
        }
        return null;
      },
    );
  }

  Widget _buildLocationField() {
    return TextFormField(
      controller: _locationController,
      decoration: const InputDecoration(
        labelText: 'Địa điểm sửa chữa',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vui lòng nhập địa điểm sửa chữa';
        }
        return null;
      },
    );
  }

  Widget _buildPreferredTimeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Thời gian mong muốn xử lý (tùy chọn)',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _preferredDateTime != null
                    ? _formatPreferredDateTime(_preferredDateTime!)
                    : 'Chưa chọn',
              ),
            ),
            TextButton(
              onPressed: _pickPreferredDateTime,
              child: const Text('Chọn thời gian'),
            ),
            if (_preferredDateTime != null)
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _preferredDateTime = null;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }

  String _formatPreferredDateTime(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildContactFields() {
    return Column(
      children: [
        TextFormField(
          controller: _contactNameController,
          decoration: const InputDecoration(
            labelText: 'Người liên hệ',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Vui lòng nhập tên người liên hệ';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
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
        ),
      ],
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Hình ảnh / Video minh họa (tùy chọn)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              tooltip: 'Chụp ảnh',
            ),
            IconButton(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              tooltip: 'Chọn ảnh',
            ),
            IconButton(
              onPressed: () => _pickVideo(ImageSource.camera),
              icon: const Icon(Icons.videocam),
              tooltip: 'Quay video',
            ),
            IconButton(
              onPressed: () => _pickVideo(ImageSource.gallery),
              icon: const Icon(Icons.video_library),
              tooltip: 'Chọn video',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
            _attachments.length,
            (index) => Stack(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade200,
                    image: _attachments[index].isVideo
                        ? null
                        : DecorationImage(
                            image: MemoryImage(
                              Uint8List.fromList(_attachments[index].bytes),
                            ),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _attachments[index].isVideo
                      ? const Center(
                          child: Icon(Icons.videocam, size: 32),
                        )
                      : null,
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _removeAttachment(index),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Đã chọn ${_attachments.length}/3 tệp',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      decoration: const InputDecoration(
        labelText: 'Ghi chú bổ sung (tùy chọn)',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }
}

