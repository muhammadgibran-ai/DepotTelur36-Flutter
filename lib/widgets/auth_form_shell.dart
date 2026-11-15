import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';

/// Menjalankan alur login Google bersama antara halaman Sign In dan Sign Up.
Future<void> runGoogleSignIn(
  BuildContext context, {
  required ValueChanged<AuthSession> onAuthenticated,
}) async {
  FocusScope.of(context).unfocus();
  final auth = context.read<AuthViewModel>();
  final success = await auth.signInWithGoogle();
  if (!context.mounted) return;
  final session = auth.session;
  if (success && session != null) {
    TextInput.finishAutofillContext();
    onAuthenticated(session);
  }
}

/// Kerangka layout bersama untuk halaman `03 Sign In` dan `04 Sign Up`:
/// header kuning melengkung di bagian atas dan lembar putih aman-keyboard di bawah.
class AuthFormShell extends StatefulWidget {
  const AuthFormShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.topActionLabel,
    required this.onTopActionPressed,
    required this.child,
    this.onBackPressed,
    this.canNavigateBack = true,
  });

  final String title;
  final String subtitle;
  final String topActionLabel;
  final VoidCallback onTopActionPressed;
  final VoidCallback? onBackPressed;
  final bool canNavigateBack;
  final Widget child;

  @override
  State<AuthFormShell> createState() => _AuthFormShellState();
}

class _AuthFormShellState extends State<AuthFormShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.entranceDuration,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: AppTokens.arrivalCurve,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppTokens.arrivalCurve,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (!widget.canNavigateBack) return;
    HapticFeedback.selectionClick();
    if (widget.onBackPressed != null) {
      widget.onBackPressed!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.canNavigateBack,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTokens.darkOnYellowOverlay,
        child: Scaffold(
        backgroundColor: AppColors.surface,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              // Latar atas kuning menjaga area top status bar saat overscroll bounce.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 160,
                child: ColoredBox(color: AppColors.yolk),
              ),
              SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: AppColors.yolk,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    onPressed: widget.canNavigateBack
                                        ? _handleBack
                                        : null,
                                    tooltip: 'Kembali',
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: AppColors.ink,
                                      size: 24,
                                    ),
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(48, 48),
                                      overlayColor: AppColors.ink
                                          .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: 'Pindah ke ${widget.topActionLabel}',
                                    child: InkWell(
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        widget.onTopActionPressed();
                                      },
                                      borderRadius: BorderRadius.circular(
                                        AppTokens.pillRadius,
                                      ),
                                      overlayColor: WidgetStatePropertyAll(
                                        AppColors.ink.withValues(alpha: 0.08),
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: 48,
                                          minHeight: 48,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          child: Center(
                                            child: Text(
                                              widget.topActionLabel,
                                              style: AppTypography.body(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: AppTypography.heading(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.ink,
                                        letterSpacing: -0.6,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.subtitle,
                                      style: AppTypography.body(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.ink,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: AppColors.yolk,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppTokens.sheetRadius),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: FadeTransition(
                            opacity: _fade,
                            child: SlideTransition(
                              position: _slide,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Teks footer interaktif di bagian bawah form (`Belum punya akun? Sign Up`)
/// dengan area sentuh minimal 48dp pada tautan aksinya.
class AuthFooterSwitch extends StatelessWidget {
  const AuthFooterSwitch({
    super.key,
    required this.prompt,
    required this.actionLabel,
    required this.onPressed,
    this.isEnabled = true,
  });

  final String prompt;
  final String actionLabel;
  final VoidCallback onPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$prompt ',
            style: AppTypography.body(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
            ),
          ),
          Semantics(
            button: true,
            enabled: isEnabled,
            label: '$prompt $actionLabel',
            child: InkWell(
              onTap: isEnabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onPressed();
                    }
                  : null,
              borderRadius: BorderRadius.circular(12),
              overlayColor: WidgetStatePropertyAll(
                AppColors.ink.withValues(alpha: 0.06),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      actionLabel,
                      style: AppTypography.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
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
