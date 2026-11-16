import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';

/// Kontrak sumber data agar [DashboardViewModel] terpisah dari implementasi
/// SQLite/Firebase langsung saat pengujian unit maupun fallback UI.
abstract class DashboardDataSource {
  Future<List<Barang>> getAllBarang();
  Future<List<Supplier>> getAllSupplier();
  Future<List<Customer>> getAllCustomer();
  Future<List<Petugas>> getAllPetugas();
  Future<List<Faktur>> getAllFaktur();
  Future<List<Nota>> getAllNota();
  Stream<void> get onDataChanged;
  SyncState get syncState;
  Listenable? get syncListenable;
  Future<void> syncNow();
}

/// Adaptor produksi yang menghubungkan [DashboardViewModel] ke [InventoryRepository]
/// dan [SyncService] (SQLite lokal + Firebase Cloud Sync).
class RepositoryDashboardDataSource implements DashboardDataSource {
  RepositoryDashboardDataSource(this._repository);

  final InventoryRepository _repository;

  @override
  Future<List<Barang>> getAllBarang() => _repository.getAllBarang();

  @override
  Future<List<Supplier>> getAllSupplier() => _repository.getAllSupplier();

  @override
  Future<List<Customer>> getAllCustomer() => _repository.getAllCustomer();

  @override
  Future<List<Petugas>> getAllPetugas() => _repository.getAllPetugas();

  @override
  Future<List<Faktur>> getAllFaktur() => _repository.getAllFaktur();

  @override
  Future<List<Nota>> getAllNota() => _repository.getAllNota();

  @override
  Stream<void> get onDataChanged => _repository.onDataChanged;

  @override
  SyncState get syncState => _repository.syncService.state;

  @override
  Listenable get syncListenable => _repository.syncService;

  @override
  Future<void> syncNow() => _repository.syncService.syncNow();
}

/// Sumber data kosong aman saat screen dirender terisolasi tanpa provider repository.
class EmptyDashboardDataSource implements DashboardDataSource {
  const EmptyDashboardDataSource();

  @override
  Future<List<Barang>> getAllBarang() async => const [];

  @override
  Future<List<Supplier>> getAllSupplier() async => const [];

  @override
  Future<List<Customer>> getAllCustomer() async => const [];

  @override
  Future<List<Petugas>> getAllPetugas() async => const [];

  @override
  Future<List<Faktur>> getAllFaktur() async => const [];

  @override
  Future<List<Nota>> getAllNota() async => const [];

  @override
  Stream<void> get onDataChanged => const Stream.empty();

  @override
  SyncState get syncState => const SyncState();

  @override
  Listenable? get syncListenable => null;

  @override
  Future<void> syncNow() async {}
}

/// ViewModel untuk Fungsi 2: Dashboard Beranda RBAC, Navigasi Tab, Pencarian,
/// Filter Cepat, serta Pusat Notifikasi & Sinkronisasi.
class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required AuthSession session,
    required DashboardDataSource dataSource,
  }) : this._(session: session, dataSource: dataSource);

  DashboardViewModel._({
    required this._session,
    required this._dataSource,
  }) {
    _dataSub = _dataSource.onDataChanged.listen(
      (_) => unawaited(loadDashboardData()),
      onError: (_) {},
    );
    _dataSource.syncListenable?.addListener(_handleSyncChanged);
  }

  factory DashboardViewModel.fromRepository({
    required AuthSession session,
    required InventoryRepository repository,
  }) {
    return DashboardViewModel(
      session: session,
      dataSource: RepositoryDashboardDataSource(repository),
    );
  }

  AuthSession _session;
  final DashboardDataSource _dataSource;

  StreamSubscription<void>? _dataSub;
  bool _disposed = false;
  int _loadEpoch = 0;

  DashboardTabId _activeTab = DashboardTabId.beranda;
  String _searchQuery = '';
  DashboardQuickFilter _activeFilter = DashboardQuickFilter.semua;
  bool _isFilterBarExpanded = false;
  bool _isLoading = false;
  bool _isManualSyncing = false;
  String? _errorMessage;
  String? _syncErrorMessage;
  String? _accessDeniedMessage;

  List<Barang> _barang = const [];
  List<Supplier> _suppliers = const [];
  List<Customer> _customers = const [];
  List<Petugas> _petugas = const [];
  List<Faktur> _fakturs = const [];
  List<Nota> _notas = const [];

  final Set<String> _readNotificationIds = {};

  AuthSession get session => _session;
  bool get isOwner => _session.isOwner;
  DashboardTabId get activeTab => _activeTab;
  String get searchQuery => _searchQuery;
  DashboardQuickFilter get activeFilter => _activeFilter;
  bool get isFilterBarExpanded => _isFilterBarExpanded;
  bool get isLoading => _isLoading;
  bool get isManualSyncing => _isManualSyncing;
  String? get errorMessage => _errorMessage;
  String? get syncErrorMessage => _syncErrorMessage;
  String? get accessDeniedMessage => _accessDeniedMessage;
  SyncState get syncState => _dataSource.syncState;

  List<Barang> get allBarang => _barang;
  List<Supplier> get allSuppliers => _suppliers;
  List<Customer> get allCustomers => _customers;
  List<Petugas> get allPetugas => isOwner ? _petugas : const [];
  List<Faktur> get allFakturs => _fakturs;
  List<Nota> get allNotas => _notas;

  List<DashboardTabSpec> get tabs => dashboardTabsForRole(_session.role);
  List<DashboardShortcutSpec> get shortcuts =>
      dashboardShortcutsForRole(_session.role);

  int get activeTabIndex {
    final idx = tabs.indexWhere((tab) => tab.id == _activeTab);
    return idx >= 0 ? idx : 0;
  }

  bool get hasActiveSearchOrFilter =>
      _searchQuery.isNotEmpty || _activeFilter != DashboardQuickFilter.semua;

  DashboardSummaryMetrics get metrics {
    var lowCount = 0;
    var outCount = 0;
    var stockUnits = 0;

    for (final item in _barang) {
      if (item.stokBarang <= 0) {
        outCount++;
      }
      if (item.stokBarang <= kLowStockThreshold) {
        lowCount++;
      }
      if (item.stokBarang > 0) {
        stockUnits += item.stokBarang;
      }
    }

    var omzetTotal = 0.0;
    for (final nota in _notas) {
      if (nota.total.isFinite && nota.total > 0) {
        omzetTotal += nota.total;
      }
    }

    var belanjaTotal = 0.0;
    for (final faktur in _fakturs) {
      if (faktur.total.isFinite && faktur.total > 0) {
        belanjaTotal += faktur.total;
      }
    }

    return DashboardSummaryMetrics(
      totalBarang: _barang.length,
      lowStockCount: lowCount,
      outOfStockCount: outCount,
      totalSupplier: _suppliers.length,
      totalCustomer: _customers.length,
      totalPetugas: isOwner ? _petugas.length : 0,
      totalNotaCount: _notas.length,
      totalNotaOmzet: isOwner ? omzetTotal : 0.0,
      totalFakturCount: _fakturs.length,
      totalFakturBelanja: isOwner ? belanjaTotal : 0.0,
      totalStokUnit: stockUnits,
    );
  }

  /// Memperbarui sesi aktif, mencegah kebocoran state antar pengguna, serta
  /// memaksa kembali ke Beranda jika tab sebelumnya dilarang untuk peran baru.
  void updateSession(AuthSession nextSession) {
    final roleChanged = nextSession.role != _session.role;
    final uidChanged = nextSession.uid != _session.uid;
    final nameChanged = nextSession.displayName != _session.displayName;
    if (!roleChanged && !uidChanged && !nameChanged) return;

    final wasOwner = isOwner;
    _session = nextSession;
    if (uidChanged) {
      _readNotificationIds.clear();
      _searchQuery = '';
      _activeFilter = DashboardQuickFilter.semua;
      _isFilterBarExpanded = false;
      _syncErrorMessage = null;
      _activeTab = DashboardTabId.beranda;
    } else if (!isTabAllowedForRole(_activeTab, _session.role)) {
      _activeTab = DashboardTabId.beranda;
    }
    if (!isOwner) {
      _petugas = const [];
    } else if (!wasOwner) {
      unawaited(loadDashboardData());
    }
    _accessDeniedMessage = null;
    _safeNotify();
  }

  /// Memuat seluruh ringkasan dan daftar lokal dari SQLite secara aman.
  Future<void> loadDashboardData() async {
    if (_disposed) return;
    final epoch = ++_loadEpoch;
    _isLoading = true;
    _errorMessage = null;
    _safeNotify();

    try {
      final results = await Future.wait<dynamic>([
        _dataSource.getAllBarang(),
        _dataSource.getAllSupplier(),
        _dataSource.getAllCustomer(),
        isOwner ? _dataSource.getAllPetugas() : Future.value(const <Petugas>[]),
        _dataSource.getAllFaktur(),
        _dataSource.getAllNota(),
      ]);

      if (_disposed || epoch != _loadEpoch) return;

      _barang = List<Barang>.unmodifiable(results[0] as List<Barang>);
      _suppliers = List<Supplier>.unmodifiable(results[1] as List<Supplier>);
      _customers = List<Customer>.unmodifiable(results[2] as List<Customer>);
      _petugas = List<Petugas>.unmodifiable(
        isOwner ? (results[3] as List<Petugas>) : const <Petugas>[],
      );
      _fakturs = List<Faktur>.unmodifiable(results[4] as List<Faktur>);
      _notas = List<Nota>.unmodifiable(results[5] as List<Nota>);
      _pruneStaleReadIds();
      _errorMessage = null;
    } catch (_) {
      if (_disposed || epoch != _loadEpoch) return;
      _errorMessage = 'Gagal memuat data lokal dashboard. Coba muat ulang.';
    } finally {
      if (!_disposed && epoch == _loadEpoch) {
        _isLoading = false;
        _safeNotify();
      }
    }
  }

  /// Pindah tab dengan penegakan RBAC ketat.
  bool selectTab(DashboardTabId tabId) {
    if (!isTabAllowedForRole(tabId, _session.role)) {
      _accessDeniedMessage =
          'Akses ditolak: fitur "${tabId.name}" khusus untuk Owner.';
      _safeNotify();
      return false;
    }
    _accessDeniedMessage = null;
    if (_activeTab == tabId) {
      return true;
    }
    _activeTab = tabId;
    _safeNotify();
    return true;
  }

  /// Pindah tab menggunakan indeks [FloatingTabBar] dengan validasi batas.
  bool selectTabIndex(int index) {
    if (index < 0 || index >= tabs.length) {
      _accessDeniedMessage = 'Tab navigasi tidak valid.';
      _safeNotify();
      return false;
    }
    return selectTab(tabs[index].id);
  }

  /// Memvalidasi dan mengeksekusi shortcut beranda sesuai RBAC peran aktif.
  DashboardShortcutSpec? activateShortcut(DashboardShortcutId shortcutId) {
    if (!isShortcutAllowedForRole(shortcutId, _session.role)) {
      _accessDeniedMessage =
          'Akses ditolak: shortcut ini khusus untuk Owner.';
      _safeNotify();
      return null;
    }

    _accessDeniedMessage = null;
    for (final shortcut in shortcuts) {
      if (shortcut.id == shortcutId) {
        return shortcut;
      }
    }
    return null;
  }

  void clearAccessDeniedMessage() {
    if (_accessDeniedMessage == null) return;
    _accessDeniedMessage = null;
    _safeNotify();
  }

  /// Mengubah query pencarian setelah disanitasi.
  void setSearchQuery(String raw) {
    final sanitized = sanitizeSearchQuery(raw);
    if (sanitized == _searchQuery) return;
    _searchQuery = sanitized;
    _safeNotify();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    _safeNotify();
  }

  void setQuickFilter(DashboardQuickFilter filter) {
    if (_activeFilter == filter) return;
    _activeFilter = filter;
    _safeNotify();
  }

  void toggleFilterBar() {
    _isFilterBarExpanded = !_isFilterBarExpanded;
    _safeNotify();
  }

  void resetSearchAndFilter() {
    if (!hasActiveSearchOrFilter && !_isFilterBarExpanded) return;
    _searchQuery = '';
    _activeFilter = DashboardQuickFilter.semua;
    _safeNotify();
  }

  String _safeIntString(double value) {
    if (!value.isFinite || value.abs() > kMaxSafeRupiahMagnitude) {
      return '';
    }
    return value.round().toString();
  }

  bool _matchesBarang(Barang item) {
    final lowerName = item.namaBarang.toLowerCase();
    switch (_activeFilter) {
      case DashboardQuickFilter.semua:
        break;
      case DashboardQuickFilter.stokMenipis:
        if (item.stokBarang > kLowStockThreshold) return false;
      case DashboardQuickFilter.stokAman:
        if (item.stokBarang <= kLowStockThreshold) return false;
      case DashboardQuickFilter.telur:
        if (!lowerName.contains('telur')) return false;
      case DashboardQuickFilter.sembako:
        if (lowerName.contains('telur')) return false;
    }

    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return lowerName.contains(q) ||
        item.satuan.toLowerCase().contains(q) ||
        item.stokBarang.toString().contains(q) ||
        _safeIntString(item.hargaSatuan).contains(q);
  }

  /// Daftar barang setelah filter cepat & query pencarian diterapkan.
  List<Barang> get filteredBarang {
    return _barang.where(_matchesBarang).toList(growable: false);
  }

  /// Daftar barang dengan stok kritis/menipis (`<= 10`), diurutkan paling kritis dulu.
  List<Barang> get lowStockItems {
    final items = filteredBarang
        .where((item) => item.stokBarang <= kLowStockThreshold)
        .toList();
    items.sort((a, b) {
      final cmp = a.stokBarang.compareTo(b.stokBarang);
      if (cmp != 0) return cmp;
      return a.namaBarang.toLowerCase().compareTo(b.namaBarang.toLowerCase());
    });
    return List.unmodifiable(items);
  }

  /// Daftar barang dengan stok sehat (`> 10`).
  List<Barang> get normalStockItems {
    return List.unmodifiable(
      filteredBarang.where((item) => item.stokBarang > kLowStockThreshold),
    );
  }

  /// Item stok menipis untuk pratinjau beranda (maksimal 2 jika mode default).
  List<Barang> get previewLowStockItems {
    final items = lowStockItems;
    if (hasActiveSearchOrFilter || items.length <= 2) {
      return items;
    }
    return List.unmodifiable(items.take(2));
  }

  /// Item stok normal untuk pratinjau beranda (maksimal 4 jika mode default).
  List<Barang> get previewNormalStockItems {
    final items = normalStockItems;
    if (hasActiveSearchOrFilter || items.length <= 4) {
      return items;
    }
    return List.unmodifiable(items.take(4));
  }

  List<Supplier> get filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliers;
    final q = _searchQuery.toLowerCase();
    return List.unmodifiable(
      _suppliers.where(
        (s) =>
            s.namaSupplier.toLowerCase().contains(q) ||
            s.alamatSupplier.toLowerCase().contains(q) ||
            s.noTelpSupplier.toLowerCase().contains(q),
      ),
    );
  }

  List<Customer> get filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final q = _searchQuery.toLowerCase();
    return List.unmodifiable(
      _customers.where((c) => c.namaCustomer.toLowerCase().contains(q)),
    );
  }

  List<Nota> get filteredNotas {
    if (_searchQuery.isEmpty) return _notas;
    final q = _searchQuery.toLowerCase();
    return List.unmodifiable(
      _notas.where(
        (n) =>
            n.remoteId.toLowerCase().contains(q) ||
            n.tanggalNota.toLowerCase().contains(q) ||
            (n.namaCustomer ?? '').toLowerCase().contains(q) ||
            (n.namaPetugas ?? '').toLowerCase().contains(q) ||
            (n.idNota?.toString() ?? '').contains(q) ||
            _safeIntString(n.total).contains(q),
      ),
    );
  }

  List<Faktur> get filteredFakturs {
    if (_searchQuery.isEmpty) return _fakturs;
    final q = _searchQuery.toLowerCase();
    return List.unmodifiable(
      _fakturs.where(
        (f) =>
            f.noFaktur.toLowerCase().contains(q) ||
            (f.namaSupplier ?? '').toLowerCase().contains(q) ||
            f.remoteId.toLowerCase().contains(q) ||
            f.tanggalFaktur.toLowerCase().contains(q) ||
            (f.idFaktur?.toString() ?? '').contains(q) ||
            _safeIntString(f.total).contains(q),
      ),
    );
  }

  int get secondaryMatchCount {
    if (_searchQuery.isEmpty) return 0;
    return filteredSuppliers.length +
        filteredCustomers.length +
        filteredFakturs.length +
        (isOwner ? filteredNotas.length : 0);
  }

  /// Daftar notifikasi terurut berdasarkan urgensi (kritis -> peringatan -> info).
  List<AppNotificationItem> get notifications {
    final result = <AppNotificationItem>[];
    final state = syncState;
    final now = DateTime.now();

    final rawError = state.lastError?.trim() ?? '';
    if (rawError.isNotEmpty) {
      final id = 'sync-error:${rawError.hashCode}';
      result.add(
        AppNotificationItem(
          id: id,
          title: 'Sinkronisasi Cloud Gagal',
          message:
              'Terjadi kendala saat menyinkronkan ke Firebase. Data tetap aman tersimpan di SQLite lokal.',
          severity: NotificationSeverity.critical,
          createdAt: now,
          isRead: _readNotificationIds.contains(id),
          isSyncAlert: true,
        ),
      );
    }

    if (!state.isOnline && state.pendingCount > 0) {
      final id = 'sync-offline-pending:${state.pendingCount}';
      result.add(
        AppNotificationItem(
          id: id,
          title: 'Mode Offline · Data Menunggu Sync',
          message:
              '${state.pendingCount} perubahan tersimpan di SQLite dan akan otomatis terunggah saat koneksi kembali.',
          severity: NotificationSeverity.warning,
          createdAt: now,
          isRead: _readNotificationIds.contains(id),
          isSyncAlert: true,
        ),
      );
    } else if (state.isOnline &&
        !state.isSyncing &&
        state.pendingCount > 0) {
      final id = 'sync-pending:${state.pendingCount}';
      result.add(
        AppNotificationItem(
          id: id,
          title: '${state.pendingCount} Data Belum Tersinkron',
          message:
              'Tekan Sinkron Sekarang untuk mengunggah antrean lokal ke Cloud Firestore.',
          severity: NotificationSeverity.info,
          createdAt: now,
          isRead: _readNotificationIds.contains(id),
          isSyncAlert: true,
        ),
      );
    }

    final sortedBarang = List<Barang>.from(_barang)
      ..sort((a, b) {
        final cmp = a.stokBarang.compareTo(b.stokBarang);
        if (cmp != 0) return cmp;
        return a.namaBarang.toLowerCase().compareTo(b.namaBarang.toLowerCase());
      });

    final seenKeys = <String, int>{};
    for (final item in sortedBarang) {
      final normalizedName = item.namaBarang.trim();
      final rawKey = item.remoteId.isNotEmpty
          ? item.remoteId
          : (item.idBarang != null
                ? 'id:${item.idBarang}'
                : 'name:${normalizedName.isEmpty ? 'unnamed' : normalizedName}');
      final occurrence = seenKeys.update(
        rawKey,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      final key = occurrence == 0 ? rawKey : '$rawKey#$occurrence';
      if (item.stokBarang <= 0) {
        final id = 'stock-empty:$key:${item.stokBarang}';
        result.add(
          AppNotificationItem(
            id: id,
            title: 'Stok Habis · ${item.namaBarang}',
            message:
                'Sisa ${item.stokBarang} ${item.satuan}. Segera lakukan restock barang masuk.',
            severity: NotificationSeverity.critical,
            createdAt: item.updatedAt,
            isRead: _readNotificationIds.contains(id),
            barangRemoteId: item.remoteId,
            barangNama: item.namaBarang,
            currentStock: item.stokBarang,
            satuan: item.satuan,
          ),
        );
      } else if (item.stokBarang <= kLowStockThreshold) {
        final id = 'stock-low:$key:${item.stokBarang}';
        result.add(
          AppNotificationItem(
            id: id,
            title: 'Stok Menipis · ${item.namaBarang}',
            message:
                'Sisa ${item.stokBarang} ${item.satuan} (batas minimum $kLowStockThreshold).',
            severity: NotificationSeverity.warning,
            createdAt: item.updatedAt,
            isRead: _readNotificationIds.contains(id),
            barangRemoteId: item.remoteId,
            barangNama: item.namaBarang,
            currentStock: item.stokBarang,
            satuan: item.satuan,
          ),
        );
      } else if (item.stokBarang <= kWatchStockThreshold) {
        final id = 'stock-watch:$key:${item.stokBarang}';
        result.add(
          AppNotificationItem(
            id: id,
            title: 'Pantauan Stok · ${item.namaBarang}',
            message:
                'Sisa ${item.stokBarang} ${item.satuan}, mendekati batas minimum.',
            severity: NotificationSeverity.info,
            createdAt: item.updatedAt,
            isRead: _readNotificationIds.contains(id),
            barangRemoteId: item.remoteId,
            barangNama: item.namaBarang,
            currentStock: item.stokBarang,
            satuan: item.satuan,
          ),
        );
      }
    }

    return List.unmodifiable(result);
  }

  int get unreadCount {
    var count = 0;
    for (final item in notifications) {
      if (!item.isRead) count++;
    }
    return count;
  }

  String get unreadBadgeText {
    final count = unreadCount;
    if (count <= 0) return '';
    if (count > 99) return '99+';
    return '$count';
  }

  void markNotificationRead(String notificationId) {
    if (notificationId.trim().isEmpty ||
        _readNotificationIds.contains(notificationId) ||
        !notifications.any((item) => item.id == notificationId)) {
      return;
    }
    _readNotificationIds.add(notificationId);
    _safeNotify();
  }

  void markAllNotificationsRead() {
    var changed = false;
    for (final item in notifications) {
      if (_readNotificationIds.add(item.id)) {
        changed = true;
      }
    }
    if (changed) {
      _safeNotify();
    }
  }

  void _pruneStaleReadIds() {
    if (_readNotificationIds.isEmpty) return;
    final activeIds = notifications.map((item) => item.id).toSet();
    _readNotificationIds.retainAll(activeIds);
  }

  /// Memicu sinkronisasi manual SQLite <-> Firebase dari Pusat Notifikasi.
  Future<void> triggerManualSync() async {
    if (_disposed || _isManualSyncing) return;
    _isManualSyncing = true;
    _syncErrorMessage = null;
    _safeNotify();
    try {
      await _dataSource.syncNow();
      await loadDashboardData();
    } catch (_) {
      if (!_disposed) {
        _syncErrorMessage = 'Gagal menjalankan sinkronisasi manual.';
      }
    } finally {
      if (!_disposed) {
        _isManualSyncing = false;
        _safeNotify();
      }
    }
  }

  void _handleSyncChanged() {
    _pruneStaleReadIds();
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _dataSub?.cancel();
    _dataSource.syncListenable?.removeListener(_handleSyncChanged);
    super.dispose();
  }
}
