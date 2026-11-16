import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
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

class _OfflineConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.none];
}

class _OnlineConnectivity implements Connectivity {
  _OnlineConnectivity({this.online = true});

  bool online;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => online
      ? const [ConnectivityResult.wifi]
      : const [ConnectivityResult.none];
}

class _NoopFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingFirestoreStore {
  final List<String> deletedDocPaths = [];
  final Map<String, Map<String, dynamic>> docs = {};
}

class _RecordingFirestore implements FirebaseFirestore {
  _RecordingFirestore(this.store);

  final _RecordingFirestoreStore store;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _FakeCollectionRef(collectionPath, store);
  }

  @override
  WriteBatch batch() => _FakeWriteBatch(store);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeCollectionRef implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionRef(this._path, this._store);

  final String _path;
  final _RecordingFirestoreStore _store;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final docId = path ?? 'auto-${_store.docs.length}';
    return _FakeDocumentRef('$_path/$docId', _store);
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return _FakeQuery(_path, _store, limitCount: limit);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    return _FakeQuery(_path, _store).get(options);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDocumentRef implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentRef(this._fullPath, this._store);

  final String _fullPath;
  final _RecordingFirestoreStore _store;

  @override
  String get path => _fullPath;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _store.docs[_fullPath] = Map<String, dynamic>.from(data);
  }

  @override
  Future<void> delete() async {
    _store.deletedDocPaths.add(_fullPath);
    _store.docs.remove(_fullPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeQuery implements Query<Map<String, dynamic>> {
  _FakeQuery(this._collectionPath, this._store, {this.limitCount});

  final String _collectionPath;
  final _RecordingFirestoreStore _store;
  final int? limitCount;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final prefix = '$_collectionPath/';
    var matching = _store.docs.entries
        .where((e) => e.key.startsWith(prefix))
        .map(
          (e) => _FakeQueryDocumentSnapshot(
            e.key.substring(prefix.length),
            e.value,
          ),
        )
        .toList();
    if (limitCount != null && matching.length > limitCount!) {
      matching = matching.take(limitCount!).toList();
    }
    return _FakeQuerySnapshot(matching);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocumentSnapshot(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWriteBatch implements WriteBatch {
  _FakeWriteBatch(this._store);

  final _RecordingFirestoreStore _store;
  final List<void Function()> _ops = [];

  @override
  void set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {
    _ops.add(() {
      if (data is Map<String, dynamic>) {
        _store.docs[document.path] = Map<String, dynamic>.from(data);
      }
    });
  }

  @override
  Future<void> commit() async {
    for (final op in _ops) {
      op();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMasterCrudDataSource implements MasterCrudDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Barang> barang = [];
  List<Supplier> suppliers = [];
  List<Customer> customers = [];
  List<Petugas> petugas = [];

  Future<List<Barang>> Function()? onGetAllBarang;
  Future<void> Function()? onSaveBarang;

  int saveBarangCalls = 0;
  int savePetugasCalls = 0;
  int deletePetugasCalls = 0;
  int saveHargaBatchCalls = 0;

  void emitChanged() {
    if (!_changes.isClosed) _changes.add(null);
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
  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) async {
    saveBarangCalls++;
    if (onSaveBarang != null) {
      await onSaveBarang!();
    }
  }

  @override
  Future<void> updateBarangHargaBatch(Map<int, double> hargaById) async {
    saveHargaBatchCalls++;
  }

  @override
  Future<void> deleteBarang(int idBarang) async {}

  @override
  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) async {}

  @override
  Future<void> deleteSupplier(int idSupplier) async {}

  @override
  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) async {}

  @override
  Future<void> deleteCustomer(int idCustomer) async {}

  @override
  Future<void> savePetugas({
    int? idPetugas,
    String? existingRemoteId,
    required String namaPetugas,
    required UserRole role,
    String pin = '1234',
    String email = '',
    String accountId = '',
    String? activeUserRemoteId,
    bool requireEmail = false,
  }) async {
    savePetugasCalls++;
  }

  @override
  Future<void> deletePetugas(
    Petugas target, {
    String? currentUserRemoteId,
  }) async {
    deletePetugasCalls++;
  }
}

AuthSession _ownerSession({String remoteId = 'owner-remote-1'}) => AuthSession(
  uid: 'uid-owner',
  email: 'owner@depottelur36.com',
  accountId: 'owner01',
  displayName: 'Budi Owner',
  role: UserRole.owner,
  petugasRemoteId: remoteId,
  provider: AuthProviderType.emailPassword,
  signedInAt: DateTime(2026, 2, 16),
);

AuthSession _operatorSession({String remoteId = 'kasir-remote-1'}) =>
    AuthSession(
      uid: 'uid-kasir',
      email: 'kasir@depottelur36.com',
      accountId: 'kasir01',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: remoteId,
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

Future<({Directory tempDir, DatabaseHelper dbHelper, InventoryRepository repo})>
_openIsolatedRepo({SyncService Function(DatabaseHelper)? syncFactory}) async {
  final tempDir = await Directory.systemTemp.createTemp('dt36_master_crud_');
  final dbPath = p.join(tempDir.path, 'master_crud.db');
  final dbHelper = DatabaseHelper.forTesting(customDbPath: dbPath);
  final sync = syncFactory != null
      ? syncFactory(dbHelper)
      : _SilentSyncService(dbHelper: dbHelper);
  final repo = InventoryRepository(dbHelper: dbHelper, syncService: sync);

  addTearDown(() async {
    BarangPhotoPresets.clearAll();
    await repo.dispose();
    final db = await dbHelper.database;
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  return (tempDir: tempDir, dbHelper: dbHelper, repo: repo);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Fungsi 3 Repository & SQLite - Skenario Normal', () {
    test('CRUD lengkap Barang + batch update harga + preset foto', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      final initialBarang = await repo.getAllBarang();
      expect(initialBarang.length, 6);

      // Create
      await repo.saveBarang(
        existingRemoteId: 'brg-bebek-custom',
        namaBarang: '  Telur   Bebek   Asin  ',
        stokBarang: 30,
        satuan: 'Butir',
        hargaSatuan: 4500,
      );
      BarangPhotoPresets.setAssetForRemoteId(
        'brg-bebek-custom',
        DashboardAssets.thumbTelurBebek,
      );

      final afterCreate = await repo.getAllBarang();
      expect(afterCreate.length, 7);
      final created = afterCreate.firstWhere(
        (b) => b.remoteId == 'brg-bebek-custom',
      );
      expect(created.namaBarang, 'Telur Bebek Asin');
      expect(created.syncStatus, SyncStatus.pending);
      expect(
        BarangPhotoPresets.resolveAssetPath(created),
        DashboardAssets.thumbTelurBebek,
      );

      // Update single
      await repo.saveBarang(
        idBarang: created.idBarang,
        existingRemoteId: created.remoteId,
        namaBarang: 'Telur Bebek Matang',
        stokBarang: 0,
        satuan: 'Pack',
        hargaSatuan: 18000,
      );
      final afterUpdate = await repo.getAllBarang();
      final updated = afterUpdate.firstWhere(
        (b) => b.idBarang == created.idBarang,
      );
      expect(updated.namaBarang, 'Telur Bebek Matang');
      expect(updated.stokBarang, 0);
      expect(updated.satuan, 'Pack');
      expect(updated.hargaSatuan, 18000);

      // Batch update harga jual
      final telurNegeri = afterUpdate.firstWhere(
        (b) => b.remoteId == 'seed-barang-telur-negeri-kg',
      );
      await repo.updateBarangHargaBatch({
        updated.idBarang!: 19500,
        telurNegeri.idBarang!: 29500,
      });
      final afterBatch = await repo.getAllBarang();
      expect(
        afterBatch
            .firstWhere((b) => b.idBarang == updated.idBarang)
            .hargaSatuan,
        19500,
      );
      expect(
        afterBatch
            .firstWhere((b) => b.idBarang == telurNegeri.idBarang)
            .hargaSatuan,
        29500,
      );

      // Delete
      await repo.deleteBarang(created.idBarang!);
      final afterDelete = await repo.getAllBarang();
      expect(afterDelete.length, 6);
      expect(
        afterDelete.any((b) => b.idBarang == created.idBarang),
        isFalse,
      );
    });

    test('CRUD lengkap Supplier, Customer & Petugas + preservasi passwordHash', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      // Supplier Create -> Update -> Delete
      await repo.saveSupplier(
        namaSupplier: 'Peternakan Maju Jaya',
        alamatSupplier: 'Jl. Raya Bogor KM 24, Jakarta Timur',
        noTelpSupplier: '0812-3456-7890',
      );
      final suppliers = await repo.getAllSupplier();
      final createdSup = suppliers.firstWhere(
        (s) => s.namaSupplier == 'Peternakan Maju Jaya',
      );
      await repo.saveSupplier(
        idSupplier: createdSup.idSupplier,
        existingRemoteId: createdSup.remoteId,
        namaSupplier: 'Peternakan Maju Abadi',
        alamatSupplier: 'Jl. Raya Bogor KM 26, Depok',
        noTelpSupplier: '+62 813 1111 2222',
      );
      final updatedSup = (await repo.getAllSupplier()).firstWhere(
        (s) => s.idSupplier == createdSup.idSupplier,
      );
      expect(updatedSup.namaSupplier, 'Peternakan Maju Abadi');
      await repo.deleteSupplier(updatedSup.idSupplier!);
      expect(
        (await repo.getAllSupplier()).any(
          (s) => s.idSupplier == updatedSup.idSupplier,
        ),
        isFalse,
      );

      // Customer Create -> Update -> Delete
      await repo.saveCustomer(namaCustomer: 'Warung Bu Dewi');
      final createdCust = (await repo.getAllCustomer()).firstWhere(
        (c) => c.namaCustomer == 'Warung Bu Dewi',
      );
      await repo.saveCustomer(
        idCustomer: createdCust.idCustomer,
        existingRemoteId: createdCust.remoteId,
        namaCustomer: 'Toko Bu Dewi Makmur',
      );
      final updatedCust = (await repo.getAllCustomer()).firstWhere(
        (c) => c.idCustomer == createdCust.idCustomer,
      );
      expect(updatedCust.namaCustomer, 'Toko Bu Dewi Makmur');
      await repo.deleteCustomer(updatedCust.idCustomer!);
      expect(
        (await repo.getAllCustomer()).any(
          (c) => c.idCustomer == updatedCust.idCustomer,
        ),
        isFalse,
      );

      // Petugas Create + passwordHash preservation + Update + Delete
      await ctx.dbHelper.upsertPetugas(
        Petugas(
          namaPetugas: 'Pemilik Utama',
          role: UserRole.owner,
          pin: '9999',
          email: 'owner@depottelur36.com',
          accountId: 'owner01',
          passwordHash: 'hash_rahasia_owner',
          remoteId: 'owner-remote-1',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime(2026, 2, 16),
        ),
      );
      await repo.savePetugas(
        namaPetugas: 'Budi Santoso',
        role: UserRole.petugas,
        pin: '4321',
        email: 'Budi.Kasir@DepotTelur36.com',
        requireEmail: true,
      );
      final createdPetugas = (await repo.getAllPetugas()).firstWhere(
        (p) => p.email == 'budi.kasir@depottelur36.com',
      );
      expect(createdPetugas.role, UserRole.petugas);
      expect(createdPetugas.pin, '4321');

      // Seed passwordHash directly lalu edit via savePetugas -> hash tidak boleh hilang
      await ctx.dbHelper.upsertPetugas(
        createdPetugas.copyWith(passwordHash: 'hash_kasir_123'),
      );
      await repo.savePetugas(
        idPetugas: createdPetugas.idPetugas,
        existingRemoteId: createdPetugas.remoteId,
        namaPetugas: 'Budi Kepala Kasir',
        role: UserRole.owner,
        pin: '5678',
        email: 'budi.kasir@depottelur36.com',
        activeUserRemoteId: 'owner-remote-1',
      );
      final updatedPetugas = (await repo.getAllPetugas()).firstWhere(
        (p) => p.idPetugas == createdPetugas.idPetugas,
      );
      expect(updatedPetugas.namaPetugas, 'Budi Kepala Kasir');
      expect(updatedPetugas.role, UserRole.owner);
      expect(updatedPetugas.passwordHash, 'hash_kasir_123');

      await repo.deletePetugas(
        updatedPetugas,
        currentUserRemoteId: 'owner-remote-1',
      );
      expect(
        (await repo.getAllPetugas()).any(
          (p) => p.idPetugas == updatedPetugas.idPetugas,
        ),
        isFalse,
      );
    });

    test('Offline delete mencatat pending_deletes, cegah cloud resurrection, dan push Firestore delete saat syncNow', () async {
      final store = _RecordingFirestoreStore();
      final firestore = _RecordingFirestore(store);
      final connectivity = _OnlineConnectivity(online: false);
      final ctx = await _openIsolatedRepo(
        syncFactory: (db) => SyncService(
          dbHelper: db,
          firestore: firestore,
          connectivity: connectivity,
        ),
      );

      await ctx.repo.saveSupplier(
        existingRemoteId: 'sup-sync-tombstone',
        namaSupplier: 'CV Telur Nusantara',
        alamatSupplier: 'Jl. Industri No. 10 Bekasi',
        noTelpSupplier: '081299988877',
      );
      await ctx.repo.saveBarang(
        existingRemoteId: 'brg-sync-tombstone',
        namaBarang: 'Telur Omega Premium',
        stokBarang: 25,
        satuan: 'Pack',
        hargaSatuan: 35000,
      );

      // Simulasi sudah ada di Firestore
      final sup = (await ctx.repo.getAllSupplier()).firstWhere(
        (s) => s.remoteId == 'sup-sync-tombstone',
      );
      final brg = (await ctx.repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == 'brg-sync-tombstone',
      );
      store.docs['supplier/sup-sync-tombstone'] = sup.toFirestore();
      store.docs['barang/brg-sync-tombstone'] = brg.toFirestore();

      // Hapus offline
      await ctx.repo.deleteSupplier(sup.idSupplier!);
      await ctx.repo.deleteBarang(brg.idBarang!);

      final pendingDeletes = await ctx.dbHelper.getPendingDeletes();
      expect(
        pendingDeletes.any(
          (e) =>
              e.tableName == 'supplier' && e.remoteId == 'sup-sync-tombstone',
        ),
        isTrue,
      );
      expect(
        pendingDeletes.any(
          (e) => e.tableName == 'barang' && e.remoteId == 'brg-sync-tombstone',
        ),
        isTrue,
      );
      expect(await ctx.dbHelper.getPendingSyncCount(), greaterThanOrEqualTo(2));

      // Simulasi event snapshot cloud usang datang sebelum delete selesai di-push
      await ctx.dbHelper.applyCloudSupplier(sup);
      await ctx.dbHelper.applyCloudBarang(brg);
      expect(
        await ctx.dbHelper.getSupplierByRemoteId('sup-sync-tombstone'),
        isNull,
      );
      expect(
        await ctx.dbHelper.getBarangByRemoteId('brg-sync-tombstone'),
        isNull,
      );

      // Jalankan syncNow saat kembali online -> harus menghapus doc Firestore dan mengosongkan tombstone
      connectivity.online = true;
      await ctx.repo.syncService.syncNow();
      expect(store.deletedDocPaths, contains('supplier/sup-sync-tombstone'));
      expect(store.deletedDocPaths, contains('barang/brg-sync-tombstone'));
      expect(store.docs.containsKey('supplier/sup-sync-tombstone'), isFalse);
      expect(store.docs.containsKey('barang/brg-sync-tombstone'), isFalse);
      expect(await ctx.dbHelper.getPendingDeletes(), isEmpty);
    });
  });

  group('Fungsi 3 Repository & Integritas - Edge Case & Salah Input', () {
    test('FK ON DELETE RESTRICT menolak penghapusan Barang, Supplier, Customer, dan Petugas yang dipakai transaksi', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      await repo.savePetugas(
        existingRemoteId: 'petugas-fk-1',
        namaPetugas: 'Kasir Aktif',
        role: UserRole.petugas,
        pin: '1122',
        email: 'kasir.fk@depottelur36.com',
      );
      await repo.savePetugas(
        existingRemoteId: 'owner-fk-1',
        namaPetugas: 'Owner Cadangan',
        role: UserRole.owner,
        pin: '9988',
        email: 'owner.fk@depottelur36.com',
      );
      final petugas = (await repo.getAllPetugas()).firstWhere(
        (p) => p.remoteId == 'petugas-fk-1',
      );
      final supplier = (await repo.getAllSupplier()).first;
      final customer = (await repo.getAllCustomer()).first;
      final barang = (await repo.getAllBarang()).first;

      await repo.createFaktur(
        noFaktur: 'FK-001',
        tanggalFaktur: '2026-02-18',
        supplier: supplier,
        petugas: petugas,
        items: [(barang: barang, quantity: 5)],
      );
      await repo.createNota(
        tanggalNota: '2026-02-18',
        customer: customer,
        petugas: petugas,
        items: [(barang: barang, banyaknya: 2)],
      );

      await expectLater(
        () => repo.deleteBarang(barang.idBarang!),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deleteSupplier(supplier.idSupplier!),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deleteCustomer(customer.idCustomer!),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deletePetugas(
          petugas,
          currentUserRemoteId: 'owner-fk-1',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Pastikan tidak ada pending_deletes palsu yang tercatat
      expect(await ctx.dbHelper.getPendingDeletes(), isEmpty);
    });

    test('Last-Owner & Self-Protection mencegah penghapusan/penurunan Owner terakhir atau akun aktif', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      await repo.savePetugas(
        existingRemoteId: 'owner-sole',
        namaPetugas: 'Owner Tunggal',
        role: UserRole.owner,
        pin: '7777',
        email: 'sole@depottelur36.com',
      );
      final soleOwner = (await repo.getAllPetugas()).first;

      // Owner tunggal tidak boleh dihapus
      await expectLater(
        () => repo.deletePetugas(soleOwner),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Owner tunggal tidak boleh diturunkan menjadi Petugas
      await expectLater(
        () => repo.savePetugas(
          idPetugas: soleOwner.idPetugas,
          existingRemoteId: soleOwner.remoteId,
          namaPetugas: soleOwner.namaPetugas,
          role: UserRole.petugas,
          pin: soleOwner.pin,
          email: soleOwner.email,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Tambah Owner kedua -> sekarang ada 2 Owner, namun self-delete & self-demote tetap ditolak
      await repo.savePetugas(
        existingRemoteId: 'owner-second',
        namaPetugas: 'Owner Kedua',
        role: UserRole.owner,
        pin: '8888',
        email: 'second@depottelur36.com',
      );
      await expectLater(
        () => repo.deletePetugas(
          soleOwner,
          currentUserRemoteId: 'owner-sole',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.savePetugas(
          idPetugas: soleOwner.idPetugas,
          existingRemoteId: soleOwner.remoteId,
          namaPetugas: soleOwner.namaPetugas,
          role: UserRole.petugas,
          pin: soleOwner.pin,
          email: soleOwner.email,
          activeUserRemoteId: 'owner-sole',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
    });

    test('Validasi salah input menolak NaN, nol/negatif, karakter kontrol, duplikat, HP invalid, PIN & email salah', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      // Barang invalid inputs
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'A',
          stokBarang: 5,
          satuan: 'Kg',
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur\nInject',
          stokBarang: 5,
          satuan: 'Kg',
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur Bagus',
          stokBarang: -1,
          satuan: 'Kg',
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur Bagus',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: 0,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur Bagus',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: double.nan,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur Bagus',
          stokBarang: 10,
          satuan: '   ',
          hargaSatuan: 15000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      // Duplikat case-insensitive & spasi ganda terhadap seed
      await expectLater(
        () => repo.saveBarang(
          namaBarang: '  telur   ayam   negeri ',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: 29000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Batch price errors
      await expectLater(
        () => repo.updateBarangHargaBatch({}),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.updateBarangHargaBatch({99999: 15000}),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.updateBarangHargaBatch({1: double.infinity}),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Supplier errors
      await expectLater(
        () => repo.saveSupplier(
          namaSupplier: 'CV Valid',
          alamatSupplier: 'Jl. Valid No. 1',
          noTelpSupplier: '0812abc',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveSupplier(
          namaSupplier: 'CV Valid',
          alamatSupplier: 'Jl.',
          noTelpSupplier: '08123456789',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Customer errors & duplicate
      await expectLater(
        () => repo.saveCustomer(namaCustomer: 'X'),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveCustomer(namaCustomer: 'pelanggan umum (eceran)'),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Petugas errors & duplicate email
      await repo.savePetugas(
        namaPetugas: 'Kasir Satu',
        role: UserRole.petugas,
        pin: '1234',
        email: 'kasir1@depottelur36.com',
      );
      await expectLater(
        () => repo.savePetugas(
          namaPetugas: 'Kasir Dua',
          role: UserRole.petugas,
          pin: '12a4',
          email: 'kasir2@depottelur36.com',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.savePetugas(
          namaPetugas: 'Kasir Dua',
          role: UserRole.petugas,
          pin: '1234',
          email: 'bukan-email',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.savePetugas(
          namaPetugas: 'Kasir Duplikat',
          role: UserRole.petugas,
          pin: '1234',
          email: 'KASIR1@depottelur36.com',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
    });
  });

  group('MasterCrudViewModel - RBAC, Filter, Epoch & Lifecycle', () {
    test('Operator diblokir dari kategori Petugas & Atur Harga, dan updateSession mereset tab terlarang', () async {
      final ds = _FakeMasterCrudDataSource()
        ..barang = [
          Barang(
            idBarang: 1,
            namaBarang: 'Telur Ayam Negeri',
            stokBarang: 50,
            satuan: 'Kg',
            hargaSatuan: 28000,
            remoteId: 'b1',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 2,
            namaBarang: 'Minyak Goreng 1L',
            stokBarang: 5,
            satuan: 'Pouch',
            hargaSatuan: 17000,
            remoteId: 'b2',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..petugas = [
          Petugas(
            idPetugas: 1,
            namaPetugas: 'Budi Owner',
            role: UserRole.owner,
            pin: '9999',
            remoteId: 'p1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final opVm = MasterCrudViewModel(
        session: _operatorSession(),
        dataSource: ds,
      );
      addTearDown(() async {
        opVm.dispose();
        await ds.dispose();
      });

      await opVm.loadData();
      expect(opVm.categories, isNot(contains(MasterCategory.petugas)));
      expect(opVm.allPetugas, isEmpty);

      opVm.selectCategory(MasterCategory.petugas);
      expect(opVm.activeCategory, MasterCategory.barang);
      expect(opVm.accessDeniedMessage, contains('hanya Owner'));

      expect(
        await opVm.savePetugas(namaPetugas: 'Hack Kasir', role: UserRole.owner),
        isFalse,
      );
      expect(await opVm.deletePetugas(ds.petugas.first), isFalse);
      expect(await opVm.saveHargaBatch({1: 99000}), isFalse);
      expect(ds.savePetugasCalls, 0);
      expect(ds.deletePetugasCalls, 0);
      expect(ds.saveHargaBatchCalls, 0);

      // Owner dapat filter harga Komoditas Telur vs Sembako + updateSession downgrade
      final ownerVm = MasterCrudViewModel(
        session: _ownerSession(),
        dataSource: ds,
      );
      addTearDown(ownerVm.dispose);
      await ownerVm.loadData();
      expect(ownerVm.categories, contains(MasterCategory.petugas));

      ownerVm.selectCategory(MasterCategory.petugas);
      expect(ownerVm.activeCategory, MasterCategory.petugas);

      ownerVm.setPriceFilter(PriceFilterCategory.telur);
      expect(ownerVm.filteredBarangForPrice.single.namaBarang, contains('Telur'));
      ownerVm.setPriceFilter(PriceFilterCategory.sembako);
      expect(
        ownerVm.filteredBarangForPrice.single.namaBarang,
        'Minyak Goreng 1L',
      );

      // Downgrade session saat sedang berada di tab Petugas -> harus reset
      ownerVm.updateSession(_operatorSession());
      expect(ownerVm.activeCategory, MasterCategory.barang);
      expect(ownerVm.allPetugas, isEmpty);
    });

    test('Epoch guard mencegah data usang menimpa data baru & re-entrancy/dispose aman', () async {
      final ds = _FakeMasterCrudDataSource();
      final slowLoad = Completer<List<Barang>>();
      var loadCalls = 0;

      ds.onGetAllBarang = () async {
        loadCalls++;
        if (loadCalls == 1) return slowLoad.future;
        return [
          Barang(
            idBarang: 10,
            namaBarang: 'Telur Baru Segar',
            stokBarang: 99,
            satuan: 'Kg',
            hargaSatuan: 31000,
            remoteId: 'b-new',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];
      };

      final vm = MasterCrudViewModel(session: _ownerSession(), dataSource: ds);
      final slowFuture = vm.loadData();
      final fastFuture = vm.loadData();

      await fastFuture;
      expect(vm.allBarang.single.namaBarang, 'Telur Baru Segar');

      slowLoad.complete([
        Barang(
          idBarang: 1,
          namaBarang: 'Telur Usang',
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 10000,
          remoteId: 'b-old',
          updatedAt: DateTime(2026, 2, 15),
        ),
      ]);
      await slowFuture;
      expect(vm.allBarang.single.namaBarang, 'Telur Baru Segar');

      // Re-entrancy guard saat _isSaving == true
      final saveGate = Completer<void>();
      ds.onSaveBarang = () => saveGate.future;
      final s1 = vm.saveBarang(
        namaBarang: 'Produk 1',
        stokBarang: 10,
        satuan: 'Kg',
        hargaSatuan: 20000,
      );
      final s2 = vm.saveBarang(
        namaBarang: 'Produk 2',
        stokBarang: 10,
        satuan: 'Kg',
        hargaSatuan: 20000,
      );
      expect(ds.saveBarangCalls, 1);
      saveGate.complete();
      await s1;
      await s2;

      // Sanitize query
      vm.setSearchQuery('  \u200B${'a' * 120}\n  ');
      expect(vm.searchQuery.length, 80);

      // Dispose harus memblokir callback berikutnya tanpa throw
      vm.dispose();
      ds.emitChanged();
      await vm.loadData();
      await ds.dispose();
    });
  });

  group('Regresi Bug & Integritas Data (Repository & SQLite)', () {
    test('Edit via id* tanpa existingRemoteId mempertahankan remoteId & mencegah double-count pending_deletes', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;
      final db = ctx.dbHelper;

      // Create seluruh entitas dengan remoteId otomatis
      await repo.saveBarang(
        namaBarang: 'Telur Puyuh Segar',
        stokBarang: 45,
        satuan: 'Pack',
        hargaSatuan: 12000,
      );
      await repo.saveSupplier(
        namaSupplier: 'Peternakan Puyuh Jaya',
        alamatSupplier: 'Jl. Alternatif Selatan No. 8',
        noTelpSupplier: '0812-3456-7890',
      );
      await repo.saveCustomer(namaCustomer: 'Warung Bakmi Sejahtera');
      await repo.savePetugas(
        namaPetugas: 'Kasir Regresi',
        role: UserRole.petugas,
        pin: '2468',
        email: 'regresi@depottelur36.com',
        accountId: 'acc-regresi-01',
      );
      final seededPetugas = (await db.getAllPetugas()).firstWhere(
        (p) => p.email == 'regresi@depottelur36.com',
      );
      await db.upsertPetugas(seededPetugas.copyWith(passwordHash: 'hash-rahasia'));

      final brg = (await repo.getAllBarang()).firstWhere(
        (b) => b.namaBarang == 'Telur Puyuh Segar',
      );
      final sup = (await repo.getAllSupplier()).firstWhere(
        (s) => s.namaSupplier == 'Peternakan Puyuh Jaya',
      );
      final cust = (await repo.getAllCustomer()).firstWhere(
        (c) => c.namaCustomer == 'Warung Bakmi Sejahtera',
      );
      final ptg = (await db.getAllPetugas()).firstWhere(
        (p) => p.email == 'regresi@depottelur36.com',
      );

      // Edit hanya memakai id* dengan existingRemoteId == null -> remoteId tidak boleh berubah
      await repo.saveBarang(
        idBarang: brg.idBarang,
        namaBarang: 'Telur Puyuh Organik',
        stokBarang: 60,
        satuan: 'Pack',
        hargaSatuan: 14000,
      );
      await repo.saveSupplier(
        idSupplier: sup.idSupplier,
        namaSupplier: 'Peternakan Puyuh Makmur',
        alamatSupplier: 'Jl. Alternatif Selatan No. 88',
        noTelpSupplier: '+62 813-9988-7766',
      );
      await repo.saveCustomer(
        idCustomer: cust.idCustomer,
        namaCustomer: 'Warung Bakmi Sejahtera Cabang 2',
      );
      await repo.savePetugas(
        idPetugas: ptg.idPetugas,
        namaPetugas: 'Kasir Regresi Edit',
        role: UserRole.petugas,
        pin: '1357',
        email: '',
        accountId: '',
      );

      final brgAfter = (await repo.getAllBarang()).firstWhere(
        (b) => b.idBarang == brg.idBarang,
      );
      final supAfter = (await repo.getAllSupplier()).firstWhere(
        (s) => s.idSupplier == sup.idSupplier,
      );
      final custAfter = (await repo.getAllCustomer()).firstWhere(
        (c) => c.idCustomer == cust.idCustomer,
      );
      final ptgAfter = (await db.getAllPetugas()).firstWhere(
        (p) => p.idPetugas == ptg.idPetugas,
      );

      expect(brgAfter.remoteId, brg.remoteId);
      expect(supAfter.remoteId, sup.remoteId);
      expect(custAfter.remoteId, cust.remoteId);
      expect(ptgAfter.remoteId, ptg.remoteId);
      expect(ptgAfter.email, 'regresi@depottelur36.com');
      expect(ptgAfter.accountId, 'acc-regresi-01');
      expect(ptgAfter.passwordHash, 'hash-rahasia');

      // Jalur upgrade UID dari AuthRepository (idPetugas sama, remoteId baru) tetap didukung
      await db.upsertPetugas(
        ptgAfter.copyWith(
          remoteId: 'firebase-uid-upgraded',
          syncStatus: SyncStatus.synced,
        ),
      );
      final ptgUpgraded = await db.getPetugasByRemoteId('firebase-uid-upgraded');
      expect(ptgUpgraded?.idPetugas, ptg.idPetugas);
      expect(ptgUpgraded?.passwordHash, 'hash-rahasia');

      // Re-create remoteId setelah offline delete harus membersihkan pending_deletes (tanpa double-count)
      await db.markSynced('barang', brg.remoteId);
      final pendingBeforeDelete = await db.getPendingSyncCount();
      await repo.deleteBarang(brg.idBarang!);
      expect(await db.hasPendingDelete('barang', brg.remoteId), isTrue);
      expect(await db.getPendingSyncCount(), pendingBeforeDelete + 1);

      await repo.saveBarang(
        existingRemoteId: brg.remoteId,
        namaBarang: 'Telur Puyuh Bangkit',
        stokBarang: 25,
        satuan: 'Pack',
        hargaSatuan: 13500,
      );
      expect(await db.hasPendingDelete('barang', brg.remoteId), isFalse);
      expect(await db.getPendingSyncCount(), pendingBeforeDelete + 1);

      // Setelah tersinkron lagi, applyCloudBarang tidak lagi diblokir oleh pending_deletes lama
      await db.markSynced('barang', brg.remoteId);
      final reborn = (await repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == brg.remoteId,
      );
      await db.applyCloudBarang(
        reborn.copyWith(stokBarang: 80, hargaSatuan: 15000),
      );
      final syncedFromCloud = await db.getBarangByRemoteId(brg.remoteId);
      expect(syncedFromCloud?.stokBarang, 80);
      expect(syncedFromCloud?.hargaSatuan, 15000);
    });

    test('Penolakan id lokal tidak ditemukan, mismatch id vs remoteId, & atomisitas batch harga', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;
      final db = ctx.dbHelper;

      // ID non-eksisten tidak boleh diam-diam return 0 baris
      await expectLater(
        () => repo.saveBarang(
          idBarang: 99999,
          namaBarang: 'Barang Hantu',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: 25000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveSupplier(
          idSupplier: 99999,
          namaSupplier: 'Supplier Hantu',
          alamatSupplier: 'Jl. Hantu No. 1',
          noTelpSupplier: '08123456789',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveCustomer(
          idCustomer: 99999,
          namaCustomer: 'Customer Hantu',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.savePetugas(
          idPetugas: 99999,
          namaPetugas: 'Petugas Hantu',
          role: UserRole.petugas,
          pin: '1234',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deleteBarang(99999),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deleteSupplier(99999),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.deleteCustomer(99999),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Mismatch id lokal milik baris A + existingRemoteId milik baris B
      final allBarang = await repo.getAllBarang();
      final allSuppliers = await repo.getAllSupplier();
      await repo.saveCustomer(namaCustomer: 'Customer Alpha');
      await repo.saveCustomer(namaCustomer: 'Customer Beta');
      final allCustomers = await repo.getAllCustomer();
      await repo.savePetugas(
        namaPetugas: 'Petugas Alpha',
        role: UserRole.petugas,
        pin: '1111',
        email: 'alpha@depottelur36.com',
      );
      await repo.savePetugas(
        namaPetugas: 'Petugas Beta',
        role: UserRole.petugas,
        pin: '2222',
        email: 'beta@depottelur36.com',
      );
      final allPetugas = await db.getAllPetugas();

      await expectLater(
        () => repo.saveBarang(
          idBarang: allBarang[0].idBarang,
          existingRemoteId: allBarang[1].remoteId,
          namaBarang: 'Konflik Barang',
          stokBarang: 5,
          satuan: 'Kg',
          hargaSatuan: 20000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveSupplier(
          idSupplier: allSuppliers[0].idSupplier,
          existingRemoteId: allSuppliers[1].remoteId,
          namaSupplier: 'Konflik Supplier',
          alamatSupplier: 'Jl. Konflik No. 1',
          noTelpSupplier: '08123456789',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveCustomer(
          idCustomer: allCustomers[0].idCustomer,
          existingRemoteId: allCustomers[1].remoteId,
          namaCustomer: 'Konflik Customer',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.savePetugas(
          idPetugas: allPetugas[0].idPetugas,
          existingRemoteId: allPetugas[1].remoteId,
          namaPetugas: 'Konflik Petugas',
          role: UserRole.petugas,
          pin: '3333',
          email: 'alpha@depottelur36.com',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Atomisitas batch harga pada layer DB: jika 1 ID gagal, seluruh batch di-rollback
      final targetBarang = allBarang.first;
      final originalPrice = targetBarang.hargaSatuan;
      await expectLater(
        () => db.updateBarangHargaBatch({
          targetBarang.idBarang!: 99000,
          99999: 88000,
        }),
        throwsA(isA<StateError>()),
      );
      final reloaded = (await repo.getAllBarang()).firstWhere(
        (b) => b.idBarang == targetBarang.idBarang,
      );
      expect(reloaded.hargaSatuan, originalPrice);

      // existingRemoteId kosong/whitespace/kontrol harus ditolak
      await expectLater(
        () => repo.saveBarang(
          existingRemoteId: '   ',
          namaBarang: 'Barang Remote Kosong',
          stokBarang: 5,
          satuan: 'Kg',
          hargaSatuan: 15000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveCustomer(
          existingRemoteId: 'rem\u200Bote',
          namaCustomer: 'Customer Remote Kontrol',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
    });
  });

  group('Validasi Boundary, Unicode Siluman & Format Input Salah', () {
    test('Skenario boundary valid (panjang min/max, stok 0..9999999, HP internasional, hapus/demote 2nd owner)', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      // Boundary minimum & maksimum Barang
      await repo.saveBarang(
        namaBarang: '  AB  ',
        stokBarang: 0,
        satuan: ' P ',
        hargaSatuan: 0.01,
      );
      await repo.saveBarang(
        namaBarang: 'B' * 80,
        stokBarang: 9999999,
        satuan: 'S' * 24,
        hargaSatuan: 1000000000,
      );

      // Boundary minimum & maksimum Supplier + format telepon internasional & alamat multiline
      await repo.saveSupplier(
        namaSupplier: 'CD',
        alamatSupplier: 'Jl. A',
        noTelpSupplier: '08123456',
      );
      await repo.saveSupplier(
        namaSupplier: 'S' * 80,
        alamatSupplier: 'Jalan Gudang Telur Blok A\n${'X' * 214}',
        noTelpSupplier: '(+62) 813-1111-2222',
      );
      await repo.saveSupplier(
        namaSupplier: 'Supplier Max Digit',
        alamatSupplier: 'Pasar Induk No. 99',
        noTelpSupplier: '081234567890123',
      );

      // Jika ada 2 Owner, Owner non-aktif boleh diturunkan rolenya lalu dihapus
      await repo.savePetugas(
        existingRemoteId: 'owner-1',
        namaPetugas: 'Owner Utama',
        role: UserRole.owner,
        pin: '1111',
        email: 'owner1@depottelur36.com',
      );
      await repo.savePetugas(
        existingRemoteId: 'owner-2',
        namaPetugas: 'Owner Kedua',
        role: UserRole.owner,
        pin: '2222',
        email: 'owner2@depottelur36.com',
      );
      final secondOwner = (await repo.getAllPetugas()).firstWhere(
        (p) => p.remoteId == 'owner-2',
      );
      await repo.savePetugas(
        idPetugas: secondOwner.idPetugas,
        existingRemoteId: secondOwner.remoteId,
        namaPetugas: 'Ex Owner Kedua',
        role: UserRole.petugas,
        pin: '2222',
        email: secondOwner.email,
        activeUserRemoteId: 'owner-1',
      );
      final demoted = (await repo.getAllPetugas()).firstWhere(
        (p) => p.remoteId == 'owner-2',
      );
      expect(demoted.role, UserRole.petugas);
      await repo.deletePetugas(demoted, currentUserRemoteId: 'owner-1');
      expect(
        (await repo.getAllPetugas()).any((p) => p.remoteId == 'owner-2'),
        isFalse,
      );
    });

    test('Menolak Unicode siluman (ZWSP/BOM/BiDi), panjang berlebih, spasi duplikat, & HP/PIN/email rusak', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      // Karakter Unicode siluman pada seluruh field teks
      for (final bad in ['\u200B', '\u200B\u200B', 'Telur\u200BAyam', 'A\uFEFFB', 'X\u202EY', 'Budi\u2060S']) {
        await expectLater(
          () => repo.saveBarang(
            namaBarang: bad,
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 25000,
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
        await expectLater(
          () => repo.saveCustomer(namaCustomer: bad),
          throwsA(isA<MasterDataValidationException>()),
        );
        await expectLater(
          () => repo.savePetugas(
            namaPetugas: bad,
            role: UserRole.petugas,
            pin: '1234',
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
      }
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Telur Bebas',
          stokBarang: 5,
          satuan: 'Kg\uFEFF',
          hargaSatuan: 25000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveSupplier(
          namaSupplier: 'CV Valid',
          alamatSupplier: 'Jl. Raya\u200BNo. 12',
          noTelpSupplier: '08123456789',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Over-length & batas numerik
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'N' * 81,
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Barang Valid',
          stokBarang: 1,
          satuan: 'S' * 25,
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Stok Berlebih',
          stokBarang: 10000000,
          satuan: 'Kg',
          hargaSatuan: 10000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Harga Berlebih',
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 1000000001,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => repo.saveSupplier(
          namaSupplier: 'CV Panjang Alamat',
          alamatSupplier: 'A' * 241,
          noTelpSupplier: '08123456789',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Duplikat nama setelah normalisasi spasi ganda
      await expectLater(
        () => repo.saveBarang(
          namaBarang: '  telur    ayam   negeri  ',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: 28000,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Format nomor telepon supplier malformed
      const badPhones = [
        '0812++++3456',
        '+62+81234567',
        '0812+3456789',
        '0812----3456',
        '-081234567',
        '0812-3456-',
        '0812 () 345678',
        '1234567',
        '1234567890123456',
        '0812-3456-7890-1234-5678-9',
        '0812-3456-abcd',
        '     ',
      ];
      for (final phone in badPhones) {
        await expectLater(
          () => repo.saveSupplier(
            namaSupplier: 'Supplier Uji HP',
            alamatSupplier: 'Jl. Pengujian No. 1',
            noTelpSupplier: phone,
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
      }

      // Email wajib saat requireEmail = true + variasi PIN salah
      await expectLater(
        () => repo.savePetugas(
          namaPetugas: 'Kasir Tanpa Email',
          role: UserRole.petugas,
          pin: '1234',
          email: '',
          requireEmail: true,
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      for (final badPin in ['123', '12345', '12\x004', 'abcd', '    ']) {
        await expectLater(
          () => repo.savePetugas(
            namaPetugas: 'Kasir PIN Rusak',
            role: UserRole.petugas,
            pin: badPin,
            email: 'pinrusak@depottelur36.com',
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
      }
    });
  });

  group('MasterCrudViewModel Lanjutan & ReadOnlyDashboardBridgeDataSource', () {
    test('Pencarian Rupiah pada Atur Harga, updateSession reset pesan, clearMessages & repository end-to-end', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;
      await repo.savePetugas(
        existingRemoteId: 'kasir-remote-1',
        namaPetugas: 'Siti Kasir',
        role: UserRole.petugas,
        pin: '1234',
        email: 'kasir@depottelur36.com',
      );
      await repo.savePetugas(
        existingRemoteId: 'owner-remote-1',
        namaPetugas: 'Budi Owner',
        role: UserRole.owner,
        pin: '9999',
        email: 'owner@depottelur36.com',
      );

      final vm = MasterCrudViewModel.fromRepository(
        session: _operatorSession(),
        repository: repo,
      );
      await vm.loadData();
      expect(vm.allBarang.length, 6);
      expect(vm.allSuppliers.length, 2);
      expect(vm.allCustomers.length, 1);
      expect(vm.allPetugas, isEmpty);

      // Pencarian di layar Atur Harga harus cocok terhadap format Rupiah (regresi bug)
      vm.setSearchQuery('28.500');
      expect(
        vm.filteredBarangForPrice.map((b) => b.namaBarang),
        ['Telur Ayam Negeri'],
      );
      vm.setSearchQuery('Rp 74');
      expect(
        vm.filteredBarangForPrice.map((b) => b.namaBarang),
        ['Beras Pandan Wangi 5 Kg'],
      );
      vm.setPriceFilter(PriceFilterCategory.telur);
      expect(vm.filteredBarangForPrice, isEmpty);
      vm.clearSearch();
      vm.setPriceFilter(PriceFilterCategory.semua);
      expect(vm.searchQuery, isEmpty);

      // Filter supplier & customer
      vm.setSearchQuery('B-05');
      expect(vm.filteredSuppliers.single.namaSupplier, 'Agen Sembako Berkah Sentosa');
      vm.setSearchQuery('Eceran');
      expect(vm.filteredCustomers.single.namaCustomer, 'Pelanggan Umum (Eceran)');
      vm.clearSearch();

      // Operator memicu accessDeniedMessage lalu upgrade session ke Owner -> pesan usang harus bersih
      vm.selectCategory(MasterCategory.petugas);
      expect(vm.accessDeniedMessage, isNotNull);

      vm.updateSession(_ownerSession());
      expect(vm.accessDeniedMessage, isNull);
      expect(vm.errorMessage, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(vm.allPetugas.length, 2);

      // Filter Petugas berdasar label role & email
      vm.setSearchQuery('owner');
      expect(vm.filteredPetugas.single.remoteId, 'owner-remote-1');
      vm.clearSearch();

      // Hapus barang tanpa idBarang -> errorMessage muncul lalu dibersihkan lewat clearMessages
      final unsavedOk = await vm.deleteBarang(
        Barang(
          namaBarang: 'Belum Simpan',
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 1000,
          remoteId: 'unsaved-b',
          updatedAt: DateTime(2026),
        ),
      );
      expect(unsavedOk, isFalse);
      expect(vm.errorMessage, isNotNull);
      vm.clearMessages();
      expect(vm.errorMessage, isNull);

      // CRUD melalui VM + auto-refresh stream onDataChanged
      final createdOk = await vm.saveBarang(
        namaBarang: 'Telur Omega Premium',
        stokBarang: 40,
        satuan: 'Kg',
        hargaSatuan: 35000,
      );
      expect(createdOk, isTrue);
      expect(
        vm.allBarang.any((b) => b.namaBarang == 'Telur Omega Premium'),
        isTrue,
      );

      // Ubah uid/email session memicu _notify walaupun role tetap sama
      var sessionNotified = 0;
      vm.addListener(() => sessionNotified++);
      vm.updateSession(_ownerSession().copyWith(uid: 'uid-owner-baru'));
      expect(sessionNotified, 1);

      vm.dispose();
    });

    test('ReadOnlyDashboardBridgeDataSource membaca snapshot & memblokir seluruh mutasi dengan aman', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;
      final dashVm = DashboardViewModel.fromRepository(
        session: _ownerSession(),
        repository: repo,
      );
      await dashVm.loadDashboardData();

      final vm = MasterCrudViewModel(
        session: _ownerSession(),
        dataSource: ReadOnlyDashboardBridgeDataSource(dashVm),
      );
      await vm.loadData();
      expect(vm.allBarang.length, 6);
      expect(vm.allSuppliers.length, 2);

      expect(
        await vm.saveBarang(
          namaBarang: 'Coba Tulis',
          stokBarang: 10,
          satuan: 'Kg',
          hargaSatuan: 20000,
        ),
        isFalse,
      );
      expect(vm.errorMessage, 'Penyimpanan lokal belum diinisialisasi.');

      expect(await vm.saveHargaBatch({1: 30000}), isFalse);
      expect(await vm.deleteBarang(vm.allBarang.first), isFalse);
      expect(
        await vm.saveSupplier(
          namaSupplier: 'CV Uji',
          alamatSupplier: 'Jl. Uji No. 1',
          noTelpSupplier: '08123456789',
        ),
        isFalse,
      );
      expect(await vm.deleteSupplier(vm.allSuppliers.first), isFalse);
      expect(await vm.saveCustomer(namaCustomer: 'Uji Pelanggan'), isFalse);
      expect(await vm.deleteCustomer(vm.allCustomers.first), isFalse);
      expect(
        await vm.savePetugas(
          namaPetugas: 'Uji Petugas',
          role: UserRole.petugas,
          pin: '1234',
        ),
        isFalse,
      );
      expect(
        await vm.deletePetugas(
          Petugas(
            idPetugas: 1,
            namaPetugas: 'Dummy',
            role: UserRole.petugas,
            pin: '1234',
            remoteId: 'dummy-p',
            updatedAt: DateTime(2026),
          ),
        ),
        isFalse,
      );

      // Error non-validasi saat loadData ditangani tanpa melempar exception
      final brokenDs = _FakeMasterCrudDataSource()
        ..onGetAllBarang = () async => throw StateError('disk failure');
      final brokenVm = MasterCrudViewModel(
        session: _ownerSession(),
        dataSource: brokenDs,
      );
      await brokenVm.loadData();
      expect(brokenVm.errorMessage, isNotNull);

      brokenVm.dispose();
      await brokenDs.dispose();
      vm.dispose();
      dashVm.dispose();
    });
  });
}
