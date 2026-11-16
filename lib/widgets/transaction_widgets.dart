import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Penghitung nominal Rupiah beranimasi halus setiap subtotal atau grand total berubah.
class AnimatedRupiahCounter extends StatelessWidget {
  const AnimatedRupiahCounter({
    super.key,
    required this.amount,
    required this.style,
    this.textAlign,
  });

  final double amount;
  final TextStyle style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    if (disableMotion) {
      return Text(
        formatRupiah(amount),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: amount),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(
          formatRupiah(animatedValue.roundToDouble()),
          textAlign: textAlign,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// Angka kuantitas beranimasi roll halus setiap tombol +/- ditekan.
class AnimatedQtyText extends StatelessWidget {
  const AnimatedQtyText({
    super.key,
    required this.qty,
    this.style,
  });

  final int qty;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final resolvedStyle = style ??
        AppTypography.heading(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        );

    return AnimatedSwitcher(
      duration: disableMotion ? Duration.zero : AppTokens.microDuration,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        if (disableMotion) return child;
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.78, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        '$qty',
        key: ValueKey<int>(qty),
        textAlign: TextAlign.center,
        style: resolvedStyle,
      ),
    );
  }
}

/// Kontrol kuantitas Pendev: morphing antara tombol `+ Tambah` dan stepper `[-] qty [+]`.
class TransactionStepperControl extends StatelessWidget {
  const TransactionStepperControl({
    super.key,
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
    this.maxQty,
    this.showAddPillWhenZero = false,
    this.itemLabel = 'barang',
    this.addKey,
    this.incrementKey,
    this.decrementKey,
  });

  final int qty;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final int? maxQty;
  final bool showAddPillWhenZero;
  final String itemLabel;
  final Key? addKey;
  final Key? incrementKey;
  final Key? decrementKey;

  bool get _canIncrement => maxQty == null || qty < maxQty!;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return AnimatedSwitcher(
      duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
      switchInCurve: AppTokens.arrivalCurve,
      switchOutCurve: Curves.easeIn,
      child: (qty <= 0 && showAddPillWhenZero)
          ? _buildAddPill(context)
          : _buildStepperRow(context),
    );
  }

  Widget _buildAddPill(BuildContext context) {
    final outOfStock = maxQty != null && maxQty! <= 0;
    return Semantics(
      key: const ValueKey('stepper_add_mode'),
      button: true,
      enabled: !outOfStock,
      label: outOfStock
          ? 'Stok $itemLabel habis'
          : 'Tambah $itemLabel ke keranjang',
      child: TactilePressScale(
        enabled: !outOfStock,
        pressedScale: 0.94,
        child: Material(
          color: outOfStock ? AppColors.dangerBg : AppColors.ink,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: addKey,
            borderRadius: BorderRadius.circular(18),
            onTap: outOfStock
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onIncrement?.call();
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 88, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  child: Text(
                    outOfStock ? 'Habis' : '+ Tambah',
                    style: AppTypography.body(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: outOfStock ? AppColors.danger : AppColors.surface,
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

  Widget _buildStepperRow(BuildContext context) {
    return Container(
      key: const ValueKey('stepper_active_mode'),
      decoration: BoxDecoration(
        color: AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperCircleButton(
            buttonKey: decrementKey,
            icon: Icons.remove_rounded,
            tooltip: 'Kurangi $itemLabel',
            backgroundColor: AppColors.inputBg,
            foregroundColor: AppColors.ink,
            onTap: qty > 0 && onDecrement != null
                ? () {
                    HapticFeedback.selectionClick();
                    onDecrement!.call();
                  }
                : null,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedQtyText(qty: qty),
            ),
          ),
          _StepperCircleButton(
            buttonKey: incrementKey,
            icon: Icons.add_rounded,
            tooltip: 'Tambah $itemLabel',
            backgroundColor: _canIncrement
                ? AppColors.yolk
                : AppColors.borderSubtle,
            foregroundColor: AppColors.ink,
            onTap: _canIncrement && onIncrement != null
                ? () {
                    HapticFeedback.lightImpact();
                    onIncrement!.call();
                  }
                : onIncrement,
          ),
        ],
      ),
    );
  }
}

class _StepperCircleButton extends StatelessWidget {
  const _StepperCircleButton({
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    this.onTap,
  });

  final Key? buttonKey;
  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: TactilePressScale(
          enabled: onTap != null,
          pressedScale: 0.9,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: buttonKey,
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: foregroundColor),
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

/// Pil pemilih ringkas (Pelanggan / Tanggal) pada layar Kasir Nota (`07`).
class TransactionContextPill extends StatelessWidget {
  const TransactionContextPill({
    super.key,
    this.pillKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isEmphasized = false,
  });

  final Key? pillKey;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: TactilePressScale(
        enabled: onTap != null,
        pressedScale: 0.96,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: pillKey,
            borderRadius: BorderRadius.circular(14),
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isEmphasized ? AppColors.yolk : AppColors.borderSubtle,
                    width: isEmphasized ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu item katalog POS (`07 Kasir Nota`) dengan sorotan kuning lembut saat aktif.
class KasirCatalogItemCard extends StatelessWidget {
  const KasirCatalogItemCard({
    super.key,
    required this.barang,
    required this.qty,
    required this.onIncrement,
    required this.onDecrement,
  });

  final Barang barang;
  final int qty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final isActive = qty > 0;
    final lowStock = barang.stokBarang <= 10;

    return AnimatedContainer(
      duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
      curve: AppTokens.arrivalCurve,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF9E5) : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? AppColors.yolk : AppColors.borderSubtle,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BarangThumbnail(
            barang: barang,
            size: 52,
            radius: 12,
          ),
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
                const SizedBox(height: 3),
                Text(
                  '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}',
                  style: AppTypography.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: lowStock
                            ? AppColors.dangerBg
                            : AppColors.inputBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Stok: ${barang.stokBarang} ${barang.satuan}',
                        style: AppTypography.body(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: lowStock
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (isActive)
                      AnimatedRupiahCounter(
                        amount: barang.hargaSatuan * qty,
                        style: AppTypography.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TransactionStepperControl(
            qty: qty,
            maxQty: barang.stokBarang,
            showAddPillWhenZero: true,
            itemLabel: barang.namaBarang,
            addKey: ValueKey('kasir_add_${barang.idBarang}'),
            incrementKey: ValueKey('kasir_inc_${barang.idBarang}'),
            decrementKey: ValueKey('kasir_dec_${barang.idBarang}'),
            onIncrement: onIncrement,
            onDecrement: onDecrement,
          ),
        ],
      ),
    );
  }
}

/// Kartu baris item transaksi untuk Faktur Masuk (`08`) dan Detail Edit (`17`, `19`).
class DetailLineItemCard extends StatelessWidget {
  const DetailLineItemCard({
    super.key,
    required this.barang,
    required this.qty,
    required this.currentWarehouseStock,
    this.stockDeltaPreview,
    this.maxQty,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    this.itemKeyPrefix = 'line',
  });

  final Barang barang;
  final int qty;
  final int currentWarehouseStock;
  final int? stockDeltaPreview;
  final int? maxQty;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final subtotal = barang.hargaSatuan * qty;
    final projectedStock = stockDeltaPreview == null
        ? null
        : currentWarehouseStock + stockDeltaPreview!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BarangThumbnail(
                barang: barang,
                size: 44,
                radius: 10,
              ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}',
                      style: AppTypography.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Hapus ${barang.namaBarang} dari daftar',
                child: Tooltip(
                  message: 'Hapus item',
                  child: TactilePressScale(
                    pressedScale: 0.9,
                    child: Material(
                      color: AppColors.dangerBg,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: ValueKey('${itemKeyPrefix}_remove'),
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          onRemove();
                        },
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              TransactionStepperControl(
                qty: qty,
                maxQty: maxQty,
                showAddPillWhenZero: false,
                itemLabel: barang.namaBarang,
                incrementKey: ValueKey('${itemKeyPrefix}_inc'),
                decrementKey: ValueKey('${itemKeyPrefix}_dec'),
                onIncrement: onIncrement,
                onDecrement: onDecrement,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedRupiahCounter(
                    amount: subtotal,
                    style: AppTypography.heading(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  if (projectedStock != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Stok: $currentWarehouseStock → $projectedStock',
                          style: AppTypography.body(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bar mengambang gelap `#121212` di bawah daftar item untuk Kasir Nota (`07`) & Faktur (`08`).
class FloatingTransactionTotalBar extends StatelessWidget {
  const FloatingTransactionTotalBar({
    super.key,
    required this.visible,
    required this.caption,
    required this.itemCountBadge,
    required this.totalAmount,
    required this.buttonLabel,
    required this.isSubmitting,
    required this.onPressed,
    this.ctaKey,
  });

  final bool visible;
  final String caption;
  final int itemCountBadge;
  final double totalAmount;
  final String buttonLabel;
  final bool isSubmitting;
  final VoidCallback? onPressed;
  final Key? ctaKey;

  @override
  Widget build(BuildContext context) {
    return SoftAnimatedReveal(
      visible: visible,
      alignment: Alignment.bottomCenter,
      slideOffset: const Offset(0, 0.2),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x28121212),
              offset: Offset(0, 8),
              blurRadius: 20,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 300;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              caption,
                              maxLines: 1,
                              style: AppTypography.body(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFFD1D5DB),
                              ),
                            ),
                          ),
                          AnimatedBadgePop(
                            visible: itemCountBadge > 0,
                            badgeKey: ValueKey<int>(itemCountBadge),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF262626),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$itemCountBadge item',
                                style: AppTypography.body(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.yolk,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedRupiahCounter(
                          amount: totalAmount,
                          style: AppTypography.heading(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.yolk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: compact ? 8 : 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * (compact ? 0.52 : 0.56),
                  ),
                  child: Semantics(
                    button: true,
                    label: buttonLabel,
                    child: TactilePillButton(
                      key: ctaKey,
                      label: buttonLabel,
                      loadingLabel: 'Menyimpan...',
                      backgroundColor: AppColors.yolk,
                      foregroundColor: AppColors.ink,
                      isLoading: isSubmitting,
                      height: 48,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 18,
                        vertical: 10,
                      ),
                      fontSize: 13.5,
                      onPressed: isSubmitting ? null : onPressed,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Footer edit & hapus dengan konfirmasi inline (`SoftAnimatedReveal`) untuk layar `17` & `19`.
class TransactionBottomSummarySheet extends StatefulWidget {
  const TransactionBottomSummarySheet({
    super.key,
    required this.totalLabel,
    required this.totalAmount,
    required this.deleteLabel,
    required this.deleteWarningText,
    required this.isSubmitting,
    required this.onDeleteConfirmed,
    required this.onSaveChanges,
    this.saveKey,
    this.deleteKey,
  });

  final String totalLabel;
  final double totalAmount;
  final String deleteLabel;
  final String deleteWarningText;
  final bool isSubmitting;
  final Future<void> Function() onDeleteConfirmed;
  final Future<void> Function() onSaveChanges;
  final Key? saveKey;
  final Key? deleteKey;

  @override
  State<TransactionBottomSummarySheet> createState() =>
      _TransactionBottomSummarySheetState();
}

class _TransactionBottomSummarySheetState
    extends State<TransactionBottomSummarySheet> {
  bool _confirmDelete = false;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = (screenHeight * 0.50).clamp(160.0, 420.0);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Color(0x12000000),
            offset: Offset(0, -4),
            blurRadius: 16,
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.totalLabel,
                      style: AppTypography.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: AnimatedRupiahCounter(
                        amount: widget.totalAmount,
                        style: AppTypography.heading(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SoftAnimatedReveal(
                visible: _confirmDelete,
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MasterUiColors.dangerBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.deleteWarningText,
                        style: AppTypography.body(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: widget.isSubmitting
                                  ? null
                                  : () =>
                                        setState(() => _confirmDelete = false),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              child: Text(
                                'Batal',
                                style: AppTypography.body(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            FilledButton(
                              key: const ValueKey('confirm_delete_tx_button'),
                              onPressed: widget.isSubmitting
                                  ? null
                                  : () async {
                                      HapticFeedback.heavyImpact();
                                      await widget.onDeleteConfirmed();
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                                foregroundColor: AppColors.surface,
                                minimumSize: const Size(96, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Ya, Hapus',
                                style: AppTypography.body(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.surface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Semantics(
                      button: true,
                      label: widget.deleteLabel,
                      child: TactilePressScale(
                        enabled: !widget.isSubmitting,
                        child: OutlinedButton(
                          key: widget.deleteKey,
                          onPressed: widget.isSubmitting
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  setState(
                                    () => _confirmDelete = !_confirmDelete,
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.dangerBg,
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(
                              color: MasterUiColors.dangerBorder,
                            ),
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.deleteLabel,
                              style: AppTypography.body(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: Semantics(
                      button: true,
                      label: 'Simpan Perubahan',
                      child: TactilePillButton(
                        key: widget.saveKey,
                        label: 'Simpan Perubahan',
                        loadingLabel: 'Menyimpan...',
                        isLoading: widget.isSubmitting,
                        height: 50,
                        fontSize: 13.5,
                        onPressed: widget.isSubmitting
                            ? null
                            : () {
                                if (_confirmDelete) {
                                  setState(() => _confirmDelete = false);
                                }
                                widget.onSaveChanges();
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baris filter chip horizontal dengan transisi warna halus untuk layar `16` & `18`.
class TransactionFilterChipBar<T> extends StatelessWidget {
  const TransactionFilterChipBar({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  final List<({T value, String label})> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _AnimatedFilterChip(
              label: options[i].label,
              selected: options[i].value == selectedValue,
              disableMotion: disableMotion,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(options[i].value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AnimatedFilterChip extends StatelessWidget {
  const _AnimatedFilterChip({
    required this.label,
    required this.selected,
    required this.disableMotion,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disableMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TactilePressScale(
        pressedScale: 0.95,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Center(
                child: AnimatedContainer(
                  duration: disableMotion
                      ? Duration.zero
                      : AppTokens.stateDuration,
                  curve: AppTokens.arrivalCurve,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.yolk : AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? AppColors.yolkPressed
                          : AppColors.borderSubtle,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppTypography.body(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.ink : AppColors.textSecondary,
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

/// Kartu riwayat transaksi Pendev untuk `16 Riwayat Nota` dan `18 Riwayat Faktur`.
class TransactionHistoryCard extends StatelessWidget {
  const TransactionHistoryCard({
    super.key,
    this.cardKey,
    required this.title,
    required this.metaText,
    required this.itemsSummary,
    required this.totalAmount,
    required this.syncStatus,
    required this.onTap,
  });

  final Key? cardKey;
  final String title;
  final String metaText;
  final String itemsSummary;
  final double totalAmount;
  final SyncStatus syncStatus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPending = syncStatus == SyncStatus.pending;

    return Semantics(
      button: true,
      label: 'Buka detail $title',
      child: TactilePressScale(
        pressedScale: 0.985,
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: cardKey,
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.heading(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isPending
                              ? AppColors.yolkSoft
                              : AppColors.successBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isPending ? 'Pending Sync' : 'Tersinkron',
                          style: AppTypography.body(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: isPending
                                ? AppColors.ink
                                : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metaText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              itemsSummary,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatRupiah(totalAmount),
                              style: AppTypography.heading(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.yolkSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 19,
                          color: AppColors.ink,
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
    );
  }
}

/// Field pemilih entitas (Pelanggan/Supplier/Petugas) atau tanggal gaya Pendev.
class TransactionMetaSelectorTile extends StatelessWidget {
  const TransactionMetaSelectorTile({
    super.key,
    this.tileKey,
    required this.label,
    required this.valueText,
    required this.leadingIcon,
    required this.trailingIcon,
    this.onTap,
  });

  final Key? tileKey;
  final String label;
  final String valueText;
  final IconData leadingIcon;
  final IconData trailingIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: enabled,
          label: '$label: $valueText',
          child: TactilePressScale(
            enabled: enabled,
            pressedScale: 0.985,
            child: Material(
              color: enabled ? AppColors.surfaceWarm : AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: tileKey,
                borderRadius: BorderRadius.circular(14),
                onTap: enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        onTap!();
                      }
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          leadingIcon,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            valueText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          trailingIcon,
                          size: 19,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pemilih tanggal transaksi berbasis `showDatePicker` dengan tema DepotTelur36.
Future<DateTime?> pickTransactionDate(
  BuildContext context,
  String currentIsoDate,
) {
  final parts = currentIsoDate.trim().split('-');
  var initial = DateTime.now();
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null) {
      initial = DateTime(y, m, d);
    }
  }
  final now = DateTime.now();
  final first = DateTime(2020, 1, 1);
  final last = DateTime(now.year + 2, 12, 31);
  final clampedInitial = initial.isBefore(first)
      ? first
      : (initial.isAfter(last) ? last : initial);

  return showDatePicker(
    context: context,
    initialDate: clampedInitial,
    firstDate: first,
    lastDate: last,
    helpText: 'Pilih Tanggal Transaksi',
    cancelText: 'Batal',
    confirmText: 'Pilih',
  );
}

/// Modal Bottom Sheet untuk memilih Pelanggan, Supplier, atau Petugas.
Future<T?> showEntitySelectorSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  String Function(T)? subtitleOf,
  T? selected,
  required bool Function(T a, T b) equals,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.65,
            ),
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
                Text(
                  title,
                  style: AppTypography.heading(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Belum ada data tersedia.',
                        style: AppTypography.body(
                          fontSize: 13.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected =
                            selected != null && equals(item, selected);
                        final subtitle = subtitleOf?.call(item);
                        return Material(
                          color: isSelected
                              ? const Color(0xFFFFF9E5)
                              : AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(sheetCtx).pop(item);
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.yolk
                                        : AppColors.borderSubtle,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            labelOf(item),
                                            style: AppTypography.heading(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (subtitle != null &&
                                              subtitle.trim().isNotEmpty)
                                            Text(
                                              subtitle,
                                              style: AppTypography.body(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.ink,
                                        size: 22,
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
            ),
          ),
        ),
      );
    },
  );
}

/// Memformat ringkasan baris barang untuk kartu Riwayat Nota & Riwayat Faktur.
String buildTransactionItemsSummary(
  List<({String? nama, int qty, String? satuan})> items,
) {
  if (items.isEmpty) return 'Tidak ada rincian barang';
  final shown = items.take(2).map((e) {
    final name = (e.nama ?? '').trim().isEmpty ? 'Barang' : e.nama!.trim();
    final unit = (e.satuan ?? '').trim();
    return unit.isEmpty ? '$name (${e.qty})' : '$name (${e.qty} $unit)';
  }).join(', ');
  final extra = items.length - 2;
  return extra > 0 ? '$shown +$extra lainnya' : shown;
}

/// Modal Bottom Sheet untuk memilih barang dari katalog dengan pencarian instan.
Future<void> showCatalogItemPickerSheet({
  required BuildContext context,
  required List<Barang> barangs,
  required int Function(Barang) currentQtyFor,
  required ValueChanged<Barang> onAddBarang,
  bool enforceAvailableStock = false,
  String title = 'Pilih Barang dari Katalog',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) {
      return _CatalogPickerSheetBody(
        barangs: barangs,
        currentQtyFor: currentQtyFor,
        onAddBarang: onAddBarang,
        enforceAvailableStock: enforceAvailableStock,
        title: title,
      );
    },
  );
}

class _CatalogPickerSheetBody extends StatefulWidget {
  const _CatalogPickerSheetBody({
    required this.barangs,
    required this.currentQtyFor,
    required this.onAddBarang,
    required this.enforceAvailableStock,
    required this.title,
  });

  final List<Barang> barangs;
  final int Function(Barang) currentQtyFor;
  final ValueChanged<Barang> onAddBarang;
  final bool enforceAvailableStock;
  final String title;

  @override
  State<_CatalogPickerSheetBody> createState() =>
      _CatalogPickerSheetBodyState();
}

class _CatalogPickerSheetBodyState extends State<_CatalogPickerSheetBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lower = _query.trim().toLowerCase();
    final filtered = widget.barangs.where((b) {
      if (lower.isEmpty) return true;
      return b.namaBarang.toLowerCase().contains(lower) ||
          b.satuan.toLowerCase().contains(lower);
    }).toList(growable: false);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 12,
          ),
          child: Column(
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    child: Text(
                      'Selesai',
                      style: AppTypography.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              MasterSearchField(
                controller: _searchCtrl,
                hintText: 'Cari nama barang atau satuan...',
                onChanged: (v) => setState(() => _query = v),
                onClear: () => setState(() {
                  _searchCtrl.clear();
                  _query = '';
                }),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Barang tidak ditemukan.',
                          style: AppTypography.body(
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final barang = filtered[index];
                          final pickedQty = widget.currentQtyFor(barang);
                          final stockLimitReached =
                              widget.enforceAvailableStock &&
                              pickedQty >= barang.stokBarang;
                          return Material(
                            color: pickedQty > 0
                                ? const Color(0xFFFFF9E5)
                                : AppColors.surfaceWarm,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: stockLimitReached
                                  ? null
                                  : () {
                                      HapticFeedback.lightImpact();
                                      widget.onAddBarang(barang);
                                      setState(() {});
                                    },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: pickedQty > 0
                                        ? AppColors.yolk
                                        : AppColors.borderSubtle,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    BarangThumbnail(
                                      barang: barang,
                                      size: 44,
                                      radius: 10,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            barang.namaBarang,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppTypography.heading(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            alignment:
                                                WrapAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan} · Stok: ${barang.stokBarang}',
                                                style: AppTypography.body(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: stockLimitReached
                                                      ? AppColors.dangerBg
                                                      : (pickedQty > 0
                                                            ? AppColors.yolk
                                                            : AppColors.ink),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  stockLimitReached
                                                      ? 'Maks'
                                                      : (pickedQty > 0
                                                            ? 'Dipilih ($pickedQty) +1'
                                                            : '+ Pilih'),
                                                  style: AppTypography.body(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: stockLimitReached
                                                        ? AppColors.danger
                                                        : (pickedQty > 0
                                                              ? AppColors.ink
                                                              : AppColors
                                                                    .surface),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
