import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppLuxeTextField extends StatefulWidget {
  const AppLuxeTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppLuxeTextField> createState() => _AppLuxeTextFieldState();
}

class _AppLuxeTextFieldState extends State<AppLuxeTextField> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _isFocused = widget.focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fillColor = isDark
        ? AppColors.navySurfaceElevated.withOpacity(0.78)
        : theme.colorScheme.surface.withOpacity(0.92);

    final iconColor = _isFocused
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withOpacity(0.55);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: _isFocused
            ? LinearGradient(
                colors: [
                  AppColors.primaryEmerald.withValues(alpha: 0.32),
                  AppColors.primaryBlue.withValues(alpha: 0.16),
                ],
              )
            : null,
        boxShadow: _isFocused ? AppColors.subtleShadow : null,
      ),
      padding: EdgeInsets.all(_isFocused ? 1.4 : 0),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: widget.obscure,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: fillColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          prefixIcon: Icon(
            widget.icon,
            color: iconColor,
          ),
          suffixIcon: widget.suffix,
          hintText: widget.hint,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: theme.colorScheme.primary.withOpacity(0.28),
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

