import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'dart:async';

import '../auth/api_client.dart';
import '../auth/email_verification_service.dart';
import '../models/household.dart';
import '../models/unit_info.dart';
import '../services/cccd_ocr_service.dart';
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
  late final EmailVerificationService _emailVerificationService;
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
  final _otpCtrl = TextEditingController();

  final _fullNameFocus = FocusNode();
  final _relationFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _nationalIdFocus = FocusNode();

  DateTime? _dob;
  Household? _currentHousehold;
  bool _loadingHousehold = false;
  String? _householdError;

  // Email verification state
  bool _emailVerified = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _otpError;
  int _otpResendCooldown = 0;
  Timer? _otpTimer;

  // Tối đa 2 ảnh minh chứng
  final List<Uint8List> _proofImages = [];
  final List<String> _proofImageMimeTypes = [];

  // Ảnh CCCD (mặt trước)
  Uint8List? _cccdFrontImage;
  String? _cccdFrontMimeType;
  bool _scanningCccd = false;

  bool _submitting = false;

  final _picker = ImagePicker();
  late final CccdOcrService _cccdOcrService;

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
    final apiClient = ApiClient();
    _service = HouseholdMemberRequestService(apiClient);
    _emailVerificationService = EmailVerificationService();
    _cccdOcrService = CccdOcrService();
    _loadHousehold(widget.unit.id);
    
    // Reset email verified state when email changes and trigger rebuild for OTP button
    _emailCtrl.addListener(() {
      if (_emailVerified) {
        setState(() {
          _emailVerified = false;
          _otpCtrl.clear();
          _otpError = null;
        });
      } else {
        // Trigger rebuild to show/hide OTP button when email is entered/cleared
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _cccdOcrService.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _nationalIdCtrl.dispose();
    _relationCtrl.dispose();
    _noteCtrl.dispose();
    _otpCtrl.dispose();
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

  /// Chụp/chọn ảnh CCCD mặt trước
  Future<void> _pickCccdFront() async {
    final source = await _showImageSourceDialog('CCCD mặt trước');
    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _cccdFrontImage = bytes;
      _cccdFrontMimeType = _inferMimeType(picked.path);
    });

    // Tự động quét CCCD sau khi chọn ảnh
    await _scanCccdImage(bytes, isFront: true);
  }


  /// Hiển thị dialog chọn nguồn ảnh
  Future<ImageSource?> _showImageSourceDialog(String title) async {
    return showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Chọn $title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Quét ảnh CCCD và tự động điền thông tin
  Future<void> _scanCccdImage(Uint8List imageBytes, {required bool isFront}) async {
    if (!mounted) return;

    setState(() {
      _scanningCccd = true;
    });

    try {
      final cccdInfo = await _cccdOcrService.scanCccdImage(imageBytes);

      if (!mounted) return;

      if (cccdInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể đọc thông tin từ ảnh CCCD. Vui lòng thử lại với ảnh rõ hơn.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _scanningCccd = false;
        });
        return;
      }

      // Tự động điền thông tin vào form
      bool hasNewInfo = false;

      if (cccdInfo.fullName != null &&
          cccdInfo.fullName!.isNotEmpty &&
          _fullNameCtrl.text.trim().isEmpty) {
        _fullNameCtrl.text = cccdInfo.fullName!;
        hasNewInfo = true;
      }

      if (cccdInfo.nationalId != null &&
          cccdInfo.nationalId!.isNotEmpty &&
          _nationalIdCtrl.text.trim().isEmpty) {
        _nationalIdCtrl.text = cccdInfo.nationalId!;
        hasNewInfo = true;
      }

      if (cccdInfo.dateOfBirth != null && _dob == null) {
        _dob = cccdInfo.dateOfBirth;
        hasNewInfo = true;
      }

      setState(() {
        _scanningCccd = false;
      });

      if (hasNewInfo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã tự động điền thông tin từ CCCD'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Không tìm thấy thông tin mới để điền. Vui lòng kiểm tra lại ảnh.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanningCccd = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi quét CCCD: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkEmailAndSendOtp() async {
    final email = _emailCtrl.text.trim();
    
    print('🔍 [HouseholdMemberRequest] Bắt đầu gửi OTP cho email: $email');
    
    // Validate email format manually (don't use form validator which checks _emailVerified)
    if (email.isEmpty) {
      setState(() {
        _otpError = 'Vui lòng nhập email.';
      });
      _emailFieldKey.currentState?.validate();
      return;
    }
    
    final emailRegex = RegExp(
        r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      setState(() {
        _otpError = 'Email không hợp lệ.';
      });
      _emailFieldKey.currentState?.validate();
      return;
    }
    
    if (email.length > 100) {
      setState(() {
        _otpError = 'Email không được quá 100 ký tự.';
      });
      _emailFieldKey.currentState?.validate();
      return;
    }
    
    setState(() {
      _sendingOtp = true;
      _otpError = null;
    });
    
    try {
      print('🔍 [HouseholdMemberRequest] Kiểm tra email đã tồn tại chưa...');
      // Check if email exists
      final emailExists = await _emailVerificationService.checkEmailExists(email);
      print('🔍 [HouseholdMemberRequest] Email exists: $emailExists');
      
      if (emailExists) {
        setState(() {
          _sendingOtp = false;
          _otpError = 'Email này đã được sử dụng. Vui lòng sử dụng email khác.';
        });
        _emailFieldKey.currentState?.validate();
        return;
      }
      
      print('🔍 [HouseholdMemberRequest] Gửi OTP...');
      // Send OTP
      await _emailVerificationService.requestOtp(email);
      print('✅ [HouseholdMemberRequest] OTP đã được gửi thành công');
      
      setState(() {
        _sendingOtp = false;
        _emailVerified = false;
        _otpResendCooldown = 60; // 60 seconds cooldown
      });
      
      // Start countdown timer
      _startOtpResendTimer();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mã OTP đã được gửi đến email của bạn. Vui lòng kiểm tra hộp thư.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ [HouseholdMemberRequest] Lỗi khi gửi OTP: $e');
      print('❌ [HouseholdMemberRequest] Stack trace: $stackTrace');
      setState(() {
        _sendingOtp = false;
        _otpError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
  
  Future<void> _verifyOtp() async {
    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    
    if (otp.length != 6) {
      setState(() {
        _otpError = 'Mã OTP phải có 6 ký tự';
      });
      return;
    }
    
    setState(() {
      _verifyingOtp = true;
      _otpError = null;
    });
    
    try {
      final verified = await _emailVerificationService.verifyOtp(email, otp);
      
      if (verified) {
        setState(() {
          _emailVerified = true;
          _verifyingOtp = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Email đã được xác thực thành công'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _verifyingOtp = false;
        _otpError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
  
  void _startOtpResendTimer() {
    _otpTimer?.cancel();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_otpResendCooldown > 0) {
        setState(() {
          _otpResendCooldown--;
        });
      } else {
        timer.cancel();
      }
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
      if (!mounted) return;
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
    
    // Double check email is verified
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !_emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng xác thực email trước khi gửi yêu cầu'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    
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
                      // Don't check _emailVerified here - that's only checked on form submit
                      // User needs to send OTP first before verifying
                      return null;
                    },
                  ),
                ),
                // OTP section - only show if email is entered and not verified
                if (_emailCtrl.text.trim().isNotEmpty && !_emailVerified) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sendingOtp || _otpResendCooldown > 0
                              ? null
                              : _checkEmailAndSendOtp,
                          icon: _sendingOtp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.email_outlined),
                          label: Text(
                            _otpResendCooldown > 0
                                ? 'Gửi lại mã OTP (${_otpResendCooldown}s)'
                                : 'Gửi mã OTP',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _otpCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP',
                      hintText: 'Nhập 6 ký tự',
                      helperText: 'Mã OTP có hiệu lực trong 1 phút',
                    ),
                    keyboardType: TextInputType.text,
                    maxLength: 6,
                    enabled: !_verifyingOtp && !_emailVerified,
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _verifyingOtp || _emailVerified
                          ? null
                          : _verifyOtp,
                      child: _verifyingOtp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Xác nhận OTP'),
                    ),
                  ),
                  if (_otpError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _otpError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
                if (_emailVerified) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Email đã được xác thực',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
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
                      if (v.length != 13) {
                        return 'CCCD phải có đúng 13 số.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Section quét CCCD
                _buildCccdSection(),
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
                                backgroundColor: Colors.black.withValues(alpha: 0.6),
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
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

  /// Widget hiển thị section quét CCCD
  Widget _buildCccdSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.4,
            ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.credit_card,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quét CCCD để tự động điền thông tin',
                  softWrap: true,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Chụp hoặc chọn ảnh CCCD để tự động điền họ tên, số CCCD và ngày sinh',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          // CCCD mặt trước
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mặt trước',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              if (_cccdFrontImage != null)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _cccdFrontImage!,
                        height: 120,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(4),
                      ),
                      onPressed: () {
                        setState(() {
                          _cccdFrontImage = null;
                          _cccdFrontMimeType = null;
                        });
                      },
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  onPressed: _scanningCccd ? null : _pickCccdFront,
                  icon: _scanningCccd
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Chụp/Chọn'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
            ],
          ),
          if (_scanningCccd) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Đang quét CCCD...',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


