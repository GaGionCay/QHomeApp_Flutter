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
        ? theme.colorScheme.primary.withOpacity(0.16)
        : AppColors.primaryEmerald.withValues(alpha: 0.18);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              final formWidth =
                  isWide ? constraints.maxWidth * 0.45 : double.infinity;

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
                  SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? constraints.maxWidth * 0.2 : 24,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: formWidth),
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
                            'Nhập mã OTP vừa được gửi đến ${widget.email}. Mã có hiệu lực trong vòng 5 phút.',
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
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) => _submit(auth),
                          ),
                          const SizedBox(height: 24),
                          AppPrimaryButton(
                            onPressed: loading ? null : () => _submit(auth),
                            label: 'Xác thực',
                            loading: loading,
                            icon: Icons.verified_user_outlined,
                            enabled: !loading,
                          ),
                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP không hợp lệ'),
          backgroundColor: Colors.red,
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
