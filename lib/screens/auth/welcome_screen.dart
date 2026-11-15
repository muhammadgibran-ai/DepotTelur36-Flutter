import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/brand_lockup.dart';

/// Halaman `02 Welcome`: memperkenalkan identitas DepotTelur36 serta menyediakan
/// aksi utama menuju `Sign In` dan `Sign Up`.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheetController;
  late final Animation<double> _sheetFade;
  late final Animation<Offset> _sheetSlide;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      vsync: this,
      duration: AppTokens.entranceDuration,
    );
    _sheetFade = CurvedAnimation(
      parent: _sheetController,
      curve: AppTokens.arrivalCurve,
    );
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _sheetController,
        curve: AppTokens.arrivalCurve,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheetController.value = 1;
    } else if (_sheetController.status == AnimationStatus.dismissed) {
      _sheetController.forward();
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _openSignIn() {
    Navigator.of(context).push(
      buildAuthRoute(const SignInScreen(), slideUp: true),
    );
  }

  void _openSignUp() {
    Navigator.of(context).push(
      buildAuthRoute(const SignUpScreen(), slideUp: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTokens.darkOnLightOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 148),
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 24,
                            ),
                            child: BrandLockup(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: _sheetFade,
                    child: SlideTransition(
                      position: _sheetSlide,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppColors.yolk,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(AppTokens.sheetRadius),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Selamat Datang',
                                  style: AppTypography.heading(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Kelola penjualan kasir, stok telur & sembako, serta faktur supplier DepotTelur36 dalam satu aplikasi.',
                                  style: AppTypography.body(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TactilePillButton(
                                        label: 'Sign In',
                                        backgroundColor: AppColors.ink,
                                        foregroundColor: AppColors.surface,
                                        onPressed: _openSignIn,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TactilePillButton(
                                        label: 'Sign Up',
                                        backgroundColor: AppColors.surface,
                                        foregroundColor: AppColors.ink,
                                        onPressed: _openSignUp,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
    );
  }
}
