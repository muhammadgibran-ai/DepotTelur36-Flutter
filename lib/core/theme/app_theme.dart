import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Token warna resmi sistem desain DepotTelur36 (Vertue Yellow & Ink palette).
class AppColors {
  AppColors._();

  static const Color yolk = Color(0xFFFBB017);
  static const Color yolkPressed = Color(0xFFE59D0B);
  static const Color yolkSoft = Color(0xFFFEF3C7);
  static const Color ink = Color(0xFF121212);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceWarm = Color(0xFFFFFDF7);
  static const Color inputBg = Color(0xFFF3F4F6);
  static const Color textPrimary = Color(0xFF141414);
  static const Color textSecondary = Color(0xFF525866);
  static const Color borderSubtle = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF166534);
  static const Color successBg = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFF92400E);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFF991B1B);
  static const Color dangerBg = Color(0xFFFEE2E2);
}

/// Token radius dan durasi animasi standar agar ritme UI konsisten.
class AppTokens {
  AppTokens._();

  static const double sheetRadius = 34;
  static const double inputRadius = 24;
  static const double badgeRadius = 20;
  static const double cardRadius = 20;
  static const double pillRadius = 999;

  static const Duration microDuration = Duration(milliseconds: 120);
  static const Duration stateDuration = Duration(milliseconds: 200);
  static const Duration routeDuration = Duration(milliseconds: 280);
  static const Duration entranceDuration = Duration(milliseconds: 420);

  static const Curve arrivalCurve = Cubic(0.16, 1, 0.3, 1);

  static const SystemUiOverlayStyle darkOnYellowOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle darkOnLightOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );
}

/// Pembantu tipografi yang memadukan `Rubik` (judul & CTA) dan `Nunito Sans` (teks).
class AppTypography {
  AppTypography._();

  static TextStyle heading({
    double fontSize = 30,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.ink,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.rubik(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle body({
    double fontSize = 15,
    FontWeight fontWeight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.nunitoSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: AppColors.surface,
      secondary: AppColors.yolk,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.danger,
      onError: AppColors.surface,
      outline: AppColors.borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.ink,
        selectionColor: AppColors.yolkSoft,
        selectionHandleColor: AppColors.ink,
      ),
      textTheme: TextTheme(
        headlineLarge: AppTypography.heading(fontSize: 30),
        headlineMedium: AppTypography.heading(fontSize: 24),
        titleLarge: AppTypography.heading(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: AppTypography.body(fontSize: 15),
        bodyMedium: AppTypography.body(fontSize: 14, color: AppColors.textSecondary),
        labelLarge: AppTypography.heading(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppTypography.body(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Membuat rute transisi halus yang menghormati pengaturan Reduce Motion sistem.
PageRoute<T> buildAuthRoute<T>(
  Widget page, {
  bool slideUp = false,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: AppTokens.routeDuration,
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final disableMotion = MediaQuery.disableAnimationsOf(context);
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppTokens.arrivalCurve,
        reverseCurve: Curves.easeIn,
      );
      if (disableMotion) {
        return FadeTransition(opacity: curved, child: child);
      }
      final beginOffset =
          slideUp ? const Offset(0, 0.05) : const Offset(0.06, 0);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
