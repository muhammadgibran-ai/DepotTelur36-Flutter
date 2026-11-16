import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/viewmodels/rekap_omzet_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

const Color _omzetGoldAccent = Color(0xFFFFB511);

/// Deretan tombol periode segmen (`Hari Ini`, `7 Hari`, `Bulan Ini`) sesuai Pendev `20`.
class RekapPeriodSegmentedBar extends StatelessWidget {
  const RekapPeriodSegmentedBar({
    super.key,
    required this.selectedPeriod,
    required this.onSelected,
  });

  final RekapOmzetPeriod selectedPeriod;
  final ValueChanged<RekapOmzetPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    const periods = RekapOmzetPeriod.values;

    return Row(
      children: [
        for (var i = 0; i < periods.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _PeriodSegmentChip(
              period: periods[i],
              selected: periods[i] == selectedPeriod,
              disableMotion: disableMotion,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(periods[i]);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _PeriodSegmentChip extends StatelessWidget {
  const _PeriodSegmentChip({
    required this.period,
    required this.selected,
    required this.disableMotion,
    required this.onTap,
  });

  final RekapOmzetPeriod period;
  final bool selected;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter periode ${period.label}',
      child: TactilePressScale(
        pressedScale: 0.96,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('rekap_period_${period.name}'),
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AnimatedContainer(
                duration:
                    disableMotion ? Duration.zero : AppTokens.stateDuration,
                curve: AppTokens.arrivalCurve,
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      period.label,
                      maxLines: 1,
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
      ),
    );
  }
}

/// Kartu hero ringkasan omzet nota, belanja faktur, dan total unit terjual (`20`).
class OmzetHeroCard extends StatelessWidget {
  const OmzetHeroCard({
    super.key,
    required this.report,
  });

  final OmzetSummaryReport report;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final compactScale = MediaQuery.textScalerOf(context).scale(1) > 1.2;

    return Container(
      key: const ValueKey('rekap_omzet_hero_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runAlignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Total Penjualan Nota',
                style: AppTypography.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFD1D5DB),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF27272A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_rounded,
                      size: 12,
                      color: _omzetGoldAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Khusus Owner',
                      style: AppTypography.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _omzetGoldAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedRupiahCounter(
              amount: report.totalPenjualanNota,
              style: AppTypography.heading(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
            child: Align(
              key: ValueKey(
                '${report.period.name}_${report.notaCount}_${report.periodRangeLabel}',
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                '${report.notaCount} Nota penjualan tercatat · ${report.periodRangeLabel}',
                style: AppTypography.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F23),
              borderRadius: BorderRadius.circular(14),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackVertically =
                    constraints.maxWidth < 250 && compactScale;
                final fakturKpi = _HeroSubKpi(
                  label: 'Belanja Faktur',
                  valueWidget: AnimatedRupiahCounter(
                    amount: report.belanjaFaktur,
                    style: AppTypography.heading(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: '${report.fakturCount} Faktur masuk',
                );
                final unitKpi = _HeroSubKpi(
                  label: 'Unit Terjual',
                  valueWidget: _AnimatedUnitCounter(
                    units: report.unitTerjual,
                    disableMotion: disableMotion,
                    style: AppTypography.heading(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _omzetGoldAccent,
                    ),
                  ),
                  subtitle: '${report.jenisProdukTerjual} jenis produk',
                );

                if (stackVertically) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      fakturKpi,
                      const Divider(
                        color: Color(0xFF323238),
                        height: 16,
                      ),
                      unitKpi,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fakturKpi),
                    const SizedBox(width: 12),
                    Expanded(child: unitKpi),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSubKpi extends StatelessWidget {
  const _HeroSubKpi({
    required this.label,
    required this.valueWidget,
    required this.subtitle,
  });

  final String label;
  final Widget valueWidget;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF9CA3AF),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: valueWidget,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.body(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

class _AnimatedUnitCounter extends StatelessWidget {
  const _AnimatedUnitCounter({
    required this.units,
    required this.disableMotion,
    required this.style,
  });

  final int units;
  final bool disableMotion;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (disableMotion) {
      return Text('$units Unit', style: style);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(end: units),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text('$value Unit', style: style);
      },
    );
  }
}

/// Grafik batang interaktif `Pemasukan 7 Hari Terakhir` (`Sen` s/d `Min`).
class OmzetTrendChartCard extends StatelessWidget {
  const OmzetTrendChartCard({
    super.key,
    required this.points,
    required this.rangeLabel,
    required this.selectedIndex,
    required this.onSelectBar,
  });

  final List<DailyOmzetBarPoint> points;
  final String rangeLabel;
  final int selectedIndex;
  final ValueChanged<int> onSelectBar;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    var maxOmzet = 0.0;
    for (final p in points) {
      if (p.totalOmzet > maxOmzet) maxOmzet = p.totalOmzet;
    }

    final safeIndex = points.isEmpty
        ? -1
        : selectedIndex.clamp(0, points.length - 1);
    final selectedPoint = safeIndex >= 0 ? points[safeIndex] : null;

    return Container(
      key: const ValueKey('rekap_trend_chart_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Pemasukan 7 Hari Terakhir',
                style: AppTypography.heading(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                rangeLabel,
                style: AppTypography.body(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (selectedPoint != null) ...[
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: disableMotion ? Duration.zero : AppTokens.microDuration,
              child: Container(
                key: ValueKey(
                  '${selectedPoint.isoDate}_${selectedPoint.totalOmzet}',
                ),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.yolkSoft),
                ),
                child: Text(
                  '${selectedPoint.dayShort}, ${selectedPoint.dateLabel} · '
                  '${formatRupiah(selectedPoint.totalOmzet)} '
                  '(${selectedPoint.notaCount} Nota)',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Belum ada data pemasukan 7 hari terakhir.',
                  style: AppTypography.body(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < points.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _ChartBarColumn(
                      index: i,
                      point: points[i],
                      maxOmzet: maxOmzet,
                      isSelected: i == safeIndex,
                      disableMotion: disableMotion,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelectBar(i);
                      },
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ChartBarColumn extends StatelessWidget {
  const _ChartBarColumn({
    required this.index,
    required this.point,
    required this.maxOmzet,
    required this.isSelected,
    required this.disableMotion,
    required this.onTap,
  });

  final int index;
  final DailyOmzetBarPoint point;
  final double maxOmzet;
  final bool isSelected;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio =
        maxOmzet > 0 ? (point.totalOmzet / maxOmzet).clamp(0.0, 1.0) : 0.0;
    final targetBarHeight = point.totalOmzet <= 0 ? 12.0 : 18.0 + (ratio * 50.0);
    final compactValue = formatCompactOmzetLabel(point.totalOmzet);

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          'Hari ${point.dayShort} ${point.dateLabel}, ${formatRupiah(point.totalOmzet)}, ${point.notaCount} nota',
      child: TactilePressScale(
        pressedScale: 0.94,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('rekap_chart_bar_$index'),
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 16,
                    child: Center(
                      child: AnimatedBadgePop(
                        visible: isSelected,
                        badgeKey: ValueKey(
                          'bar_val_${point.isoDate}_$compactValue',
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            compactValue,
                            style: AppTypography.body(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 70,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: disableMotion
                            ? Duration.zero
                            : AppTokens.routeDuration,
                        curve: AppTokens.arrivalCurve,
                        width: 24,
                        height: targetBarHeight,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.yolk
                              : AppColors.yolkSoft,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                            bottomLeft: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                          border: isSelected
                              ? Border.all(
                                  color: AppColors.yolkPressed,
                                  width: 1.2,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      point.dayShort,
                      style: AppTypography.body(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        color: isSelected
                            ? AppColors.ink
                            : AppColors.textSecondary,
                      ),
                    ),
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

/// Kartu daftar `Kontribusi Penjualan per Produk` sesuai Pendev `20 Rekap Omzet`.
class OmzetTopProductsCard extends StatelessWidget {
  const OmzetTopProductsCard({
    super.key,
    required this.products,
    required this.periodLabel,
    required this.expandedProductKey,
    required this.onToggleProduct,
  });

  final List<ProductSalesContribution> products;
  final String periodLabel;
  final String? expandedProductKey;
  final ValueChanged<String> onToggleProduct;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      key: const ValueKey('rekap_top_products_card'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Kontribusi Penjualan per Produk',
                style: AppTypography.heading(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (products.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${products.length} Produk',
                    style: AppTypography.body(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.analytics_outlined,
                      size: 32,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Belum ada penjualan produk untuk periode $periodLabel.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (var i = 0; i < products.length; i++)
              _ProductContributionRow(
                item: products[i],
                isLast: i == products.length - 1,
                isExpanded: products[i].productKey == expandedProductKey,
                disableMotion: disableMotion,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onToggleProduct(products[i].productKey);
                },
              ),
        ],
      ),
    );
  }
}

class _ProductContributionRow extends StatelessWidget {
  const _ProductContributionRow({
    required this.item,
    required this.isLast,
    required this.isExpanded,
    required this.disableMotion,
    required this.onTap,
  });

  final ProductSalesContribution item;
  final bool isLast;
  final bool isExpanded;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbBarang = item.barang ??
        Barang(
          idBarang: item.idBarang,
          namaBarang: item.namaBarang,
          stokBarang: 10,
          satuan: item.satuan,
          hargaSatuan: item.averagePricePerUnit,
          remoteId: item.productKey,
          updatedAt: DateTime(2026),
        );
    final pctLabel = (item.shareRatio * 100).toStringAsFixed(1);

    return Semantics(
      button: true,
      expanded: isExpanded,
      label:
          '${item.namaBarang}, ${item.totalQty} ${item.satuan} terjual, ${formatRupiah(item.totalRevenue)}',
      child: TactilePressScale(
        pressedScale: 0.98,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('rekap_product_row_${item.productKey}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.borderSubtle),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      BarangThumbnail(
                        barang: thumbBarang,
                        size: 40,
                        radius: 10,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.namaBarang,
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
                              '${item.totalQty} ${item.satuan} terjual · ${item.notaCount} Nota',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                height: 4,
                                width: double.infinity,
                                color: AppColors.inputBg,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween<double>(end: item.shareRatio),
                                    duration: disableMotion
                                        ? Duration.zero
                                        : AppTokens.routeDuration,
                                    curve: AppTokens.arrivalCurve,
                                    builder: (context, widthFactor, _) {
                                      return FractionallySizedBox(
                                        widthFactor: widthFactor.clamp(0.03, 1.0),
                                        child: Container(
                                          color: AppColors.yolk,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 118),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatRupiah(item.totalRevenue),
                            style: AppTypography.heading(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SoftAnimatedReveal(
                    visible: isExpanded,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, left: 50),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          'Porsi omzet: $pctLabel% · Rata-rata ${formatRupiah(item.averagePricePerUnit)}/${item.satuan}',
                          style: AppTypography.body(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
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

/// Bottom sheet pratinjau & ekspor laporan (`CSV` atau `Ringkasan Teks`).
class OmzetExportSheet extends StatefulWidget {
  const OmzetExportSheet({
    super.key,
    required this.viewModel,
  });

  final RekapOmzetViewModel viewModel;

  @override
  State<OmzetExportSheet> createState() => _OmzetExportSheetState();
}

class _OmzetExportSheetState extends State<OmzetExportSheet> {
  bool _copiedRecently = false;
  Timer? _copiedResetTimer;

  @override
  void dispose() {
    _copiedResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    final result = widget.viewModel.recordClipboardExport();
    if (result == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: result.content));
    } catch (_) {
      // Abaikan jika channel clipboard tidak tersedia di environment uji headless.
    }
    unawaited(HapticFeedback.mediumImpact());
    _copiedResetTimer?.cancel();
    if (!mounted) return;
    setState(() => _copiedRecently = true);
    _copiedResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedRecently = false);
      }
    });
  }

  Future<void> _handleSaveFile() async {
    HapticFeedback.lightImpact();
    await widget.viewModel.exportReportToFile();
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final sheetMaxHeight = MediaQuery.sizeOf(context).height * 0.86;

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final report = vm.report;
        final preview = vm.buildExportPreview();
        final feedback = vm.exportFeedback;
        final error = vm.exportError;

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: sheetMaxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ekspor Laporan Omzet',
                              style: AppTypography.heading(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${report.period.label} · ${report.periodRangeLabel}',
                              style: AppTypography.body(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Tutup dialog ekspor',
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (var i = 0; i < OmzetExportFormat.values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _ExportFormatChip(
                            format: OmzetExportFormat.values[i],
                            selected:
                                OmzetExportFormat.values[i] == vm.selectedExportFormat,
                            disableMotion: disableMotion,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              vm.selectExportFormat(OmzetExportFormat.values[i]);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 210),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: disableMotion
                            ? Duration.zero
                            : AppTokens.stateDuration,
                        child: SizedBox(
                          key: ValueKey(vm.selectedExportFormat),
                          width: double.infinity,
                          child: SelectableText(
                            preview,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.45,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SoftAnimatedReveal(
                    visible: error != null || feedback != null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: AuthFeedbackBanner(
                        errorMessage: error,
                        infoMessage: error == null ? feedback : null,
                        onDismiss: vm.clearExportMessages,
                      ),
                    ),
                  ),
                  if (vm.lastExportResult?.filePath != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Lokasi: ${vm.lastExportResult!.filePath}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final copyBtn = Semantics(
                        button: true,
                        label: 'Salin isi laporan ke clipboard',
                        child: TactilePressScale(
                          pressedScale: 0.96,
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              key: const ValueKey('rekap_export_copy_btn'),
                              onPressed: _handleCopy,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _copiedRecently
                                    ? AppColors.success
                                    : AppColors.ink,
                                backgroundColor: _copiedRecently
                                    ? AppColors.successBg
                                    : AppColors.surface,
                                side: BorderSide(
                                  color: _copiedRecently
                                      ? AppColors.success
                                      : AppColors.borderSubtle,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: AnimatedSwitcher(
                                duration: disableMotion
                                    ? Duration.zero
                                    : AppTokens.microDuration,
                                child: Icon(
                                  _copiedRecently
                                      ? Icons.check_circle_rounded
                                      : Icons.copy_rounded,
                                  key: ValueKey(_copiedRecently),
                                  size: 18,
                                ),
                              ),
                              label: AnimatedSwitcher(
                                duration: disableMotion
                                    ? Duration.zero
                                    : AppTokens.microDuration,
                                child: Text(
                                  _copiedRecently ? 'Tersalin!' : 'Salin Laporan',
                                  key: ValueKey(_copiedRecently),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );

                      final saveBtn = TactilePillButton(
                        key: const ValueKey('rekap_export_save_btn'),
                        label: 'Simpan File',
                        loadingLabel: 'Menyimpan...',
                        isLoading: vm.isExporting,
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.surface,
                        height: 48,
                        fontSize: 13.5,
                        onPressed: vm.isExporting ? null : _handleSaveFile,
                      );

                      if (constraints.maxWidth < 300) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            copyBtn,
                            const SizedBox(height: 8),
                            saveBtn,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: copyBtn),
                          const SizedBox(width: 10),
                          Expanded(child: saveBtn),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExportFormatChip extends StatelessWidget {
  const _ExportFormatChip({
    required this.format,
    required this.selected,
    required this.disableMotion,
    required this.onTap,
  });

  final OmzetExportFormat format;
  final bool selected;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Format ${format.label}',
      child: TactilePressScale(
        pressedScale: 0.96,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('rekap_export_format_${format.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: AnimatedContainer(
                duration:
                    disableMotion ? Duration.zero : AppTokens.stateDuration,
                curve: AppTokens.arrivalCurve,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected ? AppColors.yolkSoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.yolkPressed
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Center(
                  child: Text(
                    format.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
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
