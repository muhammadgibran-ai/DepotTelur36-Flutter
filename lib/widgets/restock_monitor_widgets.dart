import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Filter chips Pendev `22 Stok Menipis`: `Kritis (≤ 10)`, `Pantauan (≤ 25)`, `Semua (N)`.
class RestockFilterChipBar extends StatelessWidget {
  const RestockFilterChipBar({
    super.key,
    required this.snapshot,
    required this.onSelected,
  });

  final RestockSummarySnapshot snapshot;
  final ValueChanged<StokMenipisFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    const filters = StokMenipisFilter.values;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _RestockFilterChip(
              filter: filters[i],
              label: snapshot.labelForFilter(filters[i]),
              selected: filters[i] == snapshot.filter,
              disableMotion: disableMotion,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(filters[i]);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _RestockFilterChip extends StatelessWidget {
  const _RestockFilterChip({
    required this.filter,
    required this.label,
    required this.selected,
    required this.disableMotion,
    required this.onTap,
  });

  final StokMenipisFilter filter;
  final String label;
  final bool selected;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter $label',
      child: TactilePressScale(
        pressedScale: 0.96,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('restock_filter_${filter.name}'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AnimatedContainer(
                duration:
                    disableMotion ? Duration.zero : AppTokens.stateDuration,
                curve: AppTokens.arrivalCurve,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.ink : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.ink : AppColors.borderSubtle,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: AppTypography.body(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.surface
                          : AppColors.textPrimary,
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

/// Kartu item kritis (`stok <= 10`) sesuai Pendev `22 Stok Menipis` (`LowStockItemCard`).
class RestockLowStockItemCard extends StatelessWidget {
  const RestockLowStockItemCard({
    super.key,
    required this.item,
    required this.lowThreshold,
    required this.onAdjustQty,
    required this.onCreateFaktur,
  });

  final RestockMonitorItem item;
  final int lowThreshold;
  final ValueChanged<int> onAdjustQty;
  final VoidCallback onCreateFaktur;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final barang = item.barang;
    final isEmpty = item.alertLevel == StockAlertLevel.habis;
    final supplierSuffix = (item.lastSupplierName ?? '').trim().isNotEmpty
        ? ' · ${item.lastSupplierName}'
        : '';

    return Container(
      key: ValueKey('restock_critical_card_${barang.remoteId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFCA5A5).withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BarangThumbnail(barang: barang, size: 46, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      barang.namaBarang,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}$supplierSuffix',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedBadgePop(
                visible: true,
                badgeKey: ValueKey('badge_${barang.remoteId}_${item.alertLevel.name}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isEmpty ? AppColors.danger : Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    item.alertLevel.label,
                    style: AppTypography.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isEmpty ? Colors.white : AppColors.danger,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Sisa Stok: ${barang.stokBarang} ${barang.satuan}',
                style: AppTypography.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              Text(
                'Batas min: $lowThreshold ${barang.satuan}',
                style: AppTypography.body(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              width: double.infinity,
              color: const Color(0xFFFECACA),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: item.meterRatio),
                  duration: disableMotion
                      ? Duration.zero
                      : AppTokens.routeDuration,
                  curve: AppTokens.arrivalCurve,
                  builder: (context, ratio, _) {
                    return FractionallySizedBox(
                      widthFactor: ratio.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 310 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.25;

              final hintStepper = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Saran restok +${item.draftQty} ${barang.satuan} ke faktur',
                    style: AppTypography.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniQtyButton(
                        key: ValueKey('restock_dec_${barang.remoteId}'),
                        icon: Icons.remove_rounded,
                        tooltip: 'Kurangi jumlah saran restok',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onAdjustQty(-1);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedQtyText(
                          qty: item.draftQty,
                          style: AppTypography.heading(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      _MiniQtyButton(
                        key: ValueKey('restock_inc_${barang.remoteId}'),
                        icon: Icons.add_rounded,
                        tooltip: 'Tambah jumlah saran restok',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onAdjustQty(1);
                        },
                      ),
                    ],
                  ),
                ],
              );

              final ctaBtn = Semantics(
                button: true,
                label: 'Buat Faktur untuk ${barang.namaBarang}',
                child: TactilePressScale(
                  pressedScale: 0.95,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: FilledButton.icon(
                      key: ValueKey('restock_create_faktur_${barang.remoteId}'),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        onCreateFaktur();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.note_add_rounded, size: 17),
                      label: const Text(
                        'Buat Faktur',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hintStepper,
                    const SizedBox(height: 10),
                    ctaBtn,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: hintStepper),
                  const SizedBox(width: 10),
                  ctaBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniQtyButton extends StatelessWidget {
  const _MiniQtyButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: TactilePressScale(
          pressedScale: 0.9,
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Icon(icon, size: 17, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu daftar pantauan stok lainnya (`11..25`) atau stok aman (`> 25`) sesuai Pendev `22`.
class RestockWatchListCard extends StatelessWidget {
  const RestockWatchListCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.onQuickFaktur,
    this.isSafeList = false,
  });

  final String title;
  final String subtitle;
  final List<RestockMonitorItem> items;
  final ValueChanged<RestockMonitorItem> onQuickFaktur;
  final bool isSafeList;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  title,
                  style: AppTypography.heading(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTypography.body(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSubtle,
              ),
            _WatchRow(
              item: items[i],
              isSafe: isSafeList,
              onQuickFaktur: () => onQuickFaktur(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.item,
    required this.isSafe,
    required this.onQuickFaktur,
  });

  final RestockMonitorItem item;
  final bool isSafe;
  final VoidCallback onQuickFaktur;

  @override
  Widget build(BuildContext context) {
    final barang = item.barang;
    final chipBg = isSafe ? AppColors.successBg : AppColors.yolkSoft;
    final chipFg = isSafe ? AppColors.success : AppColors.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BarangThumbnail(barang: barang, size: 42, radius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barang.namaBarang,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.heading(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${barang.stokBarang} ${barang.satuan}',
              style: AppTypography.body(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: chipFg,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Buat faktur restock ${barang.namaBarang}',
            child: Tooltip(
              message: 'Buat faktur (+${item.suggestedQty})',
              child: TactilePressScale(
                pressedScale: 0.92,
                child: Material(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    key: ValueKey('restock_quick_faktur_${barang.remoteId}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onQuickFaktur();
                    },
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.note_add_outlined,
                        size: 20,
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

/// Kartu tenang ketika tidak ada barang pada zona stok tertentu.
class RestockEmptyCriticalCard extends StatelessWidget {
  const RestockEmptyCriticalCard({
    super.key,
    required this.threshold,
    this.titleOverride,
    this.subtitleOverride,
  });

  final int threshold;
  final String? titleOverride;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.successBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleOverride ?? 'Tidak ada stok kritis',
                  style: AppTypography.heading(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleOverride ??
                      'Seluruh barang saat ini berada di atas batas minimum $threshold unit.',
                  style: AppTypography.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
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

/// Kartu ringkas di Beranda untuk langsung membuka layar Pemantauan & Aksi Restok (`22`).
class RestockMonitorEntryBanner extends StatelessWidget {
  const RestockMonitorEntryBanner({
    super.key,
    required this.criticalCount,
    required this.watchCount,
    required this.onTap,
  });

  final int criticalCount;
  final int watchCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCritical = criticalCount > 0;
    return Semantics(
      button: true,
      label:
          'Buka Pemantauan dan Aksi Restok, $criticalCount kritis, $watchCount pantauan',
      child: TactilePressScale(
        pressedScale: 0.98,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const ValueKey('home_open_restock_monitor_btn'),
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasCritical
                      ? AppColors.yolkPressed
                      : AppColors.borderSubtle,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: hasCritical
                          ? AppColors.warningBg
                          : AppColors.inputBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.inventory_rounded,
                      size: 18,
                      color: hasCritical ? AppColors.warning : AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pemantauan & Aksi Restok',
                          style: AppTypography.heading(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '$criticalCount kritis (≤ 10) · $watchCount pantauan (≤ 25)',
                          style: AppTypography.body(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.ink,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
