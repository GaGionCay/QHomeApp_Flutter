import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/core/safe_state_mixin.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../core/app_router.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;
  const ResetPasswordScreen(
      {required this.email, required this.otp, super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> with SafeStateMixin<ResetPasswordScreen> {
  final passCtrl = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  bool loading = false;
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF04111E),
              Color(0xFF0B2137),
              Color(0xFF051323),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Colors.white,
              AppColors.neutralBackground,
              Colors.white,
            ],
          );

    final topGlow = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : AppColors.primaryBlue.withValues(alpha: 0.16);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final double availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.of(context).size.height;
            final isWide = availableWidth > 720;

            double targetWidth = isWide ? availableWidth * 0.7 : availableWidth;
            if (isWide && targetWidth < 560) {
              targetWidth = 560;
            }
            if (targetWidth > availableWidth) {
              targetWidth = availableWidth;
            }

            double horizontalPadding = (availableWidth - targetWidth) / 2;
            if (horizontalPadding < 24) {
              horizontalPadding = 24;
              targetWidth = availableWidth - horizontalPadding * 2;
            }

            const double verticalPadding = 64; // 32 top + 32 bottom
            final double minBodyHeight =
                (availableHeight - verticalPadding).clamp(0.0, double.infinity);

            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: backgroundGradient,
                    ),
                  ),
                ),
                Positioned(
                  top: -140,
                  left: -60,
                  child: Container(
                    width: constraints.maxWidth * 0.6,
                    height: constraints.maxWidth * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          topGlow,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      32,
                      horizontalPadding,
                      32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: targetWidth,
                        minHeight: minBodyHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Đặt lại mật khẩu',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tạo mật khẩu mới để bảo vệ tài khoản của bạn. Mật khẩu nên có ít nhất 8 ký tự.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                            ),
                            const SizedBox(height: 32),
                            AppLuxeTextField(
                              controller: passCtrl,
                              focusNode: _passFocus,
                              hint: 'Mật khẩu mới',
                              icon: Icons.lock_outline,
                              obscure: obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(auth),
                              suffix: IconButton(
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () =>
                                    safeSetState(() => obscure = !obscure),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Spacer(),
                            AppPrimaryButton(
                              onPressed: loading ? null : () => _submit(auth),
                              label: 'Đổi mật khẩu',
                              loading: loading,
                              icon: Icons.lock_reset_rounded,
                              enabled: !loading,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit(AuthProvider auth) async {
    FocusScope.of(context).unfocus();
    
    final password = passCtrl.text.trim();
    
    // Validate password
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập mật khẩu mới'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mật khẩu phải có ít nhất 8 ký tự'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Password must contain uppercase, lowercase, number, and special character
    final passwordRegex = RegExp(
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$',
    );
    
    if (!passwordRegex.hasMatch(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mật khẩu phải chứa chữ hoa, chữ thường, số và ký tự đặc biệt'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    safeSetState(() => loading = true);
    try {
      await auth.confirmReset(
        widget.email,
        widget.otp,
        password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đặt lại mật khẩu thành công! Vui lòng đăng nhập lại.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      // Wait a bit for snackbar to show, then navigate to login screen
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      // Navigate to login screen using go_router
      context.go(AppRoute.login.path);
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Có lỗi xảy ra. Vui lòng thử lại.';
      
      // Extract error message from DioException
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['message'] != null) {
          errorMessage = data['message'].toString();
        } else if (e.response?.statusCode == 400) {
          errorMessage = 'Mã OTP không hợp lệ hoặc đã hết hạn. Vui lòng thử lại.';
        }
      } else if (e.toString().contains('expired') || e.toString().contains('hết hạn')) {
        errorMessage = 'Mã OTP đã hết hạn. Vui lòng yêu cầu mã OTP mới.';
      } else if (e.toString().contains('invalid') || e.toString().contains('không đúng')) {
        errorMessage = 'Mã OTP không đúng. Vui lòng kiểm tra lại và thử lại.';
      } else if (e.toString().contains('Password must') || e.toString().contains('Mật khẩu')) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        safeSetState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }
}



