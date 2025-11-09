import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';
import 'profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;
  const EditProfileScreen({super.key, required this.initialData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  String _gender = 'OTHER';
  DateTime? _dob;
  File? _avatar;
  late AnimationController _anim;
  final picker = ImagePicker();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _nameCtrl =
        TextEditingController(text: widget.initialData['fullName'] ?? '');
    _phoneCtrl =
        TextEditingController(text: widget.initialData['phoneNumber'] ?? '');
    _addressCtrl =
        TextEditingController(text: widget.initialData['address'] ?? '');
    _gender = widget.initialData['gender'] ?? 'OTHER';
    if (widget.initialData['dateOfBirth'] != null) {
      _dob = DateTime.tryParse(widget.initialData['dateOfBirth']);
    }
  }

  Future<void> _pickAvatar() async {
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) setState(() => _avatar = File(picked.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = await ApiClient.create();
      final service = ProfileService(api.dio);

      String? avatarUrl;
      if (_avatar != null) {
        avatarUrl = await service.uploadAvatar(_avatar!.path);
      }

      final data = {
        "fullName": _nameCtrl.text.trim(),
        "phoneNumber": _phoneCtrl.text.trim(),
        "address": _addressCtrl.text.trim(),
        "gender": _gender,
        "dateOfBirth":
            _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
      };
      if (avatarUrl != null) data["avatarUrl"] = avatarUrl;

      await service.updateProfile(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật thành công!')),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  void setState(VoidCallback fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _showDatePicker() async {
    final now = DateTime.now();
    final initialDate = _dob ?? DateTime(now.year - 20);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 80),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarProvider = _avatar != null
        ? FileImage(_avatar!)
        : (widget.initialData['avatarUrl'] != null
            ? NetworkImage(widget.initialData['avatarUrl'])
            : null) as ImageProvider?;
    final dobText = _dob != null ? DateFormat('dd/MM/yyyy').format(_dob!) : 'Chưa cập nhật';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Chỉnh sửa hồ sơ'),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FadeTransition(
        opacity: _anim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.primaryGradient(),
                        boxShadow: AppColors.subtleShadow,
                      ),
                      child: CircleAvatar(
                        radius: 64,
                        backgroundImage: avatarProvider,
                        backgroundColor: theme.colorScheme.surface,
                        child: avatarProvider == null
                            ? Icon(Icons.person_outline,
                                size: 54,
                                color: theme.colorScheme.primary.withValues(alpha: 0.6))
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    onPressed: _pickAvatar,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Thay đổi ảnh đại diện'),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Thông tin cơ bản',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _nameCtrl,
                  label: 'Họ và tên',
                  keyboardType: TextInputType.name,
                ),
                _buildField(
                  controller: _phoneCtrl,
                  label: 'Số điện thoại',
                  keyboardType: TextInputType.phone,
                ),
                _buildField(
                  controller: _addressCtrl,
                  label: 'Địa chỉ',
                  keyboardType: TextInputType.streetAddress,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: _inputDecoration(context, 'Giới tính'),
                  items: const [
                    DropdownMenuItem(value: 'MALE', child: Text('Nam')),
                    DropdownMenuItem(value: 'FEMALE', child: Text('Nữ')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Khác')),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? 'OTHER'),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _showDatePicker,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Ngày sinh',
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Text(
                          dobText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                AppPrimaryButton(
                  onPressed: _saving ? null : _save,
                  label: 'Lưu thay đổi',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  enabled: !_saving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: _inputDecoration(context, label),
        validator: (v) =>
            v == null || v.isEmpty ? 'Vui lòng nhập $label' : null,
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String label) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: theme.textTheme.bodyMedium,
      filled: true,
      fillColor: theme.colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(
          color: theme.colorScheme.primary,
          width: 1.8,
        ),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
