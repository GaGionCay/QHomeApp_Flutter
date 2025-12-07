import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_text_field.dart';
import 'reset_password_screen.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String email;
  const VerifyOtpScreen({required this.email, super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final otpCtrl = TextEditingController();
  final FocusNode _otpFocus = FocusNode();
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF04111E),
              Color(0xFF0A1D33),
              Color(0xFF04111E),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              AppColors.neutralBackground,
              Colors.white,
            ],
          );

    final bottomGlow = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : AppColors.primaryEmerald.withValues(alpha: 0.18);

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
                  bottom: -120,
                  left: -60,
                  child: Container(
                    width: constraints.maxWidth * 0.65,
                    height: constraints.maxWidth * 0.65,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          bottomGlow,
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
                              'Xác thực OTP',
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
                              'Nhập mã OTP vừa được gửi đến ${widget.email}. Mã có hiệu lực trong vòng 1 phút.',
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
                              controller: otpCtrl,
                              focusNode: _otpFocus,
                              hint: 'Mã OTP',
                              icon: Icons.lock_open_outlined,
                              textInputAction: TextInputAction.done,
                              keyboardType: TextInputType.text,
                              onSubmitted: (_) => _submit(auth),
                            ),
                            const SizedBox(height: 24),
                            const Spacer(),
                            AppPrimaryButton(
                              onPressed: loading ? null : () => _submit(auth),
                              label: 'Xác thực',
                              loading: loading,
                              icon: Icons.verified_user_outlined,
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
    setState(() => loading = true);
    try {
      await auth.verifyOtp(widget.email, otpCtrl.text.trim());
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(
            email: widget.email,
            otp: otpCtrl.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Mã OTP không hợp lệ. Vui lòng thử lại.';
      
      // Extract error message from DioException
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['message'] != null) {
          errorMessage = data['message'].toString();
        } else if (e.response?.statusCode == 400) {
          errorMessage = 'Mã OTP không hợp lệ. Vui lòng thử lại.';
        }
      } else if (e.toString().contains('expired') || e.toString().contains('hết hạn')) {
        errorMessage = 'Mã OTP đã hết hạn. Vui lòng yêu cầu mã OTP mới.';
      } else if (e.toString().contains('invalid') || e.toString().contains('không đúng')) {
        errorMessage = 'Mã OTP không đúng. Vui lòng kiểm tra lại và thử lại.';
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
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    otpCtrl.dispose();
    _otpFocus.dispose();
    super.dispose();
  }
}

