import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_stub_screen.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/brand_lockup.dart';

/// Halaman `01 Splash Screen`: menampilkan logo DepotTelur36 dengan elemen
/// dekoratif kuning telur sambil memuat status sesi lokal pengguna.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.minimumDuration = const Duration(milliseconds: 1200),
  });

  final Duration minimumDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _brandFade;
  late final Animation<double> _brandScale;
  late final Animation<double> _blobScale;
  bool _bootstrapStarted = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: AppTokens.entranceDuration,
    );
    _brandFade = CurvedAnimation(
      parent: _entranceController,
      curve: AppTokens.arrivalCurve,
    );
    _brandScale = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTokens.arrivalCurve,
      ),
    );
    _blobScale = Tween<double>(begin: 0.84, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: AppTokens.arrivalCurve,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceController.value = 1;
    } else if (_entranceController.status == AnimationStatus.dismissed) {
      _entranceController.forward();
    }

    if (!_bootstrapStarted) {
      _bootstrapStarted = true;
      _bootstrapSession();
    }
  }

  Future<void> _bootstrapSession() async {
    final auth = context.read<AuthViewModel>();
    await Future.wait<void>([
      auth.initialize(),
      if (widget.minimumDuration > Duration.zero)
        Future<void>.delayed(widget.minimumDuration),
    ]);
    if (!mounted) return;

    final session = auth.session;
    if (auth.status == AuthStatus.authenticated && session != null) {
      Navigator.of(context).pushReplacement(
        buildAuthRoute(RoleHomeStubScreen(initialSession: session)),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      buildAuthRoute(const WelcomeScreen()),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTokens.darkOnLightOverlay,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -110,
              right: -120,
              child: IgnorePointer(
                child: ScaleTransition(
                  scale: _blobScale,
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: const BoxDecoration(
                      color: AppColors.yolk,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -66,
              left: -110,
              child: IgnorePointer(
                child: ScaleTransition(
                  scale: _blobScale,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: const BoxDecoration(
                      color: AppColors.yolk,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _brandFade,
                  child: ScaleTransition(
                    scale: _brandScale,
                    child: const BrandLockup(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
