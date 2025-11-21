import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../profile/profile_service.dart';
import '../widgets/app_primary_button.dart';
import 'verify_otp_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  String? _email;
  bool _loading = false;
  bool _emailLoading = true;
  String? _emailError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmail();
    });
  }

  Future<void> _loadEmail() async {
    final auth = context.read<AuthProvider>();
    setState(() {
      _emailLoading = true;
      _emailError = null;
    });
    try {
      final profileService = ProfileService(auth.apiClient.dio);
      final profile = await profileService.getProfile();
      final fetchedEmail = profile['email']?.toString();
      if (mounted) {
        setState(() {
          _email = fetchedEmail;
          _emailLoading = false;
          _emailError = fetchedEmail == null || fetchedEmail.isEmpty
              ? 'Không tìm thấy email cho tài khoản này.'
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _email = null;
          _emailLoading = false;
          _emailError = 'Không thể lấy thông tin email: $e';
        });
      }
    }
  }

  Future<void> _submit(AuthProvider auth) async {
    FocusScope.of(context).unfocus();

    if (_email == null || _email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không xác định được email. Vui lòng thử lại sau.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await auth.requestReset(_email!);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyOtpScreen(email: _email!),
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
        setState(() => _loading = false);
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
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : theme.colorScheme.primary.withValues(alpha: 0.18);

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
                              'Chúng tôi sẽ sử dụng email của tài khoản đang đăng nhập để gửi mã OTP đổi mật khẩu.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_emailLoading)
                              const Center(
                                child: CircularProgressIndicator(),
                              )
                            else if (_emailError != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _emailError!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.email_outlined,
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
                                            'Email xác thực',
                                            style: theme.textTheme.labelLarge,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _email ?? '',
                                            style: theme.textTheme.bodyLarge,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 24),
                            const Spacer(),
                            AppPrimaryButton(
                              onPressed: _loading || _emailLoading
                                  ? null
                                  : () => _submit(auth),
                              label: 'Gửi OTP',
                              loading: _loading,
                              icon: Icons.send_rounded,
                              enabled: !_loading && !_emailLoading,
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
