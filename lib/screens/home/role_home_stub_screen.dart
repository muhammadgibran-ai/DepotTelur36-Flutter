import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';

/// Navigasi terpusat pasca-login menuju halaman tujuan sesuai peran [session].
void navigateToRoleHome(BuildContext context, AuthSession session) {
  Navigator.of(context).pushAndRemoveUntil(
    buildAuthRoute(RoleHomeStubScreen(initialSession: session)),
    (route) => false,
  );
}

/// Halaman tujuan sementara setelah login untuk memverifikasi alur RBAC
/// (Owner vs Kasir/Gudang) serta fitur Sign Out sebelum modul beranda dibangun.
class RoleHomeStubScreen extends StatelessWidget {
  const RoleHomeStubScreen({
    super.key,
    required this.initialSession,
  });

  final AuthSession initialSession;

  String _providerLabel(AuthProviderType provider) {
    switch (provider) {
      case AuthProviderType.emailPassword:
        return 'Email & Password';
      case AuthProviderType.google:
        return 'Google';
      case AuthProviderType.offlineLocal:
        return 'Lokal Offline';
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final auth = context.read<AuthViewModel>();
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      buildAuthRoute(const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final session = auth.session ?? initialSession;
    final isOwner = session.role == UserRole.owner;
    final headerTitle = isOwner ? 'DepotTelur36 Owner' : 'DepotTelur36 Kasir';
    final roleBadgeLabel = isOwner ? 'Owner' : 'Kasir & Gudang';

    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.yolk,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(AppTokens.sheetRadius),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerTitle,
                            style: AppTypography.heading(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isOwner
                                ? 'Kelola omzet, harga jual, master data, dan operasional toko DepotTelur36.'
                                : 'Catat transaksi kasir, faktur supplier, dan pantau stok harian DepotTelur36.',
                            style: AppTypography.body(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.yolk,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.pillRadius,
                                ),
                              ),
                              child: Text(
                                roleBadgeLabel,
                                style: AppTypography.body(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Halo, ${session.displayName}',
                              style: AppTypography.heading(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.surface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sesi aktif siap digunakan untuk fitur operasional DepotTelur36 berikutnya.',
                              style: AppTypography.body(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w400,
                                color: AppColors.yolkSoft,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            _SessionInfoRow(
                              label: 'Email',
                              value: session.email.isEmpty ? '-' : session.email,
                            ),
                            const Divider(
                              height: 22,
                              color: AppColors.borderSubtle,
                            ),
                            _SessionInfoRow(
                              label: 'ID Akun',
                              value: session.accountId.isEmpty
                                  ? session.petugasRemoteId
                                  : session.accountId,
                            ),
                            const Divider(
                              height: 22,
                              color: AppColors.borderSubtle,
                            ),
                            _SessionInfoRow(
                              label: 'Metode Masuk',
                              value: _providerLabel(session.provider),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: TactilePillButton(
                      label: 'Sign Out',
                      loadingLabel: 'Keluar...',
                      isLoading: auth.isSubmitting,
                      onPressed: auth.isAnyBusy ? null : () => _handleSignOut(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionInfoRow extends StatelessWidget {
  const _SessionInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: AppTypography.body(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.body(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
