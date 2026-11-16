import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

const Color _menuIconYellow = Color(0xFFFFB511);

IconData shortcutIconFor(DashboardShortcutId id) {
  switch (id) {
    case DashboardShortcutId.aturHarga:
      return Icons.sell_rounded;
    case DashboardShortcutId.riwayatFaktur:
      return Icons.description_rounded;
    case DashboardShortcutId.dataSupplier:
    case DashboardShortcutId.supplier:
      return Icons.local_shipping_rounded;
    case DashboardShortcutId.akunPetugas:
      return Icons.manage_accounts_rounded;
    case DashboardShortcutId.riwayatNota:
      return Icons.history_rounded;
    case DashboardShortcutId.pelanggan:
      return Icons.group_rounded;
  }
}

IconData tabIconFor(DashboardTabId id) {
  switch (id) {
    case DashboardTabId.beranda:
      return Icons.grid_view_rounded;
    case DashboardTabId.omzet:
      return Icons.analytics_rounded;
    case DashboardTabId.nota:
      return Icons.receipt_long_rounded;
    case DashboardTabId.master:
    case DashboardTabId.stok:
      return Icons.inventory_2_rounded;
    case DashboardTabId.kasir:
      return Icons.point_of_sale_rounded;
    case DashboardTabId.faktur:
      return Icons.note_add_rounded;
  }
}

/// Tile shortcut beranda yang mengimplementasikan `MenuButton States` (.pen):
/// Default -> Hover -> Pressed dengan animasi skala & umpan balik haptik.
class DashboardMenuTile extends StatefulWidget {
  const DashboardMenuTile({
    super.key,
    required this.spec,
    required this.onTap,
  });

  final DashboardShortcutSpec spec;
  final VoidCallback onTap;

  @override
  State<DashboardMenuTile> createState() => _DashboardMenuTileState();
}

class _DashboardMenuTileState extends State<DashboardMenuTile> {
  bool _hovered = false;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 120);

    final Color tileBg;
    final Color iconBoxBg;
    if (_pressed) {
      tileBg = const Color(0x10000000);
      iconBoxBg = AppColors.ink;
    } else if (_hovered) {
      tileBg = const Color(0x08000000);
      iconBoxBg = const Color(0xFFE6E6E6);
    } else {
      tileBg = Colors.transparent;
      iconBoxBg = const Color(0xFFF1F1F1);
    }

    return Semantics(
      button: true,
      label: widget.spec.label,
      hint: 'Buka menu ${widget.spec.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 82),
            child: AnimatedScale(
              scale: _pressed && !disableAnimations ? 0.95 : 1.0,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: duration,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: iconBoxBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        shortcutIconFor(widget.spec.id),
                        size: 20,
                        color: _menuIconYellow,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.spec.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
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

/// Bar filter cepat untuk memfilter stok menipis, aman, telur, atau sembako.
class QuickFilterChipBar extends StatelessWidget {
  const QuickFilterChipBar({
    super.key,
    required this.activeFilter,
    required this.onSelected,
  });

  final DashboardQuickFilter activeFilter;
  final ValueChanged<DashboardQuickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: DashboardQuickFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = DashboardQuickFilter.values[index];
          final selected = filter == activeFilter;
          final disableMotion = MediaQuery.disableAnimationsOf(context);
          final duration = disableMotion
              ? Duration.zero
              : const Duration(milliseconds: 180);
          return Center(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Filter ${filter.label}',
              child: TactilePressScale(
                pressedScale: 0.94,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.ink : AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? AppColors.ink : AppColors.borderSubtle,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelected(filter);
                      },
                      borderRadius: BorderRadius.circular(999),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Center(
                            child: Text(
                              filter.label,
                              style: AppTypography.body(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
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
            ),
          );
        },
      ),
    );
  }
}

/// Kartu peringatan stok menipis/habis (`LowStockCard`) dengan tombol `Restock`.
class LowStockAlertCard extends StatelessWidget {
  const LowStockAlertCard({
    super.key,
    required this.barang,
    required this.onRestock,
  });

  final Barang barang;
  final VoidCallback onRestock;

  @override
  Widget build(BuildContext context) {
    final isEmpty = barang.stokBarang <= 0;
    final prefix = isEmpty ? 'Stok Habis' : 'Stok Menipis';
    final subtext = isEmpty
        ? 'Sisa ${barang.stokBarang} ${barang.satuan} · Segera restock'
        : 'Sisa ${barang.stokBarang} ${barang.satuan} (Batas minimum $kLowStockThreshold)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFCA5A5).withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BarangThumbnail(barang: barang, size: 44, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$prefix · ${barang.namaBarang}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.heading(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtext,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.danger,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Restock ${barang.namaBarang}',
            child: TactilePressScale(
              pressedScale: 0.94,
              child: Material(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onRestock();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 68, minHeight: 48),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Center(
                        child: Text(
                          'Restock',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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
    );
  }
}

/// Kartu daftar barang ketersediaan sehat (`HomeStockListCard`).
class HomeStockListCard extends StatelessWidget {
  const HomeStockListCard({
    super.key,
    required this.items,
    this.onItemTap,
  });

  final List<Barang> items;
  final ValueChanged<Barang>? onItemTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _StockRow(
              barang: items[i],
              onTap: onItemTap == null ? null : () => onItemTap!(items[i]),
            ),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSubtle,
              ),
          ],
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.barang,
    this.onTap,
  });

  final Barang barang;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          BarangThumbnail(barang: barang, size: 44, radius: 12),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.yolkSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${barang.stokBarang} ${barang.satuan}',
              style: AppTypography.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return rowContent;

    return Semantics(
      button: true,
      label:
          '${barang.namaBarang}, harga ${formatRupiah(barang.hargaSatuan)}, stok ${barang.stokBarang} ${barang.satuan}',
      child: TactilePressScale(
        pressedScale: 0.985,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap!();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: rowContent,
          ),
        ),
      ),
    );
  }
}

/// Floating Bottom Pill Tab Bar sesuai `.pen` `FloatingTabBar`.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onSelectTab,
  });

  final List<DashboardTabSpec> tabs;
  final DashboardTabId activeTab;
  final ValueChanged<DashboardTabId> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration = disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  for (final tab in tabs)
                    Expanded(
                      child: _FloatingTabItem(
                        tab: tab,
                        isActive: tab.id == activeTab,
                        duration: duration,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelectTab(tab.id);
                        },
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

class _FloatingTabItem extends StatelessWidget {
  const _FloatingTabItem({
    required this.tab,
    required this.isActive,
    required this.duration,
    required this.onTap,
  });

  final DashboardTabSpec tab;
  final bool isActive;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final fgColor = isActive ? AppColors.ink : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isActive,
      label: tab.semanticLabel,
      child: TactilePressScale(
        pressedScale: 0.94,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 52, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.yolkSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedScale(
                    scale: isActive && !disableAnimations ? 1.1 : 1.0,
                    duration: duration,
                    curve: Curves.easeOutBack,
                    child: Icon(tabIconFor(tab.id), size: 20, color: fgColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: fgColor,
                      height: 1.2,
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

/// Bottom sheet Pusat Notifikasi & Status Sinkronisasi.
class NotificationCenterSheet extends StatelessWidget {
  const NotificationCenterSheet({
    super.key,
    required this.notifications,
    required this.unreadCount,
    required this.syncState,
    required this.isManualSyncing,
    this.syncErrorMessage,
    required this.onMarkRead,
    required this.onMarkAllRead,
    required this.onTriggerSync,
    required this.onRestockItem,
  });

  final List<AppNotificationItem> notifications;
  final int unreadCount;
  final SyncState syncState;
  final bool isManualSyncing;
  final String? syncErrorMessage;
  final ValueChanged<String> onMarkRead;
  final VoidCallback onMarkAllRead;
  final VoidCallback onTriggerSync;
  final ValueChanged<AppNotificationItem> onRestockItem;

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.84;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    child: Text(
                      'Notifikasi & Sinkronisasi',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup notifikasi',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SyncStatusCard(
                syncState: syncState,
                isManualSyncing: isManualSyncing,
                syncErrorMessage: syncErrorMessage,
                onTriggerSync: onTriggerSync,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppTokens.stateDuration,
                      child: SizedBox(
                        key: ValueKey(unreadCount),
                        width: double.infinity,
                        child: Text(
                          unreadCount > 0
                              ? '$unreadCount peringatan belum dibaca'
                              : 'Semua notifikasi terbaca',
                          style: AppTypography.body(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedBadgePop(
                    visible: unreadCount > 0,
                    badgeKey: const ValueKey('mark_all_read_btn'),
                    child: TactilePressScale(
                      pressedScale: 0.94,
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onMarkAllRead();
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: AppColors.ink,
                        ),
                        child: const Text(
                          'Tandai Semua',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: notifications.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceWarm,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              size: 36,
                              color: AppColors.success,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Semua stok aman dan tersinkron',
                              textAlign: TextAlign.center,
                              style: AppTypography.heading(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Belum ada peringatan stok menipis atau antrean gagal.',
                              textAlign: TextAlign.center,
                              style: AppTypography.body(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = notifications[index];
                          return _NotificationTile(
                            item: item,
                            onTap: () => onMarkRead(item.id),
                            onRestock: item.isStockAlert
                                ? () => onRestockItem(item)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({
    required this.syncState,
    required this.isManualSyncing,
    this.syncErrorMessage,
    required this.onTriggerSync,
  });

  final SyncState syncState;
  final bool isManualSyncing;
  final String? syncErrorMessage;
  final VoidCallback onTriggerSync;

  @override
  Widget build(BuildContext context) {
    final manualError = (syncErrorMessage ?? '').trim();
    final stateError = (syncState.lastError ?? '').trim();
    final hasError = manualError.isNotEmpty || stateError.isNotEmpty;
    final busy = syncState.isSyncing || isManualSyncing;

    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;

    if (hasError) {
      bg = AppColors.dangerBg;
      fg = AppColors.danger;
      icon = Icons.sync_problem_rounded;
      label = manualError.isNotEmpty
          ? manualError
          : 'Sinkronisasi bermasalah · ${syncState.pendingCount} antrean lokal';
    } else if (busy) {
      bg = AppColors.warningBg;
      fg = AppColors.warning;
      icon = Icons.sync_rounded;
      label = 'Menyinkronkan data dengan Firebase Cloud...';
    } else if (!syncState.isOnline) {
      bg = AppColors.warningBg;
      fg = AppColors.warning;
      icon = Icons.cloud_off_rounded;
      label =
          'Mode Offline · ${syncState.pendingCount} perubahan menunggu internet';
    } else {
      bg = AppColors.successBg;
      fg = AppColors.success;
      icon = Icons.cloud_done_rounded;
      label = syncState.pendingCount > 0
          ? 'Online · ${syncState.pendingCount} perubahan siap disinkronkan'
          : 'Online · SQLite & Firebase tersinkron';
    }

    final disableMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          RotatingSyncIcon(
            isSpinning: busy,
            icon: icon,
            size: 20,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: disableMotion ? Duration.zero : AppTokens.microDuration,
              child: SizedBox(
                key: ValueKey(label),
                width: double.infinity,
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Sinkron sekarang',
            child: TactilePressScale(
              enabled: !busy,
              pressedScale: 0.93,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        onTriggerSync();
                      },
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: AnimatedSwitcher(
                  duration: disableMotion
                      ? Duration.zero
                      : AppTokens.microDuration,
                  child: Text(
                    busy ? 'Proses...' : 'Sinkron',
                    key: ValueKey(busy),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
    this.onRestock,
  });

  final AppNotificationItem item;
  final VoidCallback onTap;
  final VoidCallback? onRestock;

  @override
  Widget build(BuildContext context) {
    final Color cardBg;
    final Color accent;
    final IconData icon;

    switch (item.severity) {
      case NotificationSeverity.critical:
        cardBg = item.isRead ? AppColors.surface : AppColors.dangerBg;
        accent = AppColors.danger;
        icon = Icons.error_rounded;
      case NotificationSeverity.warning:
        cardBg = item.isRead ? AppColors.surface : AppColors.warningBg;
        accent = AppColors.warning;
        icon = Icons.warning_amber_rounded;
      case NotificationSeverity.info:
        cardBg = item.isRead ? AppColors.surface : AppColors.surfaceWarm;
        accent = AppColors.ink;
        icon = Icons.info_rounded;
    }

    final disableMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      label: '${item.title}. ${item.message}. ${item.isRead ? 'Sudah dibaca' : 'Belum dibaca'}',
      child: TactilePressScale(
        pressedScale: 0.985,
        child: AnimatedContainer(
          duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isRead
                  ? AppColors.borderSubtle
                  : accent.withValues(alpha: 0.35),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(icon, size: 22, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.heading(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                AnimatedBadgePop(
                                  visible: !item.isRead,
                                  badgeKey: ValueKey('notif_dot_${item.id}'),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.danger,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onRestock != null) ...[
                        const SizedBox(width: 8),
                        Semantics(
                          button: true,
                          label: 'Restock ${item.barangNama ?? ''}',
                          child: TactilePressScale(
                            pressedScale: 0.94,
                            child: Material(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  onRestock!();
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 64,
                                    minHeight: 48,
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Restock',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
