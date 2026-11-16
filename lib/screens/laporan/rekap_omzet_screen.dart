import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/viewmodels/rekap_omzet_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/rekap_omzet_widgets.dart';

/// Layar standalone Pendev `20 Rekap Omzet` (khusus Owner) beserta aksi Ekspor.
class RekapOmzetScreen extends StatelessWidget {
  const RekapOmzetScreen({
    super.key,
    required this.viewModel,
    this.onRefreshRequested,
  });

  final RekapOmzetViewModel viewModel;
  final Future<void> Function()? onRefreshRequested;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: RekapOmzetView(
        viewModel: viewModel,
        embedded: false,
        onRefreshRequested: onRefreshRequested,
      ),
    );
  }
}

/// Konten terpadu Pendev `20 Rekap Omzet` untuk tab `Omzet` Owner maupun layar penuh.
class RekapOmzetView extends StatelessWidget {
  const RekapOmzetView({
    super.key,
    required this.viewModel,
    this.embedded = true,
    this.onBackPressed,
    this.onRefreshRequested,
  });

  final RekapOmzetViewModel viewModel;
  final bool embedded;
  final VoidCallback? onBackPressed;
  final Future<void> Function()? onRefreshRequested;

  void _openExportSheet(BuildContext context) {
    if (!viewModel.isAuthorized) return;
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => OmzetExportSheet(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (!viewModel.isAuthorized) {
          return Column(
            children: [
              MasterAmberHeader(
                title: 'Rekap Omzet',
                subtitle: 'Akses terbatas khusus Owner',
                showBackButton: true,
                backKey: const ValueKey('rekap_omzet_back_btn'),
                onBack: onBackPressed,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (constraints.maxHeight - 40).clamp(
                            0.0,
                            double.infinity,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            key: const ValueKey('rekap_omzet_rbac_locked'),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.borderSubtle),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 36,
                                  color: AppColors.danger,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Akses Ditolak (Khusus Owner)',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.heading(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Laporan Rekap Omzet dan Ekspor hanya dapat dibuka oleh akun Owner DepotTelur36.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.body(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        final report = viewModel.report;
        final bottomPadding =
            embedded ? 112.0 : MediaQuery.paddingOf(context).bottom + 24;

        return Column(
          children: [
            MasterAmberHeader(
              title: 'Rekap Omzet',
              subtitle: 'Ringkasan nota & faktur toko',
              showBackButton: true,
              backKey: const ValueKey('rekap_omzet_back_btn'),
              onBack: onBackPressed,
              actionLabel: 'Ekspor',
              actionIcon: Icons.description_outlined,
              actionKey: const ValueKey('rekap_omzet_export_btn'),
              onAction: () => _openExportSheet(context),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.ink,
                backgroundColor: AppColors.surface,
                onRefresh: () async {
                  await viewModel.loadData();
                  await onRefreshRequested?.call();
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
                  children: [
                    RekapPeriodSegmentedBar(
                      selectedPeriod: viewModel.period,
                      onSelected: viewModel.selectPeriod,
                    ),
                    if (viewModel.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      AuthFeedbackBanner(
                        errorMessage: viewModel.errorMessage,
                        onDismiss: () => viewModel.loadData(silent: true),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (viewModel.isLoading &&
                        viewModel.notas.isEmpty &&
                        viewModel.fakturs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.ink,
                          ),
                        ),
                      )
                    else
                      AnimatedSwitcher(
                        duration: disableMotion
                            ? Duration.zero
                            : AppTokens.stateDuration,
                        child: Column(
                          key: ValueKey<RekapOmzetPeriod>(report.period),
                          children: [
                            OmzetHeroCard(report: report),
                            const SizedBox(height: 12),
                            OmzetTrendChartCard(
                              points: report.weeklyTrend,
                              rangeLabel: report.weeklyRangeLabel,
                              selectedIndex: viewModel.selectedBarIndex,
                              onSelectBar: viewModel.selectChartBar,
                            ),
                            const SizedBox(height: 12),
                            OmzetTopProductsCard(
                              products: report.topProducts,
                              periodLabel: report.period.label,
                              expandedProductKey: viewModel.expandedProductKey,
                              onToggleProduct: viewModel.toggleProductDetail,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
