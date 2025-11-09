import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;
  const ResetPasswordScreen({required this.email, required this.otp, super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final passCtrl = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  bool loading = false;
  bool obscure = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              final formWidth = isWide ? constraints.maxWidth * 0.45 : double.infinity;

              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            Colors.white,
                            AppColors.neutralBackground,
                            Colors.white,
                          ],
                        ),
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
                            AppColors.primaryBlue.withValues(alpha: 0.16),
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
                            'Đặt lại mật khẩu',
                            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tạo mật khẩu mới để bảo vệ tài khoản của bạn. Mật khẩu nên có ít nhất 8 ký tự.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
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
                              onPressed: () => setState(() => obscure = !obscure),
                            ),
                          ),
                          const SizedBox(height: 24),
                          AppPrimaryButton(
                            onPressed: loading ? null : () => _submit(auth),
                            label: 'Đổi mật khẩu',
                            loading: loading,
                            icon: Icons.lock_reset_rounded,
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
      await auth.confirmReset(
        widget.email,
        widget.otp,
        passCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đặt lại mật khẩu thành công!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.popUntil(context, (r) => r.isFirst);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thất bại'),
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
    passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }
}
