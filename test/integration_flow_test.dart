// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: depend_on_referenced_packages
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/home/role_home_shell_screen.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/viewmodels/rekap_omzet_view_model.dart';
import 'package:depot_telur_36/viewmodels/restock_monitor_view_model.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ==================== FAKE INFRASTRUCTURE LINTAS MODUL ====================

class _TestAuthGateway implements AuthGateway {
  final Map<String, ({String uid, String email, String password, String name})>
      accountsByEmail = {};
  final Map<String, Petugas> cloudPetugasByEmail = {};
  AuthAccountSnapshot? _currentUser;
  int _seq = 1;

  @override
  AuthAccountSnapshot? get currentUser => _currentUser;

  @override
  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    if (accountsByEmail.containsKey(key)) {
      throw const AuthGatewayException(
        AuthFailureCode.emailAlreadyInUse,
        'Email sudah terdaftar.',
      );
    }
    final uid = 'cloud-uid-${_seq++}';
    accountsByEmail[key] = (
      uid: uid,
      email: key,
      password: password,
      name: fullName,
    );
    _currentUser = AuthAccountSnapshot(
      uid: uid,
      email: key,
      displayName: fullName,
      provider: AuthProviderType.emailPassword,
    );
    return _currentUser!;
  }

  @override
  Future<AuthAccountSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final key = email.trim().toLowerCase();
    final found = accountsByEmail[key];
    if (found == null) {
      throw const AuthGatewayException(
        AuthFailureCode.userNotFound,
        'Akun tidak ditemukan.',
      );
    }
    if (found.password != password) {
      throw const AuthGatewayException(
        AuthFailureCode.invalidCredentials,
        'Password salah.',
      );
    }
    _currentUser = AuthAccountSnapshot(
      uid: found.uid,
      email: found.email,
      displayName: found.name,
      provider: AuthProviderType.emailPassword,
    );
    return _currentUser!;
  }

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() async {
    throw const AuthGatewayException(
      AuthFailureCode.cancelled,
      'Login Google dibatalkan.',
    );
  }

  @override
  Future<Petugas?> findPetugasByEmail(String email) async =>
      cloudPetugasByEmail[email.trim().toLowerCase()];

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    final q = identifier.trim().toLowerCase();
    for (final p in cloudPetugasByEmail.values) {
      if (p.email.toLowerCase() == q ||
          p.accountId.toLowerCase() == q ||
          p.remoteId.toLowerCase() == q) {
        return p;
      }
    }
    return null;
  }

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {
    if (petugas.email.isNotEmpty) {
      cloudPetugasByEmail[petugas.email.trim().toLowerCase()] = petugas;
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }
}

class _ControllableConnectivity implements Connectivity {
  _ControllableConnectivity({bool initialOnline = false})
      : _current = initialOnline
            ? const [ConnectivityResult.wifi]
            : const [ConnectivityResult.none];

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> _current;

  void setOnline(bool online) {
    _current = online
        ? const [ConnectivityResult.wifi]
        : const [ConnectivityResult.none];
    if (!_controller.isClosed) {
      _controller.add(_current);
    }
  }

  Future<void> dispose() => _controller.close();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _current;
}

class _InMemoryFirestore implements FirebaseFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};
  final Map<String, StreamController<QuerySnapshot<Map<String, dynamic>>>>
      _controllers = {};

  Map<String, Map<String, dynamic>> docsOf(String collection) =>
      store.putIfAbsent(collection, () => {});

  void putCloudDoc(
    String collection,
    String id,
    Map<String, dynamic> data, {
    bool emitSnapshot = true,
  }) {
    docsOf(collection)[id] = Map<String, dynamic>.from(data);
    if (emitSnapshot) {
      _emit(collection);
    }
  }

  void _applyWrite(
    String collection,
    String id,
    Map<String, dynamic> data, {
    bool merge = false,
  }) {
    final target = docsOf(collection);
    final base = merge && target.containsKey(id)
        ? Map<String, dynamic>.from(target[id]!)
        : <String, dynamic>{};
    data.forEach((key, value) {
      if (value is FieldValue) {
        final delegate = FieldValuePlatform.getDelegate(value);
        final delta = (delegate as dynamic).value;
        if (delta is num) {
          final prev = (base[key] as num?) ?? 0;
          base[key] = prev + delta;
        }
      } else {
        base[key] = value;
      }
    });
    target[id] = base;
  }

  void _deleteDoc(String collection, String id) {
    docsOf(collection).remove(id);
  }

  void _emit(String collection) {
    final controller = _controllers[collection];
    if (controller != null && !controller.isClosed) {
      controller.add(_FakeQuerySnapshot(docsOf(collection)));
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamFor(String collection) {
    final controller = _controllers.putIfAbsent(
      collection,
      () => StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(),
    );
    Future<void>.microtask(() {
      if (!controller.isClosed) {
        controller.add(_FakeQuerySnapshot(docsOf(collection)));
      }
    });
    return controller.stream;
  }

  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) =>
      _FakeCollectionReference(this, collectionPath);

  @override
  WriteBatch batch() => _FakeWriteBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeCollectionReference
    implements CollectionReference<Map<String, dynamic>> {
  _FakeCollectionReference(this._db, this._name);

  final _InMemoryFirestore _db;
  final String _name;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDocumentReference(_db, _name, path ?? 'auto');

  @override
  Query<Map<String, dynamic>> limit(int limit) =>
      _FakeQuery(_db, _name, limitCount: limit);

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      _db._streamFor(_name);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeQuery implements Query<Map<String, dynamic>> {
  _FakeQuery(this._db, this._name, {this.limitCount});

  final _InMemoryFirestore _db;
  final String _name;
  final int? limitCount;

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final map = _db.docsOf(_name);
    if (limitCount == null || map.length <= limitCount!) {
      return _FakeQuerySnapshot(map);
    }
    final limited = Map<String, Map<String, dynamic>>.fromEntries(
      map.entries.take(limitCount!),
    );
    return _FakeQuerySnapshot(limited);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  _FakeDocumentReference(this._db, this._collection, this.id);

  final _InMemoryFirestore _db;
  final String _collection;
  @override
  final String id;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _db._applyWrite(_collection, id, data, merge: options?.merge ?? false);
    _db._emit(_collection);
  }

  @override
  Future<void> delete() async {
    _db._deleteDoc(_collection, id);
    _db._emit(_collection);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeWriteBatch implements WriteBatch {
  _FakeWriteBatch(this._db);

  final _InMemoryFirestore _db;
  final List<void Function()> _ops = [];
  final Set<String> _touchedCollections = {};

  @override
  void set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {
    final doc = document as _FakeDocumentReference;
    final map = Map<String, dynamic>.from(data as Map);
    _touchedCollections.add(doc._collection);
    _ops.add(
      () => _db._applyWrite(
        doc._collection,
        doc.id,
        map,
        merge: options?.merge ?? false,
      ),
    );
  }

  @override
  Future<void> commit() async {
    for (final op in _ops) {
      op();
    }
    for (final c in _touchedCollections) {
      _db._emit(c);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _FakeQuerySnapshot(Map<String, Map<String, dynamic>> raw)
      : _docs = raw.entries
            .map(
              (e) => _FakeQueryDocumentSnapshot(
                e.key,
                Map<String, dynamic>.from(e.value),
              ),
            )
            .toList(growable: false);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeQueryDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeQueryDocumentSnapshot(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ==================== HARNESS TERPADU APLIKASI ====================

class _IntegratedAppContext {
  _IntegratedAppContext({
    required this.tempDir,
    required this.exportDir,
    required this.dbHelper,
    required this.gateway,
    required this.connectivity,
    required this.firestore,
    required this.syncService,
    required this.authRepository,
    required this.inventoryRepository,
    required this.authVm,
  });

  final Directory tempDir;
  final Directory exportDir;
  final DatabaseHelper dbHelper;
  final _TestAuthGateway gateway;
  final _ControllableConnectivity connectivity;
  final _InMemoryFirestore firestore;
  final SyncService syncService;
  final AuthRepository authRepository;
  final InventoryRepository inventoryRepository;
  final AuthViewModel authVm;

  Future<void> dispose() async {
    authVm.dispose();
    await inventoryRepository.dispose();
    await syncService.flushPendingTasks();
    await connectivity.dispose();
    await firestore.dispose();
    await dbHelper.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

Future<_IntegratedAppContext> _createIntegratedContext({
  bool initialOnline = false,
  bool initializeSync = false,
  bool seedDefaultPetugas = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final tempDir = Directory.systemTemp.createTempSync('dt36_int_test_');
  final exportDir = Directory(p.join(tempDir.path, 'exports'))..createSync();

  final dbHelper = DatabaseHelper.forTesting(
    customDbPath: p.join(tempDir.path, 'integrated.db'),
  );
  final gateway = _TestAuthGateway();
  final connectivity = _ControllableConnectivity(initialOnline: initialOnline);
  final firestore = _InMemoryFirestore();
  final syncService = SyncService(
    dbHelper: dbHelper,
    firestore: firestore,
    connectivity: connectivity,
  );
  final authRepository = AuthRepository(
    dbHelper: dbHelper,
    gateway: gateway,
    prefs: prefs,
    connectivity: connectivity,
    isOnlineChecker: () async =>
        (await connectivity.checkConnectivity()).any((c) => c != ConnectivityResult.none),
    syncService: syncService,
  );
  final inventoryRepository = InventoryRepository(
    dbHelper: dbHelper,
    syncService: syncService,
  );

  await dbHelper.database;
  if (seedDefaultPetugas) {
    final seedTime = DateTime(2026, 2, 16);
    await dbHelper.upsertPetugas(
      Petugas(
        namaPetugas: 'Owner Toko',
        role: UserRole.owner,
        pin: '1111',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        remoteId: 'seed-petugas-owner',
        syncStatus: SyncStatus.synced,
        updatedAt: seedTime,
      ),
    );
    await dbHelper.upsertPetugas(
      Petugas(
        namaPetugas: 'Kasir Toko',
        role: UserRole.petugas,
        pin: '1234',
        email: 'kasir@depottelur36.com',
        accountId: 'kasir01',
        remoteId: 'seed-petugas-kasir',
        syncStatus: SyncStatus.synced,
        updatedAt: seedTime,
      ),
    );
  }
  if (initializeSync) {
    await inventoryRepository.initialize();
  }

  final authVm = AuthViewModel(repository: authRepository);
  final ctx = _IntegratedAppContext(
    tempDir: tempDir,
    exportDir: exportDir,
    dbHelper: dbHelper,
    gateway: gateway,
    connectivity: connectivity,
    firestore: firestore,
    syncService: syncService,
    authRepository: authRepository,
    inventoryRepository: inventoryRepository,
    authVm: authVm,
  );
  addTearDown(ctx.dispose);
  return ctx;
}

Future<void> _drainEvents([int ms = 60]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _waitUntilCondition(
  bool Function() condition, {
  int maxMs = 4000,
}) async {
  final steps = (maxMs / 25).ceil();
  for (var i = 0; i < steps; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<void> _flushUi(
  WidgetTester tester, {
  bool Function()? until,
}) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    if (until != null && until()) break;
  }
  await tester.pump(const Duration(milliseconds: 250));
  if (until != null && !until()) {
    throw TestFailure('Kondisi UI yang ditunggu tidak terpenuhi.');
  }
  await tester.pumpAndSettle();
}

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Integration Testing - Skenario Normal (Kolaborasi Lintas Modul)', () {
    test(
      'Alur bisnis lengkap: Auth + Master CRUD (PIN kasir offline login) -> Kasir Nota -> Beranda & Stok Menipis -> Faktur Restok -> Rekap Omzet & Ekspor',
      () async {
        final ctx = await _createIntegratedContext(
          initialOnline: true,
          seedDefaultPetugas: false,
        );
        final today = DateTime(2026, 2, 18);

        // 1. Seed profil Owner di cloud sehingga SignUp menetapkan role OWNER
        const ownerEmail = 'owner.toko@depottelur36.com';
        ctx.gateway.cloudPetugasByEmail[ownerEmail] = Petugas(
          namaPetugas: 'Budi Owner',
          role: UserRole.owner,
          pin: '9988',
          email: ownerEmail,
          accountId: 'owner_toko',
          remoteId: 'owner-cloud-1',
          updatedAt: today,
        );

        final signedUp = await ctx.authVm.signUp(
          fullName: 'Budi Owner',
          email: ownerEmail,
          password: 'passwordOwner123',
          confirmPassword: 'passwordOwner123',
        );
        expect(signedUp, isTrue);
        final ownerSession = ctx.authVm.session!;
        expect(ownerSession.isOwner, isTrue);

        // 2. Hubungkan seluruh ViewModel produksi pada InventoryRepository yang sama
        final masterVm = MasterCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final dashVm = DashboardViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final restockVm = RestockMonitorViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          exportDirectory: ctx.exportDir,
          nowProvider: () => today,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        addTearDown(() {
          masterVm.dispose();
          dashVm.dispose();
          restockVm.dispose();
          rekapVm.dispose();
          txVm.dispose();
        });

        await Future.wait([
          masterVm.loadData(),
          dashVm.loadDashboardData(),
          restockVm.loadData(),
          rekapVm.loadData(),
          txVm.loadData(),
        ]);

        // 3. Owner menambahkan Petugas baru, Barang, Supplier & Customer via MasterCrudViewModel
        expect(
          await masterVm.savePetugas(
            namaPetugas: 'Joko Kasir',
            role: UserRole.petugas,
            pin: '4321',
            email: 'joko.kasir@depottelur36.com',
            accountId: 'joko4321',
            requireEmail: true,
          ),
          isTrue,
        );
        expect(
          await masterVm.saveSupplier(
            namaSupplier: 'CV Berkah Mandiri',
            alamatSupplier: 'Jl. Gudang Utama No. 88',
            noTelpSupplier: '081233445566',
          ),
          isTrue,
        );
        expect(
          await masterVm.saveCustomer(namaCustomer: 'Warung Bu Sari'),
          isTrue,
        );
        expect(
          await masterVm.saveBarang(
            namaBarang: 'Telur Puyuh Kemasan',
            stokBarang: 16,
            satuan: 'Pouch',
            hargaSatuan: 18000,
          ),
          isTrue,
        );
        await _drainEvents();

        // 4. Kasir baru ("Joko Kasir") Sign Out -> Sign In OFFLINE memakai PIN yang dibuat Owner
        await ctx.authVm.signOut();
        ctx.connectivity.setOnline(false);

        final loggedKasir = await ctx.authVm.signIn(
          identifier: 'joko4321',
          password: '4321',
        );
        expect(loggedKasir, isTrue);
        final kasirSession = ctx.authVm.session!;
        expect(kasirSession.isOwner, isFalse);
        expect(kasirSession.provider, AuthProviderType.offlineLocal);

        // Sinkronkan updateSession lintas semua ViewModel
        dashVm.updateSession(kasirSession);
        masterVm.updateSession(kasirSession);
        restockVm.updateSession(kasirSession);
        rekapVm.updateSession(kasirSession);
        txVm.updateSession(kasirSession);
        await _drainEvents();

        // Pastikan RekapOmzet terkunci bagi Operator & Master menolak akses akun Petugas
        expect(rekapVm.isAuthorized, isFalse);
        expect(dashVm.tabs.any((t) => t.id == DashboardTabId.omzet), isFalse);

        // 5. Catat Faktur pembelian awal 1 sak kecil agar supplier terakhir terekam -> stok 16 + 1 = 17
        final puyuh = txVm.barangs.firstWhere(
          (b) => b.namaBarang == 'Telur Puyuh Kemasan',
        );
        final cvBerkah = txVm.suppliers.firstWhere(
          (s) => s.namaSupplier == 'CV Berkah Mandiri',
        );
        final buSari = txVm.customers.firstWhere(
          (c) => c.namaCustomer == 'Warung Bu Sari',
        );
        txVm.selectFakturSupplier(cvBerkah.idSupplier);
        txVm.addOrIncrementFakturBarang(puyuh, delta: 1);
        final initFakturId = await txVm.submitFakturMasuk();
        expect(initFakturId, isNotNull);
        await _drainEvents();

        // 6. Kasir melakukan penjualan 11 Pouch (stok 17 - 11 = 6 -> masuk zona Kritis!)
        final puyuhAfterFaktur = txVm.barangs.firstWhere(
          (b) => b.namaBarang == 'Telur Puyuh Kemasan',
        );
        txVm.selectNotaCustomer(buSari.idCustomer);
        expect(txVm.setKasirQty(puyuhAfterFaktur, 11), isTrue);
        expect(txVm.kasirGrandTotal, 198000);
        final notaId = await txVm.submitKasirNota();
        expect(notaId, isNotNull);
        await _drainEvents();

        // Verifikasi Dash + RestockMonitor otomatis menangkap status Kritis beserta supplier terakhir
        final critDash = dashVm.allBarang.firstWhere(
          (b) => b.namaBarang == 'Telur Puyuh Kemasan',
        );
        expect(critDash.stokBarang, 6);
        expect(
          dashVm.notifications.any(
            (n) =>
                n.barangNama == 'Telur Puyuh Kemasan' &&
                n.severity == NotificationSeverity.warning,
          ),
          isTrue,
        );

        final critRestock = restockVm.snapshot.criticalItems.firstWhere(
          (i) => i.barang.namaBarang == 'Telur Puyuh Kemasan',
        );
        expect(critRestock.suggestedQty, 14);
        expect(critRestock.lastSupplierName, 'CV Berkah Mandiri');

        // 7. Operator menyesuaikan qty restok menjadi 24 -> prepareRestockDraft -> submitFakturMasuk -> stok 6 + 24 = 30
        expect(restockVm.setDraftQty(critRestock.barang, 24), isTrue);
        final updatedCrit = restockVm.snapshot.criticalItems.firstWhere(
          (i) => i.barang.namaBarang == 'Telur Puyuh Kemasan',
        );
        expect(
          restockVm.prepareRestockDraft(updatedCrit, transactionVm: txVm),
          24,
        );
        expect(txVm.selectedFakturSupplier?.idSupplier, cvBerkah.idSupplier);
        expect(txVm.fakturQtyFor(critRestock.barang), 24);
        expect(await txVm.submitFakturMasuk(), isNotNull);
        await _drainEvents();

        expect(
          restockVm.snapshot.criticalItems.where(
            (i) => i.barang.namaBarang == 'Telur Puyuh Kemasan',
          ),
          isEmpty,
        );
        final safeRestocked = restockVm.snapshot.safeItems.firstWhere(
          (i) => i.barang.namaBarang == 'Telur Puyuh Kemasan',
        );
        expect(safeRestocked.barang.stokBarang, 30);

        // 8. Owner login kembali (offline hash verify) -> verifikasi RekapOmzet & Ekspor file CSV/Teks nyata
        await ctx.authVm.signOut();
        expect(
          await ctx.authVm.signIn(
            identifier: ownerEmail,
            password: 'passwordOwner123',
          ),
          isTrue,
        );
        final restoredOwner = ctx.authVm.session!;
        rekapVm.updateSession(restoredOwner);
        await _drainEvents(100);

        expect(rekapVm.isAuthorized, isTrue);
        final report = rekapVm.report;
        expect(report.totalPenjualanNota, 198000);
        expect(report.unitTerjual, 11);
        expect(report.belanjaFaktur, (1 + 24) * 18000); // 450.000
        expect(
          report.topProducts
              .firstWhere((p) => p.namaBarang == 'Telur Puyuh Kemasan')
              .totalRevenue,
          198000,
        );

        final csvRes = await rekapVm.exportReportToFile(
          format: OmzetExportFormat.csv,
        );
        expect(csvRes, isNotNull);
        expect(File(csvRes!.filePath!).existsSync(), isTrue);
        expect(
          File(csvRes.filePath!).readAsStringSync(),
          contains('Telur Puyuh Kemasan'),
        );

        final txtRes = await rekapVm.exportReportToFile(
          format: OmzetExportFormat.ringkasanTeks,
        );
        expect(txtRes, isNotNull);
        expect(File(txtRes!.filePath!).existsSync(), isTrue);
      },
    );

    test(
      'Batch ubah harga (Atur Harga) memperbarui kalkulasi draft kasir tanpa merusak omzet nota historis',
      () async {
        final ctx = await _createIntegratedContext();
        final ownerSession = AuthSession(
          uid: 'int-owner-price',
          email: 'owner.price@depottelur36.com',
          accountId: 'owner_price',
          displayName: 'Owner Harga',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );
        final today = DateTime(2026, 2, 18);

        final masterVm = MasterCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        addTearDown(() {
          masterVm.dispose();
          txVm.dispose();
          rekapVm.dispose();
        });

        await Future.wait([
          masterVm.loadData(),
          txVm.loadData(),
          rekapVm.loadData(),
        ]);

        final telur = masterVm.allBarang.firstWhere(
          (b) => b.remoteId == 'seed-barang-telur-negeri-kg',
        );
        final idTelur = telur.idBarang!;
        final initialHarga = telur.hargaSatuan;

        // Nota historis #1 (2 unit @ harga awal 28.500 = 57.000)
        expect(txVm.setKasirQty(telur, 2), isTrue);
        expect(await txVm.submitKasirNota(), isNotNull);
        await _drainEvents();

        // Kasir mulai menyiapkan keranjang baru (3 unit @ harga awal 28.500 = 85.500)
        final updatedTelurAfterNota = txVm.barangs.firstWhere((b) => b.idBarang == idTelur);
        expect(txVm.setKasirQty(updatedTelurAfterNota, 3), isTrue);
        expect(txVm.kasirGrandTotal, initialHarga * 3);

        // Owner mengubah harga batch naik menjadi 32.000 sementara keranjang aktif
        expect(
          await masterVm.saveHargaBatch({idTelur: 32000}),
          isTrue,
        );
        await _drainEvents();

        // Keranjang kasir otomatis merefleksikan harga baru 32.000 (3 x 32.000 = 96.000)
        expect(txVm.kasirGrandTotal, 96000);
        expect(await txVm.submitKasirNota(), isNotNull);
        await _drainEvents();

        // RekapOmzet mempertahankan omzet historis Nota #1 + harga baru Nota #2
        expect(rekapVm.report.notaCount, 2);
        expect(rekapVm.report.totalPenjualanNota, (initialHarga * 2) + 96000);
      },
    );

    test(
      'Offline-First SyncService <-> InventoryRepository <-> FakeFirestore: antrean offline tersinkron presisi & pull update cloud menyegarkan seluruh ViewModel',
      () async {
        final ctx = await _createIntegratedContext(
          initialOnline: false,
          initializeSync: true,
        );
        final ownerSession = AuthSession(
          uid: 'seed-petugas-owner',
          email: 'owner@depottelur36.com',
          accountId: 'owner_sync',
          displayName: 'Owner Sync',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );

        final dashVm = DashboardViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final restockVm = RestockMonitorViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => DateTime(2026, 2, 18),
        );
        addTearDown(() {
          dashVm.dispose();
          restockVm.dispose();
          txVm.dispose();
        });

        await Future.wait([
          dashVm.loadDashboardData(),
          restockVm.loadData(),
          txVm.loadData(),
        ]);

        // Saat offline, catat barang baru (stok 10), faktur (+5), dan nota (-8) -> stok akhir = 7 (Kritis!)
        await ctx.inventoryRepository.saveBarang(
          existingRemoteId: 'sync-brg-kritis',
          namaBarang: 'Telur Sync Offline',
          hargaSatuan: 25000,
          satuan: 'Kg',
          stokBarang: 10,
        );
        await _drainEvents();

        final barang = (await ctx.inventoryRepository.getAllBarang())
            .firstWhere((b) => b.remoteId == 'sync-brg-kritis');
        final sup = (await ctx.inventoryRepository.getAllSupplier()).first;
        final cust = (await ctx.inventoryRepository.getAllCustomer()).first;
        final pet = (await ctx.inventoryRepository.getAllPetugas()).first;

        await ctx.inventoryRepository.createFaktur(
          noFaktur: 'FKT-SYNC-01',
          tanggalFaktur: '2026-02-18',
          supplier: sup,
          petugas: pet,
          items: [(barang: barang, quantity: 5)],
        );
        final barangAfterFaktur = (await ctx.inventoryRepository.getAllBarang())
            .firstWhere((b) => b.remoteId == 'sync-brg-kritis');
        await ctx.inventoryRepository.createNota(
          tanggalNota: '2026-02-18',
          customer: cust,
          petugas: pet,
          items: [(barang: barangAfterFaktur, banyaknya: 8)],
        );
        await _drainEvents();

        expect(ctx.syncService.state.isOnline, isFalse);
        expect(ctx.syncService.state.pendingCount, greaterThan(0));
        expect(
          restockVm.snapshot.criticalItems
              .any((e) => e.barang.remoteId == 'sync-brg-kritis'),
          isTrue,
        );

        // Pulihkan internet -> SyncService harus push antrean lokal ke Firestore tanpa double-count stok
        ctx.connectivity.setOnline(true);
        await _drainEvents(30);
        await ctx.syncService.flushPendingTasks();
        await _waitUntilCondition(
          () => ctx.syncService.state.pendingCount == 0,
        );

        expect(ctx.syncService.state.isOnline, isTrue);
        expect(ctx.syncService.state.pendingCount, 0);
        final cloudBarang =
            ctx.firestore.docsOf(SyncService.colBarang)['sync-brg-kritis'];
        expect(cloudBarang, isNotNull);
        expect((cloudBarang!['stok_barang'] as num).toInt(), 7);
        expect(
          ctx.firestore.docsOf(SyncService.colFaktur).values
              .any((f) => f['no_faktur'] == 'FKT-SYNC-01'),
          isTrue,
        );

        // Simulasikan perangkat lain menyinkronkan restok cloud +15 -> stok cloud menjadi 22 -> keluar dari Kritis lokal!
        ctx.firestore.putCloudDoc(SyncService.colBarang, 'sync-brg-kritis', {
          ...cloudBarang,
          'stok_barang': 22,
          'updated_at': DateTime.now().add(const Duration(seconds: 5)).toIso8601String(),
        });
        await ctx.syncService.flushPendingTasks();
        await _drainEvents(200);

        final updatedLocal = restockVm.snapshot.watchOnlyItems.firstWhere(
          (e) => e.barang.remoteId == 'sync-brg-kritis',
        );
        expect(updatedLocal.barang.stokBarang, 22);
        expect(
          dashVm.notifications.any(
            (n) =>
                n.barangNama == 'Telur Sync Offline' &&
                (n.severity == NotificationSeverity.critical ||
                    n.severity == NotificationSeverity.warning),
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'Integrasi UI multi-modul: RoleHomeShellScreen Kasir -> Stok Menipis -> Faktur Masuk terhubung SQLite nyata',
      (tester) async {
        final ctx = (await tester.runAsync(_createIntegratedContext))!;
        final opSession = AuthSession(
          uid: 'seed-petugas-kasir',
          email: 'kasir@depottelur36.com',
          accountId: 'kasir01',
          displayName: 'Kasir Uji Integrasi',
          role: UserRole.petugas,
          petugasRemoteId: 'seed-petugas-kasir',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );

        late int uiIntBarangId;
        await tester.runAsync(() async {
          await ctx.inventoryRepository.saveBarang(
            existingRemoteId: 'ui-int-item',
            namaBarang: 'Telur Puyuh Integrasi',
            stokBarang: 12,
            satuan: 'Pack',
            hargaSatuan: 15000,
          );
          await ctx.inventoryRepository.saveSupplier(
            existingRemoteId: 'ui-int-sup',
            namaSupplier: 'UD Integrasi Maju',
            noTelpSupplier: '081211112222',
            alamatSupplier: 'Jl. Harmoni 10',
          );
          final b = (await ctx.inventoryRepository.getAllBarang())
              .firstWhere((x) => x.remoteId == 'ui-int-item');
          uiIntBarangId = b.idBarang!;
          final s = (await ctx.inventoryRepository.getAllSupplier())
              .firstWhere((x) => x.remoteId == 'ui-int-sup');
          final p = (await ctx.inventoryRepository.getAllPetugas())
              .firstWhere((x) => x.remoteId == 'seed-petugas-kasir');
          await ctx.inventoryRepository.createFaktur(
            noFaktur: 'FKT-INT-INIT',
            tanggalFaktur: '2026-02-15',
            supplier: s,
            petugas: p,
            items: [(barang: b, quantity: 2)],
          ); // stok menjadi 14 (Pantauan)
        });

        await tester.pumpWidget(
          Provider<InventoryRepository>.value(
            value: ctx.inventoryRepository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: RoleHomeShellScreen(initialSession: opSession),
            ),
          ),
        );
        await _flushUi(
          tester,
          until: () =>
              find.byKey(const ValueKey('home_open_restock_monitor_btn'))
                  .evaluate()
                  .isNotEmpty,
        );

        // Pindah ke tab Kasir & jual 5 Pack agar stok turun 14 -> 9 (Kritis <= 10!)
        await tester.tap(find.text('Kasir').last);
        await _flushUi(
          tester,
          until: () => find.text('Kasir Nota Keluar').evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byType(TextField).first,
          'Telur Puyuh Integrasi',
        );
        await tester.pumpAndSettle();
        await _scrollAndTap(
          tester,
          find.byKey(ValueKey('kasir_add_$uiIntBarangId')),
        );
        await tester.pumpAndSettle();
        final incBtn = find.byKey(ValueKey('kasir_inc_$uiIntBarangId'));
        for (var i = 0; i < 4; i++) {
          await _scrollAndTap(tester, incBtn);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('kasir_submit_nota_button')));
        await _flushUi(
          tester,
          until: () => find
              .textContaining('berhasil disimpan', skipOffstage: false)
              .evaluate()
              .isNotEmpty,
        );

        // Kembali ke Beranda & buka 22 Stok Menipis -> item baru masuk zona Kritis (9)
        await tester.tap(find.text('Beranda').last);
        await _flushUi(
          tester,
          until: () =>
              find.byKey(const ValueKey('home_open_restock_monitor_btn'))
                  .evaluate()
                  .isNotEmpty,
        );
        await _scrollAndTap(
          tester,
          find.byKey(const ValueKey('home_open_restock_monitor_btn')),
        );
        await _flushUi(
          tester,
          until: () => find.text('Stok Menipis').evaluate().isNotEmpty,
        );
        expect(find.text('Telur Puyuh Integrasi'), findsOneWidget);
        expect(find.textContaining('UD Integrasi Maju'), findsWidgets);

        // Tekan Buat Faktur -> mendarat di tab Faktur -> langsung simpan Faktur (+11 -> stok 20)
        await _scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_create_faktur_ui-int-item')),
        );
        await _flushUi(
          tester,
          until: () => find.text('Faktur Barang Masuk').evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('faktur_submit_button')));
        await _flushUi(
          tester,
          until: () => find
              .textContaining('stok bertambah', skipOffstage: false)
              .evaluate()
              .isNotEmpty,
        );

        // Tunggu seluruh pemuatan ulang pasca-submit (Dashboard & ViewModel lain) selesai
        await _flushUi(tester);

        // Verifikasi SQLite mencerminkan stok akhir = 9 + 11 = 20
        final refreshedList =
            await tester.runAsync(ctx.inventoryRepository.getAllBarang);
        final updatedItem = refreshedList!.firstWhere(
          (b) => b.remoteId == 'ui-int-item',
        );
        expect(updatedItem.stokBarang, 20);
      },
    );
  });

  group('Integration Testing - Edge Case Lintas Modul', () {
    test(
      'Pergantian sesi akun lintas modul (updateSession) mereset keranjang, draft restok, pencarian & data sensitif Owner',
      () async {
        final ctx = await _createIntegratedContext();
        final ownerA = AuthSession(
          uid: 'owner-a-uid',
          email: 'owner@depottelur36.com',
          accountId: 'owner_a',
          displayName: 'Owner A',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );
        final kasirB = AuthSession(
          uid: 'kasir-b-uid',
          email: 'kasir@depottelur36.com',
          accountId: 'kasir_b',
          displayName: 'Kasir B',
          role: UserRole.petugas,
          petugasRemoteId: 'seed-petugas-kasir',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );

        final dashVm = DashboardViewModel.fromRepository(
          session: ownerA,
          repository: ctx.inventoryRepository,
        );
        final masterVm = MasterCrudViewModel.fromRepository(
          session: ownerA,
          repository: ctx.inventoryRepository,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerA,
          repository: ctx.inventoryRepository,
        );
        final restockVm = RestockMonitorViewModel.fromRepository(
          session: ownerA,
          repository: ctx.inventoryRepository,
        );
        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: ownerA,
          repository: ctx.inventoryRepository,
          exportDirectory: ctx.exportDir,
        );
        addTearDown(() {
          dashVm.dispose();
          masterVm.dispose();
          txVm.dispose();
          restockVm.dispose();
          rekapVm.dispose();
        });

        await Future.wait([
          dashVm.loadDashboardData(),
          masterVm.loadData(),
          txVm.loadData(),
          restockVm.loadData(),
          rekapVm.loadData(),
        ]);

        // Owner A mengisi state di seluruh modul
        dashVm.selectTab(DashboardTabId.omzet);
        dashVm.setSearchQuery('Telur');
        masterVm.selectCategory(MasterCategory.petugas);
        masterVm.setSearchQuery('Siti');
        final firstBarang = txVm.barangs.first;
        txVm.setKasirQty(firstBarang, 2);
        txVm.addOrIncrementFakturBarang(firstBarang, delta: 5);
        restockVm.selectFilter(StokMenipisFilter.pantauan);
        restockVm.setDraftQty(firstBarang, 44);
        expect(masterVm.allPetugas, isNotEmpty);

        // Ganti akun ke Kasir B -> seluruh state antar-pengguna harus terisolasi bersih!
        dashVm.updateSession(kasirB);
        masterVm.updateSession(kasirB);
        txVm.updateSession(kasirB);
        restockVm.updateSession(kasirB);
        rekapVm.updateSession(kasirB);
        await _drainEvents();

        expect(dashVm.activeTab, DashboardTabId.beranda);
        expect(dashVm.searchQuery, isEmpty);
        expect(masterVm.activeCategory, MasterCategory.barang);
        expect(masterVm.searchQuery, isEmpty);
        expect(masterVm.allPetugas, isEmpty);
        expect(txVm.kasirCartLines, isEmpty);
        expect(txVm.fakturCartLines, isEmpty);
        expect(restockVm.filter, StokMenipisFilter.kritis);
        expect(restockVm.draftQtyFor(firstBarang), isNot(44));
        expect(rekapVm.isAuthorized, isFalse);
        expect(rekapVm.errorMessage, isNotNull);
      },
    );

    test(
      'Transaksi cloud tertunda (_deferredCloudNota) otomatis masuk saat Master induknya tiba dari Firestore',
      () async {
        final ctx = await _createIntegratedContext(
          initialOnline: true,
          initializeSync: true,
        );
        final ownerSession = AuthSession(
          uid: 'seed-petugas-owner',
          email: 'owner@depottelur36.com',
          accountId: 'owner_def',
          displayName: 'Owner Deferred',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );
        final today = DateTime(2026, 2, 18);

        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        addTearDown(() {
          rekapVm.dispose();
          txVm.dispose();
        });
        await Future.wait([rekapVm.loadData(), txVm.loadData()]);
        final initialNotaCount = rekapVm.report.notaCount;

        // 1. Nota cloud datang LEBIH DULU sebelum Barang & Customer barunya ada
        ctx.firestore.putCloudDoc(SyncService.colNota, 'nota-cloud-deferred', {
          'tanggal_nota': '2026-02-18',
          'total': 75000.0,
          'customer_remote_id': 'cust-deferred-1',
          'petugas_remote_id': 'seed-petugas-owner',
          'remote_id': 'nota-cloud-deferred',
          'updated_at': today.toIso8601String(),
          'details': [
            {
              'barang_remote_id': 'brg-deferred-1',
              'banyaknya': 3,
              'jumlah': 75000.0,
            },
          ],
        });
        await _drainEvents(100);
        // Masih ditangguhkan di _deferredCloudNota karena barang & customer belum tersedia
        expect(rekapVm.report.notaCount, initialNotaCount);

        // 2. Customer datang dulu -> masih tertunda karena barang belum tiba
        ctx.firestore.putCloudDoc(SyncService.colCustomer, 'cust-deferred-1', {
          'nama_customer': 'Toko Cloud Deferred',
          'remote_id': 'cust-deferred-1',
          'updated_at': today.toIso8601String(),
        });
        await _drainEvents(80);
        expect(rekapVm.report.notaCount, initialNotaCount);

        // 3. Barang datang -> memicu _retryDeferredCloudTransactions -> Nota masuk otomatis ke SQLite & Rekap!
        ctx.firestore.putCloudDoc(SyncService.colBarang, 'brg-deferred-1', {
          'nama_barang': 'Telur Deferred Pack',
          'stok_barang': 17,
          'satuan': 'Pack',
          'harga_satuan': 25000.0,
          'remote_id': 'brg-deferred-1',
          'updated_at': today.toIso8601String(),
        });
        await _drainEvents(30);
        await ctx.syncService.flushPendingTasks();
        await _waitUntilCondition(
          () =>
              rekapVm.report.notaCount == initialNotaCount + 1 &&
              txVm.notas.any((n) => n.remoteId == 'nota-cloud-deferred'),
        );

        expect(rekapVm.report.notaCount, initialNotaCount + 1);
        expect(rekapVm.report.totalPenjualanNota, 75000);
        expect(
          txVm.notas.any((n) => n.remoteId == 'nota-cloud-deferred'),
          isTrue,
        );
      },
    );

    test(
      'Mutasi edit/hapus Nota dan penurunan stok eksternal menjaga konsistensi keranjang Kasir, Stok Menipis & Rekap Omzet',
      () async {
        final ctx = await _createIntegratedContext();
        final ownerSession = AuthSession(
          uid: 'seed-petugas-owner',
          email: 'owner@depottelur36.com',
          accountId: 'owner_mutasi',
          displayName: 'Owner Mutasi',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );
        final today = DateTime(2026, 2, 18);

        await ctx.inventoryRepository.saveBarang(
          existingRemoteId: 'mut-brg-1',
          namaBarang: 'Telur Mutasi Pack',
          stokBarang: 15,
          satuan: 'Pack',
          hargaSatuan: 20000,
        );

        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        final restockVm = RestockMonitorViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => today,
        );
        addTearDown(() {
          txVm.dispose();
          restockVm.dispose();
          rekapVm.dispose();
        });
        await Future.wait([
          txVm.loadData(),
          restockVm.loadData(),
          rekapVm.loadData(),
        ]);

        // 1. Jual 10 Pack -> stok 15 - 10 = 5 (Kritis), omzet = 200.000
        final barang15 =
            txVm.barangs.firstWhere((b) => b.remoteId == 'mut-brg-1');
        txVm.setKasirQty(barang15, 10);
        final idNota = await txVm.submitKasirNota();
        expect(idNota, isNotNull);
        await _drainEvents();

        expect(
          restockVm.snapshot.criticalItems
              .firstWhere((i) => i.barang.remoteId == 'mut-brg-1')
              .barang
              .stokBarang,
          5,
        );
        expect(rekapVm.report.totalPenjualanNota, 200000);

        // 2. Kasir menambahkan 4 Pack ke keranjang, tetapi mutasi eksternal menurunkan stok ke 2
        final barang5 = txVm.barangs.firstWhere((b) => b.remoteId == 'mut-brg-1');
        expect(txVm.setKasirQty(barang5, 4), isTrue);
        await ctx.inventoryRepository.saveBarang(
          idBarang: barang5.idBarang,
          existingRemoteId: barang5.remoteId,
          namaBarang: barang5.namaBarang,
          stokBarang: 2,
          satuan: barang5.satuan,
          hargaSatuan: barang5.hargaSatuan,
        );
        await _drainEvents();
        // Sinkronisasi otomatis mengecilkan qty keranjang kasir menjadi sisa 2
        expect(txVm.kasirQtyFor(barang5), 2);

        // 3. Hapus Nota sebelumnya -> stok kembali bertambah +10 (2 + 10 = 12), keluar dari Kritis, omzet menjadi 0
        expect(await txVm.deleteNotaRecord(idNota!), isTrue);
        await _drainEvents();

        expect(
          restockVm.snapshot.criticalItems
              .where((i) => i.barang.remoteId == 'mut-brg-1'),
          isEmpty,
        );
        expect(
          restockVm.snapshot.watchOnlyItems
              .firstWhere((i) => i.barang.remoteId == 'mut-brg-1')
              .barang
              .stokBarang,
          12,
        );
        expect(rekapVm.report.totalPenjualanNota, 0);
      },
    );
  });

  group('Integration Testing - Kasus Salah Input & Kegagalan Lintas Modul', () {
    test(
      'Integritas referensial lintas modul menolak hapus master terpakai & menolak hapus faktur saat stok sudah terjual',
      () async {
        final ctx = await _createIntegratedContext();
        final ownerSession = AuthSession(
          uid: 'seed-petugas-owner',
          email: 'owner@depottelur36.com',
          accountId: 'owner_fk',
          displayName: 'Owner FK',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );

        await ctx.inventoryRepository.savePetugas(
          existingRemoteId: 'fk-kasir',
          namaPetugas: 'Kasir FK',
          role: UserRole.petugas,
          pin: '2233',
          email: 'fk.kasir@depottelur36.com',
        );
        await ctx.inventoryRepository.saveSupplier(
          existingRemoteId: 'fk-sup',
          namaSupplier: 'Supplier Terpakai',
          noTelpSupplier: '081200001111',
          alamatSupplier: 'Jl. Fakta 1',
        );
        await ctx.inventoryRepository.saveCustomer(
          existingRemoteId: 'fk-cust',
          namaCustomer: 'Pelanggan Terpakai',
        );
        await ctx.inventoryRepository.saveBarang(
          existingRemoteId: 'fk-brg',
          namaBarang: 'Barang Terpakai',
          stokBarang: 2,
          satuan: 'Kg',
          hargaSatuan: 25000,
        );

        final masterVm = MasterCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: ownerSession,
          repository: ctx.inventoryRepository,
          nowProvider: () => DateTime(2026, 2, 18),
        );
        addTearDown(() {
          masterVm.dispose();
          txVm.dispose();
        });
        await Future.wait([masterVm.loadData(), txVm.loadData()]);

        final brg = masterVm.allBarang.firstWhere((b) => b.remoteId == 'fk-brg');
        final sup = masterVm.allSuppliers.firstWhere((s) => s.remoteId == 'fk-sup');
        final cust = masterVm.allCustomers.firstWhere((c) => c.remoteId == 'fk-cust');
        final kasir = masterVm.allPetugas.firstWhere((p) => p.remoteId == 'fk-kasir');

        // Catat Faktur (+10 -> stok 12) lalu Nota (-8 -> stok 4)
        final idFaktur = await ctx.inventoryRepository.createFaktur(
          noFaktur: 'FKT-FK-01',
          tanggalFaktur: '2026-02-18',
          supplier: sup,
          petugas: kasir,
          items: [(barang: brg, quantity: 10)],
        );
        final brgAfterFaktur = (await ctx.inventoryRepository.getAllBarang())
            .firstWhere((b) => b.remoteId == 'fk-brg');
        await ctx.inventoryRepository.createNota(
          tanggalNota: '2026-02-18',
          customer: cust,
          petugas: kasir,
          items: [(barang: brgAfterFaktur, banyaknya: 8)],
        );
        await _drainEvents();

        // Semua entitas yang dipakai Nota/Faktur wajib gagal dihapus
        expect(await masterVm.deleteBarang(brg), isFalse);
        expect(masterVm.errorMessage, isNotNull);

        expect(await masterVm.deleteSupplier(sup), isFalse);
        expect(masterVm.errorMessage, isNotNull);

        expect(await masterVm.deleteCustomer(cust), isFalse);
        expect(masterVm.errorMessage, isNotNull);

        expect(await masterVm.deletePetugas(kasir), isFalse);
        expect(masterVm.errorMessage, isNotNull);

        // Hapus Faktur +10 saat stok tinggal 4 (4 - 10 = -6) harus ditolak atomik
        expect(await txVm.deleteFakturRecord(idFaktur), isFalse);
        expect(txVm.errorMessage, isNotNull);
        final brgStillFour = (await ctx.inventoryRepository.getAllBarang())
            .firstWhere((b) => b.remoteId == 'fk-brg');
        expect(brgStillFour.stokBarang, 4);
      },
    );

    test(
      'Penegakan RBAC Operator serempak & rantai input invalid lintas modul tidak meninggalkan efek samping di SQLite maupun disk',
      () async {
        final ctx = await _createIntegratedContext(initialOnline: false);
        final opSession = AuthSession(
          uid: 'op-rbac-uid',
          email: 'op@depottelur36.com',
          accountId: 'op_rbac',
          displayName: 'Operator RBAC',
          role: UserRole.petugas,
          petugasRemoteId: 'seed-petugas-kasir',
          provider: AuthProviderType.offlineLocal,
          signedInAt: DateTime(2026, 2, 18),
        );

        final dashVm = DashboardViewModel.fromRepository(
          session: opSession,
          repository: ctx.inventoryRepository,
        );
        final masterVm = MasterCrudViewModel.fromRepository(
          session: opSession,
          repository: ctx.inventoryRepository,
        );
        final rekapVm = RekapOmzetViewModel.fromRepository(
          session: opSession,
          repository: ctx.inventoryRepository,
          exportDirectory: ctx.exportDir,
        );
        final restockVm = RestockMonitorViewModel.fromRepository(
          session: opSession,
          repository: ctx.inventoryRepository,
        );
        final txVm = TransactionCrudViewModel.fromRepository(
          session: opSession,
          repository: ctx.inventoryRepository,
        );
        addTearDown(() {
          dashVm.dispose();
          masterVm.dispose();
          rekapVm.dispose();
          restockVm.dispose();
          txVm.dispose();
        });

        await Future.wait([
          dashVm.loadDashboardData(),
          masterVm.loadData(),
          rekapVm.loadData(),
          restockVm.loadData(),
          txVm.loadData(),
        ]);

        // 1. Offline Sign Up harus ditolak oleh AuthViewModel & AuthRepository
        expect(
          await ctx.authVm.signUp(
            fullName: 'Kasir Offline',
            email: 'off@depottelur36.com',
            password: 'password123',
            confirmPassword: 'password123',
          ),
          isFalse,
        );
        expect(ctx.authVm.errorMessage, isNotNull);

        // 2. Operator ditolak pada seluruh jalur terlarang Owner
        expect(dashVm.selectTab(DashboardTabId.omzet), isFalse);
        expect(dashVm.selectTab(DashboardTabId.master), isFalse);
        expect(masterVm.savePetugas(
          namaPetugas: 'Ilegal Kasir',
          role: UserRole.owner,
          pin: '9999',
        ), completion(isFalse));
        expect(
          await masterVm.saveHargaBatch({1: 99000}),
          isFalse,
        );
        expect(
          await rekapVm.exportReportToFile(format: OmzetExportFormat.csv),
          isNull,
        );
        expect(ctx.exportDir.listSync(), isEmpty);

        // 3. Input invalid: Restock qty 0 & item unsaved ditolak sebelum menyentuh keranjang Faktur
        final target = restockVm.snapshot.criticalItems.first;
        expect(restockVm.setDraftQty(target.barang, -5), isFalse);
        expect(
          restockVm.prepareRestockDraft(
            RestockMonitorItem(
              barang: Barang(
                idBarang: null,
                namaBarang: 'Illegal',
                stokBarang: 0,
                satuan: 'Kg',
                hargaSatuan: 10000,
                remoteId: 'x',
                updatedAt: DateTime(2026, 2, 18),
              ),
              alertLevel: StockAlertLevel.habis,
              suggestedQty: 20,
              draftQty: 20,
              meterRatio: 0,
            ),
            transactionVm: txVm,
          ),
          isNull,
        );
        expect(txVm.fakturCartLines, isEmpty);

        // 4. Transaksi Kasir dengan kuantitas melebihi stok tersimpan ditolak bersih tanpa mengurangi stok
        expect(
          txVm.setKasirQty(target.barang, target.barang.stokBarang + 99),
          isFalse,
        );
        expect(txVm.errorMessage, isNotNull);
        expect(txVm.kasirCartLines, isEmpty);
      },
    );
  });
}
