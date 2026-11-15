import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_stub_screen.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/auth_form_shell.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';

/// Halaman `04 Sign Up`: pendaftaran akun baru DepotTelur36 dengan peran bawaan
/// Kasir/Gudang (`PETUGAS`), atau mempertahankan peran `OWNER` jika email cocok.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final FocusNode _fullNameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _confirmPasswordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _fullNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;

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
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  void _clearFeedbackIfNeeded(AuthViewModel auth) {
    if (auth.errorMessage != null || auth.infoMessage != null) {
      auth.clearFeedback();
    }
  }

  Future<void> _handleSignUp() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthViewModel>();
    final fullName = _fullNameController.text;
    final email = _emailController.text;
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    final nameError = AuthRepository.validateSignUpFullName(fullName);
    final emailError = AuthRepository.validateSignUpEmail(email);
    final pwError = AuthRepository.validateNewPassword(password);
    final confirmError = AuthRepository.validateConfirmPassword(
      password,
      confirmPassword,
    );

    if (nameError != null ||
        emailError != null ||
        pwError != null ||
        confirmError != null) {
      HapticFeedback.mediumImpact();
      setState(() {
        _fullNameError = nameError;
        _emailError = emailError;
        _passwordError = pwError;
        _confirmPasswordError = confirmError;
      });
      auth.registerValidationFailure(
        nameError ?? emailError ?? pwError ?? confirmError,
      );
      return;
    }

    setState(() {
      _fullNameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });

    final success = await auth.signUp(
      fullName: fullName,
      email: email,
      password: password,
      confirmPassword: confirmPassword,
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

  void _switchToSignIn() {
    Navigator.of(context).pushReplacement(
      buildAuthRoute(const SignInScreen(), slideUp: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();

    return AuthFormShell(
      title: 'Sign Up',
      subtitle:
          'Buat akun untuk mengelola penjualan kasir, faktur masuk, dan stok toko DepotTelur36.',
      topActionLabel: 'Sign In',
      canNavigateBack: !auth.isAnyBusy,
      onTopActionPressed: auth.isAnyBusy ? () {} : _switchToSignIn,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AuthFeedbackBanner(
              errorMessage: auth.errorMessage,
              infoMessage: auth.infoMessage,
              onDismiss: auth.clearFeedback,
            ),
            AutofillGroup(
              child: ShakeOnError(
                pulse: auth.errorPulse,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AuthTextField(
                      controller: _fullNameController,
                      focusNode: _fullNameFocus,
                      hintText: 'Nama Lengkap',
                      trailingIcon: Icons.person_rounded,
                      height: 50,
                      errorText: _fullNameError,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      onChanged: (_) {
                        if (_fullNameError != null) {
                          setState(() => _fullNameError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) => _emailFocus.requestFocus(),
                    ),
                    const SizedBox(height: 10),
                    AuthTextField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      hintText: 'Email',
                      trailingIcon: Icons.mail_rounded,
                      height: 50,
                      errorText: _emailError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      onChanged: (_) {
                        if (_emailError != null) {
                          setState(() => _emailError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 10),
                    AuthTextField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      hintText: 'Password',
                      trailingIcon: Icons.lock_outline_rounded,
                      height: 50,
                      isPasswordField: true,
                      obscureText: _obscurePassword,
                      onToggleObscure: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      errorText: _passwordError,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 10),
                    AuthTextField(
                      controller: _confirmPasswordController,
                      focusNode: _confirmPasswordFocus,
                      hintText: 'Konfirmasi Password',
                      trailingIcon: Icons.lock_outline_rounded,
                      height: 50,
                      isPasswordField: true,
                      obscureText: _obscureConfirmPassword,
                      onToggleObscure: () {
                        setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        );
                      },
                      errorText: _confirmPasswordError,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onChanged: (_) {
                        if (_confirmPasswordError != null) {
                          setState(() => _confirmPasswordError = null);
                        }
                        _clearFeedbackIfNeeded(auth);
                      },
                      onSubmitted: (_) {
                        if (!auth.isAnyBusy) {
                          _handleSignUp();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            TactilePillButton(
              label: 'Sign Up',
              loadingLabel: 'Mendaftarkan akun...',
              height: 52,
              isLoading: auth.isSubmitting,
              onPressed: auth.isAnyBusy ? null : _handleSignUp,
            ),
            const SizedBox(height: 16),
            const AuthOrDivider(),
            const SizedBox(height: 16),
            GoogleAuthButton(
              height: 54,
              isLoading: auth.isGoogleLoading,
              onPressed: auth.isAnyBusy
                  ? null
                  : () => runGoogleSignIn(
                        context,
                        onAuthenticated: (session) =>
                            navigateToRoleHome(context, session),
                      ),
            ),
            const SizedBox(height: 12),
            AuthFooterSwitch(
              prompt: 'Sudah punya akun?',
              actionLabel: 'Sign In',
              isEnabled: !auth.isAnyBusy,
              onPressed: _switchToSignIn,
            ),
          ],
        ),
      ),
    );
  }
}
