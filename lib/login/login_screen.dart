import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import '../core/app_router.dart';
import '../theme/app_colors.dart';
import '../widgets/app_primary_button.dart';
import '../widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameCtrl = TextEditingController(); // Đổi từ email sang username
  final passCtrl = TextEditingController();
  final FocusNode _usernameFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool loading = false;
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 720;
            final formWidth =
                isWide ? constraints.maxWidth * 0.45 : double.infinity;

            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
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
                  top: -120,
                  right: -80,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 340),
                    width: constraints.maxWidth * 0.8,
                    height: constraints.maxWidth * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.primaryEmerald.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -140,
                  left: -60,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 340),
                    width: constraints.maxWidth * 0.7,
                    height: constraints.maxWidth * 0.7,
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
                SafeArea(
                  child: Align(
                    alignment: isWide ? Alignment.center : Alignment.topCenter,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? constraints.maxWidth * 0.08 : 24,
                        vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isWide ? formWidth : double.infinity,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Hero(
                                  tag: 'qhome-logo',
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.primaryGradient(),
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: AppColors.elevatedShadow,
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.apartment_rounded,
                                        size: 42,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            Text(
                              'Chào mừng trở lại,',
                              style: textTheme.headlineSmall?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Đăng nhập để tiếp tục',
                              style: textTheme.displaySmall?.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 32,
                              ),
                            ),
                            const SizedBox(height: 32),
                            AppLuxeTextField(
                              controller: usernameCtrl,
                              focusNode: _usernameFocus,
                              hint: 'Tên đăng nhập',
                              icon: Icons.person_outline,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passwordFocus.requestFocus(),
                            ),
                            const SizedBox(height: 16),
                            AppLuxeTextField(
                              controller: passCtrl,
                              focusNode: _passwordFocus,
                              hint: 'Mật khẩu',
                              icon: Icons.lock_outline,
                              obscure: _obscurePassword,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(auth),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    context.push(AppRoute.forgotPassword.path),
                                child: const Text('Quên mật khẩu?'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AppPrimaryButton(
                              onPressed: loading ? null : () => _submit(auth),
                              label: 'Đăng nhập',
                              loading: loading,
                              icon: Icons.lock_open_rounded,
                              enabled: !loading,
                            ),
                            const SizedBox(height: 40),
                            _SecurityFooter(textTheme: textTheme),
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

    final ok = await auth.loginViaIam(
      usernameCtrl.text.trim(),
      passCtrl.text.trim(),
    );

    setState(() => loading = false);

    if (!mounted) return;

    if (ok) {
      context.go(AppRoute.main.path);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng nhập thất bại'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    passCtrl.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.shield_moon_outlined,
            color: AppColors.primaryEmerald.withValues(alpha: 0.8)),
        const SizedBox(height: 12),
        Text(
          'Ứng dụng cư dân thông minh',
          style: textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Kết nối với các dịch vụ quản lý, thanh toán và tiện ích cộng đồng mọi lúc mọi nơi.',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.78),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
