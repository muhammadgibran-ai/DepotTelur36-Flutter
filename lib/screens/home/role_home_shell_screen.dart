import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/dashboard_widgets.dart';

/// Navigasi terpusat pasca-login menuju Dashboard Beranda RBAC sesuai [session].
void navigateToRoleHome(BuildContext context, AuthSession session) {
  Navigator.of(context).pushAndRemoveUntil(
    buildAuthRoute(RoleHomeShellScreen(initialSession: session)),
    (route) => false,
  );
}

T? _maybeRead<T>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  }
}

T? _maybeWatch<T>(BuildContext context) {
  try {
    return Provider.of<T>(context);
  } on ProviderNotFoundException {
    return null;
  }
}

/// Shell utama Fungsi 2: Dashboard Beranda RBAC (Owner vs Operator),
/// Navigasi Tab Melayang, Pencarian, Filter Cepat, dan Pusat Notifikasi.
class RoleHomeShellScreen extends StatefulWidget {
  const RoleHomeShellScreen({
    super.key,
    required this.initialSession,
    this.viewModelOverride,
  });

  final AuthSession initialSession;
  final DashboardViewModel? viewModelOverride;

  @override
  State<RoleHomeShellScreen> createState() => _RoleHomeShellScreenState();
}

class _RoleHomeShellScreenState extends State<RoleHomeShellScreen> {
  DashboardViewModel? _ownedViewModel;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  DashboardViewModel get _vm => widget.viewModelOverride ?? _ownedViewModel!;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    if (widget.viewModelOverride == null) {
      final repo = _maybeRead<InventoryRepository>(context);
      _ownedViewModel = repo != null
          ? DashboardViewModel.fromRepository(
              session: widget.initialSession,
              repository: repo,
            )
          : DashboardViewModel(
              session: widget.initialSession,
              dataSource: const EmptyDashboardDataSource(),
            );
      unawaited(_ownedViewModel!.loadDashboardData());
    } else if (_searchController.text != widget.viewModelOverride!.searchQuery) {
      _searchController.text = widget.viewModelOverride!.searchQuery;
    }
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant RoleHomeShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ownedViewModel != null &&
        oldWidget.initialSession != widget.initialSession) {
      _ownedViewModel!.updateSession(widget.initialSession);
    }
    if (widget.viewModelOverride != null &&
        widget.viewModelOverride != oldWidget.viewModelOverride &&
        _searchController.text != widget.viewModelOverride!.searchQuery) {
      _searchController.text = widget.viewModelOverride!.searchQuery;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authSession = _maybeWatch<AuthViewModel>(context)?.session;
    if (authSession != null && _ownedViewModel != null) {
      _ownedViewModel!.updateSession(authSession);
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _ownedViewModel?.dispose();
    super.dispose();
  }

  Future<void> _handleSignOut() async {
    final auth = _maybeRead<AuthViewModel>(context);
    if (auth != null) {
      await auth.signOut();
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      buildAuthRoute(const WelcomeScreen()),
      (route) => false,
    );
  }

  void _handleSearchChanged(String raw) {
    _vm.setSearchQuery(raw);
  }

  void _handleResetSearchAndFilter() {
    _searchController.clear();
    _vm.resetSearchAndFilter();
  }

  void _handleSelectTab(DashboardTabId tabId) {
    final allowed = _vm.selectTab(tabId);
    if (!allowed && mounted && _vm.accessDeniedMessage != null) {
      _showFeedbackSnack(_vm.accessDeniedMessage!);
    }
  }

  void _handleRestockRequested(String itemName, int stock, String unit) {
    if (!_vm.isOwner) {
      _vm.selectTab(DashboardTabId.faktur);
    }
    _showFeedbackSnack(
      'Siap restock $itemName (sisa $stock $unit) melalui modul Faktur masuk.',
    );
  }

  void _handleActivateShortcut(DashboardShortcutSpec shortcut) {
    final authorized = _vm.activateShortcut(shortcut.id);
    if (authorized == null) {
      if (_vm.accessDeniedMessage != null) {
        _showFeedbackSnack(_vm.accessDeniedMessage!);
      }
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _ShortcutDetailSheet(
          shortcut: authorized,
          vm: _vm,
          onNavigateTab: authorized.targetTab == null
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  _handleSelectTab(authorized.targetTab!);
                },
        );
      },
    );
  }

  void _openNotificationSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return AnimatedBuilder(
          animation: _vm,
          builder: (context, _) {
            return NotificationCenterSheet(
              notifications: _vm.notifications,
              unreadCount: _vm.unreadCount,
              syncState: _vm.syncState,
              isManualSyncing: _vm.isManualSyncing,
              syncErrorMessage: _vm.syncErrorMessage,
              onMarkRead: _vm.markNotificationRead,
              onMarkAllRead: _vm.markAllNotificationsRead,
              onTriggerSync: () => unawaited(_vm.triggerManualSync()),
              onRestockItem: (notif) {
                Navigator.of(sheetContext).pop();
                _handleRestockRequested(
                  notif.barangNama ?? 'Barang',
                  notif.currentStock ?? 0,
                  notif.satuan ?? 'Unit',
                );
              },
            );
          },
        );
      },
    );
  }

  void _showFeedbackSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = _maybeWatch<AuthViewModel>(context);
    final isSubmittingSignOut = authVm?.isSubmitting ?? false;

    return AnimatedBuilder(
      animation: _vm,
      builder: (context, _) {
        final session = _vm.session;
        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        final filterAnimationDuration = disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220);

        return PopScope(
          canPop:
              _vm.activeTab == DashboardTabId.beranda && !isSubmittingSignOut,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || isSubmittingSignOut) return;
            _vm.selectTab(DashboardTabId.beranda);
          },
          child: Scaffold(
            backgroundColor: AppColors.surfaceWarm,
            extendBody: true,
            body: Column(
            children: [
              _DashboardHeader(
                session: session,
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
                searchQuery: _vm.searchQuery,
                unreadCount: _vm.unreadCount,
                unreadBadgeText: _vm.unreadBadgeText,
                hasActiveFilter:
                    _vm.activeFilter != DashboardQuickFilter.semua ||
                    _vm.isFilterBarExpanded,
                isSigningOut: isSubmittingSignOut,
                onSearchChanged: _handleSearchChanged,
                onClearSearch: () {
                  _searchController.clear();
                  _vm.clearSearch();
                },
                onToggleFilter: _vm.toggleFilterBar,
                onOpenNotifications: _openNotificationSheet,
                onSignOut: isSubmittingSignOut ? null : _handleSignOut,
              ),
              AnimatedSize(
                duration: filterAnimationDuration,
                curve: Curves.easeOutCubic,
                child:
                    (_vm.isFilterBarExpanded ||
                        _vm.activeFilter != DashboardQuickFilter.semua)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: QuickFilterChipBar(
                          activeFilter: _vm.activeFilter,
                          onSelected: _vm.setQuickFilter,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.ink,
                  backgroundColor: AppColors.surface,
                  onRefresh: _vm.loadDashboardData,
                  child: AnimatedSwitcher(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: _buildTabScrollView(context, session),
                  ),
                ),
              ),
            ],
          ),
            bottomNavigationBar: FloatingTabBar(
              tabs: _vm.tabs,
              activeTab: _vm.activeTab,
              onSelectTab: _handleSelectTab,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabScrollView(BuildContext context, AuthSession session) {
    final tabChildren = switch (_vm.activeTab) {
      DashboardTabId.beranda => _buildBerandaContent(context, session),
      DashboardTabId.omzet => _buildOwnerOmzetContent(),
      DashboardTabId.nota => _buildOwnerNotaContent(),
      DashboardTabId.master => _buildCatalogTabContent(isOwnerView: true),
      DashboardTabId.kasir => _buildOperatorKasirContent(),
      DashboardTabId.faktur => _buildOperatorFakturContent(),
      DashboardTabId.stok => _buildCatalogTabContent(isOwnerView: false),
    };

    return ListView(
      key: ValueKey(_vm.activeTab),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: tabChildren,
    );
  }

  List<Widget> _buildBerandaContent(BuildContext context, AuthSession session) {
    final compactWidth = MediaQuery.sizeOf(context).width < 360;
    final greetingName = session.displayName.trim().isEmpty
        ? (session.isOwner ? 'Owner' : 'Petugas')
        : session.displayName.trim();
    final lowItems = _vm.previewLowStockItems;
    final normalItems = _vm.previewNormalStockItems;

    return [
      // Banner Sambutan Dark Ink sesuai mockup `.pen`
      Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF262626),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      session.isOwner ? 'Owner' : 'Operator',
                      style: AppTypography.body(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.yolk,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Halo, $greetingName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.heading(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.isOwner
                        ? 'Selamat datang kembali di panel pengawasan DepotTelur36.'
                        : 'Selamat bertugas. Mulai catat transaksi kasir dan stok masuk.',
                    style: AppTypography.body(
                      fontSize: 12,
                      color: const Color(0xFFD1D5DB),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            RoleBannerIllustration(
              isOwner: session.isOwner,
              size: compactWidth ? 82 : 104,
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      // Shortcut Grid Beranda
      Row(
        children: [
          Expanded(
            child: Text(
              session.isOwner ? 'Fungsi Manajerial' : 'Fungsi Operasional',
              style: AppTypography.heading(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              session.isOwner ? 'Khusus Owner' : 'Kasir & Gudang',
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: session.isOwner
                    ? AppColors.warning
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _vm.shortcuts.length; i++) ...[
            Expanded(
              child: DashboardMenuTile(
                spec: _vm.shortcuts[i],
                onTap: () => _handleActivateShortcut(_vm.shortcuts[i]),
              ),
            ),
            if (i < _vm.shortcuts.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
      const SizedBox(height: 18),
      // Section Perlu Perhatian / Ketersediaan Gudang
      Row(
        children: [
          Expanded(
            child: Text(
              session.isOwner ? 'Perlu Perhatian' : 'Ketersediaan Gudang',
              style: AppTypography.heading(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Lihat semua stok barang',
            child: TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                _handleSelectTab(
                  session.isOwner
                      ? DashboardTabId.master
                      : DashboardTabId.stok,
                );
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'Lihat Semua',
                style: AppTypography.body(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
      if (_vm.hasActiveSearchOrFilter) ...[
        _ActiveFilterSummaryRow(
          resultCount: _vm.filteredBarang.length,
          activeFilter: _vm.activeFilter,
          query: _vm.searchQuery,
          onReset: _handleResetSearchAndFilter,
        ),
        const SizedBox(height: 10),
      ],
      if (_vm.errorMessage != null) ...[
        _ErrorRetryCard(
          message: _vm.errorMessage!,
          onRetry: _vm.loadDashboardData,
        ),
        const SizedBox(height: 10),
      ],
      if (_vm.isLoading && _vm.allBarang.isEmpty)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Center(
            child: Text(
              'Memuat data stok lokal...',
              style: AppTypography.body(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        )
      else if (_vm.filteredBarang.isEmpty) ...[
        _EmptyFilterCard(
          hasQueryOrFilter: _vm.hasActiveSearchOrFilter,
          onReset: _handleResetSearchAndFilter,
        ),
      ] else ...[
        for (final item in lowItems) ...[
          LowStockAlertCard(
            barang: item,
            onRestock: () => _handleRestockRequested(
              item.namaBarang,
              item.stokBarang,
              item.satuan,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (normalItems.isNotEmpty)
          HomeStockListCard(
            items: normalItems,
            onItemTap: (barang) => _showBarangQuickSheet(barang),
          ),
      ],
      if (_vm.searchQuery.isNotEmpty && _vm.secondaryMatchCount > 0) ...[
        const SizedBox(height: 12),
        _SecondarySearchMatchesCard(vm: _vm),
      ],
    ];
  }

  List<Widget> _buildOwnerOmzetContent() {
    final m = _vm.metrics;
    return [
      const _ModuleStagingBanner(
        badge: 'Khusus Owner · Tahap Berikutnya',
        title: 'Ringkasan Omzet & Arus Kas',
        subtitle:
            'Data dihitung langsung dari transaksi Nota & Faktur lokal SQLite.',
      ),
      const SizedBox(height: 14),
      _MetricTileRow(
        leftTitle: 'Total Omzet Nota',
        leftValue: formatRupiah(m.totalNotaOmzet),
        rightTitle: 'Jumlah Nota',
        rightValue: '${m.totalNotaCount} Transaksi',
      ),
      const SizedBox(height: 10),
      _MetricTileRow(
        leftTitle: 'Belanja Faktur',
        leftValue: formatRupiah(m.totalFakturBelanja),
        rightTitle: 'Stok Menipis',
        rightValue: '${m.lowStockCount} Barang',
      ),
    ];
  }

  List<Widget> _buildOwnerNotaContent() {
    final notas = _vm.filteredNotas;
    return [
      _ModuleStagingBanner(
        badge: 'Khusus Owner · Audit Nota',
        title: 'Riwayat Nota Penjualan (${notas.length})',
        subtitle:
            'Pencatatan kasir & filter tanggal penuh tersedia pada Fungsi Kasir.',
      ),
      const SizedBox(height: 14),
      if (notas.isEmpty)
        const _EmptyModuleCard(
          icon: Icons.receipt_long_rounded,
          title: 'Belum ada transaksi Nota',
          subtitle: 'Nota penjualan dari kasir akan tampil di sini secara real-time.',
        )
      else
        for (final nota in notas) ...[
          _TransactionSummaryTile(
            title:
                'Nota #${nota.idNota ?? _shortTag(nota.remoteId)}${(nota.namaCustomer ?? '').isNotEmpty ? ' · ${nota.namaCustomer}' : ''}',
            subtitle: nota.tanggalNota,
            amountText: formatRupiah(nota.total),
          ),
          const SizedBox(height: 8),
        ],
    ];
  }

  List<Widget> _buildOperatorKasirContent() {
    final m = _vm.metrics;
    return [
      const _ModuleStagingBanner(
        badge: 'Operasional Kasir',
        title: 'Meja Kasir Cepat',
        subtitle:
            'Pantau kesiapan stok sebelum membuka transaksi penjualan pada modul Kasir.',
      ),
      const SizedBox(height: 14),
      _MetricTileRow(
        leftTitle: 'Katalog Siap Jual',
        leftValue: '${m.totalBarang} Barang',
        rightTitle: 'Nota Tersimpan',
        rightValue: '${m.totalNotaCount} Nota',
      ),
      const SizedBox(height: 12),
      if (_vm.normalStockItems.isNotEmpty)
        HomeStockListCard(
          items: _vm.normalStockItems,
          onItemTap: _showBarangQuickSheet,
        ),
    ];
  }

  List<Widget> _buildOperatorFakturContent() {
    final fakturs = _vm.filteredFakturs;
    final lowItems = _vm.lowStockItems;
    return [
      const _ModuleStagingBanner(
        badge: 'Operasional Gudang',
        title: 'Faktur Stok Masuk Supplier',
        subtitle:
            'Daftar item prioritas restock dan riwayat faktur barang masuk lokal.',
      ),
      const SizedBox(height: 14),
      if (lowItems.isNotEmpty) ...[
        Text(
          'Prioritas Restock (${lowItems.length})',
          style: AppTypography.heading(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in lowItems) ...[
          LowStockAlertCard(
            barang: item,
            onRestock: () => _handleRestockRequested(
              item.namaBarang,
              item.stokBarang,
              item.satuan,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
      if (fakturs.isEmpty)
        const _EmptyModuleCard(
          icon: Icons.note_add_rounded,
          title: 'Belum ada Faktur Masuk',
          subtitle: 'Pencatatan restock dari supplier akan terdata di sini.',
        )
      else
        for (final faktur in fakturs) ...[
          _TransactionSummaryTile(
            title: faktur.noFaktur.trim().isNotEmpty
                ? faktur.noFaktur
                : 'Faktur #${faktur.idFaktur ?? _shortTag(faktur.remoteId)}',
            subtitle:
                '${faktur.tanggalFaktur}${(faktur.namaSupplier ?? '').isNotEmpty ? ' · ${faktur.namaSupplier}' : ''}',
            amountText: formatRupiah(faktur.total),
          ),
          const SizedBox(height: 8),
        ],
    ];
  }

  String _shortTag(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '-';
    return trimmed.length <= 6 ? trimmed : trimmed.substring(0, 6);
  }

  List<Widget> _buildCatalogTabContent({required bool isOwnerView}) {
    final m = _vm.metrics;
    return [
      _ModuleStagingBanner(
        badge: isOwnerView ? 'Master Data RBAC' : 'Gudang DepotTelur36',
        title: isOwnerView
            ? 'Katalog Barang & Master Entitas'
            : 'Seluruh Ketersediaan Gudang',
        subtitle: isOwnerView
            ? '${m.totalBarang} Barang · ${m.totalSupplier} Supplier · ${m.totalCustomer} Pelanggan · ${m.totalPetugas} Akun'
            : '${m.totalBarang} Barang aktif · ${m.lowStockCount} perlu perhatian · ${m.totalSupplier} Supplier',
      ),
      const SizedBox(height: 12),
      if (_vm.hasActiveSearchOrFilter) ...[
        _ActiveFilterSummaryRow(
          resultCount: _vm.filteredBarang.length,
          activeFilter: _vm.activeFilter,
          query: _vm.searchQuery,
          onReset: _handleResetSearchAndFilter,
        ),
        const SizedBox(height: 10),
      ],
      if (_vm.filteredBarang.isEmpty)
        _EmptyFilterCard(
          hasQueryOrFilter: _vm.hasActiveSearchOrFilter,
          onReset: _handleResetSearchAndFilter,
        )
      else ...[
        for (final item in _vm.lowStockItems) ...[
          LowStockAlertCard(
            barang: item,
            onRestock: () => _handleRestockRequested(
              item.namaBarang,
              item.stokBarang,
              item.satuan,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_vm.normalStockItems.isNotEmpty)
          HomeStockListCard(
            items: _vm.normalStockItems,
            onItemTap: _showBarangQuickSheet,
          ),
      ],
    ];
  }

  void _showBarangQuickSheet(Barang barang) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BarangThumbnail(barang: barang, size: 52, radius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            barang.namaBarang,
                            style: AppTypography.heading(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatRupiah(barang.hargaSatuan)} / ${barang.satuan}',
                            style: AppTypography.body(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup detail barang',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Sisa Stok: ${barang.stokBarang} ${barang.satuan} · Status Sync: ${barang.syncStatus.value}',
                  style: AppTypography.body(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.session,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.unreadCount,
    required this.unreadBadgeText,
    required this.hasActiveFilter,
    required this.isSigningOut,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onToggleFilter,
    required this.onOpenNotifications,
    required this.onSignOut,
  });

  final AuthSession session;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchQuery;
  final int unreadCount;
  final String unreadBadgeText;
  final bool hasActiveFilter;
  final bool isSigningOut;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleFilter;
  final VoidCallback onOpenNotifications;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.yolk,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.isOwner
                          ? 'DepotTelur36 Owner'
                          : 'DepotTelur36 Kasir',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: unreadCount > 0
                        ? 'Buka notifikasi, $unreadCount belum dibaca'
                        : 'Buka notifikasi, tidak ada peringatan baru',
                    child: Tooltip(
                      message: 'Notifikasi & Sinkronisasi',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onOpenNotifications,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: AppColors.surface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.notifications_rounded,
                                    size: 20,
                                    color: AppColors.ink,
                                  ),
                                ),
                                if (unreadCount > 0)
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: AnimatedScale(
                                      scale: 1.0,
                                      duration: disableAnimations
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 18,
                                          minHeight: 18,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.danger,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: AppColors.surface,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            unreadBadgeText,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                              height: 1.1,
                                            ),
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
                  ),
                  const SizedBox(width: 8),
                  TactilePillButton(
                    label: 'Sign Out',
                    loadingLabel: 'Keluar...',
                    height: 48,
                    fontSize: 12.5,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    backgroundColor: AppColors.ink,
                    foregroundColor: Colors.white,
                    isLoading: isSigningOut,
                    onPressed: onSignOut,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: searchFocusNode.hasFocus
                              ? AppColors.ink
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        onChanged: onSearchChanged,
                        maxLength: kMaxSearchQueryLength,
                        textInputAction: TextInputAction.search,
                        style: AppTypography.body(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          hintText: session.isOwner
                              ? 'Cari laporan, stok, atau supplier...'
                              : 'Cari barang telur atau sembako...',
                          hintStyle: AppTypography.body(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          suffixIcon: searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Hapus pencarian',
                                  onPressed: onClearSearch,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: 'Filter cepat stok dan kategori',
                    child: Tooltip(
                      message: 'Filter cepat',
                      child: Material(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onToggleFilter();
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(
                                  Icons.filter_alt_rounded,
                                  size: 20,
                                  color: Color(0xFFFFB511),
                                ),
                                if (hasActiveFilter)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.yolk,
                                        shape: BoxShape.circle,
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterSummaryRow extends StatelessWidget {
  const _ActiveFilterSummaryRow({
    required this.resultCount,
    required this.activeFilter,
    required this.query,
    required this.onReset,
  });

  final int resultCount;
  final DashboardQuickFilter activeFilter;
  final String query;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final filterDesc = activeFilter != DashboardQuickFilter.semua
        ? ' · ${activeFilter.label}'
        : '';
    final queryDesc = query.isNotEmpty ? ' · "$query"' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.yolkSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Menampilkan $resultCount barang$filterDesc$queryDesc',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.ink,
            ),
            child: const Text(
              'Reset',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilterCard extends StatelessWidget {
  const _EmptyFilterCard({
    required this.hasQueryOrFilter,
    required this.onReset,
  });

  final bool hasQueryOrFilter;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 32,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            hasQueryOrFilter
                ? 'Tidak ada barang yang cocok'
                : 'Belum ada data barang tersimpan',
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasQueryOrFilter
                ? 'Ubah kata kunci pencarian atau pilih filter lain.'
                : 'Tambahkan barang pada modul master untuk memantau stok.',
            textAlign: TextAlign.center,
            style: AppTypography.body(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (hasQueryOrFilter) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onReset,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: AppColors.ink,
              ),
              child: const Text(
                'Reset Filter & Pencarian',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SecondarySearchMatchesCard extends StatelessWidget {
  const _SecondarySearchMatchesCard({required this.vm});

  final DashboardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (vm.filteredSuppliers.isNotEmpty)
        'Supplier: ${vm.filteredSuppliers.map((s) => s.namaSupplier).take(3).join(', ')}',
      if (vm.filteredCustomers.isNotEmpty)
        'Pelanggan: ${vm.filteredCustomers.map((c) => c.namaCustomer).take(3).join(', ')}',
      if (vm.filteredFakturs.isNotEmpty)
        'Faktur cocok: ${vm.filteredFakturs.length} dokumen',
      if (vm.isOwner && vm.filteredNotas.isNotEmpty)
        'Nota cocok: ${vm.filteredNotas.length} transaksi',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kecocokan Data Lain (${vm.secondaryMatchCount})',
            style: AppTypography.heading(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines) ...[
            Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _ErrorRetryCard extends StatelessWidget {
  const _ErrorRetryCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: AppTypography.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: AppColors.danger,
            ),
            child: const Text(
              'Muat Ulang',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleStagingBanner extends StatelessWidget {
  const _ModuleStagingBanner({
    required this.badge,
    required this.title,
    required this.subtitle,
  });

  final String badge;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: AppTypography.body(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.yolk,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTypography.heading(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.body(
              fontSize: 12.5,
              color: const Color(0xFFD1D5DB),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTileRow extends StatelessWidget {
  const _MetricTileRow({
    required this.leftTitle,
    required this.leftValue,
    required this.rightTitle,
    required this.rightValue,
  });

  final String leftTitle;
  final String leftValue;
  final String rightTitle;
  final String rightValue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MetricTile(title: leftTitle, value: leftValue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(title: rightTitle, value: rightValue),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.heading(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionSummaryTile extends StatelessWidget {
  const _TransactionSummaryTile({
    required this.title,
    required this.subtitle,
    required this.amountText,
  });

  final String title;
  final String subtitle;
  final String amountText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.heading(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
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
          Text(
            amountText,
            style: AppTypography.body(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyModuleCard extends StatelessWidget {
  const _EmptyModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutDetailSheet extends StatelessWidget {
  const _ShortcutDetailSheet({
    required this.shortcut,
    required this.vm,
    this.onNavigateTab,
  });

  final DashboardShortcutSpec shortcut;
  final DashboardViewModel vm;
  final VoidCallback? onNavigateTab;

  @override
  Widget build(BuildContext context) {
    final previewLines = switch (shortcut.id) {
      DashboardShortcutId.dataSupplier || DashboardShortcutId.supplier =>
        vm.allSuppliers
            .take(5)
            .map((s) => '${s.namaSupplier} · ${s.noTelpSupplier}')
            .toList(),
      DashboardShortcutId.pelanggan =>
        vm.allCustomers.take(5).map((c) => c.namaCustomer).toList(),
      DashboardShortcutId.akunPetugas =>
        vm.allPetugas
            .take(5)
            .map((p) => '${p.namaPetugas} (${p.role.value})')
            .toList(),
      DashboardShortcutId.aturHarga =>
        vm.allBarang
            .take(5)
            .map(
              (b) =>
                  '${b.namaBarang} · ${formatRupiah(b.hargaSatuan)}/${b.satuan}',
            )
            .toList(),
      DashboardShortcutId.riwayatNota =>
        vm.allNotas
            .take(5)
            .map((n) => 'Nota #${n.idNota ?? '-'} · ${formatRupiah(n.total)}')
            .toList(),
      DashboardShortcutId.riwayatFaktur =>
        vm.allFakturs
            .take(5)
            .map(
              (f) => 'Faktur #${f.idFaktur ?? '-'} · ${formatRupiah(f.total)}',
            )
            .toList(),
    };

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shortcut.label,
                      style: AppTypography.heading(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup ringkasan menu',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                shortcut.description,
                style: AppTypography.body(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              if (previewLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceWarm,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in previewLines) ...[
                        Text(
                          '• $line',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ],
              if (onNavigateTab != null) ...[
                const SizedBox(height: 14),
                TactilePillButton(
                  label: 'Buka Tab Terkait',
                  height: 48,
                  onPressed: onNavigateTab,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
