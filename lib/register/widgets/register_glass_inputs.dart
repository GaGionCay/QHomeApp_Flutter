import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

class RegisterGlassPanel extends StatelessWidget {
  const RegisterGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 26,
    this.shadow,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.darkGlassLayerGradient()
                : AppColors.glassLayerGradient(),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
            boxShadow: shadow ?? AppColors.subtleShadow,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class RegisterGlassDropdown<T> extends StatefulWidget {
  const RegisterGlassDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.label,
    required this.hint,
    required this.icon,
    this.enabled = true,
    this.onChanged,
    this.validator,
    this.onDoubleTap,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final String label;
  final String hint;
  final IconData icon;
  final bool enabled;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final VoidCallback? onDoubleTap;

  @override
  State<RegisterGlassDropdown<T>> createState() =>
      _RegisterGlassDropdownState<T>();
}

class _RegisterGlassDropdownState<T> extends State<RegisterGlassDropdown<T>> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final interactive = widget.enabled;
    final labelColor = _isFocused && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: interactive ? 0.74 : 0.45);

    final borderColor = _isFocused && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: interactive ? 0.1 : 0.05);

    final iconColor = _isFocused && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: interactive ? 0.7 : 0.4);

    // Kích thước BorderRadius thống nhất
    const double borderRadius = 24;

    return GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: theme.textTheme.labelLarge?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ) ??
                TextStyle(color: labelColor),
            child: Text(widget.label),
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: interactive ? 1 : 0.85,
            child: Focus(
              canRequestFocus: interactive,
              skipTraversal: !interactive,
              onFocusChange: (focus) {
                if (interactive) {
                  if (!focus) {
                    // Validate the entire form when dropdown loses focus
                    Form.of(context).validate();
                  }
                  setState(() => _isFocused = focus);
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: isDark
                      ? AppColors.darkGlassLayerGradient()
                      : AppColors.glassLayerGradient(),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: borderColor,
                    width: _isFocused && interactive ? 2.0 : 1.0,
                  ),
                  boxShadow: AppColors.subtleShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(borderRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    // Xóa các ClipRRect và Padding không cần thiết bên trong
                    child: Padding(
                      padding: EdgeInsets.zero, // Giữ nguyên Padding.zero ở đây
                      child: DropdownButtonFormField<T>(
                        initialValue: widget.value,
                        items: widget.items,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: widget.validator,
                        onChanged: interactive ? widget.onChanged : null,
                        isExpanded: true,
                        dropdownColor: isDark
                            ? AppColors.navySurfaceElevated.withValues(alpha: 0.96)
                            : Colors.white,
                        style: theme.textTheme.bodyLarge,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: iconColor,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          hintText: widget.hint.isEmpty ? null : widget.hint,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: interactive ? 0.45 : 0.35),
                          ),
                          prefixIcon: Icon(widget.icon, color: iconColor),
                          // **QUAN TRỌNG:** Điều chỉnh contentPadding để kiểm soát không gian bên trong
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, // Tăng padding ngang để tạo không gian
                            vertical: 18,
                          ).copyWith(left: 0), // PrefixIcon đã xử lý phần lề trái
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterGlassTextField extends StatefulWidget {
  const RegisterGlassTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.enabled = true,
    this.readOnly = false,
    this.helperText,
    this.onDoubleTap,
    this.onChanged,
    this.onEditingComplete,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;
  final bool enabled;
  final bool readOnly;
  final String? helperText;
  final VoidCallback? onDoubleTap;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<RegisterGlassTextField> createState() => _RegisterGlassTextFieldState();
}

class _RegisterGlassTextFieldState extends State<RegisterGlassTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) {
      // Validate the entire form when this field loses focus
      if (!_focusNode.hasFocus) {
        Form.of(context).validate();
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasFocus = _focusNode.hasFocus;
    final interactive = widget.enabled && !widget.readOnly;

    final borderColor = hasFocus && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: interactive ? 0.1 : 0.05);
    final iconColor = hasFocus && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: interactive ? 0.65 : 0.4);

    final labelColor = hasFocus && interactive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: interactive ? 0.74 : 0.45);
    
    // Kích thước BorderRadius thống nhất
    const double borderRadius = 24;

    return GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: theme.textTheme.labelLarge?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ) ??
                TextStyle(color: labelColor),
            child: Text(widget.label),
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: interactive ? 1 : 0.85,
            child: Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? AppColors.darkGlassLayerGradient()
                    : AppColors.glassLayerGradient(),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: borderColor,
                  width: hasFocus && interactive ? 2.0 : 1.0,
                ),
                boxShadow: AppColors.subtleShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  // Xóa các ClipRRect và Padding không cần thiết bên trong
                  child: Padding(
                    padding: EdgeInsets.zero, // Giữ nguyên Padding.zero ở đây
                    child: TextFormField(
                      focusNode: _focusNode,
                      controller: widget.controller,
                      enabled: widget.enabled,
                      readOnly: widget.readOnly,
                      inputFormatters: widget.inputFormatters,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      validator: widget.validator,
                      onChanged: widget.onChanged,
                      onEditingComplete: widget.onEditingComplete,
                      keyboardType: widget.keyboardType,
                      textInputAction: widget.textInputAction,
                      maxLines: widget.maxLines,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: widget.hint.isEmpty ? null : widget.hint,
                        helperText: widget.helperText,
                        helperMaxLines: 2,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: interactive ? 0.45 : 0.35),
                        ),
                        helperStyle: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        ),
                        prefixIcon: Icon(widget.icon, color: iconColor),
                        // **QUAN TRỌNG:** Điều chỉnh contentPadding để kiểm soát không gian bên trong
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, // Tăng padding ngang để tạo không gian
                          vertical: 18,
                        ).copyWith(left: 0), // PrefixIcon đã xử lý phần lề trái
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
