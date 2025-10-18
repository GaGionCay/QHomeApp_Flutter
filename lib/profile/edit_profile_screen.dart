import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../auth/api_client.dart';
import 'profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialData;

  const EditProfileScreen({super.key, required this.initialData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late ProfileService _profileService;

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _citizenIdCtrl = TextEditingController();
  final _apartmentNameCtrl = TextEditingController();
  final _buildingBlockCtrl = TextEditingController();
  final _unitNumberCtrl = TextEditingController();
  final _floorNumberCtrl = TextEditingController();
  String _gender = 'OTHER';
  DateTime? _dob;

  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final data = widget.initialData;
    _fullNameCtrl.text = data['fullName'] ?? '';
    _phoneCtrl.text = data['phoneNumber'] ?? '';
    _addressCtrl.text = data['address'] ?? '';
    _citizenIdCtrl.text = data['citizenId'] ?? '';
    _apartmentNameCtrl.text = data['apartmentName'] ?? '';
    _buildingBlockCtrl.text = data['buildingBlock'] ?? '';
    _unitNumberCtrl.text = data['unitNumber'] ?? '';
    _floorNumberCtrl.text = data['floorNumber']?.toString() ?? '';
    _gender = data['gender'] ?? 'OTHER';
    if (data['dateOfBirth'] != null) {
      _dob = DateTime.tryParse(data['dateOfBirth']);
    }
  }

  Future<void> _pickImage() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final apiClient = await ApiClient.create();
    _profileService = ProfileService(apiClient.dio);

    // Upload avatar nếu người dùng chọn ảnh mới
    String? avatarUrl = widget.initialData['avatarUrl'];
    if (_selectedImage != null) {
      avatarUrl = await _profileService.uploadAvatar(_selectedImage!.path);
      setState(() {
        widget.initialData['avatarUrl'] = avatarUrl;
      });
    }

    final payload = {
      "fullName": _fullNameCtrl.text.trim(),
      "gender": _gender,
      "dateOfBirth":
          _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
      "phoneNumber": _phoneCtrl.text.trim(),
      "avatarUrl": avatarUrl,
      "apartmentName": _apartmentNameCtrl.text.trim(),
      "buildingBlock": _buildingBlockCtrl.text.trim(),
      "floorNumber": int.tryParse(_floorNumberCtrl.text),
      "unitNumber": _unitNumberCtrl.text.trim(),
      "address": _addressCtrl.text.trim(),
      "citizenId": _citizenIdCtrl.text.trim(),
    };

    await _profileService.updateProfile(payload);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật hồ sơ thành công!')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOnlyDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      suffixIcon: const Icon(Icons.lock, color: Colors.grey),
      border: const OutlineInputBorder(),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ======= Avatar chọn ảnh =======
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 55,
                      backgroundImage: _selectedImage != null
                          ? FileImage(_selectedImage!)
                          : (widget.initialData['avatarUrl'] != null
                              ? NetworkImage(widget.initialData['avatarUrl'])
                              : null) as ImageProvider?,
                      child: (_selectedImage == null &&
                              widget.initialData['avatarUrl'] == null)
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ======= Form nhập thông tin =======
              TextFormField(
                controller: _fullNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Không được bỏ trống' : null,
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: _gender,
                decoration: readOnlyDecoration.copyWith(labelText: 'Giới tính'),
                items: const [
                  DropdownMenuItem(value: 'MALE', child: Text('Nam')),
                  DropdownMenuItem(value: 'FEMALE', child: Text('Nữ')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Khác')),
                ],
                onChanged: null, // disable chọn giới tính
              ),
              const SizedBox(height: 10),

              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                  text: _dob != null
                      ? DateFormat('dd/MM/yyyy').format(_dob!)
                      : 'Chưa chọn ngày sinh',
                ),
                decoration: readOnlyDecoration.copyWith(
                  labelText: 'Ngày sinh',
                ),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _phoneCtrl,
                readOnly: true,
                decoration:
                    readOnlyDecoration.copyWith(labelText: 'Số điện thoại'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _addressCtrl,
                readOnly: true,
                decoration: readOnlyDecoration.copyWith(labelText: 'Địa chỉ'),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _citizenIdCtrl,
                readOnly: true,
                decoration:
                    readOnlyDecoration.copyWith(labelText: 'CMND/CCCD'),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _apartmentNameCtrl,
                readOnly: true,
                decoration:
                    readOnlyDecoration.copyWith(labelText: 'Tên căn hộ'),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _buildingBlockCtrl,
                readOnly: true,
                decoration:
                    readOnlyDecoration.copyWith(labelText: 'Tòa nhà'),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _floorNumberCtrl,
                readOnly: true,
                decoration: readOnlyDecoration.copyWith(labelText: 'Tầng'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _unitNumberCtrl,
                readOnly: true,
                decoration: readOnlyDecoration.copyWith(labelText: 'Số phòng'),
              ),
              const SizedBox(height: 25),

              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text('Lưu thay đổi'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
