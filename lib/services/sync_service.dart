import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';

/// Ringkasan status koneksi & sinkronisasi untuk banner UI.
class SyncState {
  const SyncState({
    this.isOnline = false,
    this.isSyncing = false,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool isOnline;
  final bool isSyncing;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  SyncState copyWith({
    bool? isOnline,
    bool? isSyncing,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Mesin Auto-Sync Offline-First & Realtime Listener antara SQLite lokal
/// dan Cloud Firestore (`depottelur36-570a9`).
class SyncService extends ChangeNotifier {
  SyncService({
    DatabaseHelper? dbHelper,
    FirebaseFirestore? firestore,
    Connectivity? connectivity,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _firestoreOverride = firestore,
        _connectivity = connectivity ?? Connectivity();

  final DatabaseHelper _dbHelper;
  final FirebaseFirestore? _firestoreOverride;
  final Connectivity _connectivity;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static const String colSupplier = 'supplier';
  static const String colPetugas = 'petugas';
  static const String colCustomer = 'customer';
  static const String colBarang = 'barang';
  static const String colFaktur = 'faktur';
  static const String colNota = 'nota';

  final StreamController<void> _dataUpdatedController =
      StreamController<void>.broadcast();
  Stream<void> get onDataUpdated => _dataUpdatedController.stream;

  SyncState _state = const SyncState();
  SyncState get state => _state;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _firestoreSubs = [];

  bool _isStarted = false;
  bool _isSyncing = false;
  bool _resyncRequested = false;
  bool _listenersAttached = false;
  bool _cloudSeedChecked = false;
  bool _disposed = false;
  Future<void> _serialTail = Future.value();
  final Map<String, Map<String, dynamic>> _deferredCloudFaktur = {};
  final Map<String, Map<String, dynamic>> _deferredCloudNota = {};

  Future<void> _runSerialized(Future<void> Function() action) {
    final completer = Completer<void>();
    _serialTail = _serialTail.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      try {
        await action();
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Menunggu seluruh pekerjaan sinkronisasi berantai selesai (khusus pengujian).
  @visibleForTesting
  Future<void> flushPendingTasks() => _serialTail.catchError((_) {});

  /// Memulai pemantauan jaringan, auto-sync, dan realtime listener Firestore.
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;

    await refreshPendingCount();

    final currentResults = await _connectivity.checkConnectivity();
    final online = _hasNetwork(currentResults);
    _updateState(_state.copyWith(isOnline: online));

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final nowOnline = _hasNetwork(results);
      final wasOffline = !_state.isOnline;
      _updateState(_state.copyWith(isOnline: nowOnline));

      if (nowOnline) {
        _attachRealtimeListenersIfNeeded();
        if (wasOffline || _state.pendingCount > 0) {
          unawaited(syncNow());
        }
      }
    });

    if (online) {
      _attachRealtimeListenersIfNeeded();
      await syncNow();
    }
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> refreshPendingCount() async {
    final count = await _dbHelper.getPendingSyncCount();
    _updateState(_state.copyWith(pendingCount: count));
  }

  Future<void> trySyncIfOnline() async {
    await refreshPendingCount();
    final results = await _connectivity.checkConnectivity();
    final online = _hasNetwork(results);
    _updateState(_state.copyWith(isOnline: online));
    if (online) {
      _attachRealtimeListenersIfNeeded();
      await syncNow();
    }
  }

  /// Mendorong seluruh antrean `PENDING` dari SQLite ke Cloud Firestore,
  /// memastikan koleksi awal Firestore terbuat, dan menyegarkan count lokal.
  Future<void> syncNow() async {
    if (_disposed) return;
    if (_isSyncing) {
      _resyncRequested = true;
      return;
    }
    _isSyncing = true;
    _updateState(_state.copyWith(isSyncing: true, clearError: true));

    try {
      await _runSerialized(() async {
        await _pushPendingDeletes();
        await _seedCloudCollectionsIfEmpty();
        await _pushPendingMasters();
        await _pushPendingFaktur();
        await _pushPendingNota();
      });

      if (_disposed) return;
      final remaining = await _dbHelper.getPendingSyncCount();
      _updateState(
        _state.copyWith(
          isSyncing: false,
          pendingCount: remaining,
          lastSyncedAt: DateTime.now(),
          clearError: true,
        ),
      );
      _notifyUpdated();
    } catch (e) {
      if (!_disposed) {
        final remaining = await _dbHelper.getPendingSyncCount();
        _updateState(
          _state.copyWith(
            isSyncing: false,
            pendingCount: remaining,
            lastError: e.toString(),
          ),
        );
      }
    } finally {
      _isSyncing = false;
      if (!_disposed && _resyncRequested) {
        _resyncRequested = false;
        unawaited(syncNow());
      }
    }
  }

  /// Menghitung stok dasar sebelum mutasi transaksi `PENDING` agar stok di Cloud
  /// tidak terhitung ganda ketika antrean `faktur`/`nota` ikut di-push.
  Future<Barang> _barangWithBaseStock(Barang barang) async {
    final delta =
        await _dbHelper.getPendingStockDeltaForBarang(barang.idBarang ?? 0);
    final baseStock = barang.stokBarang - delta.pendingIn + delta.pendingOut;
    return barang.copyWith(stokBarang: baseStock < 0 ? 0 : baseStock);
  }

  /// Mengisi koleksi Firestore secara otomatis jika database Cloud masih kosong
  /// sehingga `supplier`, `petugas`, `customer`, dan `barang` langsung muncul di Console.
  Future<void> _seedCloudCollectionsIfEmpty() async {
    if (_cloudSeedChecked) return;

    final existingBarang =
        await _firestore.collection(colBarang).limit(1).get();
    final existingPetugas =
        await _firestore.collection(colPetugas).limit(1).get();

    if (existingBarang.docs.isEmpty && existingPetugas.docs.isEmpty) {
      final batch = _firestore.batch();

      for (final p in await _dbHelper.getAllPetugas()) {
        batch.set(
          _firestore.collection(colPetugas).doc(p.remoteId),
          p.toFirestore(),
          SetOptions(merge: true),
        );
      }
      for (final s in await _dbHelper.getAllSupplier()) {
        batch.set(
          _firestore.collection(colSupplier).doc(s.remoteId),
          s.toFirestore(),
          SetOptions(merge: true),
        );
      }
      for (final c in await _dbHelper.getAllCustomer()) {
        batch.set(
          _firestore.collection(colCustomer).doc(c.remoteId),
          c.toFirestore(),
          SetOptions(merge: true),
        );
      }
      for (final b in await _dbHelper.getAllBarang()) {
        final seededBarang = await _barangWithBaseStock(b);
        batch.set(
          _firestore.collection(colBarang).doc(b.remoteId),
          seededBarang.toFirestore(),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    _cloudSeedChecked = true;
  }

  Future<void> _pushPendingDeletes() async {
    final deletes = await _dbHelper.getPendingDeletes();
    for (final entry in deletes) {
      final collection = switch (entry.tableName) {
        'supplier' => colSupplier,
        'petugas' => colPetugas,
        'customer' => colCustomer,
        'barang' => colBarang,
        'faktur' => colFaktur,
        'nota' => colNota,
        _ => null,
      };
      if (collection != null && entry.remoteId.isNotEmpty) {
        await _firestore.collection(collection).doc(entry.remoteId).delete();
      }
      await _dbHelper.removePendingDelete(entry.tableName, entry.remoteId);
    }
  }

  Future<void> _pushPendingMasters() async {
    for (final s in await _dbHelper.getPendingSuppliers()) {
      await _firestore
          .collection(colSupplier)
          .doc(s.remoteId)
          .set(s.toFirestore(), SetOptions(merge: true));
      await _dbHelper.markSynced('supplier', s.remoteId);
    }

    for (final p in await _dbHelper.getPendingPetugas()) {
      await _firestore
          .collection(colPetugas)
          .doc(p.remoteId)
          .set(p.toFirestore(), SetOptions(merge: true));
      await _dbHelper.markSynced('petugas', p.remoteId);
    }

    for (final c in await _dbHelper.getPendingCustomers()) {
      await _firestore
          .collection(colCustomer)
          .doc(c.remoteId)
          .set(c.toFirestore(), SetOptions(merge: true));
      await _dbHelper.markSynced('customer', c.remoteId);
    }

    for (final b in await _dbHelper.getPendingBarang()) {
      final baseBarang = await _barangWithBaseStock(b);
      await _firestore
          .collection(colBarang)
          .doc(b.remoteId)
          .set(baseBarang.toFirestore(), SetOptions(merge: true));
      await _dbHelper.markSynced('barang', b.remoteId);
    }
  }

  Future<void> _pushPendingFaktur() async {
    final pendingList = await _dbHelper.getPendingFaktur();
    for (final faktur in pendingList) {
      final batch = _firestore.batch();
      final fakturRef =
          _firestore.collection(colFaktur).doc(faktur.remoteId);
      batch.set(fakturRef, faktur.toFirestore());

      for (final item in faktur.details) {
        final barangRemoteId = item.barangRemoteId;
        if (barangRemoteId != null && barangRemoteId.isNotEmpty) {
          final barangRef =
              _firestore.collection(colBarang).doc(barangRemoteId);
          batch.set(
            barangRef,
            {
              'stok_barang': FieldValue.increment(item.quantity),
              'updated_at': faktur.updatedAt.toIso8601String(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();
      await _dbHelper.markSynced('faktur', faktur.remoteId);
    }
  }

  Future<void> _pushPendingNota() async {
    final pendingList = await _dbHelper.getPendingNota();
    for (final nota in pendingList) {
      final batch = _firestore.batch();
      final notaRef = _firestore.collection(colNota).doc(nota.remoteId);
      batch.set(notaRef, nota.toFirestore());

      for (final item in nota.details) {
        final barangRemoteId = item.barangRemoteId;
        if (barangRemoteId != null && barangRemoteId.isNotEmpty) {
          final barangRef =
              _firestore.collection(colBarang).doc(barangRemoteId);
          batch.set(
            barangRef,
            {
              'stok_barang': FieldValue.increment(-item.banyaknya),
              'updated_at': nota.updatedAt.toIso8601String(),
            },
            SetOptions(merge: true),
          );
        }
      }

      await batch.commit();
      await _dbHelper.markSynced('nota', nota.remoteId);
    }
  }

  void _attachRealtimeListenersIfNeeded() {
    if (_listenersAttached || _disposed) return;
    _listenersAttached = true;

    _listenMasterCollection(colSupplier, (data, id) {
      return _dbHelper.applyCloudSupplier(Supplier.fromFirestore(data, id));
    });
    _listenMasterCollection(colPetugas, (data, id) {
      return _dbHelper.applyCloudPetugas(Petugas.fromFirestore(data, id));
    });
    _listenMasterCollection(colCustomer, (data, id) {
      return _dbHelper.applyCloudCustomer(Customer.fromFirestore(data, id));
    });
    _listenMasterCollection(colBarang, (data, id) {
      return _dbHelper.applyCloudBarang(Barang.fromFirestore(data, id));
    });

    _listenCollection(colFaktur, (snap) {
      return _applyTransactionList(
        'faktur',
        snap.docs.map((d) => MapEntry(d.id, d.data())),
        _deferredCloudFaktur,
        _dbHelper.insertCloudFakturIfMissing,
        pruneMissingFromDeferred: true,
      );
    });

    _listenCollection(colNota, (snap) {
      return _applyTransactionList(
        'nota',
        snap.docs.map((d) => MapEntry(d.id, d.data())),
        _deferredCloudNota,
        _dbHelper.insertCloudNotaIfMissing,
        pruneMissingFromDeferred: true,
      );
    });
  }

  void _listenMasterCollection(
    String collection,
    Future<void> Function(Map<String, dynamic> data, String id) applier,
  ) {
    _listenCollection(collection, (snap) async {
      for (final doc in snap.docs) {
        if (_disposed) return false;
        await applier(doc.data(), doc.id);
      }
      if (_disposed) return false;
      final retried = await _retryDeferredCloudTransactions();
      return snap.docs.isNotEmpty || retried;
    });
  }

  Future<bool> _applyTransactionList(
    String table,
    Iterable<MapEntry<String, Map<String, dynamic>>> entries,
    Map<String, Map<String, dynamic>> deferredPool,
    Future<bool> Function({
      required String remoteId,
      required Map<String, dynamic> data,
    }) inserter, {
    bool pruneMissingFromDeferred = false,
  }) async {
    final snapshotEntries = entries.toList();
    if (pruneMissingFromDeferred) {
      final activeRemoteIds = snapshotEntries.map((e) => e.key).toSet();
      deferredPool.removeWhere((key, _) => !activeRemoteIds.contains(key));
    }
    var inserted = false;
    for (final entry in snapshotEntries) {
      if (_disposed) return inserted;
      if (await _dbHelper.hasPendingDelete(table, entry.key)) {
        deferredPool.remove(entry.key);
        continue;
      }
      if (_disposed) return inserted;
      final ok = await inserter(remoteId: entry.key, data: entry.value);
      if (ok) {
        inserted = true;
        deferredPool.remove(entry.key);
      } else if (await _dbHelper.hasRemoteRecord(table, entry.key)) {
        deferredPool.remove(entry.key);
      } else {
        deferredPool[entry.key] = entry.value;
      }
    }
    return inserted;
  }

  Future<bool> _retryDeferredCloudTransactions() async {
    var changed = false;
    if (_deferredCloudFaktur.isNotEmpty) {
      final ok = await _applyTransactionList(
        'faktur',
        _deferredCloudFaktur.entries,
        _deferredCloudFaktur,
        _dbHelper.insertCloudFakturIfMissing,
      );
      if (ok) changed = true;
    }
    if (_deferredCloudNota.isNotEmpty) {
      final ok = await _applyTransactionList(
        'nota',
        _deferredCloudNota.entries,
        _deferredCloudNota,
        _dbHelper.insertCloudNotaIfMissing,
      );
      if (ok) changed = true;
    }
    return changed;
  }

  void _listenCollection(
    String collection,
    Future<bool> Function(QuerySnapshot<Map<String, dynamic>> snap) applySnap,
  ) {
    _firestoreSubs.add(
      _firestore.collection(collection).snapshots().listen(
        (snap) {
          unawaited(
            _runSerialized(() async {
              final changed = await applySnap(snap);
              if (changed) _notifyUpdated();
            }),
          );
        },
        onError: (Object error) {
          _updateState(_state.copyWith(lastError: error.toString()));
        },
      ),
    );
  }

  void _notifyUpdated() {
    if (_disposed || _dataUpdatedController.isClosed) return;
    _dataUpdatedController.add(null);
  }

  void _updateState(SyncState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connectivitySub?.cancel();
    for (final sub in _firestoreSubs) {
      sub.cancel();
    }
    _firestoreSubs.clear();
    _dataUpdatedController.close();
    super.dispose();
  }
}
