import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_text_field.dart';
import 'verify_otp_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final emailCtrl = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  bool loading = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(AuthProvider auth) async {
    FocusScope.of(context).unfocus();
    
    final email = emailCtrl.text.trim();
    
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập email'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email không hợp lệ. Vui lòng nhập đúng định dạng email.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() => loading = true);
    try {
      await auth.requestReset(email);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(email: email),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yêu cầu thất bại: ${e.toString()}'),
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
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF040F1D),
              Color(0xFF0A1C33),
              Color(0xFF050F1F),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFF4F6FA),
              Colors.white,
            ],
          );

    final accentGlow = isDark
        ? theme.colorScheme.primary.withOpacity(0.18)
        : theme.colorScheme.primary.withOpacity(0.18);

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
                    decoration: BoxDecoration(gradient: backgroundGradient),
                  ),
                ),
                Positioned(
                  top: -160,
                  right: -80,
                  child: Container(
                    width: constraints.maxWidth * 0.6,
                    height: constraints.maxWidth * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [accentGlow, Colors.transparent],
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
                              'Đổi mật khẩu',
                              style: theme.textTheme.displaySmall?.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Nhập email của bạn. Chúng tôi sẽ gửi mã OTP để giúp bạn đổi mật khẩu.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 32),
                            AppLuxeTextField(
                              controller: emailCtrl,
                              focusNode: _emailFocus,
                              hint: 'Email đăng nhập',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(auth),
                            ),
                            const SizedBox(height: 24),
                            const Spacer(),
                            AppPrimaryButton(
                              onPressed: loading ? null : () => _submit(auth),
                              label: 'Gửi OTP',
                              loading: loading,
                              icon: Icons.send_rounded,
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
}
