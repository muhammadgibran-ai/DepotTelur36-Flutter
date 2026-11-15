import 'dart:io';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeCloudAccount {
  _FakeCloudAccount({
    required this.uid,
    required this.email,
    required this.password,
    required this.displayName,
  });

  final String uid;
  final String email;
  final String password;
  final String displayName;
}

class _FakeAuthGateway implements AuthGateway {
  final Map<String, _FakeCloudAccount> accountsByEmail = {};
  final Map<String, Petugas> cloudPetugasByEmail = {};
  final List<String> resetEmailsSent = [];
  int findByEmailCallsBeforeCreate = 0;

  AuthAccountSnapshot? _currentUser;
  AuthAccountSnapshot googleSignInResult = const AuthAccountSnapshot(
    uid: 'google-uid-1',
    email: 'google.kasir@depottelur36.com',
    displayName: 'Google Kasir',
    provider: AuthProviderType.google,
  );
  bool cancelGoogleSignIn = false;
  bool throwNetworkOnSignIn = false;
  bool throwNetworkOnLookup = false;
  bool throwOnUpsertProfile = false;
  bool throwUserNotFoundOnReset = false;
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
    if (accountsByEmail.containsKey(normalized)) {
      throw const AuthGatewayException(
        AuthFailureCode.emailAlreadyInUse,
        'Email sudah terdaftar.',
      );
    }
    final uid = 'uid-${_uidSeq++}';
    accountsByEmail[normalized] = _FakeCloudAccount(
      uid: uid,
      email: normalized,
      password: password,
      displayName: fullName,
    );
    _currentUser = AuthAccountSnapshot(
      uid: uid,
      email: normalized,
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
    if (throwNetworkOnSignIn) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Jaringan tidak stabil.',
      );
    }
    final normalized = email.trim().toLowerCase();
    final found = accountsByEmail[normalized];
    if (found == null) {
      throw const AuthGatewayException(
        AuthFailureCode.userNotFound,
        'Akun tidak ditemukan di server.',
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
      displayName: found.displayName,
      provider: AuthProviderType.emailPassword,
    );
    return _currentUser!;
  }

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() async {
    if (cancelGoogleSignIn) {
      throw const AuthGatewayException(
        AuthFailureCode.cancelled,
        'Login Google dibatalkan.',
      );
    }
    _currentUser = googleSignInResult;
    return googleSignInResult;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (throwUserNotFoundOnReset) {
      throw const AuthGatewayException(
        AuthFailureCode.userNotFound,
        'Akun tidak ditemukan.',
      );
    }
    resetEmailsSent.add(email.trim().toLowerCase());
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  @override
  Future<Petugas?> findPetugasByEmail(String email) async {
    if (_currentUser == null) {
      findByEmailCallsBeforeCreate++;
    }
    if (throwNetworkOnLookup) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Firestore tidak dapat dihubungi.',
      );
    }
    return cloudPetugasByEmail[email.trim().toLowerCase()];
  }

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    if (throwNetworkOnLookup) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Firestore tidak dapat dihubungi.',
      );
    }
    final clean = identifier.trim().toLowerCase();
    for (final p in cloudPetugasByEmail.values) {
      if (p.email.toLowerCase() == clean ||
          p.accountId.toLowerCase() == clean ||
          p.remoteId.toLowerCase() == clean) {
        return p;
      }
    }
    return null;
  }

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {
    if (throwOnUpsertProfile) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Gagal mengunggah profil ke Firestore.',
      );
    }
    if (petugas.email.isNotEmpty) {
      cloudPetugasByEmail[petugas.email.toLowerCase()] = petugas;
    }
  }
}

Matcher _throwsAuthCode(AuthFailureCode code) => throwsA(
      isA<AuthGatewayException>().having((e) => e.code, 'code', code),
    );

Future<void> _insertLegacySeedFixtures(DatabaseHelper dbHelper) async {
  final now = DateTime(2026, 2, 16);
  await dbHelper.upsertPetugas(
    Petugas(
      namaPetugas: 'Owner DepotTelur36',
      role: UserRole.owner,
      pin: '1234',
      email: 'owner@depottelur36.com',
      accountId: 'owner01',
      remoteId: 'seed-petugas-owner',
      syncStatus: SyncStatus.synced,
      updatedAt: now,
    ),
  );
  await dbHelper.upsertPetugas(
    Petugas(
      namaPetugas: 'Petugas Kasir & Gudang',
      role: UserRole.petugas,
      pin: '1111',
      email: 'kasir@depottelur36.com',
      accountId: 'kasir01',
      remoteId: 'seed-petugas-kasir-1',
      syncStatus: SyncStatus.synced,
      updatedAt: now,
    ),
  );
}

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late _FakeAuthGateway gateway;
  late bool isOnline;
  late SharedPreferences prefs;
  late AuthRepository repository;
  var dbSeq = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempDir = Directory.systemTemp.createTempSync('depot_telur_auth_repo_');
    dbHelper = DatabaseHelper.forTesting(
      customDbPath: p.join(tempDir.path, 'auth_test_${dbSeq++}.db'),
    );
    await dbHelper.database;

    gateway = _FakeAuthGateway();
    isOnline = true;
    repository = AuthRepository(
      dbHelper: dbHelper,
      gateway: gateway,
      prefs: prefs,
      isOnlineChecker: () async => isOnline,
    );
  });

  tearDown(() async {
    final db = await dbHelper.database;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AuthRepository Validations (Normal, Edge & Salah Input)', () {
    test('validator menerima format valid termasuk tag plus, subdomain & passphrase berspasi', () {
      expect(AuthRepository.isValidEmail('siti@depottelur36.com'), isTrue);
      expect(
        AuthRepository.isValidEmail('  Siti+kasir_1@sub.depot.co.id  '),
        isTrue,
      );
      expect(AuthRepository.validateSignUpFullName('  Bo  '), isNull);
      expect(AuthRepository.validateNewPassword('depot telur 36'), isNull);
      expect(
        AuthRepository.validateConfirmPassword('secret12', 'secret12'),
        isNull,
      );
    });

    test('validator menolak berbagai format email salah atau malformed', () {
      const invalidEmails = [
        '',
        '   ',
        'bukan-email',
        '@domain.com',
        'user@',
        'user@domain',
        'user@domain.c',
        'user@domain.com.',
        'user@domain..com',
        'user..name@domain.com',
        '.user@domain.com',
        'user.@domain.com',
        'user@.domain.com',
        'user@-domain.com',
        'user@domain-.com',
        'user@domain.123',
        'user name@domain.com',
      ];
      for (final bad in invalidEmails) {
        expect(
          AuthRepository.isValidEmail(bad),
          isFalse,
          reason: 'Seharusnya menolak email invalid: "$bad"',
        );
        expect(
          AuthRepository.validateSignUpEmail(bad),
          isNotNull,
          reason: 'validateSignUpEmail harus menolak "$bad"',
        );
      }
    });

    test('validator menolak password spasi saja, karakter kontrol, dan konfirmasi tidak cocok', () {
      expect(AuthRepository.validatePassword(''), isNotNull);
      expect(AuthRepository.validatePassword('    '), isNotNull);
      expect(AuthRepository.validateNewPassword('      '), isNotNull);
      expect(AuthRepository.validateNewPassword('12345'), isNotNull);
      expect(AuthRepository.validateSignUpFullName(''), isNotNull);
      expect(AuthRepository.validateSignUpFullName('A'), isNotNull);
      expect(AuthRepository.validateSignUpFullName('Budi\nAdmin'), isNotNull);
      expect(AuthRepository.validateSignInIdentifier('   '), isNotNull);
      expect(
        AuthRepository.validateSignInIdentifier('owner01\t'),
        isNotNull,
      );
      expect(
        AuthRepository.validateConfirmPassword('rahasia1', ''),
        isNotNull,
      );
      expect(
        AuthRepository.validateConfirmPassword('rahasia1', '   '),
        isNotNull,
      );
      expect(
        AuthRepository.validateConfirmPassword('rahasia1', 'rahasia2'),
        isNotNull,
      );
    });

    test('menolak input registrasi & login tidak valid sebelum memanggil gateway', () async {
      await expectLater(
        () => repository.signUpWithEmail(
          fullName: 'A',
          email: 'bukan-email',
          password: '123',
          confirmPassword: '321',
        ),
        _throwsAuthCode(AuthFailureCode.validation),
      );
      await expectLater(
        () => repository.signUpWithEmail(
          fullName: 'Kasir Valid',
          email: 'kasir@domain.com.',
          password: '      ',
          confirmPassword: '      ',
        ),
        _throwsAuthCode(AuthFailureCode.validation),
      );
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: '   ',
          password: 'password123',
        ),
        _throwsAuthCode(AuthFailureCode.validation),
      );
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'owner01',
          password: '    ',
        ),
        _throwsAuthCode(AuthFailureCode.validation),
      );
    });

    test('menolak Sign Up saat offline', () async {
      isOnline = false;
      await expectLater(
        () => repository.signUpWithEmail(
          fullName: 'Siti Kasir',
          email: 'siti@depottelur36.com',
          password: 'password123',
          confirmPassword: 'password123',
        ),
        _throwsAuthCode(AuthFailureCode.networkUnavailable),
      );
    });
  });

  group('AuthRepository Sign Up & Role Assignment', () {
    test('Sign Up membuat akun dengan peran default PETUGAS, men-trim input & cache hash SQLite', () async {
      final session = await repository.signUpWithEmail(
        fullName: '  Siti Kasir  ',
        email: '  Siti@DepotTelur36.com  ',
        password: 'password123',
        confirmPassword: 'password123',
      );

      expect(session.role, UserRole.petugas);
      expect(session.email, 'siti@depottelur36.com');
      expect(session.accountId, 'siti');
      expect(session.displayName, 'Siti Kasir');
      expect(session.provider, AuthProviderType.emailPassword);
      expect(gateway.findByEmailCallsBeforeCreate, 0);

      final localPetugas = await dbHelper.getPetugasByEmail('siti@depottelur36.com');
      expect(localPetugas, isNotNull);
      expect(localPetugas!.passwordHash, isNotEmpty);
      expect(localPetugas.role, UserRole.petugas);
      expect(localPetugas.syncStatus, SyncStatus.synced);

      final restored = await repository.restoreSession();
      expect(restored?.email, 'siti@depottelur36.com');
    });

    test('Sign Up dengan email OWNER dari cloud Firestore mempertahankan role OWNER', () async {
      gateway.cloudPetugasByEmail['bos@depottelur36.com'] = Petugas(
        namaPetugas: 'Pak Bos',
        role: UserRole.owner,
        pin: '9999',
        email: 'bos@depottelur36.com',
        accountId: 'bos01',
        remoteId: 'ptg-bos-cloud',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      );

      final session = await repository.signUpWithEmail(
        fullName: 'Pak Bos',
        email: 'bos@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      expect(session.role, UserRole.owner);
      expect(session.accountId, 'bos01');
      expect(session.petugasRemoteId, 'ptg-bos-cloud');
    });

    test('Sign Up dengan email duplikat menolak dengan emailAlreadyInUse', () async {
      await repository.signUpWithEmail(
        fullName: 'Siti Kasir',
        email: 'siti@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await repository.signOut();

      await expectLater(
        () => repository.signUpWithEmail(
          fullName: 'Siti Lain',
          email: 'SITI@depottelur36.com',
          password: 'password456',
          confirmPassword: 'password456',
        ),
        _throwsAuthCode(AuthFailureCode.emailAlreadyInUse),
      );
    });

    test('Dua akun dengan prefix email sama tidak bentrok accountId dan bisa login masing-masing', () async {
      final first = await repository.signUpWithEmail(
        fullName: 'Siti Pertama',
        email: 'siti@gmail.com',
        password: 'password111',
        confirmPassword: 'password111',
      );
      await repository.signOut();

      final second = await repository.signUpWithEmail(
        fullName: 'Siti Kedua',
        email: 'siti@yahoo.com',
        password: 'password222',
        confirmPassword: 'password222',
      );
      await repository.signOut();

      expect(first.accountId, 'siti');
      expect(second.accountId, 'siti_2');

      final loginSecond = await repository.signInWithIdentifier(
        identifier: 'siti_2',
        password: 'password222',
      );
      expect(loginSecond.email, 'siti@yahoo.com');
    });
  });

  group('AuthRepository Sign In (Online, Offline, Edge & Security Regressions)', () {
    test('Sign In dengan ID Akun case-insensitive & dilanjutkan login offline memakai hash ter-cache', () async {
      await repository.signUpWithEmail(
        fullName: 'Andi Gudang',
        email: 'andi.gudang@depottelur36.com',
        password: 'rahasia654',
        confirmPassword: 'rahasia654',
      );
      await repository.signOut();

      // Login online memakai ID Akun dengan spasi & huruf besar
      final onlineSession = await repository.signInWithIdentifier(
        identifier: '  ANDI.GUDANG  ',
        password: 'rahasia654',
      );
      expect(onlineSession.provider, AuthProviderType.emailPassword);
      expect(onlineSession.displayName, 'Andi Gudang');

      await repository.signOut();
      isOnline = false;

      // Login offline memakai ID Akun & password persis
      final offlineSession = await repository.signInWithIdentifier(
        identifier: 'andi.gudang',
        password: 'rahasia654',
      );
      expect(offlineSession.provider, AuthProviderType.offlineLocal);
      expect(offlineSession.email, 'andi.gudang@depottelur36.com');
      expect(offlineSession.role, UserRole.petugas);

      // Login offline case-sensitive & spasi pada password tetap ditolak
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'andi.gudang',
          password: 'Rahasia654',
        ),
        _throwsAuthCode(AuthFailureCode.invalidCredentials),
      );
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'andi.gudang',
          password: ' rahasia654',
        ),
        _throwsAuthCode(AuthFailureCode.invalidCredentials),
      );
    });

    test('Login saat gateway melempar networkUnavailable otomatis fallback ke verifikasi offline SQLite', () async {
      await repository.signUpWithEmail(
        fullName: 'Dewi Kasir',
        email: 'dewi@depottelur36.com',
        password: 'password789',
        confirmPassword: 'password789',
      );
      await repository.signOut();

      gateway.throwNetworkOnSignIn = true;
      final session = await repository.signInWithIdentifier(
        identifier: 'dewi@depottelur36.com',
        password: 'password789',
      );
      expect(session.provider, AuthProviderType.offlineLocal);
      expect(session.email, 'dewi@depottelur36.com');
    });

    test('Bila sync profil cloud gagal saat Sign In, SQLite menyimpan syncStatus PENDING', () async {
      await repository.signUpWithEmail(
        fullName: 'Budi Kasir',
        email: 'budi@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await repository.signOut();

      gateway.throwOnUpsertProfile = true;
      await repository.signInWithIdentifier(
        identifier: 'budi@depottelur36.com',
        password: 'password123',
      );

      final local = await dbHelper.getPetugasByEmail('budi@depottelur36.com');
      expect(local?.syncStatus, SyncStatus.pending);
    });

    test('DatabaseHelper awal tidak menyisipkan akun testing pada tabel petugas dan migrasi v2->v3 membersihkannya aman terhadap FK', () async {
      expect(await dbHelper.getAllPetugas(), isEmpty);
      expect(await dbHelper.getAllBarang(), isNotEmpty);
      expect(await dbHelper.getAllSupplier(), isNotEmpty);
      expect(await dbHelper.getAllCustomer(), isNotEmpty);

      // Simulasikan database versi 2 yang masih berisi akun testing + faktur/nota terhubung FK
      final legacyPath = p.join(tempDir.path, 'legacy_v2.db');
      final legacyDb = await openDatabase(
        legacyPath,
        version: 2,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE supplier (
              id_supplier INTEGER PRIMARY KEY AUTOINCREMENT,
              nama_supplier TEXT NOT NULL,
              alamat_supplier TEXT NOT NULL DEFAULT '',
              no_telp_supplier TEXT NOT NULL DEFAULT '',
              remote_id TEXT NOT NULL UNIQUE,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE petugas (
              id_petugas INTEGER PRIMARY KEY AUTOINCREMENT,
              nama_petugas TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'PETUGAS',
              pin TEXT NOT NULL DEFAULT '1234',
              email TEXT NOT NULL DEFAULT '',
              account_id TEXT NOT NULL DEFAULT '',
              password_hash TEXT NOT NULL DEFAULT '',
              remote_id TEXT NOT NULL UNIQUE,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE customer (
              id_customer INTEGER PRIMARY KEY AUTOINCREMENT,
              nama_customer TEXT NOT NULL,
              remote_id TEXT NOT NULL UNIQUE,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE barang (
              id_barang INTEGER PRIMARY KEY AUTOINCREMENT,
              nama_barang TEXT NOT NULL,
              stok_barang INTEGER NOT NULL DEFAULT 0,
              satuan TEXT NOT NULL,
              harga_satuan REAL NOT NULL DEFAULT 0.0,
              remote_id TEXT NOT NULL UNIQUE,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE faktur (
              id_faktur INTEGER PRIMARY KEY AUTOINCREMENT,
              no_faktur TEXT NOT NULL,
              tanggal_faktur TEXT NOT NULL,
              total REAL NOT NULL DEFAULT 0.0,
              id_supplier INTEGER NOT NULL,
              id_petugas INTEGER NOT NULL,
              remote_id TEXT NOT NULL UNIQUE,
              supplier_remote_id TEXT,
              petugas_remote_id TEXT,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL,
              FOREIGN KEY (id_supplier) REFERENCES supplier (id_supplier) ON UPDATE CASCADE ON DELETE RESTRICT,
              FOREIGN KEY (id_petugas) REFERENCES petugas (id_petugas) ON UPDATE CASCADE ON DELETE RESTRICT
            )
          ''');
          await db.execute('''
            CREATE TABLE detail_faktur (
              id_faktur INTEGER NOT NULL,
              id_barang INTEGER NOT NULL,
              jumlah REAL NOT NULL DEFAULT 0.0,
              quantity INTEGER NOT NULL,
              barang_remote_id TEXT,
              PRIMARY KEY (id_faktur, id_barang),
              FOREIGN KEY (id_faktur) REFERENCES faktur (id_faktur) ON UPDATE CASCADE ON DELETE CASCADE,
              FOREIGN KEY (id_barang) REFERENCES barang (id_barang) ON UPDATE CASCADE ON DELETE RESTRICT
            )
          ''');
          await db.execute('''
            CREATE TABLE nota (
              id_nota INTEGER PRIMARY KEY AUTOINCREMENT,
              tanggal_nota TEXT NOT NULL,
              total REAL NOT NULL DEFAULT 0.0,
              id_petugas INTEGER NOT NULL,
              id_customer INTEGER NOT NULL,
              remote_id TEXT NOT NULL UNIQUE,
              petugas_remote_id TEXT,
              customer_remote_id TEXT,
              sync_status TEXT NOT NULL DEFAULT 'PENDING',
              updated_at TEXT NOT NULL,
              FOREIGN KEY (id_petugas) REFERENCES petugas (id_petugas) ON UPDATE CASCADE ON DELETE RESTRICT,
              FOREIGN KEY (id_customer) REFERENCES customer (id_customer) ON UPDATE CASCADE ON DELETE RESTRICT
            )
          ''');
          await db.execute('''
            CREATE TABLE detail_nota (
              id_nota INTEGER NOT NULL,
              id_barang INTEGER NOT NULL,
              jumlah REAL NOT NULL DEFAULT 0.0,
              banyaknya INTEGER NOT NULL,
              barang_remote_id TEXT,
              PRIMARY KEY (id_nota, id_barang),
              FOREIGN KEY (id_nota) REFERENCES nota (id_nota) ON UPDATE CASCADE ON DELETE CASCADE,
              FOREIGN KEY (id_barang) REFERENCES barang (id_barang) ON UPDATE CASCADE ON DELETE RESTRICT
            )
          ''');

          final supId = await db.insert('supplier', {
            'nama_supplier': 'Supplier A',
            'remote_id': 'seed-supplier-1',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
          final custId = await db.insert('customer', {
            'nama_customer': 'Umum',
            'remote_id': 'seed-customer-umum',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
          final ownerId = await db.insert('petugas', {
            'nama_petugas': 'Owner DepotTelur36',
            'role': 'OWNER',
            'pin': '1234',
            'email': 'owner@depottelur36.com',
            'account_id': 'owner01',
            'password_hash': '',
            'remote_id': 'seed-petugas-owner',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
          await db.insert('petugas', {
            'nama_petugas': 'User Real',
            'role': 'PETUGAS',
            'pin': '1111',
            'email': 'real@depottelur36.com',
            'account_id': 'real',
            'password_hash': 'salt:hash',
            'remote_id': 'uid-real-1',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
          await db.insert('faktur', {
            'no_faktur': 'FKT-1',
            'tanggal_faktur': '2026-02-16',
            'total': 1000.0,
            'id_supplier': supId,
            'id_petugas': ownerId,
            'remote_id': 'seed-faktur-contoh-1',
            'supplier_remote_id': 'seed-supplier-1',
            'petugas_remote_id': 'seed-petugas-owner',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
          await db.insert('nota', {
            'tanggal_nota': '2026-02-16',
            'total': 1000.0,
            'id_petugas': ownerId,
            'id_customer': custId,
            'remote_id': 'seed-nota-contoh-1',
            'petugas_remote_id': 'seed-petugas-owner',
            'customer_remote_id': 'seed-customer-umum',
            'sync_status': 'SYNCED',
            'updated_at': '2026-02-16T00:00:00.000',
          });
        },
      );
      await legacyDb.close();

      final upgradedHelper = DatabaseHelper.forTesting(customDbPath: legacyPath);
      try {
        final remainingPetugas = await upgradedHelper.getAllPetugas();
        expect(remainingPetugas.map((p) => p.remoteId), ['uid-real-1']);
        expect(await upgradedHelper.getAllFaktur(), isEmpty);
        expect(await upgradedHelper.getAllNota(), isEmpty);
      } finally {
        await upgradedHelper.close();
      }
    });

    test('Seeded owner01 & kasir01 mendukung login memakai PIN bawaan saat belum termigrasi ke Firebase', () async {
      await _insertLegacySeedFixtures(dbHelper);
      final ownerSession = await repository.signInWithIdentifier(
        identifier: 'owner01',
        password: '1234',
      );
      expect(ownerSession.role, UserRole.owner);
      expect(ownerSession.accountId, 'owner01');
      expect(ownerSession.provider, AuthProviderType.offlineLocal);

      await repository.signOut();
      isOnline = false;

      final kasirSession = await repository.signInWithIdentifier(
        identifier: 'kasir@depottelur36.com',
        password: '1111',
      );
      expect(kasirSession.role, UserRole.petugas);
      expect(kasirSession.accountId, 'kasir01');

      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'owner01',
          password: '9999',
        ),
        _throwsAuthCode(AuthFailureCode.invalidCredentials),
      );
    });

    test('REGRESSION Celah #1: Seed Owner yang sudah terdaftar di Cloud atau login Google tidak bisa ditembus PIN default 1234', () async {
      await _insertLegacySeedFixtures(dbHelper);
      // Skenario A: akun Owner sudah eksis di Cloud dengan password kuat
      gateway.accountsByEmail['owner@depottelur36.com'] = _FakeCloudAccount(
        uid: 'uid-real-owner',
        email: 'owner@depottelur36.com',
        password: 'PasswordKuatOwner!',
        displayName: 'Owner Asli',
      );
      gateway.cloudPetugasByEmail['owner@depottelur36.com'] = Petugas(
        namaPetugas: 'Owner Asli',
        role: UserRole.owner,
        pin: '1234',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        remoteId: 'seed-petugas-owner',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      );

      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'owner01',
          password: '1234',
        ),
        _throwsAuthCode(AuthFailureCode.invalidCredentials),
      );

      // Skenario B: akun Kasir seed tertaut lewat Google Sign-In lalu dicoba offline pakai PIN '1111'
      gateway.googleSignInResult = const AuthAccountSnapshot(
        uid: 'google-kasir-uid',
        email: 'kasir@depottelur36.com',
        displayName: 'Kasir Google',
        provider: AuthProviderType.google,
      );
      await repository.signInWithGoogle();
      await repository.signOut();

      isOnline = false;
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'kasir01',
          password: '1111',
        ),
        _throwsAuthCode(AuthFailureCode.invalidCredentials),
      );
    });

    test('REGRESSION Celah #2: Kegagalan membaca Firestore saat Sign In perangkat baru tidak menurunkan role OWNER menjadi PETUGAS', () async {
      gateway.accountsByEmail['owner.cloud@depottelur36.com'] = _FakeCloudAccount(
        uid: 'uid-owner-cloud',
        email: 'owner.cloud@depottelur36.com',
        password: 'passwordOwner123',
        displayName: 'Owner Cloud',
      );
      gateway.cloudPetugasByEmail['owner.cloud@depottelur36.com'] = Petugas(
        namaPetugas: 'Owner Cloud',
        role: UserRole.owner,
        pin: '9999',
        email: 'owner.cloud@depottelur36.com',
        accountId: 'ownercloud',
        remoteId: 'uid-owner-cloud',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      );
      gateway.throwNetworkOnLookup = true;

      await repository.signInWithIdentifier(
        identifier: 'owner.cloud@depottelur36.com',
        password: 'passwordOwner123',
      );

      // Dokumen OWNER di cloud tidak boleh tertimpa menjadi PETUGAS
      expect(
        gateway.cloudPetugasByEmail['owner.cloud@depottelur36.com']?.role,
        UserRole.owner,
      );

      // Pencarian ID Akun perangkat baru saat Firestore error memunculkan networkUnavailable (bukan userNotFound)
      await repository.signOut();
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'id_tidak_ada_di_perangkat',
          password: 'password123',
        ),
        _throwsAuthCode(AuthFailureCode.networkUnavailable),
      );
    });

    test('REGRESSION Celah #3: Nama lengkap tidak bisa membajak ID Akun & upsert email sama tidak menduplikasi baris SQLite', () async {
      await _insertLegacySeedFixtures(dbHelper);
      await repository.signUpWithEmail(
        fullName: 'owner01',
        email: 'penipu@depottelur36.com',
        password: 'passwordPenipu123',
        confirmPassword: 'passwordPenipu123',
      );
      await repository.signOut();

      // Lookup 'owner01' harus tetap mengarah ke Owner asli, bukan penipu
      final targetReset = await repository.sendPasswordReset('owner01');
      expect(targetReset, 'owner@depottelur36.com');

      // Mengetik Nama Lengkap pada login harus ditolak karena bukan ID Akun atau Email
      await repository.signUpWithEmail(
        fullName: 'Nama Saja',
        email: 'namasaja@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      await repository.signOut();

      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'Nama Saja',
          password: 'password123',
        ),
        _throwsAuthCode(AuthFailureCode.userNotFound),
      );

      // Upsert profil dengan remoteId baru untuk email existing tidak membuat duplikat
      await dbHelper.upsertPetugas(
        Petugas(
          namaPetugas: 'Kasir Updated',
          role: UserRole.petugas,
          pin: '1111',
          email: 'kasir@depottelur36.com',
          accountId: 'kasir01',
          remoteId: 'uid-baru-kasir',
          syncStatus: SyncStatus.synced,
          updatedAt: DateTime(2026, 2, 17),
        ),
      );
      final allRows = await dbHelper.getAllPetugas();
      final matches = allRows
          .where((e) => e.email.toLowerCase() == 'kasir@depottelur36.com')
          .toList();
      expect(matches, hasLength(1));
      expect(matches.first.remoteId, 'uid-baru-kasir');
    });

    test('Login offline akun yang belum pernah ada di perangkat gagal dengan pesan butuh internet', () async {
      isOnline = false;
      await expectLater(
        () => repository.signInWithIdentifier(
          identifier: 'belum.terdaftar@depottelur36.com',
          password: 'password123',
        ),
        _throwsAuthCode(AuthFailureCode.networkUnavailable),
      );
    });
  });

  group('AuthRepository Google Sign-In, Reset Password & Session', () {
    test('Google Sign-In mempertahankan role OWNER & menjaga passwordHash lama akun email', () async {
      await repository.signUpWithEmail(
        fullName: 'Kasir Tetap',
        email: 'tetap@depottelur36.com',
        password: 'passwordLama123',
        confirmPassword: 'passwordLama123',
      );
      await repository.signOut();

      gateway.googleSignInResult = const AuthAccountSnapshot(
        uid: 'google-tetap-uid',
        email: 'tetap@depottelur36.com',
        displayName: '',
        provider: AuthProviderType.google,
      );
      final linkedSession = await repository.signInWithGoogle();
      expect(linkedSession.displayName, 'Kasir Tetap');
      expect(linkedSession.provider, AuthProviderType.google);

      // Password offline lama masih tetap valid setelah login Google
      await repository.signOut();
      isOnline = false;
      final offline = await repository.signInWithIdentifier(
        identifier: 'tetap@depottelur36.com',
        password: 'passwordLama123',
      );
      expect(offline.provider, AuthProviderType.offlineLocal);

      // Google Sign-In untuk Owner terdaftar di Cloud
      isOnline = true;
      gateway.cloudPetugasByEmail['owner@depottelur36.com'] = Petugas(
        namaPetugas: 'Owner Toko',
        role: UserRole.owner,
        pin: '1234',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        remoteId: 'google-owner-uid',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      );
      gateway.googleSignInResult = const AuthAccountSnapshot(
        uid: 'google-owner-uid',
        email: 'owner@depottelur36.com',
        displayName: 'Owner Toko',
        provider: AuthProviderType.google,
      );

      final ownerSession = await repository.signInWithGoogle();
      expect(ownerSession.role, UserRole.owner);
      expect(ownerSession.provider, AuthProviderType.google);
    });

    test('Google Sign-In offline, dibatalkan, atau data Google kosong ditolak sesuai kode', () async {
      isOnline = false;
      await expectLater(
        () => repository.signInWithGoogle(),
        _throwsAuthCode(AuthFailureCode.networkUnavailable),
      );

      isOnline = true;
      gateway.cancelGoogleSignIn = true;
      await expectLater(
        () => repository.signInWithGoogle(),
        _throwsAuthCode(AuthFailureCode.cancelled),
      );

      gateway.cancelGoogleSignIn = false;
      gateway.googleSignInResult = const AuthAccountSnapshot(
        uid: '',
        email: '',
        displayName: 'Tanpa Email',
        provider: AuthProviderType.google,
      );
      await expectLater(
        () => repository.signInWithGoogle(),
        _throwsAuthCode(AuthFailureCode.configuration),
      );
    });

    test('sendPasswordReset menangani input normal, offline, tidak dikenal, dan propagasi error gateway', () async {
      await expectLater(
        () => repository.sendPasswordReset('   '),
        _throwsAuthCode(AuthFailureCode.validation),
      );

      isOnline = false;
      await expectLater(
        () => repository.sendPasswordReset('kasir01'),
        _throwsAuthCode(AuthFailureCode.networkUnavailable),
      );

      isOnline = true;
      await expectLater(
        () => repository.sendPasswordReset('akun_tidak_terdaftar'),
        _throwsAuthCode(AuthFailureCode.validation),
      );

      await _insertLegacySeedFixtures(dbHelper);
      final resolvedById = await repository.sendPasswordReset('  KASIR01 ');
      expect(resolvedById, 'kasir@depottelur36.com');

      final resolvedByEmail = await repository.sendPasswordReset('  Boss@DepotTelur36.COM ');
      expect(resolvedByEmail, 'boss@depottelur36.com');
      expect(
        gateway.resetEmailsSent,
        ['kasir@depottelur36.com', 'boss@depottelur36.com'],
      );

      gateway.throwUserNotFoundOnReset = true;
      await expectLater(
        () => repository.sendPasswordReset('kosong@depottelur36.com'),
        _throwsAuthCode(AuthFailureCode.userNotFound),
      );
    });

    test('restoreSession menyegarkan role, nama & accountId dari SQLite, aman dari JSON korup & signOut membersihkan sesi', () async {
      await prefs.setString(AuthRepository.sessionStorageKey, '{rusak');
      expect(await repository.restoreSession(), isNull);

      await repository.signUpWithEmail(
        fullName: 'Rina Kasir',
        email: 'rina@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );

      final existing = await dbHelper.getPetugasByEmail('rina@depottelur36.com');
      expect(existing, isNotNull);
      await dbHelper.upsertPetugas(
        existing!.copyWith(
          role: UserRole.owner,
          namaPetugas: 'Rina Owner',
          accountId: 'rina_owner',
        ),
      );

      final refreshed = await repository.restoreSession();
      expect(refreshed?.role, UserRole.owner);
      expect(refreshed?.displayName, 'Rina Owner');
      expect(refreshed?.accountId, 'rina_owner');

      // Verifikasi perubahan accountId benar-benar tersimpan ke SharedPreferences
      final storedAfter = AuthSession.tryParseJson(
        prefs.getString(AuthRepository.sessionStorageKey),
      );
      expect(storedAfter?.accountId, 'rina_owner');

      await repository.signOut();
      expect(await repository.restoreSession(), isNull);
      expect(gateway.currentUser, isNull);
    });
  });
}
