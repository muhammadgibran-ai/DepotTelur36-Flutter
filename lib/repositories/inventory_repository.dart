import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/services/sync_service.dart';

/// Single Source of Truth untuk seluruh operasi data DepotTelur36.
/// Setiap input selalu disimpan ke SQLite lokal terlebih dahulu (100% jalan saat offline),
/// lalu dipicu untuk auto-sync ke Cloud Firestore bila koneksi internet tersedia.
class InventoryRepository {
  InventoryRepository({
    DatabaseHelper? dbHelper,
    SyncService? syncService,
    Uuid? uuid,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        syncService = syncService ?? SyncService(dbHelper: dbHelper),
        _uuid = uuid ?? const Uuid();

  final DatabaseHelper _dbHelper;
  final SyncService syncService;
  final Uuid _uuid;

  final StreamController<void> _localChangesController =
      StreamController<void>.broadcast();

  StreamSubscription<void>? _syncDataSub;
  bool _initialized = false;

  /// Stream gabungan yang memberi tahu ViewModel saat ada perubahan lokal maupun dari Cloud.
  Stream<void> get onDataChanged => _localChangesController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _dbHelper.database;
    _syncDataSub = syncService.onDataUpdated.listen((_) {
      if (!_localChangesController.isClosed) {
        _localChangesController.add(null);
      }
    });
    await syncService.start();
  }

  // ==================== BACA DATA LOKAL (INSTAN & OFFLINE) ====================

  Future<List<Barang>> getAllBarang() => _dbHelper.getAllBarang();
  Future<List<Supplier>> getAllSupplier() => _dbHelper.getAllSupplier();
  Future<List<Customer>> getAllCustomer() => _dbHelper.getAllCustomer();
  Future<List<Petugas>> getAllPetugas() => _dbHelper.getAllPetugas();
  Future<List<Faktur>> getAllFaktur() => _dbHelper.getAllFaktur();
  Future<List<Nota>> getAllNota() => _dbHelper.getAllNota();

  // ==================== SIMPAN MASTER DATA (OFFLINE-FIRST) ====================

  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) async {
    final barang = Barang(
      idBarang: idBarang,
      namaBarang: namaBarang.trim(),
      stokBarang: stokBarang,
      satuan: satuan.trim(),
      hargaSatuan: hargaSatuan,
      remoteId: existingRemoteId ?? _uuid.v4(),
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    await _dbHelper.upsertBarang(barang);
    await _afterLocalWrite();
  }

  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) async {
    final supplier = Supplier(
      idSupplier: idSupplier,
      namaSupplier: namaSupplier.trim(),
      alamatSupplier: alamatSupplier.trim(),
      noTelpSupplier: noTelpSupplier.trim(),
      remoteId: existingRemoteId ?? _uuid.v4(),
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    await _dbHelper.upsertSupplier(supplier);
    await _afterLocalWrite();
  }

  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) async {
    final customer = Customer(
      idCustomer: idCustomer,
      namaCustomer: namaCustomer.trim(),
      remoteId: existingRemoteId ?? _uuid.v4(),
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    await _dbHelper.upsertCustomer(customer);
    await _afterLocalWrite();
  }

  Future<void> savePetugas({
    int? idPetugas,
    String? existingRemoteId,
    required String namaPetugas,
    required UserRole role,
    String pin = '1234',
  }) async {
    final petugas = Petugas(
      idPetugas: idPetugas,
      namaPetugas: namaPetugas.trim(),
      role: role,
      pin: pin,
      remoteId: existingRemoteId ?? _uuid.v4(),
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    await _dbHelper.upsertPetugas(petugas);
    await _afterLocalWrite();
  }

  // ==================== SIMPAN TRANSAKSI (BPMN TO-BE) ====================

  /// Mencatat pembelian barang masuk dari supplier (`faktur` + `detail_faktur`)
  /// dan langsung menambah stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    if (supplier.idSupplier == null || petugas.idPetugas == null) {
      throw ArgumentError('Supplier dan Petugas harus tersimpan di database.');
    }
    final now = DateTime.now();
    final details = items.map((entry) {
      final barang = entry.barang;
      if (barang.idBarang == null) {
        throw ArgumentError('Barang "${barang.namaBarang}" belum memiliki ID.');
      }
      return DetailFaktur(
        idBarang: barang.idBarang!,
        jumlah: barang.hargaSatuan * entry.quantity,
        quantity: entry.quantity,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      );
    }).toList();

    final faktur = Faktur(
      noFaktur: noFaktur.trim(),
      tanggalFaktur: tanggalFaktur,
      total: Faktur.hitungTotal(details),
      idSupplier: supplier.idSupplier!,
      idPetugas: petugas.idPetugas!,
      remoteId: _uuid.v4(),
      supplierRemoteId: supplier.remoteId,
      petugasRemoteId: petugas.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      details: details,
    );

    final idFaktur = await _dbHelper.insertFakturTransaction(faktur, details);
    await _afterLocalWrite();
    return idFaktur;
  }

  /// Mencatat penjualan kasir ke customer (`nota` + `detail_nota`)
  /// dan langsung memotong stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    if (customer.idCustomer == null || petugas.idPetugas == null) {
      throw ArgumentError('Customer dan Petugas harus tersimpan di database.');
    }
    final now = DateTime.now();
    final details = items.map((entry) {
      final barang = entry.barang;
      if (barang.idBarang == null) {
        throw ArgumentError('Barang "${barang.namaBarang}" belum memiliki ID.');
      }
      return DetailNota(
        idBarang: barang.idBarang!,
        jumlah: barang.hargaSatuan * entry.banyaknya,
        banyaknya: entry.banyaknya,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      );
    }).toList();

    final nota = Nota(
      tanggalNota: tanggalNota,
      total: Nota.hitungTotal(details),
      idPetugas: petugas.idPetugas!,
      idCustomer: customer.idCustomer!,
      remoteId: _uuid.v4(),
      petugasRemoteId: petugas.remoteId,
      customerRemoteId: customer.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      details: details,
    );

    final idNota = await _dbHelper.insertNotaTransaction(nota, details);
    await _afterLocalWrite();
    return idNota;
  }

  Future<void> _afterLocalWrite() async {
    if (!_localChangesController.isClosed) {
      _localChangesController.add(null);
    }
    await syncService.trySyncIfOnline();
  }

  Future<void> dispose() async {
    await _syncDataSub?.cancel();
    syncService.dispose();
    await _localChangesController.close();
  }
}
