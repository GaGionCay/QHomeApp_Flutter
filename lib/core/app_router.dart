import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../common/main_shell.dart';
import '../login/forgot_password_screen.dart';
import '../login/login_screen.dart';
import '../register/register_guide_screen.dart';
import '../splash_screen.dart';

enum AppRoute {
  splash('/'),
  login('/auth/login'),
  forgotPassword('/auth/forgot-password'),
  registerGuide('/auth/register'),
  main('/main');

  const AppRoute(this.path);
  final String path;
}

class MainShellArgs {
  const MainShellArgs({this.initialIndex = 0, this.snackMessage});

  final int initialIndex;
  final String? snackMessage;
}

class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoute.splash.path,
    routes: [
      GoRoute(
        path: AppRoute.splash.path,
        name: AppRoute.splash.name,
        pageBuilder: (context, state) {
          return _buildSharedAxisPage(
            key: state.pageKey,
            child: const SplashScreen(),
            transitionType: SharedAxisTransitionType.scaled,
            duration: const Duration(milliseconds: 280),
          );
        },
      ),
      GoRoute(
        path: AppRoute.login.path,
        name: AppRoute.login.name,
        pageBuilder: (context, state) {
          return _buildSharedAxisPage(
            key: state.pageKey,
            child: const LoginScreen(),
            transitionType: SharedAxisTransitionType.scaled,
          );
        },
      ),
      GoRoute(
        path: AppRoute.forgotPassword.path,
        name: AppRoute.forgotPassword.name,
        pageBuilder: (context, state) {
          return _buildSharedAxisPage(
            key: state.pageKey,
            child: const ForgotPasswordScreen(),
            transitionType: SharedAxisTransitionType.scaled,
          );
        },
      ),
      GoRoute(
        path: AppRoute.registerGuide.path,
        name: AppRoute.registerGuide.name,
        pageBuilder: (context, state) {
          return _buildSharedAxisPage(
            key: state.pageKey,
            child: const RegisterGuideScreen(),
            transitionType: SharedAxisTransitionType.scaled,
          );
        },
      ),
      GoRoute(
        path: AppRoute.main.path,
        name: AppRoute.main.name,
        pageBuilder: (context, state) {
          final args = state.extra is MainShellArgs
              ? state.extra as MainShellArgs
              : const MainShellArgs();
          return _buildFadeThroughPage(
            key: state.pageKey,
            child: MainShell(
              initialIndex: args.initialIndex,
              initialSnackMessage: args.snackMessage,
            ),
          );
        },
      ),
    ],
  );

  static CustomTransitionPage<void> _buildFadeThroughPage({
    required LocalKey key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      barrierDismissible: false,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
    );
  }

  static CustomTransitionPage<void> _buildSharedAxisPage({
    required LocalKey key,
    required Widget child,
    SharedAxisTransitionType transitionType =
        SharedAxisTransitionType.horizontal,
    Duration duration = const Duration(milliseconds: 320),
  }) {
    return CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transitionType: transitionType,
          fillColor: Colors.black.withValues(alpha: 0.02),
          child: child,
        );
      },
    );
  }
}
