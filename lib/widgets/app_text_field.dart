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
        style: theme.textTheme.bodyLarge,
        decoration: InputDecoration(
          prefixIcon: Icon(
            widget.icon,
            color: _isFocused
                ? AppColors.primaryEmerald
                : theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          suffixIcon: widget.suffix,
          hintText: widget.hint,
        ),
      ),
    );
  }
}

