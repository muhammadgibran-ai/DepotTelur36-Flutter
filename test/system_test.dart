// ignore_for_file: subtype_of_sealed_class, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_firestore_platform_interface/src/method_channel/method_channel_field_value.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/main.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
import 'package:depot_telur_36/screens/auth/splash_screen.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_shell_screen.dart';
import 'package:depot_telur_36/screens/laporan/rekap_omzet_screen.dart';
import 'package:depot_telur_36/screens/master/atur_harga_screen.dart';
import 'package:depot_telur_36/screens/master/barang_form_screen.dart';
import 'package:depot_telur_36/screens/master/master_data_tab_view.dart';
import 'package:depot_telur_36/screens/master/petugas_form_screen.dart';
import 'package:depot_telur_36/screens/master/supplier_form_screen.dart';
import 'package:depot_telur_36/screens/stok/stok_menipis_screen.dart';
import 'package:depot_telur_36/screens/transaksi/detail_faktur_screen.dart';
import 'package:depot_telur_36/screens/transaksi/detail_nota_screen.dart';
import 'package:depot_telur_36/screens/transaksi/faktur_masuk_screen.dart';
import 'package:depot_telur_36/screens/transaksi/kasir_nota_screen.dart';
import 'package:depot_telur_36/screens/transaksi/riwayat_faktur_screen.dart';
import 'package:depot_telur_36/screens/transaksi/riwayat_nota_screen.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/viewmodels/rekap_omzet_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/dashboard_widgets.dart';
import 'package:depot_telur_36/widgets/rekap_omzet_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Realistic System Test Doubles (Connectivity, Cloud Firestore, Auth Gateway)
// ---------------------------------------------------------------------------

class _SystemConnectivity extends Fake implements Connectivity {
  _SystemConnectivity({bool initialOnline = true}) : _online = initialOnline;

  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  bool _online;

  bool get isOnline => _online;

  void setOnline(bool next) {
    _online = next;
    if (!_controller.isClosed) {
      _controller.add([
        next ? ConnectivityResult.wifi : ConnectivityResult.none,
      ]);
    }
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    return [_online ? ConnectivityResult.wifi : ConnectivityResult.none];
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void dispose() {
    unawaited(_controller.close());
  }
}

class _SystemQueryDocumentSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _SystemQueryDocumentSnapshot(this._id, Map<String, dynamic> data)
      : _data = Map<String, dynamic>.from(data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_data);
}

class _SystemDocumentSnapshot extends Fake
    implements DocumentSnapshot<Map<String, dynamic>> {
  _SystemDocumentSnapshot(this._id, Map<String, dynamic>? data)
      : _data = data == null ? null : Map<String, dynamic>.from(data);

  final String _id;
  final Map<String, dynamic>? _data;

  @override
  String get id => _id;

  @override
  bool get exists => _data != null;

  @override
  Map<String, dynamic>? data() =>
      _data == null ? null : Map<String, dynamic>.from(_data);
}

class _SystemQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  _SystemQuerySnapshot(this._docs);

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;
}

class _SystemDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _SystemDocumentReference(this._store, this._collection, this._id);

  final _SystemFirestore _store;
  final String _collection;
  final String _id;

  @override
  String get id => _id;

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _store._applySet(_collection, _id, data, merge: options?.merge ?? false);
  }

  @override
  Future<void> delete() async {
    _store._applyDelete(_collection, _id);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    return _SystemDocumentSnapshot(
      _id,
      _store.collectionMap(_collection)[_id],
    );
  }
}

class _SystemQuery extends Fake implements Query<Map<String, dynamic>> {
  _SystemQuery(
    this._store,
    this._collection, [
    this._filters = const [],
    this._limitCount,
  ]);

  final _SystemFirestore _store;
  final String _collection;
  final List<({String field, Object? isEqualTo})> _filters;
  final int? _limitCount;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final fieldName = field.toString();
    return _SystemQuery(
      _store,
      _collection,
      [..._filters, (field: fieldName, isEqualTo: isEqualTo)],
      _limitCount,
    );
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return _SystemQuery(
      _store,
      _collection,
      _filters,
      limit,
    );
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final table = _store.collectionMap(_collection);
    final matches = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final entry in table.entries) {
      var passed = true;
      for (final f in _filters) {
        if (entry.value[f.field] != f.isEqualTo) {
          passed = false;
          break;
        }
      }
      if (!passed) continue;
      matches.add(_SystemQueryDocumentSnapshot(entry.key, entry.value));
      if (_limitCount != null && matches.length >= _limitCount) break;
    }
    return _SystemQuerySnapshot(matches);
  }
}

class _SystemCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _SystemCollectionReference(this._store, this._name);

  final _SystemFirestore _store;
  final String _name;

  @override
  String get id => _name;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    return _SystemDocumentReference(
      _store,
      _name,
      path ?? _store._nextAutoId(),
    );
  }

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return _SystemQuery(
      _store,
      _name,
      [(field: field.toString(), isEqualTo: isEqualTo)],
    );
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    return _SystemQuery(_store, _name, const [], limit);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    return _SystemQuery(_store, _name).get(options);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    return _store._streamForCollection(_name);
  }
}

class _SystemWriteBatch extends Fake implements WriteBatch {
  _SystemWriteBatch(this._store);

  final _SystemFirestore _store;
  final List<void Function()> _ops = [];

  @override
  void set<T>(
    DocumentReference<T> document,
    T data, [
    SetOptions? options,
  ]) {
    final docRef = document as _SystemDocumentReference;
    final map = Map<String, dynamic>.from(data as Map<String, dynamic>);
    final merge = options?.merge ?? false;
    _ops.add(
      () => _store._applySet(docRef._collection, docRef._id, map, merge: merge),
    );
  }

  @override
  void delete(DocumentReference<Object?> document) {
    final docRef = document as _SystemDocumentReference;
    _ops.add(() => _store._applyDelete(docRef._collection, docRef._id));
  }

  @override
  Future<void> commit() async {
    for (final op in _ops) {
      op();
    }
    _ops.clear();
  }
}

class _SystemFirestore extends Fake implements FirebaseFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, StreamController<QuerySnapshot<Map<String, dynamic>>>>
      _controllers = {};
  int _autoSeq = 1;

  String _nextAutoId() => 'auto-${_autoSeq++}';

  Map<String, Map<String, dynamic>> collectionMap(String name) {
    return _collections.putIfAbsent(name, () => <String, Map<String, dynamic>>{});
  }

  Map<String, dynamic>? getDocData(String collection, String id) {
    return collectionMap(collection)[id];
  }

  int docCount(String collection) => collectionMap(collection).length;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return _SystemCollectionReference(this, collectionPath);
  }

  @override
  WriteBatch batch() => _SystemWriteBatch(this);

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamForCollection(String name) {
    final ctrl = _controllers.putIfAbsent(
      name,
      () => StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(),
    );
    return ctrl.stream;
  }

  void _emitCollection(String name) {
    final ctrl = _controllers[name];
    if (ctrl == null || ctrl.isClosed) return;
    final table = collectionMap(name);
    final docs = table.entries
        .map((e) => _SystemQueryDocumentSnapshot(e.key, e.value))
        .toList(growable: false);
    ctrl.add(_SystemQuerySnapshot(docs));
  }

  void _applySet(
    String collection,
    String id,
    Map<String, dynamic> incoming, {
    required bool merge,
  }) {
    final table = collectionMap(collection);
    final target = merge && table.containsKey(id)
        ? Map<String, dynamic>.from(table[id]!)
        : <String, dynamic>{};

    incoming.forEach((key, value) {
      if (value is FieldValue) {
        final delegate = FieldValuePlatform.getDelegate(value);
        if (delegate is MethodChannelFieldValue) {
          if (delegate.type == FieldValueType.incrementInteger ||
              delegate.type == FieldValueType.incrementDouble) {
            final current = (target[key] as num?) ?? 0;
            final delta = (delegate.value as num?) ?? 0;
            target[key] = current + delta;
            return;
          }
          if (delegate.type == FieldValueType.serverTimestamp) {
            target[key] = DateTime.now().toIso8601String();
            return;
          }
        }
      }
      target[key] = value;
    });

    table[id] = target;
    _emitCollection(collection);
  }

  void _applyDelete(String collection, String id) {
    collectionMap(collection).remove(id);
    _emitCollection(collection);
  }

  void dispose() {
    for (final ctrl in _controllers.values) {
      unawaited(ctrl.close());
    }
    _controllers.clear();
  }
}

class _SystemAuthGateway implements AuthGateway {
  _SystemAuthGateway(this._firestore);

  final _SystemFirestore _firestore;
  final Map<String, String> _passwords = {};
  final Map<String, AuthAccountSnapshot> _accountsByEmail = {};
  final List<String> sentResetEmails = [];

  AuthAccountSnapshot? _currentUser;
  int _uidSeq = 1;

  @override
  AuthAccountSnapshot? get currentUser => _currentUser;

  @override
  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_passwords.containsKey(normalized)) {
      throw const AuthGatewayException(
        AuthFailureCode.emailAlreadyInUse,
        'Email sudah terdaftar. Silakan Sign In.',
      );
    }
    final account = AuthAccountSnapshot(
      uid: 'uid-sys-${_uidSeq++}',
      email: normalized,
      displayName: fullName.trim(),
      provider: AuthProviderType.emailPassword,
    );
    _passwords[normalized] = password;
    _accountsByEmail[normalized] = account;
    _currentUser = account;
    return account;
  }

  @override
  Future<AuthAccountSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final savedPass = _passwords[normalized];
    if (savedPass == null) {
      throw const AuthGatewayException(
        AuthFailureCode.userNotFound,
        'Akun tidak ditemukan.',
      );
    }
    if (savedPass != password) {
      throw const AuthGatewayException(
        AuthFailureCode.invalidCredentials,
        'Email/ID atau password tidak sesuai.',
      );
    }
    final account = _accountsByEmail[normalized]!;
    _currentUser = account;
    return account;
  }

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() async {
    const account = AuthAccountSnapshot(
      uid: 'uid-google-sys-1',
      email: 'google.owner@depottelur36.id',
      displayName: 'Google Owner',
      provider: AuthProviderType.google,
    );
    _currentUser = account;
    return account;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    sentResetEmails.add(email.trim().toLowerCase());
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  @override
  Future<Petugas?> findPetugasByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final table = _firestore.collectionMap(SyncService.colPetugas);
    for (final entry in table.entries) {
      final rawEmail = (entry.value['email'] as String?)?.trim().toLowerCase();
      if (rawEmail == normalized) {
        return Petugas.fromFirestore(entry.value, entry.key);
      }
    }
    return null;
  }

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    final normalized = identifier.trim().toLowerCase();
    final table = _firestore.collectionMap(SyncService.colPetugas);
    for (final entry in table.entries) {
      final rawEmail = (entry.value['email'] as String?)?.trim().toLowerCase();
      final rawAccountId =
          (entry.value['account_id'] as String?)?.trim().toLowerCase();
      if (rawEmail == normalized ||
          rawAccountId == normalized ||
          entry.key.toLowerCase() == normalized) {
        return Petugas.fromFirestore(entry.value, entry.key);
      }
    }
    return null;
  }

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {
    await _firestore
        .collection(SyncService.colPetugas)
        .doc(petugas.remoteId)
        .set(petugas.toFirestore(), SetOptions(merge: true));
  }
}

// ---------------------------------------------------------------------------
// Complete Persistent System Harness (Supports Cold App Restart)
// ---------------------------------------------------------------------------

class _SystemAppHarness {
  _SystemAppHarness({
    required this.tempDir,
    required this.dbPath,
    required this.connectivity,
    required this.firestore,
    required this.gateway,
  });

  final Directory tempDir;
  final String dbPath;
  final _SystemConnectivity connectivity;
  final _SystemFirestore firestore;
  final _SystemAuthGateway gateway;

  DatabaseHelper? dbHelper;
  SyncService? syncService;
  InventoryRepository? inventoryRepository;
  AuthRepository? authRepository;
  AuthViewModel? authViewModel;
  int _generation = 0;

  static Future<_SystemAppHarness> create({
    required WidgetTester tester,
    bool initialOnline = true,
    Map<String, Object> initialPrefs = const <String, Object>{},
  }) async {
    final tempDir = Directory.systemTemp.createTempSync('depot36_system_');
    final dbPath = p.join(tempDir.path, 'depot_telur_36_system.db');
    SharedPreferences.setMockInitialValues(
      Map<String, Object>.from(initialPrefs),
    );
    final connectivity = _SystemConnectivity(initialOnline: initialOnline);
    final firestore = _SystemFirestore();
    final gateway = _SystemAuthGateway(firestore);

    final harness = _SystemAppHarness(
      tempDir: tempDir,
      dbPath: dbPath,
      connectivity: connectivity,
      firestore: firestore,
      gateway: gateway,
    );
    await harness._mountDependencies(tester);
    return harness;
  }

  Future<void> _mountDependencies(WidgetTester tester) async {
    await tester.runAsync(() async {
      final db = DatabaseHelper.forTesting(customDbPath: dbPath);
      await db.database;
      final sync = SyncService(
        dbHelper: db,
        firestore: firestore,
        connectivity: connectivity,
      );
      final repo = InventoryRepository(dbHelper: db, syncService: sync);
      await repo.initialize();
      await sync.flushPendingTasks();

      final authRepo = AuthRepository(
        dbHelper: db,
        gateway: gateway,
        syncService: sync,
        connectivity: connectivity,
      );
      final authVm = AuthViewModel(repository: authRepo);

      dbHelper = db;
      syncService = sync;
      inventoryRepository = repo;
      authRepository = authRepo;
      authViewModel = authVm;
    });
  }

  Future<void> provisionOwnerInCloud({
    required String email,
    required String name,
    String pin = '1111',
  }) async {
    final normalized = email.trim().toLowerCase();
    final remoteId = 'owner-prov-${normalized.hashCode.abs()}';
    await gateway.upsertPetugasProfile(
      Petugas(
        namaPetugas: name,
        role: UserRole.owner,
        pin: pin,
        email: normalized,
        accountId: 'OWN01',
        remoteId: remoteId,
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 11, 16, 7, 0),
      ),
    );
  }

  Future<void> launchApp(
    WidgetTester tester, {
    double width = 412,
    double height = 892,
    double textScale = 1.0,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;

    _generation++;
    Widget app = DepotTelur36App(
      key: ValueKey('system_app_gen_$_generation'),
      authViewModelOverride: authViewModel,
      inventoryRepositoryOverride: inventoryRepository,
      splashDelay: Duration.zero,
    );

    if (textScale != 1.0 || disableAnimations) {
      final base = app;
      app = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: base,
        ),
      );
    }

    await tester.pumpWidget(app);
    await _pumpUntil(
      tester,
      () => find.byType(SplashScreen).evaluate().isEmpty,
    );
    await _flushIo(tester, rounds: 10);
  }

  Future<void> simulateColdRestart(WidgetTester tester) async {
    await _flushIo(tester, rounds: 6);
    await tester.pumpWidget(const SizedBox.shrink());
    await _flushIo(tester, rounds: 4);

    await tester.runAsync(() async {
      await syncService?.flushPendingTasks();
      authViewModel?.dispose();
      inventoryRepository?.dispose();
      syncService?.dispose();
      await dbHelper?.close();
    });

    await _mountDependencies(tester);
    await launchApp(tester);
  }

  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _flushIo(tester, rounds: 4);
    await tester.runAsync(() async {
      await syncService?.flushPendingTasks();
      authViewModel?.dispose();
      inventoryRepository?.dispose();
      syncService?.dispose();
      await dbHelper?.close();
      connectivity.dispose();
      firestore.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  }
}

// ---------------------------------------------------------------------------
// Deterministic UI Automation Helpers for Real End-User Interaction
// ---------------------------------------------------------------------------

Future<void> _flushIo(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxRounds = 120,
}) async {
  for (var i = 0; i < maxRounds; i++) {
    if (condition()) {
      await tester.pump(const Duration(milliseconds: 40));
      return;
    }
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Timed out waiting for expected UI state during system test.');
}

Future<void> _tapScrolled(
  WidgetTester tester,
  Finder finder, {
  bool warnIfMissed = true,
}) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 80));
  await tester.tap(finder, warnIfMissed: warnIfMissed);
  await _flushIo(tester, rounds: 6);
}

Finder _authFieldByHint(String hint) {
  return find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );
}

Future<void> _enterAuthField(
  WidgetTester tester,
  String hint,
  String text,
) async {
  final finder = _authFieldByHint(hint);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> _enterKeyField(
  WidgetTester tester,
  String keyName,
  String text,
) async {
  final finder = find.byKey(ValueKey(keyName));
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump(const Duration(milliseconds: 40));
}

Future<void> _selectBottomTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byType(FloatingTabBar),
    matching: find.text(label),
  );
  expect(tab, findsOneWidget);
  await tester.tap(tab);
  await _flushIo(tester, rounds: 8);
}

Future<void> _signUpOwnerViaUi(
  WidgetTester tester, {
  required _SystemAppHarness harness,
  required String name,
  required String email,
  required String password,
}) async {
  await harness.provisionOwnerInCloud(email: email, name: name);
  await _tapScrolled(
    tester,
    find.descendant(
      of: find.byType(WelcomeScreen),
      matching: find.widgetWithText(TactilePillButton, 'Sign Up'),
    ),
  );
  await _pumpUntil(tester, () => find.byType(SignUpScreen).evaluate().isNotEmpty);

  await _enterAuthField(tester, 'Nama Lengkap', name);
  await _enterAuthField(tester, 'Email', email);
  await _enterAuthField(tester, 'Password', password);
  await _enterAuthField(tester, 'Konfirmasi Password', password);
  await _tapScrolled(
    tester,
    find.descendant(
      of: find.byType(SignUpScreen),
      matching: find.widgetWithText(TactilePillButton, 'Sign Up'),
    ),
  );

  await _pumpUntil(
    tester,
    () => find.byType(RoleHomeShellScreen).evaluate().isNotEmpty,
  );
  await _flushIo(tester, rounds: 10);
}

Future<void> _signInViaUi(
  WidgetTester tester, {
  required String identifier,
  required String password,
}) async {
  if (find.byType(WelcomeScreen).evaluate().isNotEmpty &&
      find.byType(SignInScreen).evaluate().isEmpty) {
    await _tapScrolled(
      tester,
      find.descendant(
        of: find.byType(WelcomeScreen),
        matching: find.widgetWithText(TactilePillButton, 'Sign In'),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(SignInScreen).evaluate().isNotEmpty,
    );
  }

  await _enterAuthField(tester, 'ID Akun atau Email', identifier);
  await _enterAuthField(tester, 'Password', password);
  await _tapScrolled(
    tester,
    find.descendant(
      of: find.byType(SignInScreen),
      matching: find.widgetWithText(TactilePillButton, 'Sign In'),
    ),
  );

  await _pumpUntil(
    tester,
    () => find.byType(RoleHomeShellScreen).evaluate().isNotEmpty,
  );
  await _flushIo(tester, rounds: 10);
}

Future<void> _signOutViaUi(WidgetTester tester) async {
  await _tapScrolled(tester, find.widgetWithText(TactilePillButton, 'Sign Out'));
  await _pumpUntil(
    tester,
    () => find.byType(WelcomeScreen).evaluate().isNotEmpty,
  );
  await _flushIo(tester, rounds: 8);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  GoogleFonts.config.allowRuntimeFetching = false;

  group('System Testing - Skenario Normal (End-to-End Pengguna & Cold Restart)',
      () {
    testWidgets(
      'ST-N01 Siklus Lengkap Owner & Kasir Offline -> Stok Menipis -> Faktur -> Nota -> Omzet Ekspor -> Cold Restart',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        final createdExportFiles = <String>[];
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // 1. Launch app root & Sign Up Owner pertama kali
          await harness.launchApp(tester);
          expect(find.byType(WelcomeScreen), findsOneWidget);

          await _signUpOwnerViaUi(
            tester,
            harness: harness,
            name: 'H. Ahmad Fauzi',
            email: 'owner@depottelur36.id',
            password: 'Owner!3636',
          );
          expect(find.text('DepotTelur36 Owner'), findsOneWidget);

          // 2. Owner kelola Master: tambah Barang, ubah harga via Atur Harga, tambah Supplier, Customer, Kasir
          await _selectBottomTab(tester, 'Master');
          expect(find.byType(MasterDataTabView), findsOneWidget);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(tester, 'barang_nama_field', 'Telur Omega Super');
          await _enterKeyField(tester, 'barang_stok_field', '15');
          await _tapScrolled(tester, find.byKey(const ValueKey('unit_chip_Kg')));
          await _enterKeyField(tester, 'barang_harga_field', '32000');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 8);
          expect(find.text('Telur Omega Super'), findsWidgets);

          final allBarangs1 =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final telurOmega = allBarangs1!
              .firstWhere((b) => b.namaBarang == 'Telur Omega Super');

          // Batch update harga di Pendev 21 Atur Harga Jual
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_open_atur_harga_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(AturHargaScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(
            tester,
            'atur_harga_input_${telurOmega.remoteId}',
            '34000',
          );
          expect(find.text('Simpan Harga Baru (1)'), findsOneWidget);
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('atur_harga_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find
                .textContaining('berhasil diperbarui')
                .evaluate()
                .isNotEmpty,
          );
          expect(
            find.textContaining('berhasil diperbarui'),
            findsOneWidget,
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_back_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(AturHargaScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 6);
          expect(find.byType(MasterDataTabView), findsOneWidget);

          // Tambah Supplier riil
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_category_tab_supplier')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(SupplierFormScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(
            tester,
            'supplier_nama_field',
            'UD Sari Jaya Makmur',
          );
          await _enterKeyField(tester, 'supplier_telp_field', '081355778899');
          await _enterKeyField(
            tester,
            'supplier_alamat_field',
            'Jl. Peternakan Raya No. 18, Blitar',
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(SupplierFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 8);
          expect(find.text('UD Sari Jaya Makmur'), findsOneWidget);

          // Tambah Pelanggan riil via formulir cepat inline
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_category_tab_pelanggan')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _enterKeyField(
            tester,
            'customer_quick_nama_field',
            'Warung Nasi Ibu Tuti',
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('customer_quick_save_button')),
          );
          await _flushIo(tester, rounds: 8);
          expect(find.text('Warung Nasi Ibu Tuti'), findsOneWidget);

          // Tambah Akun Kasir (Operator)
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_category_tab_petugas')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(PetugasFormScreen).evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('petugas_role_${UserRole.petugas.value}')),
          );
          await _enterKeyField(tester, 'petugas_nama_field', 'Rina Amelia');
          await _enterKeyField(
            tester,
            'petugas_email_field',
            'rina@depottelur36.id',
          );
          await _enterKeyField(tester, 'petugas_pin_field', '5678');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(PetugasFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 8);
          expect(find.text('Rina Amelia'), findsOneWidget);

          // Kembali ke Beranda & Sign Out sebagai Owner
          await _selectBottomTab(tester, 'Beranda');
          await _signOutViaUi(tester);

          // 3. Matikan jaringan (Mode Offline) -> Kasir Login pakai Email + PIN 5678
          harness.connectivity.setOnline(false);
          await _signInViaUi(
            tester,
            identifier: 'rina@depottelur36.id',
            password: '5678',
          );
          expect(find.text('DepotTelur36 Kasir'), findsOneWidget);

          // 4. Kasir jual 6 Kg Telur Omega Super ke Warung Nasi Ibu Tuti (Stok: 15 -> 9 Kritis!)
          await _selectBottomTab(tester, 'Kasir');
          expect(find.byType(KasirNotaView), findsOneWidget);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('kasir_customer_pill')),
          );
          await _pumpUntil(
            tester,
            () => find.text('Warung Nasi Ibu Tuti').evaluate().isNotEmpty,
          );
          await _tapScrolled(tester, find.text('Warung Nasi Ibu Tuti').last);
          await _flushIo(tester, rounds: 5);

          final kasirSearchN01 = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('Cari telur') ?? false),
          );
          await tester.enterText(kasirSearchN01, 'Telur Omega');
          await _flushIo(tester, rounds: 4);

          await _tapScrolled(
            tester,
            find.byKey(ValueKey('kasir_add_${telurOmega.idBarang}')),
          );
          for (var i = 0; i < 5; i++) {
            await _tapScrolled(
              tester,
              find.byKey(ValueKey('kasir_inc_${telurOmega.idBarang}')),
            );
          }
          await _pumpUntil(
            tester,
            () => find.textContaining('204.000').evaluate().isNotEmpty,
          );
          expect(find.textContaining('204.000'), findsWidgets);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('kasir_submit_nota_button')),
          );
          await _flushIo(tester, rounds: 10);

          final barangsAfterSale =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final omegaAfterSale = barangsAfterSale!
              .firstWhere((b) => b.idBarang == telurOmega.idBarang);
          expect(omegaAfterSale.stokBarang, 9);

          // 5. Kasir buka Pemantauan Stok Menipis -> Buat Faktur Restok +13 Kg -> Stok jadi 22 Kg
          await _selectBottomTab(tester, 'Beranda');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('home_open_restock_monitor_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(StokMenipisScreen).evaluate().isNotEmpty,
          );
          await _flushIo(tester, rounds: 6);
          expect(
            find.byKey(ValueKey('restock_critical_card_${telurOmega.remoteId}')),
            findsOneWidget,
          );

          await _tapScrolled(
            tester,
            find.byKey(ValueKey('restock_inc_${telurOmega.remoteId}')),
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('restock_create_faktur_${telurOmega.remoteId}')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(FakturMasukView).evaluate().isNotEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // Pilih supplier UD Sari Jaya Makmur di Faktur Masuk & Simpan
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_supplier_selector')),
          );
          await _pumpUntil(
            tester,
            () => find.text('UD Sari Jaya Makmur').evaluate().isNotEmpty,
          );
          await _tapScrolled(tester, find.text('UD Sari Jaya Makmur').last);
          await _flushIo(tester, rounds: 5);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_submit_button')),
          );
          await _pumpUntil(
            tester,
            () => find
                .textContaining('berhasil disimpan')
                .evaluate()
                .isNotEmpty,
          );
          await _flushIo(tester, rounds: 8);

          // Kembali ke Beranda Kasir lalu Sign Out
          await _selectBottomTab(tester, 'Beranda');

          final barangsAfterRestock =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final omegaAfterRestock = barangsAfterRestock!
              .firstWhere((b) => b.idBarang == telurOmega.idBarang);
          expect(omegaAfterRestock.stokBarang, 21); // 9 + 12 restock

          // Sign Out Kasir
          await _signOutViaUi(tester);

          // 6. Online lagi -> Owner Sign In -> Edit Nota di Riwayat Nota & Cek Riwayat Faktur
          harness.connectivity.setOnline(true);
          await _signInViaUi(
            tester,
            identifier: 'owner@depottelur36.id',
            password: 'Owner!3636',
          );
          expect(find.text('DepotTelur36 Owner'), findsOneWidget);

          await _selectBottomTab(tester, 'Nota');
          expect(find.byType(RiwayatNotaView), findsOneWidget);

          final notas1 =
              await tester.runAsync(() => harness.dbHelper!.getAllNota());
          expect(notas1!.length, 1);
          final createdNota = notas1.first;
          expect(createdNota.total, 204000);

          // Ubah banyaknya dari 6 -> 7 Kg via DetailNotaScreen (Total: Rp 238.000, Stok: 22 -> 21)
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('nota_card_${createdNota.idNota}')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(DetailNotaScreen).evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('detail_nota_${telurOmega.idBarang}_inc')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('detail_nota_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(DetailNotaScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 8);
          expect(find.textContaining('238.000'), findsWidgets);

          // Cek Riwayat Faktur melalui shortcut Beranda
          await _selectBottomTab(tester, 'Beranda');
          await _tapScrolled(tester, find.text('Riwayat Faktur'));
          await _pumpUntil(
            tester,
            () => find.byType(RiwayatFakturScreen).evaluate().isNotEmpty,
          );
          await _flushIo(tester, rounds: 6);
          final fakturs1 =
              await tester.runAsync(() => harness.dbHelper!.getAllFaktur());
          expect(fakturs1!.length, 1);
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('faktur_card_${fakturs1.first.idFaktur}')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(DetailFakturScreen).evaluate().isNotEmpty,
          );
          expect(find.text('UD Sari Jaya Makmur'), findsWidgets);
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(DetailFakturScreen),
              matching: find.byKey(const ValueKey('master_header_back_button')),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(DetailFakturScreen).evaluate().isEmpty,
          );
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(RiwayatFakturScreen),
              matching: find.byKey(const ValueKey('master_header_back_button')),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(RiwayatFakturScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // 7. Owner buka Rekap Omzet -> pilih periode, ketuk chart bar, ekspansi produk, ekspor CSV ke file
          await _selectBottomTab(tester, 'Omzet');
          expect(find.byType(RekapOmzetView), findsOneWidget);
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('rekap_period_${RekapOmzetPeriod.tujuhHari.name}')),
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('rekap_period_${RekapOmzetPeriod.bulanIni.name}')),
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('rekap_period_${RekapOmzetPeriod.hariIni.name}')),
          );
          await _pumpUntil(
            tester,
            () =>
                find.byKey(const ValueKey('rekap_chart_bar_6')).evaluate().length ==
                1,
          );
          await _tapScrolled(tester, find.byKey(const ValueKey('rekap_chart_bar_6')));
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('rekap_product_row_id_${telurOmega.idBarang}')),
          );

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('rekap_omzet_export_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(OmzetExportSheet).evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('rekap_export_format_${OmzetExportFormat.csv.name}')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('rekap_export_copy_btn')),
          );
          expect(find.text('Tersalin!'), findsOneWidget);

          final exportSheetState = tester.widget<OmzetExportSheet>(
            find.byType(OmzetExportSheet),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('rekap_export_save_btn')),
          );
          await _pumpUntil(
            tester,
            () => exportSheetState.viewModel.lastExportResult?.filePath != null,
          );
          await _flushIo(tester, rounds: 4);
          final savedExport = exportSheetState.viewModel.lastExportResult;
          expect(savedExport, isNotNull);
          expect(savedExport!.filePath, isNotNull);
          createdExportFiles.add(savedExport.filePath!);
          final exportedText = await tester.runAsync(
            () => File(savedExport.filePath!).readAsString(),
          );
          expect(exportedText, contains('Telur Omega Super'));
          expect(exportedText, contains('238000'));

          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(OmzetExportSheet),
              matching: find.byIcon(Icons.close_rounded),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(OmzetExportSheet).evaluate().isEmpty,
          );

          // 8. SIMULATED COLD APP RESTART: Sesi Owner & Seluruh Transaksi SQLite Tetap Utuh
          await harness.simulateColdRestart(tester);
          expect(find.byType(WelcomeScreen), findsNothing);
          expect(find.byType(SignInScreen), findsNothing);
          expect(find.byType(RoleHomeShellScreen), findsOneWidget);
          expect(find.text('DepotTelur36 Owner'), findsOneWidget);

          await _selectBottomTab(tester, 'Nota');
          expect(find.textContaining('238.000'), findsWidgets);

          final finalBarangs =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final finalOmega = finalBarangs!
              .firstWhere((b) => b.idBarang == telurOmega.idBarang);
          expect(finalOmega.stokBarang, 20); // 15 - 7 + 12
          expect(finalOmega.hargaSatuan, 34000);
        } finally {
          for (final filePath in createdExportFiles) {
            await tester.runAsync(() async {
              final f = File(filePath);
              if (await f.exists()) {
                await f.delete();
              }
            });
          }
          await harness.disposeAll(tester);
        }
      },
    );

    testWidgets(
      'ST-N02 Pencarian Global, Filter Cepat, & Konsistensi Back Navigation Multi-Layar',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(tester);
          await _signUpOwnerViaUi(
            tester,
            harness: harness,
            name: 'Owner Audit',
            email: 'audit@depottelur36.id',
            password: 'Audit!3636',
          );

          // Pencarian Beranda: hasil kosong lalu bersihkan query
          final homeSearch = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('Cari laporan') ?? false),
          );
          expect(homeSearch, findsOneWidget);
          await tester.enterText(homeSearch, 'KomoditasFiktif999');
          await _pumpUntil(
            tester,
            () => find.byKey(const ValueKey('search_empty')).evaluate().isEmpty,
          );
          expect(find.byKey(const ValueKey('search_clear')), findsOneWidget);
          expect(find.byKey(const ValueKey('search_empty')), findsNothing);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('search_clear')),
          );
          await _pumpUntil(
            tester,
            () => find.byKey(const ValueKey('search_clear')).evaluate().isEmpty,
          );
          expect(find.byKey(const ValueKey('search_clear')), findsNothing);
          expect(find.byKey(const ValueKey('search_empty')), findsOneWidget);

          // Buka shortcut Beranda -> Master Data Supplier & Petugas lalu kembali
          await _tapScrolled(tester, find.text('Data Supplier'));
          await _flushIo(tester, rounds: 6);
          expect(find.byType(MasterDataTabView), findsOneWidget);
          expect(find.byKey(const ValueKey('master_search_field')), findsOneWidget);

          await _enterKeyField(tester, 'master_search_field', 'Peternakan');
          await _flushIo(tester, rounds: 4);
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_search_clear')),
          );
          await _flushIo(tester, rounds: 4);

          await _selectBottomTab(tester, 'Beranda');
          expect(find.text('Atur Harga'), findsOneWidget);
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );
  });

  group('System Testing - Edge Case (Sync Recovery, Layout 320px, & RBAC)', () {
    testWidgets(
      'ST-E01 Offline Mutations lalu Online -> Sinkron Manual via Notification Sheet Update Cloud Firestore',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(tester);
          await _signUpOwnerViaUi(
            tester,
            harness: harness,
            name: 'Owner Sync',
            email: 'sync@depottelur36.id',
            password: 'Sync!3636',
          );

          // Matikan internet setelah login
          harness.connectivity.setOnline(false);
          await _flushIo(tester, rounds: 5);

          // Tambah barang baru saat offline
          await _selectBottomTab(tester, 'Master');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(tester, 'barang_nama_field', 'Telur Asin Asap');
          await _enterKeyField(tester, 'barang_stok_field', '24');
          await _enterKeyField(tester, 'barang_harga_field', '5000');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 8);

          // Buka Notifikasi & Sinkronisasi saat offline
          await _selectBottomTab(tester, 'Beranda');
          await _tapScrolled(
            tester,
            find.byTooltip('Notifikasi & Sinkronisasi'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(NotificationCenterSheet).evaluate().isNotEmpty,
          );
          expect(
            find.text('Mode Offline · 1 perubahan menunggu internet'),
            findsOneWidget,
          );

          // Pulihkan internet & tekan tombol Sinkron di sheet
          harness.connectivity.setOnline(true);
          await _flushIo(tester, rounds: 8);
          await _tapScrolled(tester, find.text('Sinkron'));
          await _pumpUntil(
            tester,
            () => find
                .text('Online · SQLite & Firebase tersinkron')
                .evaluate()
                .isNotEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // Pastikan barang baru sudah terunggah ke Cloud Firestore
          final barangs =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final asin =
              barangs!.firstWhere((b) => b.namaBarang == 'Telur Asin Asap');
          final cloudDoc =
              harness.firestore.getDocData(SyncService.colBarang, asin.remoteId);
          expect(cloudDoc, isNotNull);
          expect(cloudDoc!['nama_barang'], 'Telur Asin Asap');
          expect(asin.syncStatus, SyncStatus.synced);
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );

    testWidgets(
      'ST-E02 Viewport Sempit 320x568 + TextScale 1.4x + Reduce Motion Bebas Overflow di Seluruh Layar',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(
            tester,
            width: 320,
            height: 568,
            textScale: 1.4,
            disableAnimations: true,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(WelcomeScreen), findsOneWidget);

          // Cek Sign In screen & kembali -> Sign Up
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign In'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(SignInScreen).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);

          await _tapScrolled(tester, find.text('Sign Up').first);
          await _pumpUntil(
            tester,
            () => find.byType(SignUpScreen).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);

          await harness.provisionOwnerInCloud(
            email: 'mini@depottelur36.id',
            name: 'Owner Mini',
          );
          await _enterAuthField(tester, 'Nama Lengkap', 'Owner Mini');
          await _enterAuthField(tester, 'Email', 'mini@depottelur36.id');
          await _enterAuthField(tester, 'Password', 'Mini!3636');
          await _enterAuthField(tester, 'Konfirmasi Password', 'Mini!3636');
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign Up'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(RoleHomeShellScreen).evaluate().isNotEmpty,
          );
          await _flushIo(tester, rounds: 10);
          expect(tester.takeException(), isNull);

          // Jelajahi semua tab utama di layar sempit 320x568 + 1.4x font
          for (final tabLabel in const ['Omzet', 'Nota', 'Master', 'Beranda']) {
            await _selectBottomTab(tester, tabLabel);
            expect(
              tester.takeException(),
              isNull,
              reason: 'Overflow saat membuka tab $tabLabel pada 320x568 1.4x',
            );
          }

          // Buka Ekspor Rekap Omzet sheet di layar sempit
          await _selectBottomTab(tester, 'Omzet');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('rekap_omzet_export_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(OmzetExportSheet).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(OmzetExportSheet),
              matching: find.byIcon(Icons.close_rounded),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(OmzetExportSheet).evaluate().isEmpty,
          );

          // Buka Kasir, Faktur, & Stok Menipis via Beranda / Riwayat Nota
          await _selectBottomTab(tester, 'Nota');
          await _tapScrolled(tester, find.text('+ Nota'));
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_back_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isEmpty,
          );

          await _selectBottomTab(tester, 'Beranda');
          await _tapScrolled(
            tester,
            find.byTooltip('Notifikasi & Sinkronisasi'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(NotificationCenterSheet).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('notif_open_restock_monitor_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(StokMenipisScreen).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);

          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('stok_menipis_new_faktur_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(FakturMasukScreen).evaluate().isNotEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );

    testWidgets(
      'ST-E03 Isolasi Hak Akses Operator (RBAC): Tab, Shortcut Beranda, Master Data, & Deep-Link Guard',
      (tester) async {
        final kasirSession = AuthSession(
          uid: 'uid-kasir-rbac',
          email: 'kasir@depottelur36.id',
          accountId: 'P02',
          displayName: 'Budi Kasir',
          role: UserRole.petugas,
          petugasRemoteId: 'ptg-kasir-rbac',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 11, 16, 8, 0),
        );
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: false,
          initialPrefs: {
            AuthRepository.sessionStorageKey: kasirSession.toJson(),
          },
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.runAsync(() async {
            await harness.dbHelper!.upsertPetugas(
              Petugas(
                namaPetugas: 'Budi Kasir',
                role: UserRole.petugas,
                pin: '1234',
                email: 'kasir@depottelur36.id',
                accountId: 'P02',
                remoteId: 'ptg-kasir-rbac',
                syncStatus: SyncStatus.synced,
                updatedAt: DateTime(2026, 11, 16, 8, 0),
              ),
            );
          });

          await harness.launchApp(tester);
          expect(find.text('DepotTelur36 Kasir'), findsOneWidget);

          // FloatingTabBar kasir hanya menampilkan 4 tab operasional
          Finder tabFinder(String label) => find.descendant(
                of: find.byType(FloatingTabBar),
                matching: find.text(label),
              );
          expect(tabFinder('Beranda'), findsOneWidget);
          expect(tabFinder('Kasir'), findsOneWidget);
          expect(tabFinder('Faktur'), findsOneWidget);
          expect(tabFinder('Stok'), findsOneWidget);
          expect(tabFinder('Omzet'), findsNothing);
          expect(tabFinder('Nota'), findsNothing);
          expect(tabFinder('Master'), findsNothing);

          // Beranda kasir tidak menampilkan shortcut khusus Owner
          expect(find.text('Atur Harga'), findsNothing);
          expect(find.text('Akun Petugas'), findsNothing);
          expect(find.text('Riwayat Nota'), findsOneWidget);
          expect(find.text('Riwayat Faktur'), findsOneWidget);

          // Tab Stok (MasterDataTabView mode operator) juga tidak membuka tab Petugas / Atur Harga
          await _selectBottomTab(tester, 'Stok');
          expect(find.byType(MasterDataTabView), findsOneWidget);
          expect(
            find.byKey(const ValueKey('master_open_atur_harga_button')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('master_category_tab_petugas')),
            findsNothing,
          );

          // Deep-link guard langsung ke layar RekapOmzetScreen & PetugasFormScreen tetap terkunci
          final rekapVm = RekapOmzetViewModel.fromRepository(
            session: kasirSession,
            repository: harness.inventoryRepository!,
          );
          final masterVm = MasterCrudViewModel.fromRepository(
            session: kasirSession,
            repository: harness.inventoryRepository!,
          );
          addTearDown(() {
            rekapVm.dispose();
            masterVm.dispose();
          });

          await tester.pumpWidget(
            MaterialApp(
              home: RekapOmzetScreen(viewModel: rekapVm),
            ),
          );
          await _flushIo(tester, rounds: 4);
          expect(
            find.byKey(const ValueKey('rekap_omzet_rbac_locked')),
            findsOneWidget,
          );
          expect(find.text('Akses Ditolak (Khusus Owner)'), findsOneWidget);

          await tester.pumpWidget(
            MaterialApp(
              home: PetugasFormScreen(viewModel: masterVm),
            ),
          );
          await _flushIo(tester, rounds: 4);
          expect(find.text('Khusus Owner DepotTelur36'), findsOneWidget);
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );
  });

  group('System Testing - Kasus Salah Input & Ketahanan Error Sistem', () {
    testWidgets(
      'ST-I01 Validasi Auth (SignUp Mismatch/Offline, SignIn Salah Password, Reset Password Offline -> Online)',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(tester);
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign Up'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(SignUpScreen).evaluate().isNotEmpty,
          );

          // 1. Konfirmasi password tidak cocok
          await _enterAuthField(tester, 'Nama Lengkap', 'Pemilik Depot');
          await _enterAuthField(tester, 'Email', 'pemilik@depottelur36.id');
          await _enterAuthField(tester, 'Password', 'Rahasia123');
          await _enterAuthField(tester, 'Konfirmasi Password', 'Beda9999');
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign Up'),
          );
          await _flushIo(tester, rounds: 4);
          expect(find.byType(SignUpScreen), findsOneWidget);
          expect(find.text('Konfirmasi password tidak sama.'), findsWidgets);

          // 2. Coba Sign Up saat Offline -> gagal ramah dengan banner, tidak pindah layar
          harness.connectivity.setOnline(false);
          await _enterAuthField(tester, 'Konfirmasi Password', 'Rahasia123');
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign Up'),
          );
          await _flushIo(tester, rounds: 6);
          expect(find.byType(SignUpScreen), findsOneWidget);
          expect(
            find.textContaining(
              'Pendaftaran akun baru membutuhkan koneksi internet.',
            ),
            findsOneWidget,
          );

          // 3. Pulihkan koneksi -> Sign Up sukses -> langsung Sign Out untuk uji Sign In
          harness.connectivity.setOnline(true);
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Sign Up'),
          );
          await _pumpUntil(
            tester,
            () => find.byType(RoleHomeShellScreen).evaluate().isNotEmpty,
          );
          await _signOutViaUi(tester);

          // 4. Sign In: kosong -> error validasi, password salah -> banner error
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(WelcomeScreen),
              matching: find.widgetWithText(TactilePillButton, 'Sign In'),
            ),
          );
          await _pumpUntil(
            tester,
            () => find.byType(SignInScreen).evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(SignInScreen),
              matching: find.widgetWithText(TactilePillButton, 'Sign In'),
            ),
          );
          await _flushIo(tester, rounds: 3);
          expect(find.byType(SignInScreen), findsOneWidget);

          await _enterAuthField(
            tester,
            'ID Akun atau Email',
            'pemilik@depottelur36.id',
          );
          await _enterAuthField(tester, 'Password', 'PasswordSalah');
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(SignInScreen),
              matching: find.widgetWithText(TactilePillButton, 'Sign In'),
            ),
          );
          await _flushIo(tester, rounds: 6);
          expect(find.byType(SignInScreen), findsOneWidget);
          expect(
            find.text('Email/ID atau password tidak sesuai.'),
            findsOneWidget,
          );

          // 5. Lupa Password saat Offline -> error banner di sheet -> Online -> sukses & tampil banner di SignInScreen
          harness.connectivity.setOnline(false);
          await _tapScrolled(tester, find.text('Lupa Password?'));
          await _pumpUntil(
            tester,
            () => find.text('Kirim Tautan Reset').evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Kirim Tautan Reset'),
          );
          await _flushIo(tester, rounds: 4);
          expect(
            find.text('Reset password membutuhkan koneksi internet.'),
            findsOneWidget,
          );

          harness.connectivity.setOnline(true);
          await _tapScrolled(
            tester,
            find.widgetWithText(TactilePillButton, 'Kirim Tautan Reset'),
          );
          await _pumpUntil(
            tester,
            () => find.text('Kirim Tautan Reset').evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 5);
          expect(harness.gateway.sentResetEmails, ['pemilik@depottelur36.id']);
          expect(
            find.text(
              'Tautan reset password dikirim ke pemilik@depottelur36.id.',
            ),
            findsOneWidget,
          );
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );

    testWidgets(
      'ST-I02 Penolakan Input Master Salah, Atur Harga Rp 0, & Proteksi Hapus Data Terpakai di UI',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(tester);
          await _signUpOwnerViaUi(
            tester,
            harness: harness,
            name: 'Owner Guard',
            email: 'guard@depottelur36.id',
            password: 'Guard!3636',
          );

          // Buat Nota dengan pelanggan default agar berelasi aktif dengan Master Pelanggan
          await _selectBottomTab(tester, 'Nota');
          await _tapScrolled(tester, find.text('+ Nota'));
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isNotEmpty,
          );
          final seededBarangs =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final firstBarang = seededBarangs!.first;
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('kasir_add_${firstBarang.idBarang}')),
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('kasir_submit_nota_button')),
          );
          await _pumpUntil(
            tester,
            () => find.textContaining('berhasil disimpan').evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_back_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // 1. BarangFormScreen salah input -> tetap di layar form dengan pesan jelas -> perbaiki -> simpan
          await _selectBottomTab(tester, 'Master');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(tester, 'barang_nama_field', 'X');
          await _enterKeyField(tester, 'barang_stok_field', '5');
          await _enterKeyField(tester, 'barang_harga_field', '0');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _flushIo(tester, rounds: 4);
          expect(find.byType(BarangFormScreen), findsOneWidget);
          expect(find.text('Nama barang minimal 2 karakter.'), findsOneWidget);
          expect(find.text('Harga satuan harus > Rp 0.'), findsOneWidget);

          await _enterKeyField(tester, 'barang_nama_field', 'Telur Bebek Asin');
          await _enterKeyField(tester, 'barang_harga_field', '4500');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // 2. AturHargaScreen tanpa perubahan & harga 0
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_open_atur_harga_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(AturHargaScreen).evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('atur_harga_save_button')),
          );
          await _flushIo(tester, rounds: 3);
          expect(
            find.text('Ubah minimal satu harga barang terlebih dahulu.'),
            findsOneWidget,
          );

          await _enterKeyField(
            tester,
            'atur_harga_input_${firstBarang.remoteId}',
            '0',
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('atur_harga_save_button')),
          );
          await _flushIo(tester, rounds: 3);
          expect(
            find.textContaining('harus lebih dari Rp 0'),
            findsOneWidget,
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_back_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(AturHargaScreen).evaluate().isEmpty,
          );

          // 3. Proteksi hapus Customer yang sudah punya Nota via dialog konfirmasi Master Data
          final customers =
              await tester.runAsync(() => harness.dbHelper!.getAllCustomer());
          final usedCustomer = customers!.first;
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_category_tab_pelanggan')),
          );
          await _pumpUntil(
            tester,
            () => find
                .byKey(ValueKey('delete_customer_${usedCustomer.remoteId}'))
                .evaluate()
                .isNotEmpty,
          );
          await _flushIo(tester, rounds: 10);
          await _tapScrolled(
            tester,
            find.byKey(ValueKey('delete_customer_${usedCustomer.remoteId}')),
          );
          await _pumpUntil(
            tester,
            () => find
                .byKey(const ValueKey('delete_confirm_submit_button'))
                .evaluate()
                .isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('delete_confirm_submit_button')),
          );
          await _flushIo(tester, rounds: 8);
          expect(find.text(usedCustomer.namaCustomer), findsWidgets);
          expect(
            find.textContaining('tidak dapat dihapus'),
            findsOneWidget,
          );
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );

    testWidgets(
      'ST-I03 Kasir Stok Kosong/Keranjang Kosong, Faktur Duplikat/Kosong, & Validasi Floor Stok Menipis',
      (tester) async {
        final harness = await _SystemAppHarness.create(
          tester: tester,
          initialOnline: true,
        );
        try {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await harness.launchApp(tester);
          await _signUpOwnerViaUi(
            tester,
            harness: harness,
            name: 'Owner EdgeTx',
            email: 'edgetx@depottelur36.id',
            password: 'EdgeTx!3636',
          );

          // Tambah 1 barang stok 0 (kritis + habis) untuk menguji UI Kasir & Stok Menipis
          await _selectBottomTab(tester, 'Master');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_add_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isNotEmpty,
          );
          await _enterKeyField(tester, 'barang_nama_field', 'Telur Kosong Promo');
          await _enterKeyField(tester, 'barang_stok_field', '0');
          await _enterKeyField(tester, 'barang_harga_field', '15000');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(BarangFormScreen).evaluate().isEmpty,
          );
          await _flushIo(tester, rounds: 6);

          final barangs =
              await tester.runAsync(() => harness.dbHelper!.getAllBarang());
          final emptyBarang =
              barangs!.firstWhere((b) => b.namaBarang == 'Telur Kosong Promo');
          final inStockBarang = barangs.firstWhere((b) => b.stokBarang > 0);

          // 1. Uji Kasir Nota: barang stok 0 menampilkan chip 'Habis' non-interaktif & keranjang kosong ditolak
          await _selectBottomTab(tester, 'Nota');
          await _tapScrolled(tester, find.text('+ Nota'));
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isNotEmpty,
          );
          final kasirSearch = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('Cari telur') ?? false),
          );
          await tester.enterText(kasirSearch, 'Telur Kosong');
          await _flushIo(tester, rounds: 4);
          expect(find.text('Habis'), findsOneWidget);
          // Tombol submit nota disembunyikan progresif saat keranjang kosong (pencegahan input kosong)
          expect(
            find.byKey(const ValueKey('kasir_submit_nota_button')),
            findsNothing,
          );
          await tester.tap(find.byKey(const ValueKey('master_search_clear')));
          await _flushIo(tester, rounds: 4);
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('master_header_back_button')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(KasirNotaScreen).evaluate().isEmpty,
          );

          // 2. Uji Stok Menipis floor validation < 1 -> ShakeOnError banner -> auto-clear saat increment
          await _selectBottomTab(tester, 'Beranda');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('home_open_restock_monitor_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(StokMenipisScreen).evaluate().isNotEmpty,
          );
          final decBtn =
              find.byKey(ValueKey('restock_dec_${emptyBarang.remoteId}'));
          final incBtn =
              find.byKey(ValueKey('restock_inc_${emptyBarang.remoteId}'));
          // Turunkan draft restok hingga batas minimum (1 unit) lalu verifikasi pesan validasi
          for (var i = 0; i < 35; i++) {
            if (find
                .text('Jumlah restok "Telur Kosong Promo" minimal 1 Kg.')
                .evaluate()
                .isNotEmpty) {
              break;
            }
            await _tapScrolled(tester, decBtn);
          }
          await _flushIo(tester, rounds: 4);
          expect(
            find.text('Jumlah restok "Telur Kosong Promo" minimal 1 Kg.'),
            findsOneWidget,
          );

          await _tapScrolled(tester, incBtn);
          await _flushIo(tester, rounds: 4);
          expect(
            find.text('Jumlah restok "Telur Kosong Promo" minimal 1 Kg.'),
            findsNothing,
          );

          // 3. Uji Faktur Masuk: kosongkan No Faktur -> validasi gagal, simpan faktur valid lalu coba No Faktur duplikat
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('stok_menipis_new_faktur_btn')),
          );
          await _pumpUntil(
            tester,
            () => find.byType(FakturMasukScreen).evaluate().isNotEmpty,
          );

          // Tambah 1 item dari katalog modal
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_add_catalog_button')),
          );
          await _pumpUntil(
            tester,
            () => find.text('Tambah Barang ke Faktur').evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.text(inStockBarang.namaBarang),
                )
                .first,
          );
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Selesai'),
            ),
          );
          await _flushIo(tester, rounds: 4);

          // Kosongkan No. Faktur -> ditolak
          await _enterKeyField(tester, 'faktur_no_field', '   ');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_submit_button')),
          );
          await _flushIo(tester, rounds: 4);
          expect(find.byType(FakturMasukScreen), findsOneWidget);
          expect(find.textContaining('Nomor faktur'), findsOneWidget);

          // Simpan faktur pertama dengan nomor valid
          await _enterKeyField(tester, 'faktur_no_field', 'FKT-SYS-UNIK-01');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_submit_button')),
          );
          await _pumpUntil(
            tester,
            () => find
                .textContaining('FKT-SYS-UNIK-01 berhasil disimpan')
                .evaluate()
                .isNotEmpty,
          );
          await _flushIo(tester, rounds: 6);

          // Coba buat faktur baru lagi dengan No. Faktur duplikat (case-insensitive)
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_add_catalog_button')),
          );
          await _pumpUntil(
            tester,
            () => find.text('Tambah Barang ke Faktur').evaluate().isNotEmpty,
          );
          await _tapScrolled(
            tester,
            find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.text(inStockBarang.namaBarang),
                )
                .first,
          );
          await _tapScrolled(
            tester,
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text('Selesai'),
            ),
          );
          await _enterKeyField(tester, 'faktur_no_field', 'fkt-sys-unik-01');
          await _tapScrolled(
            tester,
            find.byKey(const ValueKey('faktur_submit_button')),
          );
          await _flushIo(tester, rounds: 6);
          expect(find.byType(FakturMasukScreen), findsOneWidget);
          expect(find.textContaining('sudah terdaftar'), findsOneWidget);

          final fakturs =
              await tester.runAsync(() => harness.dbHelper!.getAllFaktur());
          expect(fakturs!.length, 1);
        } finally {
          await harness.disposeAll(tester);
        }
      },
    );
  });
}
