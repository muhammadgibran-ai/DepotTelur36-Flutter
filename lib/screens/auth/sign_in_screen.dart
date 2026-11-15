import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_shell_screen.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/auth_form_shell.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';

/// Halaman `03 Sign In`: login Hybrid Offline-First dengan `ID Akun atau Email`,
/// `Password`, lupa password, serta `Continue with Google`.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _identifierFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isForgotSheetOpen = false;
  String? _identifierError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AuthViewModel>().clearFeedback();
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _clearFeedbackIfNeeded(AuthViewModel auth) {
    if (auth.errorMessage != null || auth.infoMessage != null) {
      auth.clearFeedback();
    }
  }

  Future<void> _handleSignIn() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthViewModel>();
    final identifier = _identifierController.text;
    final password = _passwordController.text;

    final idError = AuthRepository.validateSignInIdentifier(identifier);
    final pwError = AuthRepository.validatePassword(password);

    if (idError != null || pwError != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _identifierError = idError;
        _passwordError = pwError;
      });
      auth.registerValidationFailure(idError ?? pwError);
      return;
    }

    setState(() {
      _identifierError = null;
      _passwordError = null;
    });

    final success = await auth.signIn(
      identifier: identifier,
      password: password,
    );
    if (!mounted) return;

    final session = auth.session;
    if (success && session != null) {
      HapticFeedback.lightImpact();
      TextInput.finishAutofillContext();
      navigateToRoleHome(context, session);
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _openForgotPasswordSheet() async {
    HapticFeedback.selectionClick();
    final auth = context.read<AuthViewModel>();
    auth.clearFeedback();
    setState(() => _isForgotSheetOpen = true);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ChangeNotifierProvider<AuthViewModel>.value(
          value: auth,
          child: _ForgotPasswordSheet(
            initialIdentifier: _identifierController.text.trim(),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _isForgotSheetOpen = false);
    // Jangan biarkan pesan error dari modal yang ditutup muncul di halaman Sign In.
    if (auth.infoMessage == null && auth.errorMessage != null) {
      auth.clearFeedback();
    }
  }

  void _switchToSignUp() {
    Navigator.of(context).pushReplacement(
      buildAuthRoute(const SignUpScreen(), slideUp: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return AuthFormShell(
      title: 'Sign In',
      subtitle:
          'Aplikasi kasir dan manajemen stok harian untuk operasional DepotTelur36.',
      topActionLabel: 'Sign Up',
      canNavigateBack: !auth.isAnyBusy,
      onTopActionPressed: auth.isAnyBusy ? () {} : _switchToSignUp,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthFeedbackBanner(
              errorMessage: _isForgotSheetOpen ? null : auth.errorMessage,
              infoMessage: _isForgotSheetOpen ? null : auth.infoMessage,
              onDismiss: auth.clearFeedback,
            ),
            AutofillGroup(
              child: ShakeOnError(
                pulse: auth.errorPulse,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthTextField(
                      controller: _identifierController,
                      focusNode: _identifierFocus,
                      hintText: 'ID Akun atau Email',
                      trailingIcon: Icons.person_rounded,
                      errorText: _identifierError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      onChanged: (_) {
                        if (_identifierError != null) {
                          setState(() => _identifierError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 14),
                    AuthTextField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      hintText: 'Password',
                      trailingIcon: Icons.lock_outline_rounded,
                      isPasswordField: true,
                      obscureText: _obscurePassword,
                      onToggleObscure: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      errorText: _passwordError,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) {
                        if (!auth.isAnyBusy) {
                          _handleSignIn();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: 'Lupa Password?',
                child: InkWell(
                  onTap: auth.isAnyBusy ? null : _openForgotPasswordSheet,
                  borderRadius: BorderRadius.circular(12),
                  overlayColor: WidgetStatePropertyAll(
                    AppColors.ink.withValues(alpha: 0.06),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          'Lupa Password?',
                          style: AppTypography.body(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TactilePillButton(
              label: 'Sign In',
              loadingLabel: 'Memeriksa akun...',
              isLoading: auth.isSubmitting,
              onPressed: auth.isAnyBusy ? null : _handleSignIn,
            ),
            const SizedBox(height: 20),
            const AuthOrDivider(),
            const SizedBox(height: 20),
            GoogleAuthButton(
              height: 56,
              isLoading: auth.isGoogleLoading,
              onPressed: auth.isAnyBusy
                  ? null
                  : () => runGoogleSignIn(
                        context,
                        onAuthenticated: (session) =>
                            navigateToRoleHome(context, session),
                      ),
            ),
            const SizedBox(height: 16),
            AuthFooterSwitch(
              prompt: 'Belum punya akun?',
              actionLabel: 'Sign Up',
              isEnabled: !auth.isAnyBusy,
              onPressed: _switchToSignUp,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({required this.initialIdentifier});

  final String initialIdentifier;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  late final TextEditingController _controller;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialIdentifier);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitReset() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthViewModel>();
    final idError = AuthRepository.validateSignInIdentifier(_controller.text);
    if (idError != null) {
      HapticFeedback.mediumImpact();
      setState(() => _fieldError = idError);
      return;
    }

    setState(() => _fieldError = null);
    final sentTo = await auth.sendPasswordReset(_controller.text);
    if (!mounted) return;
    if (sentTo != null) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.sheetRadius),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(AppTokens.pillRadius),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Reset Password',
                  style: AppTypography.heading(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Masukkan email atau ID Akun terdaftar untuk menerima tautan reset password.',
                  style: AppTypography.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                AuthFeedbackBanner(
                  errorMessage: auth.errorMessage,
                  onDismiss: auth.clearFeedback,
                ),
                AuthTextField(
                  controller: _controller,
                  hintText: 'ID Akun atau Email',
                  trailingIcon: Icons.mail_rounded,
                  errorText: _fieldError,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_fieldError != null) {
                      setState(() => _fieldError = null);
                    }
                    if (auth.errorMessage != null) {
                      auth.clearFeedback();
                    }
                  },
                  onSubmitted: (_) {
                    if (!auth.isResettingPassword) {
                      _submitReset();
                    }
                  },
                ),
                const SizedBox(height: 18),
                TactilePillButton(
                  label: 'Kirim Tautan Reset',
                  loadingLabel: 'Mengirim...',
                  isLoading: auth.isResettingPassword,
                  onPressed: auth.isResettingPassword ? null : _submitReset,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
