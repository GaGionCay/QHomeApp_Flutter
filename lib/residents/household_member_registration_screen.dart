// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import '../models/resident_without_account.dart';
import '../models/unit_info.dart';
import 'resident_account_service.dart';

import '../core/safe_state_mixin.dart';
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
    extends State<HouseholdMemberRegistrationScreen> 
    with SafeStateMixin<HouseholdMemberRegistrationScreen> {
  late final ResidentAccountService _service;
  List<ResidentWithoutAccount> _members = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ResidentAccountService(ApiClient());
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    safeSetState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await _service.getResidentsWithoutAccount(widget.unit.id);
      if (mounted) {
        safeSetState(() {
          _members = members;
        });
      }
    } catch (e) {
      if (mounted) {
        safeSetState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        safeSetState(() {
          _loading = false;
        });
      }
    }
  }

  String? _validateUsername(String username) {
    final trimmed = username.trim();
    
    if (trimmed.isEmpty) {
      return 'Username không được để trống.';
    }
    
    if (trimmed.length < 3) {
      return 'Username phải dài tối thiểu 3 ký tự.';
    }
    
    if (trimmed.length > 20) {
      return 'Username không được dài quá 20 ký tự.';
    }
    
    // Check for consecutive spaces (more than 1 space) - không được có "  "
    if (trimmed.contains('  ')) {
      return 'Username không được có khoảng trắng cách quá 2 lần liên tiếp.';
    }
    
    // Check total number of spaces - chỉ được có tối đa 1 khoảng trắng
    final spaceCount = ' '.allMatches(trimmed).length;
    if (spaceCount > 1) {
      return 'Username chỉ được chứa tối đa 1 khoảng trắng.';
    }
    
    // Check for special characters - only allow a-z, A-Z, 0-9, underscore, hyphen, and single space
    final validPattern = RegExp(r'^[a-zA-Z0-9_ -]+$');
    if (!validPattern.hasMatch(trimmed)) {
      return 'Username chỉ được chứa chữ cái (a-z, A-Z), số (0-9), gạch dưới (_), gạch ngang (-) và khoảng trắng (chỉ 1 khoảng trắng).';
    }
    
    return null;
  }

  Future<void> _showCreateRequestDialog(ResidentWithoutAccount member) async {
    bool autoGenerate = true;
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool submitting = false;
    String? errorText;
    String? usernameError;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          Future<void> submit() async {
            if (!autoGenerate) {
              // Validate username
              final usernameValidation = _validateUsername(usernameCtrl.text);
              if (usernameValidation != null) {
                setStateDialog(() {
                  errorText = usernameValidation;
                  usernameError = usernameValidation;
                });
                return;
              }
              
              if (passwordCtrl.text.trim().length < 6) {
                setStateDialog(() {
                  errorText = 'Password phải dài tối thiểu 6 ký tự.';
                  usernameError = null;
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
                proofOfRelationImages: [], // Không cần ảnh minh chứng
              );
              if (!mounted) return;
              Navigator.of(context).pop();
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
                      decoration: InputDecoration(
                        labelText: 'Username',
                        hintText:
                            'Nhập username (a-z, 0-9, gạch dưới, gạch ngang, khoảng trắng)',
                        errorText: usernameError,
                        helperText: 'Tối thiểu 3 ký tự, tối đa 20 ký tự, chỉ 1 khoảng trắng',
                      ),
                      enabled: !submitting,
                      onChanged: (value) {
                        // Clear error when user starts typing
                        if (usernameError != null) {
                          setStateDialog(() {
                            usernameError = null;
                            errorText = null;
                          });
                        }
                      },
                      maxLength: 20,
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
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Text(
                                    'Tất cả thành viên trong căn hộ đã có tài khoản.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                    textAlign: TextAlign.center,
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

}




