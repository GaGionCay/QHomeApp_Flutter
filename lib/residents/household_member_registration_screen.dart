import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../auth/api_client.dart';
import '../models/resident_without_account.dart';
import '../models/unit_info.dart';
import 'resident_account_service.dart';

class HouseholdMemberRegistrationScreen extends StatefulWidget {
  const HouseholdMemberRegistrationScreen({
    super.key,
    required this.unit,
  });

  final UnitInfo unit;

  @override
  State<HouseholdMemberRegistrationScreen> createState() =>
      _HouseholdMemberRegistrationScreenState();
}

class _HouseholdMemberRegistrationScreenState
    extends State<HouseholdMemberRegistrationScreen> {
  late final ResidentAccountService _service;
  List<ResidentWithoutAccount> _members = [];
  bool _loading = true;
  String? _error;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _service = ResidentAccountService(ApiClient());
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _service.getResidentsWithoutAccount(widget.unit.id);
      if (mounted) {
        setState(() {
          _members = members;
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

  Future<void> _showCreateRequestDialog(ResidentWithoutAccount member) async {
    bool autoGenerate = true;
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool submitting = false;
    String? errorText;
    final List<_ProofImage> proofImages = [];

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          Future<void> pickImages() async {
            final remaining = 6 - proofImages.length;
            if (remaining <= 0) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chỉ được chọn tối đa 6 ảnh minh chứng.'),
                  ),
                );
              }
              return;
            }
            final pickedFiles = await _picker.pickMultiImage(imageQuality: 80);
            if (pickedFiles.isEmpty) return;
            for (final file in pickedFiles.take(remaining)) {
              final bytes = await file.readAsBytes();
              setStateDialog(() {
                proofImages.add(
                  _ProofImage(
                    bytes: bytes,
                    mimeType: _inferMimeType(file.path),
                  ),
                );
              });
            }
          }

          Future<void> takePhoto() async {
            if (proofImages.length >= 6) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chỉ được chụp tối đa 6 ảnh minh chứng.'),
                  ),
                );
              }
              return;
            }
            final photo = await _picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 85,
            );
            if (photo == null) return;
            final bytes = await photo.readAsBytes();
            setStateDialog(() {
              proofImages.add(
                _ProofImage(
                  bytes: bytes,
                  mimeType: _inferMimeType(photo.path),
                ),
              );
            });
          }

          Future<void> submit() async {
            if (!autoGenerate) {
              if (usernameCtrl.text.trim().length < 3) {
                setStateDialog(() {
                  errorText = 'Username phải dài tối thiểu 3 ký tự.';
                });
                return;
              }
              if (passwordCtrl.text.trim().length < 6) {
                setStateDialog(() {
                  errorText = 'Password phải dài tối thiểu 6 ký tự.';
                });
                return;
              }
            }
            setStateDialog(() {
              submitting = true;
              errorText = null;
            });
            try {
              await _service.createAccountRequest(
                residentId: member.id,
                autoGenerate: autoGenerate,
                username: autoGenerate ? null : usernameCtrl.text.trim(),
                password: autoGenerate ? null : passwordCtrl.text.trim(),
                proofOfRelationImages: proofImages
                    .map((image) => image.dataUri)
                    .toList(growable: false),
              );
              if (!mounted) return;
              // ignore: use_build_context_synchronously
              Navigator.of(context).pop();
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đã gửi yêu cầu tạo tài khoản thành công.'),
                  backgroundColor: Colors.green,
                ),
              );
              await _loadMembers();
            } catch (e) {
              setStateDialog(() {
                submitting = false;
                errorText = 'Lỗi: $e';
              });
            }
          }

          return AlertDialog(
            title: Text(
              'Tạo tài khoản cho ${member.fullName ?? 'thành viên'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tự tạo tài khoản (username/password)'),
                    value: !autoGenerate,
                    onChanged: submitting
                        ? null
                        : (value) {
                            setStateDialog(() {
                              autoGenerate = !value;
                              if (autoGenerate) {
                                usernameCtrl.clear();
                                passwordCtrl.clear();
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  if (!autoGenerate) ...[
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        hintText:
                            'Nhập username (a-z, 0-9, gạch dưới, gạch ngang)',
                      ),
                      enabled: !submitting,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                      ),
                      obscureText: true,
                      enabled: !submitting,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: submitting ? null : pickImages,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text('Chọn ảnh (${proofImages.length}/6)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: submitting ? null : takePhoto,
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Chụp ảnh'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (proofImages.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: proofImages
                          .asMap()
                          .entries
                          .map(
                            (entry) => Stack(
                              alignment: Alignment.topRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    entry.value.bytes,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: GestureDetector(
                                    onTap: submitting
                                        ? null
                                        : () {
                                            setStateDialog(() {
                                              proofImages.removeAt(entry.key);
                                            });
                                          },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
              ElevatedButton(
                onPressed: submitting ? null : submit,
                child: submitting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Gửi yêu cầu'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng ký tài khoản thành viên'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildUnitBanner(context),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMembers,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'Không thể tải danh sách thành viên.\n$_error',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        )
                      : _members.isEmpty
                          ? ListView(
                              children: const [
                                Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Text(
                                    'Tất cả thành viên trong căn hộ đã có tài khoản.',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              itemCount: _members.length,
                              itemBuilder: (context, index) {
                                final member = _members[index];
                                final isDark =
                                    theme.brightness == Brightness.dark;
                                final cardColor = isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.white;
                                final borderColor = isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05);
                                final primaryText = theme.colorScheme.onSurface;
                                final secondaryText =
                                    theme.colorScheme.onSurfaceVariant;

                                return Container(
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: borderColor),
                                    boxShadow: [
                                      if (!isDark)
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.04),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                    ],
                                  ),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 22,
                                            backgroundColor: theme
                                                .colorScheme.primary
                                                .withValues(alpha: 0.16),
                                            child: Icon(
                                              Icons.person_outline,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  member.fullName ??
                                                      'Thành viên chưa có tên',
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: primaryText,
                                                  ),
                                                ),
                                                if ((member.relation ?? '')
                                                    .isNotEmpty)
                                                  Text(
                                                    member.relation!,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: secondaryText,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (member.isPrimary)
                                            Chip(
                                              label: Text(
                                                'Chủ hộ',
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  color: isDark
                                                      ? Colors.white
                                                      : theme
                                                          .colorScheme.primary,
                                                ),
                                              ),
                                              backgroundColor: theme
                                                  .colorScheme.primary
                                                  .withValues(alpha: 
                                                      isDark ? 0.25 : 0.12),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if ((member.phone ?? '').isNotEmpty)
                                        Text(
                                          'Điện thoại: ${member.phone}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if ((member.email ?? '').isNotEmpty)
                                        Text(
                                          'Email: ${member.email}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if ((member.nationalId ?? '').isNotEmpty)
                                        Text(
                                          'CCCD: ${member.nationalId}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      if (member.dob != null)
                                        Text(
                                          'Ngày sinh: ${member.formattedDob}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: secondaryText,
                                          ),
                                        ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: () =>
                                              _showCreateRequestDialog(member),
                                          icon: const Icon(
                                              Icons.person_add_alt_1),
                                          label: const Text(
                                              'Tạo yêu cầu tài khoản'),
                                        ),
                                      ),
                                    ],
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

  Widget _buildUnitBanner(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.unit;
    final buildingLabel = unit.buildingName ?? unit.buildingCode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 
          theme.brightness == Brightness.dark ? 0.3 : 0.6,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đăng ký tài khoản cho',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((buildingLabel ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Tòa $buildingLabel',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Muốn đổi căn hộ? Vào Cài đặt > Căn hộ của tôi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
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

class _ProofImage {
  _ProofImage({
    required this.bytes,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String mimeType;

  String get dataUri => 'data:$mimeType;base64,${base64Encode(bytes)}';
}


