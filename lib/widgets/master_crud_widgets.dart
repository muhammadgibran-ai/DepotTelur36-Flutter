import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Warna aksen biru terkurasi sesuai UI Pendev (kontras teks >= 5.3:1).
abstract final class MasterUiColors {
  static const Color editBlue = Color(0xFF2563EB);
  static const Color editBlueText = Color(0xFF1D4ED8);
  static const Color editBlueBg = Color(0xFFEFF6FF);
  static const Color neutralButtonBg = Color(0xFFF1F1F1);
  static const Color dangerBorder = Color(0xFFFCA5A5);
}

/// Header kuning melengkung ala Pendev untuk layar daftar maupun form Master Data.
class MasterAmberHeader extends StatelessWidget {
  const MasterAmberHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.showBackButton = false,
    this.onBack,
    this.backKey,
    this.actionLabel,
    this.actionIcon,
    this.actionKey,
    this.onAction,
    this.badgeLabel,
  });

  final String title;
  final String subtitle;
  final bool showBackButton;
  final VoidCallback? onBack;
  final Key? backKey;
  final String? actionLabel;
  final IconData? actionIcon;
  final Key? actionKey;
  final VoidCallback? onAction;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final headerDuration = disableMotion
        ? Duration.zero
        : const Duration(milliseconds: 170);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTokens.darkOnYellowOverlay,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.yolk,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 12,
          16,
          18,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showBackButton) ...[
              Semantics(
                button: true,
                label: 'Kembali',
                child: Tooltip(
                  message: 'Kembali',
                  child: TactilePressScale(
                    pressedScale: 0.92,
                    child: Material(
                      color: AppColors.surface,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: backKey ?? const ValueKey('master_header_back_button'),
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (onBack != null) {
                            onBack!();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 22,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration: headerDuration,
                switchInCurve: AppTokens.arrivalCurve,
                child: SizedBox(
                  key: ValueKey('$title|$subtitle|$badgeLabel'),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (badgeLabel != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.ink,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeLabel!,
                            style: AppTypography.body(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.yolk,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.heading(
                          fontSize: 20,
                          color: AppColors.ink,
                          height: 1.18,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: actionLabel,
                child: TactilePressScale(
                  pressedScale: 0.94,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Material(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        key: actionKey ?? const ValueKey('master_header_add_button'),
                        borderRadius: BorderRadius.circular(22),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onAction?.call();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: headerDuration,
                              child: Row(
                                key: ValueKey('${actionIcon?.codePoint}_$actionLabel'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (actionIcon != null) ...[
                                    Icon(
                                      actionIcon,
                                      size: 16,
                                      color: AppColors.yolk,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    actionLabel!,
                                    style: AppTypography.body(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.surface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Deretan pill kategori Master (`Barang`, `Supplier`, `Pelanggan`, `Petugas`).
class MasterCategoryTabBar extends StatelessWidget {
  const MasterCategoryTabBar({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onSelected,
  });

  final List<MasterCategory> categories;
  final MasterCategory activeCategory;
  final ValueChanged<MasterCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < categories.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _CategoryPill(
              category: categories[i],
              isActive: categories[i] == activeCategory,
              onTap: () => onSelected(categories[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.category,
    required this.isActive,
    required this.onTap,
  });

  final MasterCategory category;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: isActive,
      label: 'Kategori ${category.label}',
      child: TactilePressScale(
        pressedScale: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isActive ? AppColors.ink : AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? AppColors.ink : AppColors.borderSubtle,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey('master_category_tab_${category.name}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Center(
                    child: Text(
                      category.label,
                      style: AppTypography.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isActive
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

/// Kolom pencarian putih bersih dengan sorotan fokus teranimasi untuk Master Data & Atur Harga.
class MasterSearchField extends StatefulWidget {
  const MasterSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<MasterSearchField> createState() => _MasterSearchFieldState();
}

class _MasterSearchFieldState extends State<MasterSearchField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final focused = _focusNode.hasFocus;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        return AnimatedContainer(
          duration: disableMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: AppTokens.arrivalCurve,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? AppColors.ink : AppColors.borderSubtle,
              width: focused ? 1.5 : 1,
            ),
            boxShadow: focused
                ? const [
                    BoxShadow(
                      color: Color(0x12121212),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(
                Icons.search_rounded,
                size: 20,
                color: focused ? AppColors.ink : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('master_search_field'),
                  controller: widget.controller,
                  focusNode: _focusNode,
                  onChanged: widget.onChanged,
                  textInputAction: TextInputAction.search,
                  style: AppTypography.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: AppTypography.body(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: disableMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: value.text.isNotEmpty
                    ? IconButton(
                        key: const ValueKey('master_search_clear'),
                        tooltip: 'Bersihkan pencarian',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.onClear();
                        },
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey('master_search_spacer'),
                        width: 12,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tombol ikon aksi kecil (`Edit` biru / `Hapus` merah) ber-hit-area 48x48 agar lolos aksesibilitas.
class MasterActionIconButton extends StatelessWidget {
  const MasterActionIconButton.edit({
    super.key,
    required this.semanticLabel,
    required this.onTap,
  }) : isDelete = false;

  const MasterActionIconButton.delete({
    super.key,
    required this.semanticLabel,
    required this.onTap,
  }) : isDelete = true;

  final String semanticLabel;
  final VoidCallback? onTap;
  final bool isDelete;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDelete ? AppColors.dangerBg : MasterUiColors.neutralButtonBg;
    final fgColor = isDelete ? AppColors.danger : MasterUiColors.editBlue;
    final icon = isDelete ? Icons.delete_outline_rounded : Icons.edit_rounded;

    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: semanticLabel,
        child: TactilePressScale(
          enabled: onTap != null,
          pressedScale: 0.88,
          hoverScale: 1.04,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap == null
                  ? null
                  : () {
                      if (isDelete) {
                        HapticFeedback.mediumImpact();
                      } else {
                        HapticFeedback.selectionClick();
                      }
                      onTap!();
                    },
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Opacity(
                    opacity: onTap == null ? 0.45 : 1,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 18, color: fgColor),
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

/// Kontainer kartu putih standar dengan border halus sesuai Pendev.
class MasterSectionCard extends StatelessWidget {
  const MasterSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// Field input berlabel gaya Pendev dengan sorotan fokus teranimasi & validasi halus.
class MasterInputField extends StatefulWidget {
  const MasterInputField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.controller,
    required this.hintText,
    this.errorText,
    this.prefixText,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.onChanged,
  });

  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String hintText;
  final String? errorText;
  final String? prefixText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  State<MasterInputField> createState() => _MasterInputFieldState();
}

class _MasterInputFieldState extends State<MasterInputField> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final hasError =
        widget.errorText != null && widget.errorText!.trim().isNotEmpty;
    final focused = _focusNode.hasFocus;
    final Color borderColor;
    final double borderWidth;
    if (hasError) {
      borderColor = AppColors.danger;
      borderWidth = 1.4;
    } else if (focused) {
      borderColor = AppColors.ink;
      borderWidth = 1.5;
    } else {
      borderColor = AppColors.borderSubtle;
      borderWidth = 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTypography.body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: disableMotion
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: AppTokens.arrivalCurve,
          decoration: BoxDecoration(
            color: focused ? AppColors.surface : AppColors.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
            boxShadow: focused && !hasError
                ? const [
                    BoxShadow(
                      color: Color(0x0F121212),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              if (widget.prefixText != null) ...[
                const SizedBox(width: 12),
                Text(
                  widget.prefixText!,
                  style: AppTypography.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  key: widget.fieldKey,
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  maxLines: widget.maxLines,
                  maxLength: widget.maxLength,
                  obscureText: widget.obscureText,
                  onChanged: widget.onChanged,
                  style: AppTypography.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: AppTypography.body(
                      fontSize: 13.5,
                      color: AppColors.textSecondary,
                    ),
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: widget.prefixText == null ? 14 : 4,
                      vertical: 13,
                    ),
                  ),
                ),
              ),
              ?widget.suffix,
            ],
          ),
        ),
        SoftAnimatedReveal(
          visible: hasError,
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: AppColors.danger,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    widget.errorText ?? '',
                    style: AppTypography.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Banner status / error inline yang kontrasnya terjamin >= 4.5:1 dengan animasi masuk halus.
class MasterFeedbackBanner extends StatelessWidget {
  const MasterFeedbackBanner({
    super.key,
    required this.message,
    this.isError = true,
    this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final bgColor = isError ? AppColors.dangerBg : AppColors.successBg;
    final fgColor = isError ? AppColors.danger : AppColors.success;
    final icon =
        isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded;

    return TweenAnimationBuilder<double>(
      key: ValueKey('$isError|$message'),
      tween: Tween<double>(
        begin: disableMotion ? 1.0 : 0.0,
        end: 1.0,
      ),
      duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
      curve: AppTokens.arrivalCurve,
      builder: (context, t, child) {
        if (disableMotion) return child!;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.97 + 0.03 * t,
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError ? MasterUiColors.dangerBorder : const Color(0xFF86EFAC),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fgColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: fgColor,
                ),
              ),
            ),
            if (onDismiss != null)
              TactilePressScale(
                pressedScale: 0.9,
                child: IconButton(
                  tooltip: 'Tutup pesan',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onDismiss!();
                  },
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: Icon(Icons.close_rounded, size: 18, color: fgColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kartu konfirmasi penghapusan ala Pendev (`Konfirmasi Hapus ...?`).
class DeleteConfirmCard extends StatelessWidget {
  const DeleteConfirmCard({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isBusy,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool isBusy;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MasterUiColors.dangerBorder, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.heading(
                    fontSize: 15,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppTypography.body(
              fontSize: 13,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TactilePressScale(
                  enabled: !isBusy,
                  pressedScale: 0.96,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Material(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const ValueKey('delete_confirm_cancel_button'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: isBusy
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onCancel();
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Center(
                            child: Text(
                              'Batal',
                              style: AppTypography.body(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TactilePressScale(
                  enabled: !isBusy,
                  pressedScale: 0.96,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Material(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const ValueKey('delete_confirm_submit_button'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: isBusy
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                onConfirm();
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : AppTokens.microDuration,
                              child: Text(
                                isBusy ? 'Menghapus...' : confirmLabel,
                                key: ValueKey(isBusy),
                                textAlign: TextAlign.center,
                                style: AppTypography.body(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.surface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Membuka dialog konfirmasi hapus yang memakai [DeleteConfirmCard].
Future<bool> showMasterDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: DeleteConfirmCard(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          isBusy: false,
          onCancel: () => Navigator.of(dialogContext).pop(false),
          onConfirm: () => Navigator.of(dialogContext).pop(true),
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// Footer sticky bawah untuk layar form CRUD (`Hapus` merah soft + `Simpan ...` hitam).
class CrudActionFooter extends StatelessWidget {
  const CrudActionFooter({
    super.key,
    required this.saveLabel,
    required this.onSave,
    this.isSaving = false,
    this.showDelete = false,
    this.onDelete,
  });

  final String saveLabel;
  final VoidCallback onSave;
  final bool isSaving;
  final bool showDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      child: Row(
        children: [
          if (showDelete && onDelete != null) ...[
            Semantics(
              button: true,
              label: 'Hapus data',
              child: TactilePressScale(
                enabled: !isSaving,
                pressedScale: 0.95,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
                  child: Material(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: const ValueKey('crud_footer_delete_button'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: isSaving
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              onDelete?.call();
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppColors.danger,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Hapus',
                              style: AppTypography.body(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Semantics(
              button: true,
              label: saveLabel,
              child: TactilePressScale(
                enabled: !isSaving,
                pressedScale: 0.97,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Material(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: const ValueKey('crud_footer_save_button'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: isSaving
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              onSave();
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RotatingSyncIcon(
                              isSpinning: isSaving,
                              icon: isSaving
                                  ? Icons.sync_rounded
                                  : Icons.check_rounded,
                              size: 18,
                              color: AppColors.yolk,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: AnimatedSwitcher(
                                duration: MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : AppTokens.microDuration,
                                child: Text(
                                  isSaving ? 'Menyimpan...' : saveLabel,
                                  key: ValueKey(isSaving ? 'saving' : saveLabel),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.surface,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// State kosong konsisten untuk daftar kategori yang belum memiliki entitas / hasil cari kosong.
class MasterEmptyStateCard extends StatelessWidget {
  const MasterEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return MasterSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.yolkSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 26, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.heading(fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
