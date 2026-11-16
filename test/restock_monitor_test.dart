import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/restock_monitor_view_model.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentSyncService extends SyncService {
  _SilentSyncService({required super.dbHelper})
      : super(
          firestore: _NoopFirestore(),
          connectivity: _OfflineConnectivity(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> trySyncIfOnline() async {}

  @override
  Future<void> syncNow() async {}
}

class _NoopFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OfflineConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.none];
}

class _FakeRestockDataSource implements TransactionCrudDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Barang> barang = [];
  List<Supplier> suppliers = [];
  List<Customer> customers = [];
  List<Petugas> petugas = [];
  List<Faktur> fakturs = [];
  List<Nota> notas = [];

  Future<List<Barang>> Function()? onGetAllBarang;
  Future<List<Faktur>> Function()? onGetAllFaktur;

  void emitChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void emitStreamError(Object error) {
    if (!_changes.isClosed) _changes.addError(error);
  }

  Future<void> dispose() => _changes.close();

  @override
  Stream<void> get onDataChanged => _changes.stream;

  @override
  Future<List<Barang>> getAllBarang() async =>
      onGetAllBarang != null ? onGetAllBarang!() : barang;

  @override
  Future<List<Supplier>> getAllSupplier() async => suppliers;

  @override
  Future<List<Customer>> getAllCustomer() async => customers;

  @override
  Future<List<Petugas>> getAllPetugas() async => petugas;

  @override
  Future<List<Faktur>> getAllFaktur() async =>
      onGetAllFaktur != null ? onGetAllFaktur!() : fakturs;

  @override
  Future<List<Nota>> getAllNota() async => notas;

  @override
  Future<Faktur?> getFakturById(int idFaktur) async => null;

  @override
  Future<Nota?> getNotaById(int idNota) async => null;

  @override
  Future<String> generateNextNoFaktur({DateTime? date}) async => 'FKT-2026-001';

  @override
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async =>
      1;

  @override
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {}

  @override
  Future<void> deleteFaktur(int idFaktur) async {}

  @override
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async =>
      1;

  @override
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {}

  @override
  Future<void> deleteNota(int idNota) async {}
}

final _baseTime = DateTime(2026, 2, 18, 9, 0);

AuthSession _ownerSession() => AuthSession(
      uid: 'owner-restock-uid',
      email: 'owner@depottelur36.com',
      accountId: 'owner_restock',
      displayName: 'Budi Owner',
      role: UserRole.owner,
      petugasRemoteId: 'pet-owner',
      provider: AuthProviderType.emailPassword,
      signedInAt: _baseTime,
    );

AuthSession _operatorSession() => AuthSession(
      uid: 'op-restock-uid',
      email: 'kasir@depottelur36.com',
      accountId: 'op_restock',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: 'pet-kasir',
      provider: AuthProviderType.emailPassword,
      signedInAt: _baseTime,
    );

Barang _makeBarang({
  int? id = 1,
  String nama = 'Telur Puyuh Kemasan',
  int stok = 8,
  String satuan = 'Pouch',
  double harga = 17500,
  String remoteId = 'brg-1',
}) {
  return Barang(
    idBarang: id,
    namaBarang: nama,
    stokBarang: stok,
    satuan: satuan,
    hargaSatuan: harga,
    remoteId: remoteId,
    updatedAt: _baseTime,
  );
}

Supplier _makeSupplier({
  int? id = 1,
  String nama = 'Berkah Sentosa',
  String remoteId = 'sup-1',
}) {
  return Supplier(
    idSupplier: id,
    namaSupplier: nama,
    alamatSupplier: 'Jl. Pasar Baru 1',
    noTelpSupplier: '081234567890',
    remoteId: remoteId,
    updatedAt: _baseTime,
  );
}

Future<({
  Directory tempDir,
  DatabaseHelper dbHelper,
  InventoryRepository repo,
})> _openIsolatedRepo() async {
  final tempDir = Directory.systemTemp.createTempSync('dt36_restock_test_');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final dbHelper = DatabaseHelper.forTesting(
    customDbPath: p.join(tempDir.path, 'restock_test.db'),
  );
  addTearDown(dbHelper.close);
  final repo = InventoryRepository(
    dbHelper: dbHelper,
    syncService: _SilentSyncService(dbHelper: dbHelper),
  );
  addTearDown(repo.dispose);
  await repo.initialize();
  return (tempDir: tempDir, dbHelper: dbHelper, repo: repo);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Pemantauan & Aksi Restok - Skenario Normal', () {
    test(
      'mengelompokkan stok habis/kritis/pantauan/aman, mengurutkan prioritas & menghitung rasio meter',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        ds.barang = [
          _makeBarang(id: 1, nama: 'Jagung Giling', stok: 45, remoteId: 'b1'),
          _makeBarang(id: 2, nama: 'Telur Bebek', stok: 18, remoteId: 'b2'),
          _makeBarang(id: 3, nama: 'Minyak 1L', stok: 8, remoteId: 'b3'),
          _makeBarang(id: 4, nama: 'Egg Tray', stok: 0, remoteId: 'b4'),
          _makeBarang(id: 5, nama: 'Beras Merah', stok: 8, remoteId: 'b5'),
          _makeBarang(id: 6, nama: 'Gula Pasir', stok: 25, remoteId: 'b6'),
        ];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);

        await vm.loadData();
        final snap = vm.snapshot;

        expect(snap.totalCatalogCount, 6);
        expect(snap.outOfStockCount, 1);
        expect(snap.criticalCount, 3);
        expect(snap.watchBandCount, 2);
        expect(snap.watchAndCriticalCount, 5);

        // Urutan kritis: 0 terlebih dahulu, lalu stok 8 alfabetis (Beras Merah < Minyak 1L)
        expect(
          snap.criticalItems.map((e) => e.barang.namaBarang).toList(),
          ['Egg Tray', 'Beras Merah', 'Minyak 1L'],
        );
        expect(snap.criticalItems[0].alertLevel, StockAlertLevel.habis);
        expect(snap.criticalItems[0].meterRatio, 0.0);
        expect(snap.criticalItems[1].alertLevel, StockAlertLevel.kritis);
        expect(snap.criticalItems[1].meterRatio, closeTo(0.8, 1e-6));

        expect(
          snap.watchOnlyItems.map((e) => e.barang.namaBarang).toList(),
          ['Telur Bebek', 'Gula Pasir'],
        );
        expect(snap.watchOnlyItems.every((e) => e.isWatchOnly), isTrue);

        expect(
          snap.safeItems.map((e) => e.barang.namaBarang).toList(),
          ['Jagung Giling'],
        );
        expect(snap.safeItems.single.isSafe, isTrue);

        // Label filter dinamis
        expect(snap.labelForFilter(StokMenipisFilter.kritis), 'Kritis (≤ 10)');
        expect(snap.labelForFilter(StokMenipisFilter.pantauan), 'Pantauan (≤ 25)');
        expect(snap.labelForFilter(StokMenipisFilter.semua), 'Semua (6)');
      },
    );

    test(
      'mengambil supplier terakhir berdasarkan faktur terbaru (tanggal lalu idFaktur lalu updatedAt)',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final item = _makeBarang(id: 1, nama: 'Telur Ayam', stok: 5, remoteId: 'b1');
        final supLama = _makeSupplier(id: 10, nama: 'CV Lama', remoteId: 's-lama');
        final supTengah = _makeSupplier(id: 11, nama: 'PT Tengah', remoteId: 's-tengah');
        final supBaru = _makeSupplier(id: 12, nama: 'Berkah Sentosa', remoteId: 's-baru');
        ds.barang = [item];
        ds.suppliers = [supLama, supTengah, supBaru];
        ds.fakturs = [
          Faktur(
            idFaktur: 1,
            noFaktur: 'FKT-01',
            tanggalFaktur: '2026-02-10',
            total: 100000,
            idSupplier: 10,
            supplierRemoteId: 's-lama',
            idPetugas: 1,
            remoteId: 'f1',
            updatedAt: DateTime(2026, 2, 10),
            details: const [
              DetailFaktur(idBarang: 1, barangRemoteId: 'b1', jumlah: 100000, quantity: 5),
            ],
          ),
          // Tanggal sama (2026-02-15), idFaktur 9 vs 4 -> pilih 9 (Berkah Sentosa)
          Faktur(
            idFaktur: 4,
            noFaktur: 'FKT-02',
            tanggalFaktur: '2026-02-15',
            total: 100000,
            idSupplier: 11,
            supplierRemoteId: 's-tengah',
            idPetugas: 1,
            remoteId: 'f2',
            updatedAt: DateTime(2026, 2, 15, 16),
            details: const [
              DetailFaktur(idBarang: 1, barangRemoteId: 'b1', jumlah: 100000, quantity: 5),
            ],
          ),
          Faktur(
            idFaktur: 9,
            noFaktur: 'FKT-03',
            tanggalFaktur: '2026-02-15',
            total: 100000,
            idSupplier: 12,
            supplierRemoteId: 's-baru',
            idPetugas: 1,
            remoteId: 'f3',
            updatedAt: DateTime(2026, 2, 15, 9),
            details: const [
              DetailFaktur(idBarang: 1, barangRemoteId: 'b1', jumlah: 100000, quantity: 5),
            ],
          ),
        ];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);

        await vm.loadData();
        final mon = vm.snapshot.criticalItems.single;
        expect(mon.lastSupplierId, 12);
        expect(mon.lastSupplierRemoteId, 's-baru');
        expect(mon.lastSupplierName, 'Berkah Sentosa');
        expect(mon.lastRestockDate, '2026-02-15');
      },
    );

    test(
      'menghitung saran restok, kustomisasi stepper draftQty, resetDraftQty & selectFilter tanpa notify duplikat',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final kritis = _makeBarang(id: 1, stok: 8, remoteId: 'b1');
        final pantauan = _makeBarang(id: 2, nama: 'Bebek', stok: 18, remoteId: 'b2');
        final aman = _makeBarang(id: 3, nama: 'Jagung', stok: 40, remoteId: 'b3');
        ds.barang = [kritis, pantauan, aman];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        await vm.loadData();

        expect(vm.suggestedRestockQtyFor(kritis), 12); // max(20,20)-8
        expect(vm.suggestedRestockQtyFor(pantauan), 12); // (25+5)-18
        expect(vm.suggestedRestockQtyFor(aman), 10);

        expect(vm.adjustDraftQty(kritis, 3), isTrue);
        expect(vm.draftQtyFor(kritis), 15);
        expect(vm.snapshot.criticalItems.single.projectedStockAfterRestock, 23);

        vm.resetDraftQty(kritis);
        expect(vm.draftQtyFor(kritis), 12);

        var notifyCount = 0;
        vm.addListener(() => notifyCount++);
        vm.selectFilter(StokMenipisFilter.kritis); // filter sama -> tidak notify
        expect(notifyCount, 0);
        vm.selectFilter(StokMenipisFilter.pantauan);
        expect(notifyCount, 1);
        expect(vm.filter, StokMenipisFilter.pantauan);
      },
    );

    test(
      'integrasi SQLite nyata: nota menurunkan stok -> auto-reload memantau kritis -> prefill & submit faktur menaikkan stok kembali',
      () async {
        final env = await _openIsolatedRepo();
        final opSession = _operatorSession();

        await env.repo.savePetugas(
          existingRemoteId: opSession.petugasRemoteId,
          namaPetugas: opSession.displayName,
          role: opSession.role,
          pin: '1234',
          email: opSession.email,
        );
        await env.repo.saveBarang(
          existingRemoteId: 'it-e2e-telur',
          namaBarang: 'Telur Puyuh E2E',
          hargaSatuan: 18000,
          satuan: 'Pouch',
          stokBarang: 14,
        );
        await env.repo.saveSupplier(
          existingRemoteId: 'sup-e2e-berkah',
          namaSupplier: 'CV Puyuh Mandiri',
          noTelpSupplier: '081300011122',
          alamatSupplier: 'Jl. Sentral No. 3',
        );

        final barangs = await env.repo.getAllBarang();
        final puyuh = barangs.firstWhere((b) => b.remoteId == 'it-e2e-telur');
        final sup = (await env.repo.getAllSupplier())
            .firstWhere((s) => s.remoteId == 'sup-e2e-berkah');
        final cust = (await env.repo.getAllCustomer()).first;
        final petugas = (await env.repo.getAllPetugas())
            .firstWhere((p) => p.remoteId == opSession.petugasRemoteId);

        // Catat faktur awal agar supplier terakhir terekam (stok 14 -> 17)
        await env.repo.createFaktur(
          noFaktur: 'FKT-E2E-1',
          tanggalFaktur: '2026-02-16',
          supplier: sup,
          petugas: petugas,
          items: [(barang: puyuh, quantity: 3)],
        );

        final restockVm = RestockMonitorViewModel.fromRepository(
          session: opSession,
          repository: env.repo,
        );
        addTearDown(restockVm.dispose);
        final txVm = TransactionCrudViewModel.fromRepository(
          session: opSession,
          repository: env.repo,
        );
        addTearDown(txVm.dispose);

        await Future.wait([restockVm.loadData(), txVm.loadData()]);
        // Stok 17 berada di Pantauan, belum Kritis
        expect(
          restockVm.snapshot.criticalItems
              .where((i) => i.barang.remoteId == 'it-e2e-telur'),
          isEmpty,
        );

        // Penjualan menurunkan stok 17 - 10 = 7 (masuk Kritis!)
        final puyuhAfterFaktur = (await env.repo.getAllBarang())
            .firstWhere((b) => b.remoteId == 'it-e2e-telur');
        await env.repo.createNota(
          tanggalNota: '2026-02-18',
          customer: cust,
          petugas: petugas,
          items: [(barang: puyuhAfterFaktur, banyaknya: 10)],
        );
        // Biarkan stream onDataChanged memicu reload asinkron
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final critItem = restockVm.snapshot.criticalItems
            .firstWhere((i) => i.barang.remoteId == 'it-e2e-telur');
        expect(critItem.barang.stokBarang, 7);
        expect(critItem.lastSupplierName, 'CV Puyuh Mandiri');
        expect(critItem.suggestedQty, 13);

        // Ubah saran restok -> siapkan faktur -> submit
        expect(restockVm.setDraftQty(critItem.barang, 20), isTrue);
        final updatedItem = restockVm.snapshot.criticalItems
            .firstWhere((i) => i.barang.remoteId == 'it-e2e-telur');
        final prepared = restockVm.prepareRestockDraft(
          updatedItem,
          transactionVm: txVm,
        );
        expect(prepared, 20);
        expect(txVm.selectedFakturSupplier?.remoteId, 'sup-e2e-berkah');
        expect(txVm.fakturQtyFor(critItem.barang), 20);

        final savedId = await txVm.submitFakturMasuk();
        expect(savedId, isNotNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Setelah submit faktur +20 -> stok 27 (pindah ke Stok Aman)
        expect(
          restockVm.snapshot.criticalItems
              .where((i) => i.barang.remoteId == 'it-e2e-telur'),
          isEmpty,
        );
        final safeMatch = restockVm.snapshot.safeItems
            .firstWhere((i) => i.barang.remoteId == 'it-e2e-telur');
        expect(safeMatch.barang.stokBarang, 27);
      },
    );
  });

  group('Pemantauan & Aksi Restok - Edge Case & Perbaikan Celah', () {
    test(
      'katalog kosong, stok negatif korup, batas ambang 0/1/10/11/25/26, & custom threshold',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);

        await vm.loadData();
        expect(vm.snapshot.totalCatalogCount, 0);
        expect(vm.snapshot.criticalItems, isEmpty);
        expect(vm.snapshot.watchOnlyItems, isEmpty);
        expect(vm.snapshot.safeItems, isEmpty);

        ds.barang = [
          _makeBarang(id: 1, nama: 'Korup Negatif', stok: -4, remoteId: 'n1'),
          _makeBarang(id: 2, nama: 'Nol Persis', stok: 0, remoteId: 'z0'),
          _makeBarang(id: 3, nama: 'Satu Unit', stok: 1, remoteId: 's1'),
          _makeBarang(id: 4, nama: 'Batas Kritis 10', stok: 10, remoteId: 'k10'),
          _makeBarang(id: 5, nama: 'Awal Pantauan 11', stok: 11, remoteId: 'p11'),
          _makeBarang(id: 6, nama: 'Batas Pantauan 25', stok: 25, remoteId: 'p25'),
          _makeBarang(id: 7, nama: 'Mulai Aman 26', stok: 26, remoteId: 'a26'),
        ];
        await vm.loadData();
        final snap = vm.snapshot;

        expect(snap.outOfStockCount, 2); // -4 dan 0
        expect(snap.criticalCount, 4); // -4, 0, 1, 10
        expect(snap.watchBandCount, 2); // 11, 25
        expect(snap.safeItems.single.barang.namaBarang, 'Mulai Aman 26');

        // Korup negatif tidak bikin saran < 20 maupun meter < 0
        final negItem = snap.criticalItems.firstWhere((e) => e.barang.idBarang == 1);
        expect(negItem.alertLevel, StockAlertLevel.habis);
        expect(negItem.meterRatio, 0.0);
        expect(negItem.suggestedQty, 20);

        // stok 1/10 = 0.1 (>= 0.08), sedangkan 10/10 = 1.0
        final oneItem = snap.criticalItems.firstWhere((e) => e.barang.idBarang == 3);
        expect(oneItem.meterRatio, closeTo(0.1, 1e-6));

        // Threshold kustom low == watch (15 == 15) tanpa watchOnly band
        final customVm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
          lowThreshold: 15,
          watchThreshold: 15,
        );
        addTearDown(customVm.dispose);
        await customVm.loadData();
        expect(customVm.snapshot.watchOnlyItems, isEmpty);
        expect(customVm.snapshot.criticalCount, 5); // <= 15 (termasuk 11)
        expect(customVm.snapshot.safeItems.length, 2); // 25, 26
        // Stok 1 dengan lowThreshold 15 -> 1/15 = 0.066 -> di-clamp ke 0.08
        final minBar = customVm.snapshot.criticalItems
            .firstWhere((e) => e.barang.idBarang == 3);
        expect(minBar.meterRatio, closeTo(0.08, 1e-6));
      },
    );

    test(
      'celah sinkronisasi lintas-perangkat: cocokkan supplierRemoteId & barangRemoteId walau idBarang/idSupplier beda + id=0 + trim remoteId',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);

        // idBarang=0 & remoteId punya spasi, plus barang id lokal berbeda dgn DetailFaktur cloud
        final barangIdNol = _makeBarang(
          id: 0,
          nama: 'Tray Cloud',
          stok: 4,
          remoteId: '  rem-tray  ',
        );
        final barangBedaId = _makeBarang(
          id: 42,
          nama: 'Telur Sync',
          stok: 6,
          remoteId: 'rem-telur-sync',
        );
        final supLokal1 = _makeSupplier(id: 1, nama: 'Supplier Salah ID', remoteId: 'sup-a');
        final supLokal2 = _makeSupplier(id: 2, nama: 'Supplier Remote Benar', remoteId: 'sup-target');
        ds.barang = [barangIdNol, barangBedaId];
        ds.suppliers = [supLokal1, supLokal2];
        ds.fakturs = [
          // Faktur terbaru tanpa nama supplier sama sekali -> harus dilewati, tidak menutupi faktur valid lama
          Faktur(
            idFaktur: 99,
            noFaktur: 'FKT-KOSONG',
            tanggalFaktur: '2026-02-18',
            total: 50000,
            idSupplier: 999,
            idPetugas: 1,
            remoteId: 'f-null',
            updatedAt: _baseTime,
            details: const [
              DetailFaktur(
                idBarang: 42,
                barangRemoteId: 'rem-telur-sync',
                jumlah: 50000,
                quantity: 2,
              ),
            ],
          ),
          // Faktur dari perangkat lain: idSupplier=1 bertabrakan secara lokal, tetapi supplierRemoteId menunjuk supLokal2
          Faktur(
            idFaktur: 50,
            noFaktur: 'FKT-CLOUD',
            tanggalFaktur: '2026-02-17',
            total: 90000,
            idSupplier: 1,
            supplierRemoteId: 'sup-target',
            idPetugas: 1,
            remoteId: 'f-cloud',
            updatedAt: _baseTime,
            details: const [
              DetailFaktur(
                idBarang: 999, // ID perangkat lain
                barangRemoteId: 'rem-telur-sync',
                jumlah: 50000,
                quantity: 3,
              ),
              DetailFaktur(
                idBarang: 0,
                barangRemoteId: 'rem-tray',
                jumlah: 40000,
                quantity: 10,
              ),
            ],
          ),
        ];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        await vm.loadData();

        final trayMon = vm.snapshot.criticalItems
            .firstWhere((e) => e.barang.namaBarang == 'Tray Cloud');
        expect(trayMon.lastSupplierId, 2);
        expect(trayMon.lastSupplierName, 'Supplier Remote Benar');

        final syncMon = vm.snapshot.criticalItems
            .firstWhere((e) => e.barang.namaBarang == 'Telur Sync');
        expect(syncMon.lastSupplierId, 2);
        expect(syncMon.lastSupplierName, 'Supplier Remote Benar');

        // Custom qty untuk barang id=0 dengan spasi di remoteId tersimpan konsisten
        expect(vm.setDraftQty(barangIdNol, 35), isTrue);
        expect(vm.draftQtyFor(barangIdNol), 35);
      },
    );

    test(
      'celah race & tabrakan substring: prepareRestockDraft sebelum txVm selesai loadData mempertahankan qty/override/supplier & tepat memilih ID barang',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);

        final telurBebek = _makeBarang(
          id: 1,
          nama: 'Telur Bebek',
          stok: 20,
          remoteId: 'b-bebek',
        );
        final telurBebekAsin = _makeBarang(
          id: 2,
          nama: 'Telur Bebek Asin',
          stok: 3,
          remoteId: 'b-asin',
        );
        final supUtama = _makeSupplier(id: 5, nama: 'UD Utama', remoteId: 'sup-5');
        final supKedua = _makeSupplier(id: 8, nama: 'CV Kedua', remoteId: 'sup-8');

        ds.barang = [telurBebek, telurBebekAsin];
        ds.suppliers = [supUtama, supKedua];
        ds.fakturs = [
          Faktur(
            idFaktur: 77,
            noFaktur: 'FKT-77',
            tanggalFaktur: '2026-02-17',
            total: 100000,
            idSupplier: 8,
            supplierRemoteId: 'sup-8',
            idPetugas: 1,
            remoteId: 'f-77',
            updatedAt: _baseTime,
            details: const [
              DetailFaktur(
                idBarang: 2,
                barangRemoteId: 'b-asin',
                jumlah: 100000,
                quantity: 5,
              ),
            ],
          ),
        ];

        final restockVm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(restockVm.dispose);
        await restockVm.loadData();

        restockVm.setDraftQty(telurBebekAsin, 27);
        final targetItem = restockVm.snapshot.criticalItems.single;

        // Simulasikan txVm BELUM memuat katalog & supplier (masih kosong)
        final gate = Completer<void>();
        ds.onGetAllBarang = () async {
          await gate.future;
          return [telurBebek, telurBebekAsin];
        };
        final txVm = TransactionCrudViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(txVm.dispose);

        final loadFuture = txVm.loadData();
        // Panggil prepareRestockDraft SEBELUM loadData() selesai
        final qtyPrepared = restockVm.prepareRestockDraft(
          targetItem,
          transactionVm: txVm,
        );
        expect(qtyPrepared, 27);

        // Selesaikan loadData -> custom qty 27, ID barang exact, dan supplier ke-8 harus tetap terpasang!
        gate.complete();
        await loadFuture;

        expect(txVm.fakturQtyFor(telurBebekAsin), 27);
        expect(txVm.fakturQtyFor(telurBebek), 0);
        expect(txVm.selectedFakturSupplier?.idSupplier, 8);
      },
    );

    test(
      'proteksi asinkron: epoch guard loadData, stream error tidak crash, bersihkan draft barang terhapus, & dispose aman',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final a = _makeBarang(id: 1, nama: 'Barang A', stok: 4, remoteId: 'ba');
        final b = _makeBarang(id: 2, nama: 'Barang B', stok: 2, remoteId: 'bb');

        final slowFirstLoad = Completer<List<Barang>>();
        var calls = 0;
        ds.onGetAllBarang = () {
          calls++;
          if (calls == 1) return slowFirstLoad.future;
          return Future.value([b]);
        };

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        vm.setDraftQty(a, 19);
        vm.setDraftQty(b, 25);

        final first = vm.loadData();
        final second = vm.loadData();
        await second;
        expect(vm.snapshot.criticalItems.length, 1);
        expect(vm.snapshot.criticalItems.single.barang.namaBarang, 'Barang B');
        // Draft barang terhapus (Barang A) dibersihkan; Barang B tetap 25
        expect(vm.draftQtyFor(a), 16); // kembali ke default saran karena tidak ada di katalog lagi
        expect(vm.draftQtyFor(b), 25);

        // Load pertama selesai belakangan -> TIDAK boleh menimpa state yang lebih baru
        slowFirstLoad.complete([a, b]);
        await first;
        expect(vm.snapshot.criticalItems.length, 1);
        expect(vm.snapshot.criticalItems.single.barang.namaBarang, 'Barang B');

        // Error pada stream onDataChanged tidak menyebabkan uncaught exception
        ds.emitStreamError(StateError('stream terputus'));
        await Future<void>.delayed(Duration.zero);

        // Dispose saat request lambat sedang berjalan tidak melempar FlutterError
        final pendingAfterDispose = Completer<List<Barang>>();
        ds.onGetAllBarang = () => pendingAfterDispose.future;
        final disposableVm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        final inflight = disposableVm.loadData();
        disposableVm.dispose();
        pendingAfterDispose.complete([a]);
        await inflight;
      },
    );
  });

  group('Pemantauan & Aksi Restok - Kasus Salah Input & Kegagalan', () {
    test(
      'menolak threshold konfigurasi tidak valid dengan ArgumentError',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);

        expect(
          () => RestockMonitorViewModel(
            session: _ownerSession(),
            dataSource: ds,
            lowThreshold: 0,
          ),
          throwsArgumentError,
        );
        expect(
          () => RestockMonitorViewModel(
            session: _ownerSession(),
            dataSource: ds,
            lowThreshold: -5,
          ),
          throwsArgumentError,
        );
        expect(
          () => RestockMonitorViewModel(
            session: _ownerSession(),
            dataSource: ds,
            lowThreshold: 12,
            watchThreshold: 10,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'menolak qty tidak valid (0, negatif, > 9.999.999, serta delta ekstrem int64 overflow) & menjaga errorShakePulse',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final barang = _makeBarang(id: 1, nama: 'Minyak 1L', stok: 8, remoteId: 'b1');
        ds.barang = [barang];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        await vm.loadData();

        expect(vm.setDraftQty(barang, 0), isFalse);
        expect(vm.errorMessage, contains('minimal 1 Pouch'));
        expect(vm.errorShakePulse, 1);
        expect(vm.draftQtyFor(barang), 12);

        expect(vm.setDraftQty(barang, -500), isFalse);
        expect(vm.errorShakePulse, 2);

        expect(vm.setDraftQty(barang, 10000000), isFalse);
        expect(vm.errorMessage, contains('maksimal 9.999.999'));
        expect(vm.errorShakePulse, 3);

        // Overflow guard: int64 max dan int64 min tidak boleh wrap-around
        expect(vm.adjustDraftQty(barang, 0x7FFFFFFFFFFFFFFF), isFalse);
        expect(vm.errorMessage, contains('maksimal 9.999.999'));
        expect(vm.errorShakePulse, 4);

        expect(vm.adjustDraftQty(barang, -0x8000000000000000), isFalse);
        expect(vm.errorMessage, contains('minimal 1 Pouch'));
        expect(vm.errorShakePulse, 5);

        // Delta 0 aman dan tidak mengubah errorMessage atau draft
        expect(vm.adjustDraftQty(barang, 0), isTrue);
        expect(vm.draftQtyFor(barang), 12);
        expect(vm.errorMessage, isNotNull);

        vm.clearError();
        expect(vm.errorMessage, isNull);

        // Input valid membersihkan pesan error secara otomatis
        expect(vm.setDraftQty(barang, 1), isTrue);
        expect(vm.adjustDraftQty(barang, -1), isFalse);
        expect(vm.errorMessage, isNotNull);
        expect(vm.setDraftQty(barang, 9999999), isTrue);
        expect(vm.errorMessage, isNull);
        expect(vm.draftQtyFor(barang), 9999999);
      },
    );

    test(
      'prepareRestockDraft menolak barang tanpa ID/ID<=0/nama kosong/draftQty invalid & aman saat supplier telah dihapus',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final validSup = _makeSupplier(id: 3, nama: 'Sup Aktif', remoteId: 'sup-3');
        final validBarang = _makeBarang(id: 7, nama: 'Telur Kampung', stok: 4, remoteId: 'b-7');
        ds.barang = [validBarang];
        ds.suppliers = [validSup];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        final txVm = TransactionCrudViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(txVm.dispose);
        await Future.wait([vm.loadData(), txVm.loadData()]);

        // Barang belum tersimpan (id null)
        final unsaved = _makeBarang(id: null, nama: 'Belum Tersimpan', stok: 2);
        expect(
          vm.prepareRestockDraft(
            RestockMonitorItem(
              barang: unsaved,
              alertLevel: StockAlertLevel.kritis,
              suggestedQty: 18,
              draftQty: 18,
              meterRatio: 0.2,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );
        expect(vm.errorMessage, contains('belum tersimpan'));
        expect(txVm.fakturCartLines, isEmpty);

        // Barang ID <= 0
        expect(
          vm.prepareRestockDraft(
            RestockMonitorItem(
              barang: _makeBarang(id: 0, nama: 'ID Nol', stok: 2),
              alertLevel: StockAlertLevel.kritis,
              suggestedQty: 18,
              draftQty: 18,
              meterRatio: 0.2,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );

        // Nama kosong / spasi
        expect(
          vm.prepareRestockDraft(
            RestockMonitorItem(
              barang: _makeBarang(id: 7, nama: '   ', stok: 2),
              alertLevel: StockAlertLevel.kritis,
              suggestedQty: 18,
              draftQty: 18,
              meterRatio: 0.2,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );

        // Craft invalid draftQty (0 dan > batas)
        expect(
          vm.prepareRestockDraft(
            RestockMonitorItem(
              barang: validBarang,
              alertLevel: StockAlertLevel.kritis,
              suggestedQty: 16,
              draftQty: 0,
              meterRatio: 0.4,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );
        expect(vm.errorMessage, contains('harus antara 1 sampai 9.999.999'));

        expect(
          vm.prepareRestockDraft(
            RestockMonitorItem(
              barang: validBarang,
              alertLevel: StockAlertLevel.kritis,
              suggestedQty: 16,
              draftQty: 10000001,
              meterRatio: 0.4,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );
        expect(txVm.fakturCartLines, isEmpty);

        // Supplier lama sudah dihapus (lastSupplierId=99 tidak ada di txVm.suppliers):
        // Tetap mengisi keranjang tanpa menimpa supplier aktif menjadi ID invalid
        final res = vm.prepareRestockDraft(
          RestockMonitorItem(
            barang: validBarang,
            alertLevel: StockAlertLevel.kritis,
            suggestedQty: 16,
            draftQty: 16,
            meterRatio: 0.4,
            lastSupplierId: 99,
            lastSupplierRemoteId: 'sup-deleted',
            lastSupplierName: 'Supplier Lama Terhapus',
          ),
          transactionVm: txVm,
        );
        expect(res, 16);
        expect(txVm.selectedFakturSupplier?.idSupplier, 3); // tetap Sup Aktif, bukan 99
        expect(txVm.fakturQtyFor(validBarang), 16);
      },
    );

    test(
      'kegagalan sumber data saat loadData mempertahankan custom draft & pulih saat retry berhasil',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final b = _makeBarang(id: 1, nama: 'Telur Asli', stok: 5, remoteId: 'ba');
        ds.barang = [b];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        await vm.loadData();
        expect(vm.setDraftQty(b, 42), isTrue);

        // Simulasikan kegagalan SQLite
        ds.onGetAllBarang = () async => throw StateError('disk I/O failure');
        await vm.loadData();
        expect(vm.isLoading, isFalse);
        expect(vm.errorMessage, contains('Gagal memuat pemantauan stok'));
        // Data & custom draft sebelumnya tidak terhapus saat error sementara
        expect(vm.snapshot.criticalItems.single.draftQty, 42);

        // Pulih saat reload ulang berhasil
        ds.onGetAllBarang = null;
        await vm.loadData();
        expect(vm.errorMessage, isNull);
        expect(vm.snapshot.criticalItems.single.draftQty, 42);
      },
    );

    test(
      'pergantian akun (uid berubah) mereset custom draft/filter/error & pending supplier tidak bocor antar prefill',
      () async {
        final ds = _FakeRestockDataSource();
        addTearDown(ds.dispose);
        final b = _makeBarang(id: 1, nama: 'Telur Bebek', stok: 5, remoteId: 'b1');
        final s1 = _makeSupplier(id: 1, nama: 'Sup Awal', remoteId: 's-1');
        final s2 = _makeSupplier(id: 2, nama: 'Sup Target', remoteId: 's-2');
        ds.barang = [b];
        ds.suppliers = [s1, s2];

        final vm = RestockMonitorViewModel(
          session: _ownerSession(),
          dataSource: ds,
        );
        addTearDown(vm.dispose);
        await vm.loadData();

        vm.selectFilter(StokMenipisFilter.pantauan);
        vm.setDraftQty(b, 44);
        vm.setDraftQty(b, 0); // memicu errorMessage

        // Update dengan UID yang sama (misal perbarui displayName) -> state draft tetap
        vm.updateSession(
          _ownerSession().copyWith(displayName: 'Budi Pemilik'),
        );
        expect(vm.filter, StokMenipisFilter.pantauan);
        expect(vm.draftQtyFor(b), 44);
        expect(vm.errorMessage, isNotNull);

        // Ganti akun ke UID berbeda -> tidak boleh membocorkan draft/filter/error akun lama
        vm.updateSession(_operatorSession());
        expect(vm.filter, StokMenipisFilter.kritis);
        expect(vm.draftQtyFor(b), 15); // saran awal 20 - 5
        expect(vm.errorMessage, isNull);

        // Pending supplier yang dibatalkan prefill berikutnya tidak bocor saat loadData selesai
        final gate = Completer<void>();
        ds.onGetAllBarang = () async {
          await gate.future;
          return [b];
        };
        final txVm = TransactionCrudViewModel(
          session: _operatorSession(),
          dataSource: ds,
        );
        addTearDown(txVm.dispose);

        final loadFuture = txVm.loadData();
        txVm.prefillFakturRestock(
          'Telur Bebek',
          barangId: 1,
          defaultQty: 22,
          supplierId: 2,
          supplierRemoteId: 's-2',
        );
        // Panggil prefill kedua tanpa supplier -> harus menghapus pending supplier s-2
        txVm.prefillFakturRestock(
          'Telur Bebek',
          barangId: 1,
          defaultQty: 19,
          overrideExisting: true,
        );
        gate.complete();
        await loadFuture;

        expect(txVm.fakturQtyFor(b), 19);
        expect(txVm.selectedFakturSupplier?.idSupplier, 1); // fallback supplier pertama s1, bukan s2
      },
    );
  });
}
