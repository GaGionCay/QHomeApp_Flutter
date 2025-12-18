import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:provider/provider.dart';
import 'core/app_router.dart';
import 'theme/app_colors.dart';
import 'auth/auth_provider.dart';

import 'core/safe_state_mixin.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> 
    with TickerProviderStateMixin, SafeStateMixin<SplashScreen> {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scaleUp;
  late Animation<double> _blurTween;
  late Animation<double> _glowTween;
  final AppLinks _appLinks = AppLinks();
  Uri? _pendingDeepLink;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _fadeIn = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );

    _scaleUp = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeInOutCubic),
      ),
    );

    _blurTween = Tween<double>(begin: 40, end: 10).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.9, curve: Curves.easeInOutCubic),
      ),
    );

    _glowTween = Tween<double>(begin: 0.0, end: 0.45).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.forward();
    _checkInitialDeepLink();
    _listenForDeepLink();

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _navigateAfterSplash();
    });
  }

  Future<void> _checkInitialDeepLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _pendingDeepLink = initialUri;
        debugPrint('🔗 [SplashScreen] Initial deep link: $initialUri');
      }
    } catch (e) {
      debugPrint('⚠️ [SplashScreen] Error getting initial link: $e');
    }
  }

  void _listenForDeepLink() {
    _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _pendingDeepLink = uri;
        debugPrint('🔗 [SplashScreen] Deep link received: $uri');
        // If splash is still showing, navigate immediately
        if (mounted) {
          _navigateAfterSplash();
        }
      }
    });
  }

  void _navigateAfterSplash() {
    if (!mounted || _hasNavigated) return;

    // Check authentication state
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Wait for auth to finish loading
    if (authProvider.isLoading) {
      debugPrint('⏳ [SplashScreen] Auth still loading, waiting...');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_hasNavigated) {
          _navigateAfterSplash();
        }
      });
      return;
    }

    // Mark as navigated to prevent multiple navigations
    _hasNavigated = true;

    // Check if there's a VNPay payment result deep link
    final hasVnpaySuccess = _pendingDeepLink != null && 
                            _pendingDeepLink!.scheme == 'qhomeapp' &&
                            _isVnpaySuccessLink(_pendingDeepLink!);

    // If user is authenticated and has VNPay success link, navigate to MainShell
    if (authProvider.isAuthenticated && hasVnpaySuccess) {
      debugPrint('✅ [SplashScreen] User authenticated + VNPay success, navigating to MainShell');
      context.go(
        AppRoute.main.path,
        extra: MainShellArgs(
          initialIndex: 1,
          snackMessage: 'Thanh toán thành công!',
        ),
      );
      return;
    }

    // If user is authenticated (even without VNPay link), navigate to MainShell
    if (authProvider.isAuthenticated) {
      debugPrint('✅ [SplashScreen] User authenticated, navigating to MainShell');
      context.go(AppRoute.main.path);
      return;
    }

    // If not authenticated, navigate to login
    debugPrint('🔐 [SplashScreen] User not authenticated, navigating to login');
    context.go(AppRoute.login.path);
  }

  bool _isVnpaySuccessLink(Uri uri) {
    final host = uri.host;
    final responseCode = uri.queryParameters['responseCode'];
    final successParam = uri.queryParameters['success'];

    return (host == 'vnpay-resident-card-result' ||
            host == 'vnpay-elevator-card-result' ||
            host == 'vnpay-registration-result' ||
            host == 'service-booking-result') &&
           (responseCode == '00' || (successParam ?? '').toLowerCase() == 'true');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLogo() {
    return Hero(
      tag: 'qhome-logo',
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
        return ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 0.9).animate(animation),
          child: toContext.widget,
        );
      },
      child: ScaleTransition(
        scale: _scaleUp,
        child: Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient(),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryEmerald.withValues(alpha: 0.32),
                blurRadius: 25,
                spreadRadius: 2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.apartment_rounded, size: 52, color: Colors.white),
              SizedBox(height: 10),
              Text(
                'QHOME',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to auth provider to know when auth is ready
    final authProvider = context.watch<AuthProvider>();
    
    // If auth is ready and we haven't navigated yet, trigger navigation check
    if (!authProvider.isLoading && !_hasNavigated && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Small delay to ensure deep link is processed
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_hasNavigated) {
            _navigateAfterSplash();
          }
        });
      });
    }
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final scaffoldColor =
        isDark ? AppColors.deepNight : AppColors.neutralBackground;

    final backgroundGradient = isDark
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF050F1F),
              Color(0xFF0C2139),
              Color(0xFF081526),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Color(0xFFF4F6FA),
              Color(0xFFF0F4FF),
            ],
          );

    return Scaffold(
      backgroundColor: scaffoldColor,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glowColor = isDark
              ? AppColors.primaryBlue.withValues(alpha: _glowTween.value)
              : AppColors.primaryEmerald.withValues(alpha: _glowTween.value);

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: backgroundGradient,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: glowColor,
                          blurRadius: 160 - _blurTween.value,
                          spreadRadius: 16,
                        ),
                      ],
                    ),
                    child: _buildLogo(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


