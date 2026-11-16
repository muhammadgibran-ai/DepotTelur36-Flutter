import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';

/// ViewModel Fungsi 6: Pemantauan Stok Menipis & Aksi Restok (`22 Stok Menipis`).
class RestockMonitorViewModel extends ChangeNotifier {
  RestockMonitorViewModel({
    required AuthSession session,
    required TransactionCrudDataSource dataSource,
    this.lowThreshold = kLowStockThreshold,
    this.watchThreshold = kWatchMonitorThreshold,
  }) {
    if (lowThreshold <= 0) {
      throw ArgumentError.value(
        lowThreshold,
        'lowThreshold',
        'Batas stok kritis harus lebih dari 0.',
      );
    }
    if (watchThreshold < lowThreshold) {
      throw ArgumentError.value(
        watchThreshold,
        'watchThreshold',
        'Batas pantauan tidak boleh kurang dari lowThreshold.',
      );
    }
    _session = session;
    _dataSource = dataSource;
    _subscription = _dataSource.onDataChanged.listen(
      (_) => unawaited(loadData(silent: true)),
      onError: (_) {},
    );
  }

  factory RestockMonitorViewModel.fromRepository({
    required AuthSession session,
    required InventoryRepository repository,
    int lowThreshold = kLowStockThreshold,
    int watchThreshold = kWatchMonitorThreshold,
  }) {
    return RestockMonitorViewModel(
      session: session,
      dataSource: RepositoryTransactionCrudDataSource(repository),
      lowThreshold: lowThreshold,
      watchThreshold: watchThreshold,
    );
  }

  static const int _maxRestockQty = 9999999;

  late final TransactionCrudDataSource _dataSource;
  final int lowThreshold;
  final int watchThreshold;

  AuthSession _session = AuthSession(
    uid: '',
    email: '',
    accountId: '',
    displayName: '',
    role: UserRole.petugas,
    petugasRemoteId: '',
    provider: AuthProviderType.offlineLocal,
    signedInAt: DateTime(2026),
  );

  StreamSubscription<void>? _subscription;
  int _loadEpoch = 0;
  bool _disposed = false;

  bool _isLoading = false;
  String? _errorMessage;
  int _errorShakePulse = 0;
  StokMenipisFilter _filter = StokMenipisFilter.kritis;

  List<Barang> _barangs = const [];
  List<Supplier> _suppliers = const [];
  List<Faktur> _fakturs = const [];
  final Map<String, int> _customDraftQtys = <String, int>{};

  AuthSession get session => _session;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get errorShakePulse => _errorShakePulse;
  StokMenipisFilter get filter => _filter;
  List<Barang> get barangs => _barangs;
  List<Supplier> get suppliers => _suppliers;
  List<Faktur> get fakturs => _fakturs;

  String _itemKey(Barang barang) {
    if (barang.idBarang != null && barang.idBarang! > 0) {
      return 'id_${barang.idBarang}';
    }
    final trimmedRemote = barang.remoteId.trim();
    if (trimmedRemote.isNotEmpty) return 'remote_$trimmedRemote';
    return 'name_${barang.namaBarang.trim().toLowerCase()}';
  }

  /// Menghitung saran restok awal agar stok kembali berada pada rentang aman.
  int suggestedRestockQtyFor(Barang barang) {
    final stock = barang.stokBarang < 0 ? 0 : barang.stokBarang;
    if (stock <= lowThreshold) {
      final safeTarget = math.max(lowThreshold * 2, 20);
      return (safeTarget - stock).clamp(1, _maxRestockQty);
    }
    if (stock <= watchThreshold) {
      final safeTarget = watchThreshold + 5;
      return (safeTarget - stock).clamp(5, _maxRestockQty);
    }
    return 10;
  }

  /// Mengembalikan jumlah draft restok per barang (custom user atau saran otomatis).
  int draftQtyFor(Barang barang) {
    final custom = _customDraftQtys[_itemKey(barang)];
    if (custom != null && custom >= 1 && custom <= _maxRestockQty) {
      return custom;
    }
    return suggestedRestockQtyFor(barang);
  }

  /// Snapshot pemantauan stok lengkap, terurut dari stok paling kritis.
  RestockSummarySnapshot get snapshot {
    if (_barangs.isEmpty) {
      return RestockSummarySnapshot.empty(
        filter: _filter,
        lowThreshold: lowThreshold,
        watchThreshold: watchThreshold,
      );
    }

    final supplierById = <int, Supplier>{
      for (final s in _suppliers)
        if (s.idSupplier != null) s.idSupplier!: s,
    };
    final supplierByRemote = <String, Supplier>{
      for (final s in _suppliers)
        if (s.remoteId.trim().isNotEmpty) s.remoteId.trim(): s,
    };

    final sortedFakturs = List<Faktur>.from(_fakturs)
      ..sort((a, b) {
        final dateCmp = b.tanggalFaktur.compareTo(a.tanggalFaktur);
        if (dateCmp != 0) return dateCmp;
        final idCmp = (b.idFaktur ?? 0).compareTo(a.idFaktur ?? 0);
        if (idCmp != 0) return idCmp;
        return b.updatedAt.compareTo(a.updatedAt);
      });

    final lastSupplierByBarangKey = <String, _LastSupplierMeta>{};
    for (final faktur in sortedFakturs) {
      final supRemote = faktur.supplierRemoteId?.trim() ?? '';
      final matchedSup =
          (supRemote.isNotEmpty ? supplierByRemote[supRemote] : null) ??
          supplierById[faktur.idSupplier];
      final supName = matchedSup?.namaSupplier ??
          (faktur.namaSupplier?.trim().isNotEmpty == true
              ? faktur.namaSupplier!.trim()
              : null);
      if (supName == null) continue;

      final resolvedSupplierId = matchedSup?.idSupplier ??
          (faktur.idSupplier > 0 ? faktur.idSupplier : null);
      final resolvedSupplierRemote =
          matchedSup?.remoteId ?? (supRemote.isNotEmpty ? supRemote : null);
      final meta = _LastSupplierMeta(
        supplierId: resolvedSupplierId,
        supplierRemoteId: resolvedSupplierRemote,
        supplierName: supName,
        tanggalFaktur: faktur.tanggalFaktur,
      );

      for (final detail in faktur.details) {
        final candidateKeys = <String>[
          if (detail.idBarang > 0) 'id_${detail.idBarang}',
          if (detail.barangRemoteId?.trim().isNotEmpty == true)
            'remote_${detail.barangRemoteId!.trim()}',
        ];
        for (final key in candidateKeys) {
          lastSupplierByBarangKey.putIfAbsent(key, () => meta);
        }
      }
    }

    final sortedBarangs = List<Barang>.from(_barangs)
      ..sort((a, b) {
        final stockCmp = a.stokBarang.compareTo(b.stokBarang);
        if (stockCmp != 0) return stockCmp;
        return a.namaBarang
            .trim()
            .toLowerCase()
            .compareTo(b.namaBarang.trim().toLowerCase());
      });

    var outOfStockCount = 0;
    var criticalCount = 0;
    var watchBandCount = 0;

    final criticalItems = <RestockMonitorItem>[];
    final watchOnlyItems = <RestockMonitorItem>[];
    final safeItems = <RestockMonitorItem>[];

    for (final barang in sortedBarangs) {
      final stock = barang.stokBarang;
      final StockAlertLevel level;
      if (stock <= 0) {
        level = StockAlertLevel.habis;
        outOfStockCount++;
        criticalCount++;
      } else if (stock <= lowThreshold) {
        level = StockAlertLevel.kritis;
        criticalCount++;
      } else if (stock <= watchThreshold) {
        level = StockAlertLevel.pantauan;
        watchBandCount++;
      } else {
        level = StockAlertLevel.aman;
      }

      final meta = lastSupplierByBarangKey[_itemKey(barang)] ??
          (barang.remoteId.trim().isNotEmpty
              ? lastSupplierByBarangKey['remote_${barang.remoteId.trim()}']
              : null);

      final meterRatio = stock <= 0
          ? 0.0
          : (stock / lowThreshold).clamp(0.08, 1.0);

      final item = RestockMonitorItem(
        barang: barang,
        alertLevel: level,
        suggestedQty: suggestedRestockQtyFor(barang),
        draftQty: draftQtyFor(barang),
        meterRatio: meterRatio,
        lastSupplierId: meta?.supplierId,
        lastSupplierRemoteId: meta?.supplierRemoteId,
        lastSupplierName: meta?.supplierName,
        lastRestockDate: meta?.tanggalFaktur,
      );

      if (item.isCritical) {
        criticalItems.add(item);
      } else if (item.isWatchOnly) {
        watchOnlyItems.add(item);
      } else {
        safeItems.add(item);
      }
    }

    return RestockSummarySnapshot(
      filter: _filter,
      lowThreshold: lowThreshold,
      watchThreshold: watchThreshold,
      outOfStockCount: outOfStockCount,
      criticalCount: criticalCount,
      watchBandCount: watchBandCount,
      totalCatalogCount: sortedBarangs.length,
      criticalItems: List.unmodifiable(criticalItems),
      watchOnlyItems: List.unmodifiable(watchOnlyItems),
      safeItems: List.unmodifiable(safeItems),
    );
  }

  void updateSession(AuthSession nextSession) {
    if (_session == nextSession) return;
    final uidChanged = nextSession.uid != _session.uid;
    _session = nextSession;
    if (uidChanged) {
      _customDraftQtys.clear();
      _filter = StokMenipisFilter.kritis;
      _errorMessage = null;
    }
    _notifySafely();
  }

  Future<void> loadData({bool silent = false}) async {
    final epoch = ++_loadEpoch;
    if (!silent) {
      _isLoading = true;
      _notifySafely();
    }

    try {
      final results = await Future.wait<dynamic>([
        _dataSource.getAllBarang(),
        _dataSource.getAllSupplier(),
        _dataSource.getAllFaktur(),
      ]);
      if (_disposed || epoch != _loadEpoch) return;

      _barangs = List<Barang>.unmodifiable(results[0] as List<Barang>);
      _suppliers = List<Supplier>.unmodifiable(results[1] as List<Supplier>);
      _fakturs = List<Faktur>.unmodifiable(results[2] as List<Faktur>);

      final validKeys = _barangs.map(_itemKey).toSet();
      _customDraftQtys.removeWhere((k, _) => !validKeys.contains(k));
      _errorMessage = null;
    } catch (e) {
      if (_disposed || epoch != _loadEpoch) return;
      _errorMessage = 'Gagal memuat pemantauan stok: $e';
    } finally {
      if (!_disposed && epoch == _loadEpoch) {
        _isLoading = false;
        _notifySafely();
      }
    }
  }

  void selectFilter(StokMenipisFilter next) {
    if (_filter == next) return;
    _filter = next;
    _errorMessage = null;
    _notifySafely();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    _notifySafely();
  }

  /// Mengubah draft jumlah restok per barang dengan penegakan batas `1..9.999.999`.
  bool adjustDraftQty(Barang barang, int delta) {
    final current = draftQtyFor(barang);
    if (delta == 0) return true;
    if (delta > 0 && delta > _maxRestockQty - current) {
      _failValidation(
        'Jumlah restok "${barang.namaBarang}" maksimal 9.999.999.',
      );
      return false;
    }
    if (delta < 0 && delta < 1 - current) {
      _failValidation(
        'Jumlah restok "${barang.namaBarang}" minimal 1 ${barang.satuan}.',
      );
      return false;
    }
    return setDraftQty(barang, current + delta);
  }

  bool setDraftQty(Barang barang, int qty) {
    if (qty < 1) {
      _failValidation(
        'Jumlah restok "${barang.namaBarang}" minimal 1 ${barang.satuan}.',
      );
      return false;
    }
    if (qty > _maxRestockQty) {
      _failValidation(
        'Jumlah restok "${barang.namaBarang}" maksimal 9.999.999.',
      );
      return false;
    }
    _customDraftQtys[_itemKey(barang)] = qty;
    _errorMessage = null;
    _notifySafely();
    return true;
  }

  void resetDraftQty(Barang barang) {
    if (_customDraftQtys.remove(_itemKey(barang)) != null) {
      _errorMessage = null;
      _notifySafely();
    }
  }

  /// Mempersiapkan keranjang `FakturMasuk` di [transactionVm] beserta supplier terakhir bila ada.
  int? prepareRestockDraft(
    RestockMonitorItem item, {
    required TransactionCrudViewModel transactionVm,
  }) {
    final barang = item.barang;
    if (barang.idBarang == null ||
        barang.idBarang! <= 0 ||
        barang.namaBarang.trim().isEmpty) {
      _failValidation('Barang "${barang.namaBarang}" belum tersimpan di katalog.');
      return null;
    }
    if (item.draftQty < 1 || item.draftQty > _maxRestockQty) {
      _failValidation(
        'Jumlah restok "${barang.namaBarang}" harus antara 1 sampai 9.999.999.',
      );
      return null;
    }
    final safeQty = item.draftQty;
    transactionVm.prefillFakturRestock(
      barang.namaBarang,
      barangId: barang.idBarang,
      defaultQty: safeQty,
      overrideExisting: true,
      supplierId: item.lastSupplierId,
      supplierRemoteId: item.lastSupplierRemoteId,
    );
    _errorMessage = null;
    _notifySafely();
    return safeQty;
  }

  void _failValidation(String message) {
    _errorMessage = message;
    _errorShakePulse++;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class _LastSupplierMeta {
  const _LastSupplierMeta({
    this.supplierId,
    required this.supplierRemoteId,
    required this.supplierName,
    required this.tanggalFaktur,
  });

  final int? supplierId;
  final String? supplierRemoteId;
  final String supplierName;
  final String tanggalFaktur;
}
