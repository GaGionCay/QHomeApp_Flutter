import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/app_router.dart';
import 'theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scaleUp;
  late Animation<double> _blurTween;
  late Animation<double> _glowTween;

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

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.go(AppRoute.login.path);
    });
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
              ? AppColors.primaryBlue.withOpacity(_glowTween.value)
              : AppColors.primaryEmerald.withOpacity(_glowTween.value);

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
