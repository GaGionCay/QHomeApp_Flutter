import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../auth/api_client.dart';
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
    final api = await ApiClient.create();
    final service = ProfileService(api.dio);

    String? avatarUrl;
    if (_avatar != null) {
      // Upload file avatar
      avatarUrl = await service.uploadAvatar(_avatar!.path);
    }

    // Gọi updateProfile, thêm avatarUrl nếu có
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật thành công!')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [Color(0xFF26A69A), Color(0xFF80CBC4)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Chỉnh sửa hồ sơ"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: FadeTransition(
        opacity: _anim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: _avatar != null
                            ? FileImage(_avatar!)
                            : (widget.initialData['avatarUrl'] != null
                                ? NetworkImage(widget.initialData['avatarUrl'])
                                : null) as ImageProvider?,
                        backgroundColor: Colors.grey.shade100,
                        child: (_avatar == null &&
                                widget.initialData['avatarUrl'] == null)
                            ? const Icon(Icons.person,
                                size: 60, color: Colors.grey)
                            : null,
                      ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: gradient,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                _buildField(_nameCtrl, "Họ và tên"),
                _buildField(_phoneCtrl, "Số điện thoại",
                    keyboardType: TextInputType.phone),
                _buildField(_addressCtrl, "Địa chỉ"),

                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: _inputDecoration("Giới tính"),
                  items: const [
                    DropdownMenuItem(value: "MALE", child: Text("Nam")),
                    DropdownMenuItem(value: "FEMALE", child: Text("Nữ")),
                    DropdownMenuItem(value: "OTHER", child: Text("Khác")),
                  ],
                  onChanged: (v) => setState(() => _gender = v ?? 'OTHER'),
                ),
                const SizedBox(height: 15),

                // Save button
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: Text(
                          "💾 Lưu thay đổi",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
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

  Widget _buildField(TextEditingController ctrl, String label,
      {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        decoration: _inputDecoration(label),
        validator: (v) =>
            v == null || v.isEmpty ? "Vui lòng nhập $label" : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
