import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/widgets/google_logo.dart';

/// Tombol pil taktil dengan micro-interaction skala ringan saat ditekan,
/// haptic feedback, dan transisi halus antara label idle dan loading.
class TactilePillButton extends StatefulWidget {
  const TactilePillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = AppColors.ink,
    this.foregroundColor = AppColors.surface,
    this.isLoading = false,
    this.loadingLabel = 'Memproses...',
    this.height = 54,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLoading;
  final String loadingLabel;
  final double height;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  @override
  State<TactilePillButton> createState() => _TactilePillButtonState();
}

class _TactilePillButtonState extends State<TactilePillButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool next) {
    if (!_enabled || _pressed == next) return;
    setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final effectiveBg = _enabled
        ? widget.backgroundColor
        : widget.backgroundColor.withValues(alpha: 0.72);

    return AnimatedScale(
      scale: (_pressed && !disableMotion) ? 0.975 : 1.0,
      duration: AppTokens.microDuration,
      curve: Curves.easeOut,
      child: Material(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(AppTokens.pillRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.pillRadius),
          onTap: _enabled
              ? () {
                  HapticFeedback.lightImpact();
                  widget.onPressed?.call();
                }
              : null,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.height,
              minWidth: 48,
            ),
            child: Padding(
              padding: widget.padding,
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppTokens.stateDuration,
                  child: widget.isLoading
                      ? Row(
                          key: const ValueKey('loading'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.foregroundColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.loadingLabel,
                                  maxLines: 1,
                                  style: AppTypography.heading(
                                    fontSize: widget.fontSize,
                                    fontWeight: FontWeight.w600,
                                    color: widget.foregroundColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : FittedBox(
                          key: ValueKey(widget.label),
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            style: AppTypography.heading(
                              fontSize: widget.fontSize,
                              fontWeight: FontWeight.w600,
                              color: widget.foregroundColor,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol "Continue with Google" yang sesuai mockup (`height 54-56`, border halus,
/// bayangan ringan, logo Google 4-warna, dan ikon panah lingkaran solid).
class GoogleAuthButton extends StatefulWidget {
  const GoogleAuthButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.height = 56,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;

  @override
  State<GoogleAuthButton> createState() => _GoogleAuthButtonState();
}

class _GoogleAuthButtonState extends State<GoogleAuthButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool next) {
    if (!_enabled || _pressed == next) return;
    setState(() => _pressed = next);
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedScale(
      scale: (_pressed && !disableMotion) ? 0.98 : 1.0,
      duration: AppTokens.microDuration,
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTokens.pillRadius),
          border: Border.all(
            color: _pressed ? AppColors.ink : AppColors.borderSubtle,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10000000),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppTokens.pillRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.pillRadius),
            onTap: _enabled
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onPressed?.call();
                  }
                : null,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.height,
                minWidth: 48,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GoogleLogo(size: 22),
                          const SizedBox(width: 12),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                widget.isLoading
                                    ? 'Menghubungkan Google...'
                                    : 'Continue with Google',
                                maxLines: 1,
                                style: AppTypography.heading(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedSwitcher(
                      duration: AppTokens.stateDuration,
                      child: widget.isLoading
                          ? const SizedBox(
                              key: ValueKey('google-spinner'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(AppColors.ink),
                              ),
                            )
                          : AnimatedSlide(
                              key: const ValueKey('google-arrow'),
                              offset: (_pressed && !disableMotion)
                                  ? const Offset(0.15, 0)
                                  : Offset.zero,
                              duration: AppTokens.microDuration,
                              child: const Icon(
                                Icons.arrow_circle_right,
                                size: 20,
                                color: AppColors.ink,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Input field khusus Auth dengan transisi fokus border, warna ikon adaptif,
/// animasi pesan error terstruktur, dan tombol toggle visibility >= 48x48dp.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.trailingIcon,
    this.errorText,
    this.obscureText = false,
    this.isPasswordField = false,
    this.onToggleObscure,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.height = 54,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData trailingIcon;
  final String? errorText;
  final bool obscureText;
  final bool isPasswordField;
  final VoidCallback? onToggleObscure;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final double height;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  late final FocusNode _internalFocusNode;
  bool _hasFocus = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
    _hasFocus = _effectiveFocusNode.hasFocus;
  }

  void _handleFocusChange() {
    if (!mounted) return;
    if (_hasFocus != _effectiveFocusNode.hasFocus) {
      setState(() => _hasFocus = _effectiveFocusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant AuthTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode)
          .removeListener(_handleFocusChange);
      _effectiveFocusNode.addListener(_handleFocusChange);
      _hasFocus = _effectiveFocusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final borderColor = hasError
        ? AppColors.danger
        : (_hasFocus ? AppColors.ink : Colors.transparent);
    final bgColor = _hasFocus ? AppColors.surface : AppColors.inputBg;
    final iconColor = hasError
        ? AppColors.danger
        : (_hasFocus ? AppColors.ink : AppColors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: AppTokens.stateDuration,
          curve: Curves.easeOut,
          constraints: BoxConstraints(minHeight: widget.height),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppTokens.inputRadius),
            border: Border.all(
              color: borderColor,
              width: (hasError || _hasFocus) ? 1.5 : 1.0,
            ),
            boxShadow: _hasFocus && !hasError
                ? const [
                    BoxShadow(
                      color: Color(0x1FFBB017),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.only(left: 20, right: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _effectiveFocusNode,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textInputAction,
                  textCapitalization: widget.textCapitalization,
                  autofillHints: widget.autofillHints,
                  scrollPadding: const EdgeInsets.only(bottom: 110),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  style: AppTypography.body(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: AppTypography.body(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (widget.isPasswordField && widget.onToggleObscure != null)
                Semantics(
                  button: true,
                  label: widget.obscureText
                      ? 'Tampilkan ${widget.hintText}'
                      : 'Sembunyikan ${widget.hintText}',
                  child: IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      widget.onToggleObscure?.call();
                    },
                    tooltip: widget.obscureText
                        ? 'Tampilkan password'
                        : 'Sembunyikan password',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        widget.obscureText
                            ? Icons.visibility_off
                            : Icons.visibility,
                        key: ValueKey(widget.obscureText),
                        size: 20,
                        color: iconColor,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Icon(
                      widget.trailingIcon,
                      size: 18,
                      color: iconColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppTokens.stateDuration,
          curve: Curves.easeOut,
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 6, left: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.errorText!,
                          style: AppTypography.body(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Micro-interaction getaran horizontal teredam saat validasi/login gagal.
class ShakeOnError extends StatefulWidget {
  const ShakeOnError({
    super.key,
    required this.pulse,
    required this.child,
  });

  final int pulse;
  final Widget child;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void didUpdateWidget(covariant ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse > oldWidget.pulse) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _controller.forward(from: 0);
      }
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final dx = t == 0 || t == 1
            ? 0.0
            : math.sin(t * math.pi * 4) * (1 - t) * 7.0;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Banner umpan balik autentikasi non-warna-saja (ikon + teks jelas + tombol tutup).
class AuthFeedbackBanner extends StatelessWidget {
  const AuthFeedbackBanner({
    super.key,
    this.errorMessage,
    this.infoMessage,
    this.onDismiss,
  });

  final String? errorMessage;
  final String? infoMessage;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final isError = errorMessage != null && errorMessage!.isNotEmpty;
    final text = isError ? errorMessage : infoMessage;
    final visible = text != null && text.isNotEmpty;

    return AnimatedSize(
      duration: AppTokens.stateDuration,
      curve: Curves.easeOut,
      child: !visible
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isError ? AppColors.dangerBg : AppColors.successBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isError ? AppColors.danger : AppColors.success,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    isError ? Icons.error : Icons.check_circle,
                    size: 18,
                    color: isError ? AppColors.danger : AppColors.success,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: AppTypography.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isError ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ),
                  if (onDismiss != null)
                    IconButton(
                      onPressed: onDismiss,
                      tooltip: 'Tutup pesan',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: isError ? AppColors.danger : AppColors.success,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Garis pemisah horizontal dengan label tengah (`Atau`).
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, this.label = 'Atau'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.borderSubtle,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: AppTypography.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: AppColors.borderSubtle,
          ),
        ),
      ],
    );
  }
}
