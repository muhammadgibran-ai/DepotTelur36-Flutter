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
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentSyncService extends SyncService {
  _SilentSyncService({required super.dbHelper})
      : super(
          firestore: _NoopFirestore(),
          connectivity: _ToggleConnectivity(online: false),
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

class _ToggleConnectivity implements Connectivity {
  _ToggleConnectivity({this.online = true});

  bool online;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => online
      ? const [ConnectivityResult.wifi]
      : const [ConnectivityResult.none];

  Future<void> dispose() => _controller.close();
}

class _RecordingFirestoreStore {
  final List<String> deletedDocPaths = [];
  final Map<String, Map<String, dynamic>> docs = {};
  final Map<String, StreamController<QuerySnapshot<Map<String, dynamic>>>>
      _controllers = {};

  StreamController<QuerySnapshot<Map<String, dynamic>>> controllerFor(
    String collection,
  ) {
    return _controllers.putIfAbsent(
      collection,
      () => StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(),
    );
  }

  void emitSnapshot(
    String collection,
    Map<String, Map<String, dynamic>> snapshotDocs,
  ) {
    final prefix = '$collection/';
    docs.removeWhere((key, _) => key.startsWith(prefix));
    snapshotDocs.forEach((docId, data) {
      docs['$prefix$docId'] = Map<String, dynamic>.from(data);
    });
    final queryDocs = snapshotDocs.entries
        .map((e) => _FakeQueryDocumentSnapshot(e.key, e.value))
        .toList();
    controllerFor(collection).add(_FakeQuerySnapshot(queryDocs));
  }

  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
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
  }) =>
      _store.controllerFor(_path).stream;

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
    if (options?.merge == true && _store.docs.containsKey(_fullPath)) {
      _store.docs[_fullPath] = {
        ..._store.docs[_fullPath]!,
        ...data,
      };
    } else {
      _store.docs[_fullPath] = Map<String, dynamic>.from(data);
    }
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

  int? _decodeIncrementDelta(FieldValue fv) {
    for (var delta = -250; delta <= 250; delta++) {
      if (fv == FieldValue.increment(delta)) {
        return delta;
      }
    }
    return null;
  }

  @override
  void set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {
    _ops.add(() {
      if (data is! Map<String, dynamic>) return;
      final merge = options?.merge == true;
      final existing = merge && _store.docs.containsKey(document.path)
          ? Map<String, dynamic>.from(_store.docs[document.path]!)
          : <String, dynamic>{};

      for (final entry in data.entries) {
        final value = entry.value;
        if (value is FieldValue) {
          final delta = _decodeIncrementDelta(value);
          if (delta != null) {
            final current = (existing[entry.key] as num?)?.toInt() ?? 0;
            existing[entry.key] = current + delta;
            continue;
          }
        }
        existing[entry.key] = value;
      }
      _store.docs[document.path] = existing;
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

Future<({
  Directory tempDir,
  DatabaseHelper dbHelper,
  InventoryRepository repo,
})> _openIsolatedRepo({
  SyncService Function(DatabaseHelper dbHelper)? syncFactory,
  bool clearSeededMasters = true,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('dt36_tx_test_');
  addTearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });
  final dbHelper = DatabaseHelper.forTesting(
    customDbPath: p.join(tempDir.path, 'depot_tx_test.db'),
  );
  addTearDown(() async {
    await dbHelper.close();
  });
  if (clearSeededMasters) {
    final db = await dbHelper.database;
    await db.delete('barang');
    await db.delete('supplier');
    await db.delete('customer');
  }
  final sync = syncFactory != null
      ? syncFactory(dbHelper)
      : _SilentSyncService(dbHelper: dbHelper);
  final repo = InventoryRepository(dbHelper: dbHelper, syncService: sync);
  addTearDown(repo.dispose);
  await repo.initialize();
  return (tempDir: tempDir, dbHelper: dbHelper, repo: repo);
}

Future<({
  Barang telur,
  Barang puyuh,
  Supplier supplierA,
  Supplier supplierB,
  Customer customerA,
  Customer customerB,
  Petugas kasir,
  Petugas owner,
})> _seedStandardCatalog(InventoryRepository repo) async {
  await repo.saveBarang(
    existingRemoteId: 'brg-telur',
    namaBarang: 'Telur Ayam Negeri',
    stokBarang: 50,
    satuan: 'Kg',
    hargaSatuan: 28000,
  );
  await repo.saveBarang(
    existingRemoteId: 'brg-puyuh',
    namaBarang: 'Telur Puyuh',
    stokBarang: 20,
    satuan: 'Pack',
    hargaSatuan: 15000,
  );
  await repo.saveSupplier(
    existingRemoteId: 'sup-a',
    namaSupplier: 'CV Ternak Jaya',
    alamatSupplier: 'Jl. Raya Bogor No. 12',
    noTelpSupplier: '081234567890',
  );
  await repo.saveSupplier(
    existingRemoteId: 'sup-b',
    namaSupplier: 'UD Sumber Rezeki',
    alamatSupplier: 'Jl. Pemuda No. 88',
    noTelpSupplier: '082233445566',
  );
  await repo.saveCustomer(
    existingRemoteId: 'cust-a',
    namaCustomer: 'Toko Sembako Berkah',
  );
  await repo.saveCustomer(
    existingRemoteId: 'cust-b',
    namaCustomer: 'Warung Bu Sari',
  );
  await repo.savePetugas(
    existingRemoteId: 'pet-kasir',
    namaPetugas: 'Budi Kasir',
    role: UserRole.petugas,
    pin: '1122',
    email: 'budi@depottelur36.com',
  );
  await repo.savePetugas(
    existingRemoteId: 'pet-owner',
    namaPetugas: 'Siti Owner',
    role: UserRole.owner,
    pin: '9988',
    email: 'owner@depottelur36.com',
  );

  final barangs = await repo.getAllBarang();
  final suppliers = await repo.getAllSupplier();
  final customers = await repo.getAllCustomer();
  final petugasList = await repo.getAllPetugas();

  return (
    telur: barangs.firstWhere((e) => e.remoteId == 'brg-telur'),
    puyuh: barangs.firstWhere((e) => e.remoteId == 'brg-puyuh'),
    supplierA: suppliers.firstWhere((e) => e.remoteId == 'sup-a'),
    supplierB: suppliers.firstWhere((e) => e.remoteId == 'sup-b'),
    customerA: customers.firstWhere((e) => e.remoteId == 'cust-a'),
    customerB: customers.firstWhere((e) => e.remoteId == 'cust-b'),
    kasir: petugasList.firstWhere((e) => e.remoteId == 'pet-kasir'),
    owner: petugasList.firstWhere((e) => e.remoteId == 'pet-owner'),
  );
}

class _FakeTransactionCrudDataSource implements TransactionCrudDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Barang> barang = [];
  List<Supplier> suppliers = [];
  List<Customer> customers = [];
  List<Petugas> petugas = [];
  List<Faktur> fakturs = [];
  List<Nota> notas = [];
  String nextNoFaktur = 'FKT-20261116-001';

  Future<List<Barang>> Function()? onGetAllBarang;
  Future<int> Function()? onCreateNota;
  Future<int> Function()? onCreateFaktur;
  Future<void> Function()? onUpdateNota;
  Future<void> Function()? onDeleteNota;
  Future<void> Function()? onUpdateFaktur;
  Future<void> Function()? onDeleteFaktur;

  int createNotaCalls = 0;
  int createFakturCalls = 0;
  int updateNotaCalls = 0;
  int deleteNotaCalls = 0;
  int updateFakturCalls = 0;
  int deleteFakturCalls = 0;

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
  Future<List<Faktur>> getAllFaktur() async => fakturs;

  @override
  Future<List<Nota>> getAllNota() async => notas;

  @override
  Future<Faktur?> getFakturById(int idFaktur) async {
    for (final f in fakturs) {
      if (f.idFaktur == idFaktur) return f;
    }
    return null;
  }

  @override
  Future<Nota?> getNotaById(int idNota) async {
    for (final n in notas) {
      if (n.idNota == idNota) return n;
    }
    return null;
  }

  @override
  Future<String> generateNextNoFaktur({DateTime? date}) async => nextNoFaktur;

  @override
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    createFakturCalls++;
    if (onCreateFaktur != null) return onCreateFaktur!();
    return 101;
  }

  @override
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    updateFakturCalls++;
    if (onUpdateFaktur != null) await onUpdateFaktur!();
  }

  @override
  Future<void> deleteFaktur(int idFaktur) async {
    deleteFakturCalls++;
    if (onDeleteFaktur != null) await onDeleteFaktur!();
  }

  @override
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    createNotaCalls++;
    if (onCreateNota != null) return onCreateNota!();
    return 202;
  }

  @override
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    updateNotaCalls++;
    if (onUpdateNota != null) await onUpdateNota!();
  }

  @override
  Future<void> deleteNota(int idNota) async {
    deleteNotaCalls++;
    if (onDeleteNota != null) await onDeleteNota!();
  }
}

final _testUpdatedAt = DateTime(2026, 11, 16, 9, 0);

AuthSession _makeSession({
  required UserRole role,
  required String displayName,
  required String email,
  required String petugasRemoteId,
}) {
  return AuthSession(
    uid: 'uid-$petugasRemoteId',
    email: email,
    accountId: 'acc-$petugasRemoteId',
    displayName: displayName,
    role: role,
    petugasRemoteId: petugasRemoteId,
    provider: AuthProviderType.emailPassword,
    signedInAt: _testUpdatedAt,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Model Transaksi (Faktur, DetailFaktur, Nota, DetailNota)', () {
    test('hitungTotal, copyWith, toMap/fromMap, dan toFirestore bekerja akurat', () {
      final now = DateTime(2026, 11, 16, 10, 30);
      final df1 = DetailFaktur(
        idFaktur: 1,
        idBarang: 2,
        jumlah: 140000,
        quantity: 5,
        barangRemoteId: 'brg-1',
        namaBarang: 'Telur Ayam Negeri',
        satuan: 'Kg',
      );
      final df2 = DetailFaktur(
        idFaktur: 1,
        idBarang: 3,
        jumlah: 30000,
        quantity: 2,
        barangRemoteId: 'brg-2',
        namaBarang: 'Telur Puyuh',
        satuan: 'Pack',
      );

      final faktur = Faktur(
        idFaktur: 1,
        noFaktur: 'FKT-20261116-001',
        tanggalFaktur: '2026-11-16',
        total: Faktur.hitungTotal([df1, df2]),
        idSupplier: 7,
        idPetugas: 9,
        remoteId: 'fkt-r1',
        supplierRemoteId: 'sup-r1',
        petugasRemoteId: 'pet-r1',
        syncStatus: SyncStatus.pending,
        updatedAt: now,
        details: [df1, df2],
        namaSupplier: 'CV Ternak',
        namaPetugas: 'Budi',
      );
      expect(faktur.total, 170000);
      expect(Faktur.hitungTotal(const []), 0.0);

      final fakturRoundtrip = Faktur.fromMap(
        {
          ...faktur.toMap(),
          'nama_supplier': 'CV Ternak',
          'nama_petugas': 'Budi',
        },
        details: [DetailFaktur.fromMap(df1.toMap())],
      );
      expect(fakturRoundtrip.noFaktur, 'FKT-20261116-001');
      expect(fakturRoundtrip.total, 170000);
      expect(fakturRoundtrip.namaSupplier, 'CV Ternak');
      expect(fakturRoundtrip.details.first.quantity, 5);

      final fsFaktur = faktur.toFirestore();
      expect(fsFaktur['no_faktur'], 'FKT-20261116-001');
      expect(fsFaktur['total'], 170000);
      expect((fsFaktur['details'] as List).length, 2);

      final dn = DetailNota(
        idNota: 4,
        idBarang: 2,
        jumlah: 84000,
        banyaknya: 3,
        barangRemoteId: 'brg-1',
        namaBarang: 'Telur Ayam Negeri',
        satuan: 'Kg',
      );
      final nota = Nota(
        idNota: 4,
        tanggalNota: '2026-11-16',
        total: Nota.hitungTotal([dn]),
        idPetugas: 9,
        idCustomer: 11,
        remoteId: 'nota-r1',
        petugasRemoteId: 'pet-r1',
        customerRemoteId: 'cust-r1',
        syncStatus: SyncStatus.synced,
        updatedAt: now,
        details: [dn],
        namaCustomer: 'Toko Berkah',
        namaPetugas: 'Budi',
      );
      expect(nota.total, 84000);
      expect(Nota.hitungTotal(const []), 0.0);
      final notaRoundtrip = Nota.fromMap(
        {
          ...nota.toMap(),
          'nama_customer': 'Toko Berkah',
        },
        details: [DetailNota.fromMap(dn.toMap())],
      );
      expect(notaRoundtrip.syncStatus, SyncStatus.synced);
      expect(notaRoundtrip.namaCustomer, 'Toko Berkah');
      expect(notaRoundtrip.details.single.banyaknya, 3);
      expect(nota.toFirestore()['customer_remote_id'], 'cust-r1');
    });

    test('fromMap aman menghadapi map kosong atau field bertipe tidak lengkap (edge case)', () {
      final fEmpty = Faktur.fromMap({});
      expect(fEmpty.idFaktur, isNull);
      expect(fEmpty.noFaktur, '');
      expect(fEmpty.total, 0.0);
      expect(fEmpty.syncStatus, SyncStatus.pending);

      final nCoerced = Nota.fromMap({
        'id_nota': 5.0,
        'total': 56000,
        'id_petugas': 1,
        'id_customer': 2,
        'updated_at': 'invalid-iso-string',
      });
      expect(nCoerced.idNota, 5);
      expect(nCoerced.total, 56000.0);
      expect(nCoerced.remoteId, '');

      final dF = DetailFaktur.fromMap({});
      final dN = DetailNota.fromMap({});
      expect(dF.quantity, 0);
      expect(dN.banyaknya, 0);
    });
  });

  group('DatabaseHelper Transaksi SQLite Atomik (Normal, Edge Case & Salah Input)', () {
    test('CRUD Faktur lengkap: insert tambah stok, update rekonsiliasi selisih + ganti barang, delete kembalikan stok & cascade', () async {
      final ctx = await _openIsolatedRepo();
      final db = ctx.dbHelper;
      final seed = await _seedStandardCatalog(ctx.repo);

      final idFaktur = await db.insertFakturTransaction(
        Faktur(
          noFaktur: 'FKT-DB-001',
          tanggalFaktur: '2026-11-16',
          total: 280000,
          idSupplier: seed.supplierA.idSupplier!,
          idPetugas: seed.kasir.idPetugas!,
          remoteId: 'fkt-db-1',
          supplierRemoteId: seed.supplierA.remoteId,
          petugasRemoteId: seed.kasir.remoteId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime(2026, 11, 16, 8),
        ),
        [
          DetailFaktur(
            idBarang: seed.telur.idBarang!,
            jumlah: 280000,
            quantity: 10,
            barangRemoteId: seed.telur.remoteId,
          ),
        ],
      );

      final telurAfterInsert = await db.getBarangByRemoteId('brg-telur');
      expect(telurAfterInsert!.stokBarang, 60);

      final loaded = await db.getFakturById(idFaktur);
      expect(loaded, isNotNull);
      expect(loaded!.namaSupplier, 'CV Ternak Jaya');
      expect(loaded.namaPetugas, 'Budi Kasir');
      expect(loaded.details.single.namaBarang, 'Telur Ayam Negeri');

      // Update faktur: kurangi Telur 10 -> 4 (-6), tambah Puyuh 0 -> 5 (+5)
      await db.updateFakturTransaction(
        loaded.copyWith(
          total: 187000,
          idSupplier: seed.supplierB.idSupplier!,
          supplierRemoteId: seed.supplierB.remoteId,
          updatedAt: DateTime(2026, 11, 16, 9),
        ),
        [
          DetailFaktur(
            idBarang: seed.telur.idBarang!,
            jumlah: 112000,
            quantity: 4,
            barangRemoteId: seed.telur.remoteId,
          ),
          DetailFaktur(
            idBarang: seed.puyuh.idBarang!,
            jumlah: 75000,
            quantity: 5,
            barangRemoteId: seed.puyuh.remoteId,
          ),
        ],
      );

      final telurAfterEdit = await db.getBarangByRemoteId('brg-telur');
      final puyuhAfterEdit = await db.getBarangByRemoteId('brg-puyuh');
      expect(telurAfterEdit!.stokBarang, 54);
      expect(puyuhAfterEdit!.stokBarang, 25);
      expect(telurAfterEdit.syncStatus, SyncStatus.pending);
      expect(puyuhAfterEdit.syncStatus, SyncStatus.pending);

      final editedFaktur = await db.getFakturById(idFaktur);
      expect(editedFaktur!.details.length, 2);
      expect(editedFaktur.namaSupplier, 'UD Sumber Rezeki');
      expect(editedFaktur.syncStatus, SyncStatus.pending);

      // Delete faktur -> kembalikan stok & catat tombstone pending_deletes
      await db.deleteFakturTransaction(idFaktur);
      expect(await db.getFakturById(idFaktur), isNull);
      expect((await db.getBarangByRemoteId('brg-telur'))!.stokBarang, 50);
      expect((await db.getBarangByRemoteId('brg-puyuh'))!.stokBarang, 20);
      expect(await db.hasPendingDelete('faktur', 'fkt-db-1'), isTrue);

      final sqlite = await db.database;
      final orphanDetails = await sqlite.query(
        'detail_faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
      expect(orphanDetails, isEmpty);
    });

    test('CRUD Nota lengkap: insert potong stok, update kembalikan lama & potong baru, delete pulihkan stok', () async {
      final ctx = await _openIsolatedRepo();
      final db = ctx.dbHelper;
      final seed = await _seedStandardCatalog(ctx.repo);

      final idNota = await db.insertNotaTransaction(
        Nota(
          tanggalNota: '2026-11-16',
          total: 280000,
          idPetugas: seed.kasir.idPetugas!,
          idCustomer: seed.customerA.idCustomer!,
          remoteId: 'nota-db-1',
          petugasRemoteId: seed.kasir.remoteId,
          customerRemoteId: seed.customerA.remoteId,
          syncStatus: SyncStatus.pending,
          updatedAt: DateTime(2026, 11, 16, 10),
        ),
        [
          DetailNota(
            idBarang: seed.telur.idBarang!,
            jumlah: 280000,
            banyaknya: 10,
            barangRemoteId: seed.telur.remoteId,
          ),
        ],
      );
      expect((await db.getBarangByRemoteId('brg-telur'))!.stokBarang, 40);

      final loaded = await db.getNotaById(idNota);
      expect(loaded!.namaCustomer, 'Toko Sembako Berkah');

      // Update Nota: ganti item dari Telur (10) ke Puyuh (8) -> Telur balik 50, Puyuh 20 -> 12
      await db.updateNotaTransaction(
        loaded.copyWith(
          total: 120000,
          idCustomer: seed.customerB.idCustomer!,
          customerRemoteId: seed.customerB.remoteId,
          updatedAt: DateTime(2026, 11, 16, 11),
        ),
        [
          DetailNota(
            idBarang: seed.puyuh.idBarang!,
            jumlah: 120000,
            banyaknya: 8,
            barangRemoteId: seed.puyuh.remoteId,
          ),
        ],
      );

      expect((await db.getBarangByRemoteId('brg-telur'))!.stokBarang, 50);
      expect((await db.getBarangByRemoteId('brg-puyuh'))!.stokBarang, 12);

      // Delete Nota -> Puyuh kembali 20
      await db.deleteNotaTransaction(idNota);
      expect(await db.getNotaById(idNota), isNull);
      expect((await db.getBarangByRemoteId('brg-puyuh'))!.stokBarang, 20);
      expect(await db.hasPendingDelete('nota', 'nota-db-1'), isTrue);
    });

    test('Delete Faktur ditolak & rollback bila sebagian stok sudah terjual sehingga stok akan minus', () async {
      final ctx = await _openIsolatedRepo();
      final db = ctx.dbHelper;
      final seed = await _seedStandardCatalog(ctx.repo);

      // Stok Puyuh awal = 20. Masuk faktur +30 -> 50. Terjual nota -35 -> sisa 15.
      final idFaktur = await db.insertFakturTransaction(
        Faktur(
          noFaktur: 'FKT-LOCK-01',
          tanggalFaktur: '2026-11-16',
          total: 450000,
          idSupplier: seed.supplierA.idSupplier!,
          idPetugas: seed.kasir.idPetugas!,
          remoteId: 'fkt-lock-1',
          updatedAt: DateTime(2026, 11, 16, 8),
        ),
        [
          DetailFaktur(
            idBarang: seed.puyuh.idBarang!,
            jumlah: 450000,
            quantity: 30,
          ),
        ],
      );
      await db.insertNotaTransaction(
        Nota(
          tanggalNota: '2026-11-16',
          total: 525000,
          idPetugas: seed.kasir.idPetugas!,
          idCustomer: seed.customerA.idCustomer!,
          remoteId: 'nota-lock-1',
          updatedAt: DateTime(2026, 11, 16, 9),
        ),
        [
          DetailNota(
            idBarang: seed.puyuh.idBarang!,
            jumlah: 525000,
            banyaknya: 35,
          ),
        ],
      );
      expect((await db.getBarangByRemoteId('brg-puyuh'))!.stokBarang, 15);

      await expectLater(
        () => db.deleteFakturTransaction(idFaktur),
        throwsA(isA<StateError>()),
      );

      // Rollback sempurna: faktur tetap ada, tidak masuk pending_deletes, stok tetap 15
      expect(await db.getFakturById(idFaktur), isNotNull);
      expect(await db.hasPendingDelete('faktur', 'fkt-lock-1'), isFalse);
      expect((await db.getBarangByRemoteId('brg-puyuh'))!.stokBarang, 15);
    });

    test('insertCloudFakturIfMissing & insertCloudNotaIfMissing: tahan duplikat tanpa updated_at, tahan timestamp usang, tahan payload korup, dan hormati pending_deletes/PENDING', () async {
      final ctx = await _openIsolatedRepo();
      final db = ctx.dbHelper;
      await _seedStandardCatalog(ctx.repo);

      // 1. Tanpa updated_at -> insert 1x lalu skip pada replay berikutnya (anti-loop DateTime.now)
      final noTsPayload = <String, dynamic>{
        'no_faktur': 'FKT-CLOUD-001',
        'tanggal_faktur': '2026-11-16',
        'total': 56000,
        'supplier_remote_id': 'sup-a',
        'petugas_remote_id': 'pet-kasir',
        'details': [
          {
            'barang_remote_id': 'brg-telur',
            'quantity': 2,
            'jumlah': 56000,
          },
        ],
      };
      expect(
        await db.insertCloudFakturIfMissing(
          remoteId: 'cloud-fkt-1',
          data: noTsPayload,
        ),
        isTrue,
      );
      expect(
        await db.insertCloudFakturIfMissing(
          remoteId: 'cloud-fkt-1',
          data: noTsPayload,
        ),
        isFalse,
      );
      // Stok lokal TIDAK ikut diubah oleh sinkronisasi header/detail transaksi
      expect((await db.getBarangByRemoteId('brg-telur'))!.stokBarang, 50);

      // 2. Timestamp lebih baru masuk -> update berhasil
      expect(
        await db.insertCloudFakturIfMissing(
          remoteId: 'cloud-fkt-1',
          data: {
            ...noTsPayload,
            'total': 84000,
            'updated_at': '2026-11-16T12:00:00.000Z',
            'details': [
              {
                'barang_remote_id': 'brg-telur',
                'quantity': 3,
                'jumlah': 84000,
              },
            ],
          },
        ),
        isTrue,
      );

      // 3. Replay snapshot usang (lebih lama dari 12:00:00Z) harus DITOLAK!
      expect(
        await db.insertCloudFakturIfMissing(
          remoteId: 'cloud-fkt-1',
          data: {
            ...noTsPayload,
            'total': 28000,
            'updated_at': '2026-11-16T11:00:00.000Z',
            'details': [
              {
                'barang_remote_id': 'brg-telur',
                'quantity': 1,
                'jumlah': 28000,
              },
            ],
          },
        ),
        isFalse,
      );
      final currentFaktur = (await db.getAllFaktur())
          .firstWhere((e) => e.remoteId == 'cloud-fkt-1');
      expect(currentFaktur.total, 84000);

      // 4. Payload cloud korup (qty <= 0, duplikat barang, total negatif/NaN, item bukan Map) ditolak aman
      final corruptPayloads = <Map<String, dynamic>>[
        {
          'tanggal_nota': '2026-11-16',
          'total': 28000,
          'petugas_remote_id': 'pet-kasir',
          'customer_remote_id': 'cust-a',
          'details': const [],
        },
        {
          'tanggal_nota': '2026-11-16',
          'total': 28000,
          'petugas_remote_id': 'pet-kasir',
          'customer_remote_id': 'cust-a',
          'details': ['not-a-map'],
        },
        {
          'tanggal_nota': '2026-11-16',
          'total': 28000,
          'petugas_remote_id': 'pet-kasir',
          'customer_remote_id': 'cust-a',
          'details': [
            {'barang_remote_id': 'brg-telur', 'banyaknya': 0, 'jumlah': 0},
          ],
        },
        {
          'tanggal_nota': '2026-11-16',
          'total': 56000,
          'petugas_remote_id': 'pet-kasir',
          'customer_remote_id': 'cust-a',
          'details': [
            {'barang_remote_id': 'brg-telur', 'banyaknya': 1, 'jumlah': 28000},
            {'barang_remote_id': 'brg-telur', 'banyaknya': 1, 'jumlah': 28000},
          ],
        },
        {
          'tanggal_nota': '2026-11-16',
          'total': -100,
          'petugas_remote_id': 'pet-kasir',
          'customer_remote_id': 'cust-a',
          'details': [
            {'barang_remote_id': 'brg-telur', 'banyaknya': 1, 'jumlah': 28000},
          ],
        },
      ];
      for (var i = 0; i < corruptPayloads.length; i++) {
        expect(
          await db.insertCloudNotaIfMissing(
            remoteId: 'bad-nota-$i',
            data: corruptPayloads[i],
          ),
          isFalse,
        );
      }

      // 5. Pending lokal & tombstone mengalahkan snapshot cloud
      expect(
        await db.insertCloudNotaIfMissing(
          remoteId: 'cloud-nota-1',
          data: {
            'tanggal_nota': '2026-11-16',
            'total': 28000,
            'petugas_remote_id': 'pet-kasir',
            'customer_remote_id': 'cust-a',
            'updated_at': '2026-11-16T09:00:00.000Z',
            'details': [
              {'barang_remote_id': 'brg-telur', 'banyaknya': 1, 'jumlah': 28000},
            ],
          },
        ),
        isTrue,
      );
      final syncedNota = (await db.getAllNota())
          .firstWhere((e) => e.remoteId == 'cloud-nota-1');
      await db.deleteNotaTransaction(syncedNota.idNota!);
      expect(
        await db.insertCloudNotaIfMissing(
          remoteId: 'cloud-nota-1',
          data: {
            'tanggal_nota': '2026-11-16',
            'total': 28000,
            'petugas_remote_id': 'pet-kasir',
            'customer_remote_id': 'cust-a',
            'updated_at': '2026-11-16T15:00:00.000Z',
            'details': [
              {'barang_remote_id': 'brg-telur', 'banyaknya': 1, 'jumlah': 28000},
            ],
          },
        ),
        isFalse,
      );
    });

    test('Validasi input buruk DatabaseHelper: kosong, duplikat, qty <= 0 / overflow, total/jumlah negatif atau NaN, FK invalid', () async {
      final ctx = await _openIsolatedRepo();
      final db = ctx.dbHelper;
      final seed = await _seedStandardCatalog(ctx.repo);

      await expectLater(
        () => db.insertFakturTransaction(
          Faktur(
            noFaktur: 'FKT-ERR-1',
            tanggalFaktur: '2026-11-16',
            total: 0,
            idSupplier: seed.supplierA.idSupplier!,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'err-1',
            updatedAt: DateTime.now(),
          ),
          const [],
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.insertFakturTransaction(
          Faktur(
            noFaktur: 'FKT-ERR-2',
            tanggalFaktur: '2026-11-16',
            total: 56000,
            idSupplier: seed.supplierA.idSupplier!,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'err-2',
            updatedAt: DateTime.now(),
          ),
          [
            DetailFaktur(idBarang: seed.telur.idBarang!, jumlah: 28000, quantity: 1),
            DetailFaktur(idBarang: seed.telur.idBarang!, jumlah: 28000, quantity: 1),
          ],
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.insertNotaTransaction(
          Nota(
            tanggalNota: '2026-11-16',
            total: -5000,
            idPetugas: seed.kasir.idPetugas!,
            idCustomer: seed.customerA.idCustomer!,
            remoteId: 'err-neg',
            updatedAt: DateTime.now(),
          ),
          [
            DetailNota(idBarang: seed.telur.idBarang!, jumlah: 28000, banyaknya: 1),
          ],
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.insertNotaTransaction(
          Nota(
            tanggalNota: '2026-11-16',
            total: double.nan,
            idPetugas: seed.kasir.idPetugas!,
            idCustomer: seed.customerA.idCustomer!,
            remoteId: 'err-nan',
            updatedAt: DateTime.now(),
          ),
          [
            DetailNota(idBarang: seed.telur.idBarang!, jumlah: 28000, banyaknya: 1),
          ],
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.insertFakturTransaction(
          Faktur(
            noFaktur: 'FKT-ERR-OVERFLOW',
            tanggalFaktur: '2026-11-16',
            total: 280000,
            idSupplier: seed.supplierA.idSupplier!,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'err-overflow',
            updatedAt: DateTime.now(),
          ),
          [
            DetailFaktur(
              idBarang: seed.telur.idBarang!,
              jumlah: 280000,
              quantity: 9999990,
            ),
          ],
        ),
        throwsStateError,
      );

      await expectLater(
        () => db.insertFakturTransaction(
          Faktur(
            noFaktur: 'FKT-ERR-FK',
            tanggalFaktur: '2026-11-16',
            total: 28000,
            idSupplier: 99999,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'err-fk',
            updatedAt: DateTime.now(),
          ),
          [
            DetailFaktur(idBarang: seed.telur.idBarang!, jumlah: 28000, quantity: 1),
          ],
        ),
        throwsStateError,
      );

      await expectLater(
        () => db.insertNotaTransaction(
          Nota(
            tanggalNota: '2026-11-16',
            total: 2800000,
            idPetugas: seed.kasir.idPetugas!,
            idCustomer: seed.customerA.idCustomer!,
            remoteId: 'err-stok',
            updatedAt: DateTime.now(),
          ),
          [
            DetailNota(
              idBarang: seed.telur.idBarang!,
              jumlah: 2800000,
              banyaknya: 100,
            ),
          ],
        ),
        throwsStateError,
      );
      expect((await db.getBarangByRemoteId('brg-telur'))!.stokBarang, 50);

      await expectLater(
        () => db.updateFakturTransaction(
          Faktur(
            idFaktur: null,
            noFaktur: 'X',
            tanggalFaktur: '2026-11-16',
            total: 10,
            idSupplier: seed.supplierA.idSupplier!,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'x',
            updatedAt: DateTime.now(),
          ),
          [
            DetailFaktur(idBarang: seed.telur.idBarang!, jumlah: 10, quantity: 1),
          ],
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.deleteNotaTransaction(987654),
        throwsStateError,
      );
    });
  });

  group('InventoryRepository & SyncService Integrasi Transaksi', () {
    test('generateNextNoFaktur otomatis menghitung urutan & tahan huruf kecil', () async {
      final ctx = await _openIsolatedRepo();
      final seed = await _seedStandardCatalog(ctx.repo);
      final targetDate = DateTime(2026, 11, 16);

      expect(
        await ctx.repo.generateNextNoFaktur(date: targetDate),
        'FKT-20261116-001',
      );

      await ctx.repo.createFaktur(
        noFaktur: 'fkt-20261116-002',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierA,
        petugas: seed.kasir,
        items: [(barang: seed.telur, quantity: 2)],
      );

      expect(
        await ctx.repo.generateNextNoFaktur(date: targetDate),
        'FKT-20261116-003',
      );
      expect(
        await ctx.repo.generateNextNoFaktur(date: DateTime(2026, 11, 17)),
        'FKT-20261117-001',
      );
    });

    test('Alur offline create -> edit -> delete Faktur & Nota sinkron akurat dengan stok Firestore via syncNow', () async {
      final store = _RecordingFirestoreStore();
      addTearDown(store.dispose);
      final firestore = _RecordingFirestore(store);
      final connectivity = _ToggleConnectivity(online: false);
      addTearDown(connectivity.dispose);

      final ctx = await _openIsolatedRepo(
        syncFactory: (db) => SyncService(
          dbHelper: db,
          firestore: firestore,
          connectivity: connectivity,
        ),
      );
      final seed = await _seedStandardCatalog(ctx.repo);

      // Offline buat Faktur (+10 Telur: 50 -> 60) dan Nota (-4 Telur: 60 -> 56)
      final idFaktur = await ctx.repo.createFaktur(
        noFaktur: 'FKT-SYNC-001',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierA,
        petugas: seed.kasir,
        items: [(barang: seed.telur, quantity: 10)],
      );
      final latestTelur = (await ctx.repo.getAllBarang())
          .firstWhere((b) => b.remoteId == 'brg-telur');
      final idNota = await ctx.repo.createNota(
        tanggalNota: '2026-11-16',
        customer: seed.customerA,
        petugas: seed.kasir,
        items: [(barang: latestTelur, banyaknya: 4)],
      );

      expect((await ctx.repo.getAllBarang()).firstWhere((b) => b.idBarang == seed.telur.idBarang).stokBarang, 56);
      expect(await ctx.dbHelper.getPendingSyncCount(), greaterThanOrEqualTo(2));

      // Kembali online & syncNow: _barangWithBaseStock push base=50, lalu +10 faktur, -4 nota -> Firestore = 56!
      connectivity.online = true;
      await ctx.repo.syncService.syncNow();

      expect(store.docs['barang/brg-telur']?['stok_barang'], 56);
      final syncedFaktur = await ctx.repo.getFakturById(idFaktur);
      final syncedNota = await ctx.repo.getNotaById(idNota);
      expect(syncedFaktur!.syncStatus, SyncStatus.synced);
      expect(syncedNota!.syncStatus, SyncStatus.synced);
      expect(store.docs['faktur/${syncedFaktur.remoteId}']?['no_faktur'], 'FKT-SYNC-001');
      expect(store.docs['nota/${syncedNota.remoteId}']?['total'], 112000);

      // Offline edit Nota: 4 -> 7 (-3 lagi, stok lokal 56 -> 53) & syncNow
      connectivity.online = false;
      await ctx.repo.updateNota(
        existing: syncedNota,
        tanggalNota: '2026-11-16',
        customer: seed.customerB,
        petugas: seed.kasir,
        items: [(barang: latestTelur, banyaknya: 7)],
      );
      connectivity.online = true;
      await ctx.repo.syncService.syncNow();
      expect(store.docs['barang/brg-telur']?['stok_barang'], 53);

      // Offline delete Faktur (-10, stok lokal 53 -> 43) & syncNow
      connectivity.online = false;
      await ctx.repo.deleteFaktur(idFaktur);
      connectivity.online = true;
      await ctx.repo.syncService.syncNow();

      expect(store.deletedDocPaths, contains('faktur/${syncedFaktur.remoteId}'));
      expect(store.docs['barang/brg-telur']?['stok_barang'], 43);
    });

    test('Realtime cloud listener menangguhkan faktur/nota sampai master lengkap & membuang antrean jika doc dihapus di cloud', () async {
      final store = _RecordingFirestoreStore();
      addTearDown(store.dispose);
      final firestore = _RecordingFirestore(store);
      final connectivity = _ToggleConnectivity(online: true);
      addTearDown(connectivity.dispose);

      final ctx = await _openIsolatedRepo(
        syncFactory: (db) => SyncService(
          dbHelper: db,
          firestore: firestore,
          connectivity: connectivity,
        ),
      );
      await _seedStandardCatalog(ctx.repo);

      // Seed initial snapshot supaya sync service mendengarkan
      store.emitSnapshot(SyncService.colFaktur, {
        'cloud-wait-1': {
          'no_faktur': 'FKT-DEFER-01',
          'tanggal_faktur': '2026-11-16',
          'total': 90000,
          'supplier_remote_id': 'sup-late',
          'petugas_remote_id': 'pet-kasir',
          'updated_at': '2026-11-16T10:00:00.000Z',
          'details': [
            {'barang_remote_id': 'brg-telur', 'quantity': 3, 'jumlah': 84000},
          ],
        },
        'cloud-cancelled': {
          'no_faktur': 'FKT-DEFER-CANCEL',
          'tanggal_faktur': '2026-11-16',
          'total': 28000,
          'supplier_remote_id': 'sup-ghost',
          'petugas_remote_id': 'pet-kasir',
          'updated_at': '2026-11-16T10:00:00.000Z',
          'details': [
            {'barang_remote_id': 'brg-telur', 'quantity': 1, 'jumlah': 28000},
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await ctx.repo.getAllFaktur(), isEmpty);

      // Snapshot faktur berikutnya tidak lagi memuat 'cloud-cancelled' -> harus dipangkas dari deferred
      store.emitSnapshot(SyncService.colFaktur, {
        'cloud-wait-1': {
          'no_faktur': 'FKT-DEFER-01',
          'tanggal_faktur': '2026-11-16',
          'total': 90000,
          'supplier_remote_id': 'sup-late',
          'petugas_remote_id': 'pet-kasir',
          'updated_at': '2026-11-16T10:00:00.000Z',
          'details': [
            {'barang_remote_id': 'brg-telur', 'quantity': 3, 'jumlah': 84000},
          ],
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Sekarang supplier 'sup-late' & 'sup-ghost' datang -> hanya 'cloud-wait-1' yang muncul
      store.emitSnapshot(SyncService.colSupplier, {
        'sup-late': {
          'nama_supplier': 'CV Telat Hadir',
          'alamat_supplier': 'Jl. Lambat No. 1',
          'no_telp_supplier': '081200001111',
          'updated_at': '2026-11-16T10:05:00.000Z',
        },
        'sup-ghost': {
          'nama_supplier': 'CV Batal',
          'alamat_supplier': 'Jl. Hantu No. 2',
          'no_telp_supplier': '081200002222',
          'updated_at': '2026-11-16T10:05:00.000Z',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final allFakturs = await ctx.repo.getAllFaktur();
      expect(allFakturs.length, 1);
      expect(allFakturs.single.remoteId, 'cloud-wait-1');
    });

    test('Validasi bisnis Faktur & Nota: duplikat no_faktur, tanggal tidak valid, qty/stok/master invalid', () async {
      final ctx = await _openIsolatedRepo();
      final seed = await _seedStandardCatalog(ctx.repo);

      // Tahun kabisat 2024-02-29 valid!
      final idF1 = await ctx.repo.createFaktur(
        noFaktur: 'FKT-UNIK-01',
        tanggalFaktur: '2024-02-29',
        supplier: seed.supplierA,
        petugas: seed.kasir,
        items: [(barang: seed.telur, quantity: 2)],
      );
      final f1 = (await ctx.repo.getFakturById(idF1))!;

      // Duplikat noFaktur case-insensitive + spasi ditolak
      await expectLater(
        () => ctx.repo.createFaktur(
          noFaktur: '  fkt-unik-01 ',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [(barang: seed.telur, quantity: 1)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Update faktur yang sama dengan nomor fakturnya sendiri DIPERBOLEHKAN, tapi nomor faktur lain yang sudah ada DITOLAK
      await ctx.repo.createFaktur(
        noFaktur: 'FKT-UNIK-02',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierA,
        petugas: seed.kasir,
        items: [(barang: seed.telur, quantity: 1)],
      );
      await ctx.repo.updateFaktur(
        existing: f1,
        noFaktur: 'FKT-UNIK-01',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierA,
        petugas: seed.kasir,
        items: [(barang: seed.telur, quantity: 3)],
      );
      await expectLater(
        () => ctx.repo.updateFaktur(
          existing: f1,
          noFaktur: 'fkt-unik-02',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [(barang: seed.telur, quantity: 3)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Tanggal invalid (non-kabisat, tahun 1999, tahun 2101, format salah)
      for (final badDate in [
        '2025-02-29',
        '2026-02-30',
        '1999-12-31',
        '2101-01-01',
        '16-11-2026',
        '2026-11-16\u200B',
      ]) {
        await expectLater(
          () => ctx.repo.createNota(
            tanggalNota: badDate,
            customer: seed.customerA,
            petugas: seed.kasir,
            items: [(barang: seed.telur, banyaknya: 1)],
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
      }

      // Nomor faktur terlalu pendek / kontrol char
      for (final badNo in ['AB', 'A' * 51, 'FKT\n001']) {
        await expectLater(
          () => ctx.repo.createFaktur(
            noFaktur: badNo,
            tanggalFaktur: '2026-11-16',
            supplier: seed.supplierA,
            petugas: seed.kasir,
            items: [(barang: seed.telur, quantity: 1)],
          ),
          throwsA(isA<MasterDataValidationException>()),
        );
      }

      // Snapshot barang kedaluwarsa (objek lama stok 50 padahal di SQLite sudah tinggal 1 setelah dijual) tidak bisa oversell
      final staleTelur = seed.telur.copyWith(stokBarang: 999);
      await expectLater(
        () => ctx.repo.createNota(
          tanggalNota: '2026-11-16',
          customer: seed.customerA,
          petugas: seed.kasir,
          items: [(barang: staleTelur, banyaknya: 100)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );

      // Qty <= 0 / > 9.999.999 / item duplikat / item kosong / master tanpa ID
      await expectLater(
        () => ctx.repo.createFaktur(
          noFaktur: 'FKT-QTY-ZERO',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [(barang: seed.telur, quantity: 0)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.createFaktur(
          noFaktur: 'FKT-QTY-MAX',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [(barang: seed.telur, quantity: 10000000)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.createNota(
          tanggalNota: '2026-11-16',
          customer: seed.customerA,
          petugas: seed.kasir,
          items: const [],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.createNota(
          tanggalNota: '2026-11-16',
          customer: Customer(
            namaCustomer: 'Belum Tersimpan',
            remoteId: 'cust-unsaved',
            updatedAt: _testUpdatedAt,
          ),
          petugas: seed.kasir,
          items: [(barang: seed.telur, banyaknya: 1)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.createNota(
          tanggalNota: '2026-11-16',
          customer: seed.customerA,
          petugas: seed.kasir,
          items: [
            (barang: seed.telur, banyaknya: 1),
            (barang: seed.telur, banyaknya: 2),
          ],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.createFaktur(
          noFaktur: 'FKT-INF-PRICE',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [
            (barang: seed.telur.copyWith(hargaSatuan: double.infinity), quantity: 1),
          ],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.updateFaktur(
          existing: Faktur(
            noFaktur: 'FKT-NO-ID',
            tanggalFaktur: '2026-11-16',
            total: 28000,
            idSupplier: seed.supplierA.idSupplier!,
            idPetugas: seed.kasir.idPetugas!,
            remoteId: 'fkt-no-id',
            updatedAt: _testUpdatedAt,
          ),
          noFaktur: 'FKT-NO-ID',
          tanggalFaktur: '2026-11-16',
          supplier: seed.supplierA,
          petugas: seed.kasir,
          items: [(barang: seed.telur, quantity: 1)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.deleteFaktur(999999),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => ctx.repo.deleteNota(999999),
        throwsA(isA<MasterDataValidationException>()),
      );
    });
  });

  group('TransactionCrudViewModel (Normal, Edge Case & Salah Input)', () {
    test('Alur lengkap Kasir Nota, Faktur Masuk, Filter Riwayat, dan Edit/Delete detail', () async {
      final ctx = await _openIsolatedRepo();
      final seed = await _seedStandardCatalog(ctx.repo);
      final fixedNow = DateTime(2026, 11, 16, 9, 30);

      final vm = TransactionCrudViewModel.fromRepository(
        session: _makeSession(
          role: UserRole.petugas,
          displayName: 'Budi Kasir',
          email: 'budi@depottelur36.com',
          petugasRemoteId: 'pet-kasir',
        ),
        repository: ctx.repo,
        nowProvider: () => fixedNow,
      );
      addTearDown(vm.dispose);

      await vm.loadData();
      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, isNull);
      expect(vm.noFakturInput, 'FKT-20261116-001');
      expect(vm.selectedNotaCustomerId, seed.customerA.idCustomer);
      expect(vm.selectedFakturSupplierId, seed.supplierA.idSupplier);
      expect(vm.activePetugas?.remoteId, 'pet-kasir');

      // Pencarian katalog kasir (nama & satuan)
      vm.setKasirSearchQuery('Pack');
      expect(vm.filteredKasirBarangs.map((b) => b.remoteId), ['brg-puyuh']);
      vm.setKasirSearchQuery('');

      // Tambah item ke keranjang kasir & submit Nota
      expect(vm.incrementKasirQty(seed.telur), isTrue);
      expect(vm.setKasirQty(seed.puyuh, 2), isTrue);
      expect(vm.kasirTotalUnits, 3);
      expect(vm.kasirItemCount, 2);
      expect(vm.kasirGrandTotal, 28000 + 30000);

      final newNotaId = await vm.submitKasirNota();
      expect(newNotaId, isNotNull);
      expect(vm.kasirItemCount, 0);
      expect(vm.successMessage, contains('Nota #$newNotaId'));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Nota tercatat & bisa dicari di Riwayat Nota
      expect(vm.notas.length, 1);
      vm.setNotaHistoryQuery('nota #$newNotaId');
      expect(vm.filteredNotas.length, 1);
      vm.setNotaHistoryQuery('');

      // Tambah item ke Faktur Masuk via restock prefill & manual qty
      vm.prefillFakturRestock('Puyuh', defaultQty: 15);
      expect(vm.fakturQtyFor(seed.puyuh), 15);
      vm.addOrIncrementFakturBarang(seed.telur, delta: 4);
      expect(vm.fakturGrandTotal, (15 * 15000) + (4 * 28000));

      final newFakturId = await vm.submitFakturMasuk();
      expect(newFakturId, isNotNull);
      expect(vm.fakturItemCount, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.noFakturInput, 'FKT-20261116-002');
      vm.setFakturSupplierFilter('sup-a');
      expect(vm.filteredFakturs.length, 1);
      vm.setFakturSupplierFilter('sup-b');
      expect(vm.filteredFakturs, isEmpty);
      vm.setFakturSupplierFilter(null);
      vm.setFakturHistoryQuery('puyuh');
      expect(vm.filteredFakturs.length, 1);

      // Edit & Hapus lewat ViewModel
      final loadedFaktur = await vm.reloadFakturById(newFakturId!);
      final loadedNota = await vm.reloadNotaById(newNotaId!);
      expect(loadedFaktur, isNotNull);
      expect(loadedNota, isNotNull);

      final okUpdateNota = await vm.updateNotaRecord(
        existing: loadedNota!,
        tanggalNota: '2026-11-16',
        customer: seed.customerB,
        petugas: seed.kasir,
        items: [(barang: seed.telur, banyaknya: 2)],
      );
      expect(okUpdateNota, isTrue);

      final okUpdateFaktur = await vm.updateFakturRecord(
        existing: loadedFaktur!,
        noFaktur: 'FKT-20261116-009',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierB,
        petugas: seed.kasir,
        items: [(barang: seed.puyuh, quantity: 10)],
      );
      expect(okUpdateFaktur, isTrue);

      final failUpdateFaktur = await vm.updateFakturRecord(
        existing: loadedFaktur,
        noFaktur: 'AB',
        tanggalFaktur: '2026-11-16',
        supplier: seed.supplierB,
        petugas: seed.kasir,
        items: [(barang: seed.puyuh, quantity: 10)],
      );
      expect(failUpdateFaktur, isFalse);
      expect(vm.errorMessage, isNotNull);

      final okDeleteNota = await vm.deleteNotaRecord(newNotaId);
      expect(okDeleteNota, isTrue);

      final okDeleteFaktur = await vm.deleteFakturRecord(newFakturId);
      expect(okDeleteFaktur, isTrue);
    });

    test('Filter tanggal Nota Hari Ini vs 7 Hari vs Semua menangani batas 6 hari & tanggal invalid', () async {
      final fake = _FakeTransactionCrudDataSource();
      addTearDown(fake.dispose);
      final fixedNow = DateTime(2026, 11, 16, 14);
      fake.notas = [
        Nota(
          idNota: 1,
          tanggalNota: '2026-11-16',
          total: 28000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n1',
          updatedAt: fixedNow,
        ),
        Nota(
          idNota: 2,
          tanggalNota: '2026-11-10',
          total: 28000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n2',
          updatedAt: fixedNow,
        ),
        Nota(
          idNota: 3,
          tanggalNota: '2026-11-09',
          total: 28000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n3',
          updatedAt: fixedNow,
        ),
        Nota(
          idNota: 4,
          tanggalNota: 'corrupt-date',
          total: 28000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n4',
          updatedAt: fixedNow,
        ),
      ];

      final vm = TransactionCrudViewModel(
        session: _makeSession(
          role: UserRole.owner,
          displayName: 'Owner',
          email: 'owner@depottelur36.com',
          petugasRemoteId: 'pet-1',
        ),
        dataSource: fake,
        nowProvider: () => fixedNow,
      );
      addTearDown(vm.dispose);
      await vm.loadData();

      vm.setNotaDateFilter(NotaHistoryDateFilter.semua);
      expect(vm.filteredNotas.length, 4);

      vm.setNotaDateFilter(NotaHistoryDateFilter.hariIni);
      expect(vm.filteredNotas.map((e) => e.idNota), [1]);

      vm.setNotaDateFilter(NotaHistoryDateFilter.tujuhHari);
      expect(vm.filteredNotas.map((e) => e.idNota), [1, 2]);
    });

    test('Bug regression: prefillFakturRestock string kosong/spasi tidak boleh memilih barang acak & antrean restock bekerja', () async {
      final fake = _FakeTransactionCrudDataSource();
      addTearDown(fake.dispose);
      final barang1 = Barang(
        idBarang: 1,
        namaBarang: 'Telur Ayam Negeri',
        stokBarang: 10,
        satuan: 'Kg',
        hargaSatuan: 28000,
        remoteId: 'b1',
        updatedAt: _testUpdatedAt,
      );
      final vm = TransactionCrudViewModel(
        session: _makeSession(
          role: UserRole.petugas,
          displayName: 'Kasir',
          email: 'k@x.com',
          petugasRemoteId: 'p1',
        ),
        dataSource: fake,
      );
      addTearDown(vm.dispose);

      // Sebelum katalog dimuat, restock kosong/spasi harus diabaikan
      vm.prefillFakturRestock('   ');
      fake.barang = [barang1];
      await vm.loadData();
      expect(vm.fakturCartLines, isEmpty);

      // Setelah katalog dimuat, string kosong tetap tidak memilih barang pertama
      vm.prefillFakturRestock('');
      vm.prefillFakturRestock('  \t ');
      expect(vm.fakturCartLines, isEmpty);

      // Reset, lalu uji pending restock valid sebelum loadData -> otomatis terisi saat katalog datang
      final vm2 = TransactionCrudViewModel(
        session: _makeSession(
          role: UserRole.petugas,
          displayName: 'Kasir',
          email: 'k@x.com',
          petugasRemoteId: 'p1',
        ),
        dataSource: fake,
      );
      addTearDown(vm2.dispose);
      vm2.prefillFakturRestock('ayam', defaultQty: 8);
      await vm2.loadData();
      expect(vm2.fakturQtyFor(barang1), 12);
    });

    test('Validasi ViewModel & edge case: batas stok kasir, batas qty faktur 9.999.999, input kosong, concurrent load, re-entrancy, & ReadOnlyBridge', () async {
      final fake = _FakeTransactionCrudDataSource();
      addTearDown(fake.dispose);
      final barangStok2 = Barang(
        idBarang: 1,
        namaBarang: 'Telur Omega',
        stokBarang: 2,
        satuan: 'Pack',
        hargaSatuan: 35000,
        remoteId: 'b-omega',
        updatedAt: _testUpdatedAt,
      );
      final customer = Customer(
        idCustomer: 10,
        namaCustomer: 'Pelanggan 1',
        remoteId: 'c1',
        updatedAt: _testUpdatedAt,
      );
      final supplier = Supplier(
        idSupplier: 20,
        namaSupplier: 'Supplier 1',
        alamatSupplier: 'Jl. 2',
        noTelpSupplier: '08123456780',
        remoteId: 's1',
        updatedAt: _testUpdatedAt,
      );
      final petugas = Petugas(
        idPetugas: 30,
        namaPetugas: 'Kasir 1',
        role: UserRole.petugas,
        pin: '1234',
        email: 'kasir@x.com',
        remoteId: 'p1',
        updatedAt: _testUpdatedAt,
      );
      fake.barang = [barangStok2];
      fake.customers = [customer];
      fake.suppliers = [supplier];
      fake.petugas = [petugas];

      final vm = TransactionCrudViewModel(
        session: _makeSession(
          role: UserRole.petugas,
          displayName: 'Kasir 1',
          email: 'kasir@x.com',
          petugasRemoteId: 'p1',
        ),
        dataSource: fake,
      );
      addTearDown(vm.dispose);
      await vm.loadData();

      // Validasi submit keranjang kosong
      expect(await vm.submitKasirNota(), isNull);
      expect(vm.errorMessage, isNotNull);
      expect(vm.errorShakePulse, 1);

      expect(await vm.submitFakturMasuk(), isNull);
      expect(vm.errorShakePulse, 2);

      // Melebihi stok di keranjang kasir
      expect(vm.setKasirQty(barangStok2, 2), isTrue);
      expect(vm.incrementKasirQty(barangStok2), isFalse);
      expect(vm.errorShakePulse, 3);
      expect(vm.setKasirQty(barangStok2, 99), isFalse);
      expect(vm.errorShakePulse, 4);

      // Batas qty Faktur max 9.999.999
      vm.setFakturQty(barangStok2, 10000000);
      expect(vm.fakturQtyFor(barangStok2), 0);
      expect(vm.errorShakePulse, 5);
      vm.addOrIncrementFakturBarang(barangStok2, delta: -3);
      expect(vm.fakturQtyFor(barangStok2), 0);
      vm.addOrIncrementFakturBarang(barangStok2, delta: 9999999);
      vm.addOrIncrementFakturBarang(barangStok2, delta: 1);
      expect(vm.fakturQtyFor(barangStok2), 9999999);
      expect(vm.errorShakePulse, 6);

      // Clamping stok otomatis saat reload jika stok di SQLite turun ke 1
      fake.barang = [barangStok2.copyWith(stokBarang: 1)];
      await vm.loadData(silent: true);
      expect(vm.kasirQtyFor(barangStok2), 1);

      // Re-entrancy guard saat submitNota sedang berjalan
      final submitGate = Completer<int>();
      fake.onCreateNota = () => submitGate.future;
      final firstSubmit = vm.submitKasirNota();
      final secondSubmit = vm.submitKasirNota();
      expect(await secondSubmit, isNull);
      submitGate.complete(505);
      expect(await firstSubmit, 505);
      expect(fake.createNotaCalls, 1);

      // ReadOnlyTransactionBridgeDataSource menolak operasi tulis dengan aman
      final dashboardVm = DashboardViewModel(
        session: vm.session,
        dataSource: RepositoryDashboardDataSource(
          (await _openIsolatedRepo()).repo,
        ),
      );
      addTearDown(dashboardVm.dispose);
      final bridge = ReadOnlyTransactionBridgeDataSource(dashboardVm);
      await expectLater(
        () => bridge.createFaktur(
          noFaktur: 'FKT-RO',
          tanggalFaktur: '2026-11-16',
          supplier: supplier,
          petugas: petugas,
          items: [(barang: barangStok2, quantity: 1)],
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
      await expectLater(
        () => bridge.deleteNota(1),
        throwsA(isA<MasterDataValidationException>()),
      );
    });

    test('Concurrent loadData epoch guard & dispose aman saat request masih berjalan', () async {
      final fake = _FakeTransactionCrudDataSource();
      addTearDown(fake.dispose);
      final firstGate = Completer<List<Barang>>();
      final secondGate = Completer<List<Barang>>();
      var callIndex = 0;
      fake.onGetAllBarang = () {
        callIndex++;
        return callIndex == 1 ? firstGate.future : secondGate.future;
      };

      final vm = TransactionCrudViewModel(
        session: _makeSession(
          role: UserRole.owner,
          displayName: 'Owner',
          email: 'owner@x.com',
          petugasRemoteId: 'p1',
        ),
        dataSource: fake,
      );

      final f1 = vm.loadData();
      final f2 = vm.loadData();

      secondGate.complete([
        Barang(
          idBarang: 2,
          namaBarang: 'Terbaru',
          stokBarang: 25,
          satuan: 'Kg',
          hargaSatuan: 29000,
          remoteId: 'b-new',
          updatedAt: _testUpdatedAt,
        ),
      ]);
      await f2;

      // Respon lambat dari epoch 1 tidak boleh menimpa epoch 2
      firstGate.complete([
        Barang(
          idBarang: 1,
          namaBarang: 'Kedaluwarsa',
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 1000,
          remoteId: 'b-old',
          updatedAt: _testUpdatedAt,
        ),
      ]);
      await f1;

      expect(vm.barangs.map((b) => b.namaBarang), ['Terbaru']);

      // Dispose aman tanpa crash notifyListeners
      vm.dispose();
      fake.emitChanged();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
