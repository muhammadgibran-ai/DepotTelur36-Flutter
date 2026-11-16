import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/viewmodels/restock_monitor_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/restock_monitor_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Layar Pendev `22 Stok Menipis` untuk pemantauan stok kritis/pantauan & aksi restok cepat.
class StokMenipisScreen extends StatelessWidget {
  const StokMenipisScreen({
    super.key,
    required this.viewModel,
    required this.onStartRestockFaktur,
    required this.onOpenEmptyFaktur,
    this.onRefreshRequested,
  });

  final RestockMonitorViewModel viewModel;
  final ValueChanged<RestockMonitorItem> onStartRestockFaktur;
  final VoidCallback onOpenEmptyFaktur;
  final Future<void> Function()? onRefreshRequested;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final snap = viewModel.snapshot;
          final error = viewModel.errorMessage;

          return Column(
            children: [
              MasterAmberHeader(
                title: 'Stok Menipis',
                subtitle: 'Barang dengan stok ≤ ${snap.lowThreshold} unit',
                showBackButton: true,
                backKey: const ValueKey('stok_menipis_back_btn'),
                actionLabel: '+ Faktur',
                actionIcon: Icons.note_add_outlined,
                actionKey: const ValueKey('stok_menipis_new_faktur_btn'),
                onAction: () {
                  HapticFeedback.selectionClick();
                  onOpenEmptyFaktur();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: RestockFilterChipBar(
                  snapshot: snap,
                  onSelected: viewModel.selectFilter,
                ),
              ),
              ShakeOnError(
                pulse: viewModel.errorShakePulse,
                child: SoftAnimatedReveal(
                  visible: error != null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: AuthFeedbackBanner(
                      errorMessage: error,
                      onDismiss: viewModel.clearError,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.ink,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async {
                    await viewModel.loadData();
                    await onRefreshRequested?.call();
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    child: viewModel.isLoading && viewModel.barangs.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 48),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.ink,
                              ),
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: disableMotion
                                ? Duration.zero
                                : AppTokens.stateDuration,
                            child: _FilteredSectionsBody(
                              key: ValueKey<StokMenipisFilter>(snap.filter),
                              snapshot: snap,
                              onAdjustQty: (item, delta) =>
                                  viewModel.adjustDraftQty(item.barang, delta),
                              onCreateFaktur: onStartRestockFaktur,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilteredSectionsBody extends StatelessWidget {
  const _FilteredSectionsBody({
    super.key,
    required this.snapshot,
    required this.onAdjustQty,
    required this.onCreateFaktur,
  });

  final RestockSummarySnapshot snapshot;
  final void Function(RestockMonitorItem item, int delta) onAdjustQty;
  final ValueChanged<RestockMonitorItem> onCreateFaktur;

  @override
  Widget build(BuildContext context) {
    final filter = snapshot.filter;
    final watchPreviewItems = filter == StokMenipisFilter.kritis
        ? snapshot.watchOnlyItems.take(2).toList(growable: false)
        : snapshot.watchOnlyItems;
    final showWatchFirst = filter == StokMenipisFilter.pantauan;
    final showCritical = snapshot.criticalItems.isNotEmpty ||
        filter == StokMenipisFilter.kritis ||
        (filter == StokMenipisFilter.semua &&
            snapshot.watchOnlyItems.isEmpty &&
            snapshot.safeItems.isEmpty);
    final showWatch = watchPreviewItems.isNotEmpty ||
        (filter == StokMenipisFilter.pantauan &&
            snapshot.criticalItems.isEmpty);
    final showSafe =
        filter == StokMenipisFilter.semua && snapshot.safeItems.isNotEmpty;

    Widget buildCriticalSection() {
      if (snapshot.criticalItems.isEmpty) {
        return RestockEmptyCriticalCard(threshold: snapshot.lowThreshold);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < snapshot.criticalItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            RestockLowStockItemCard(
              item: snapshot.criticalItems[i],
              lowThreshold: snapshot.lowThreshold,
              onAdjustQty: (delta) =>
                  onAdjustQty(snapshot.criticalItems[i], delta),
              onCreateFaktur: () => onCreateFaktur(snapshot.criticalItems[i]),
            ),
          ],
        ],
      );
    }

    Widget buildWatchSection() {
      if (watchPreviewItems.isEmpty) {
        return RestockEmptyCriticalCard(
          threshold: snapshot.watchThreshold,
          titleOverride: 'Belum ada stok di zona pantauan',
          subtitleOverride:
              'Tidak ada barang dengan stok antara ${snapshot.lowThreshold + 1}–${snapshot.watchThreshold} unit.',
        );
      }
      return RestockWatchListCard(
        title: filter == StokMenipisFilter.pantauan
            ? 'Pantauan Stok (${snapshot.lowThreshold + 1}–${snapshot.watchThreshold})'
            : 'Pantauan Stok Lainnya',
        subtitle: 'Di atas batas ${snapshot.lowThreshold}',
        items: watchPreviewItems,
        onQuickFaktur: onCreateFaktur,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showWatchFirst) ...[
          if (showWatch) buildWatchSection(),
          if (snapshot.criticalItems.isNotEmpty) ...[
            if (showWatch) const SizedBox(height: 12),
            buildCriticalSection(),
          ],
        ] else ...[
          if (showCritical) buildCriticalSection(),
          if (showWatch) ...[
            if (showCritical) const SizedBox(height: 12),
            buildWatchSection(),
          ],
          if (showSafe) ...[
            const SizedBox(height: 12),
            RestockWatchListCard(
              title: 'Stok Aman (> ${snapshot.watchThreshold})',
              subtitle: 'Tersedia di gudang',
              items: snapshot.safeItems,
              isSafeList: true,
              onQuickFaktur: onCreateFaktur,
            ),
          ],
        ],
      ],
    );
  }
}
