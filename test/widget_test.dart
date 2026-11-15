import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/main.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_shell_screen.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/dashboard_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _WidgetFakeAuthGateway implements AuthGateway {
  final Map<String, Petugas> _cloudProfiles = {};
  final Map<String, String> _passwords = {};
  final List<String> sentResetEmails = [];

  AuthAccountSnapshot? _currentUser;
  Completer<void>? pendingSignInGate;
  int _seq = 1;

  @override
  AuthAccountSnapshot? get currentUser => _currentUser;

  @override
  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    _passwords[normalized] = password;
    _currentUser = AuthAccountSnapshot(
      uid: 'uid-widget-${_seq++}',
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
    if (pendingSignInGate != null && !pendingSignInGate!.isCompleted) {
      await pendingSignInGate!.future;
    }
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
        'Password salah.',
      );
    }
    _currentUser = AuthAccountSnapshot(
      uid: 'uid-widget-signin',
      email: normalized,
      displayName: normalized.split('@').first,
      provider: AuthProviderType.emailPassword,
    );
    return _currentUser!;
  }

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() async {
    _currentUser = const AuthAccountSnapshot(
      uid: 'google-widget-uid',
      email: 'kasir.google@depottelur36.com',
      displayName: 'Kasir Google',
      provider: AuthProviderType.google,
    );
    return _currentUser!;
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
  Future<Petugas?> findPetugasByEmail(String email) async =>
      _cloudProfiles[email.trim().toLowerCase()];

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    final clean = identifier.trim().toLowerCase();
    for (final p in _cloudProfiles.values) {
      if (p.email.toLowerCase() == clean ||
          p.accountId.toLowerCase() == clean) {
        return p;
      }
    }
    return null;
  }

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {
    if (petugas.email.isNotEmpty) {
      _cloudProfiles[petugas.email.toLowerCase()] = petugas;
    }
  }
}

class _WidgetFakeSyncService extends SyncService {
  _WidgetFakeSyncService({required super.dbHelper})
      : super(
          firestore: _WidgetDummyFirestore(),
          connectivity: _WidgetDummyConnectivity(),
        );

  int manualSyncCalls = 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> trySyncIfOnline() async {}

  @override
  Future<void> syncNow() async {
    manualSyncCalls++;
  }
}

class _WidgetDummyFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _WidgetDummyConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.wifi];
}

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late _WidgetFakeAuthGateway gateway;
  late _WidgetFakeSyncService syncService;
  late InventoryRepository inventoryRepository;
  late SharedPreferences prefs;
  late AuthRepository repository;
  late AuthViewModel viewModel;
  var dbCounter = 0;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempDir = Directory.systemTemp.createTempSync('depot_telur_widget_test_');
    dbHelper = DatabaseHelper.forTesting(
      customDbPath: p.join(tempDir.path, 'widget_${dbCounter++}.db'),
    );
    await dbHelper.database;

    gateway = _WidgetFakeAuthGateway();
    syncService = _WidgetFakeSyncService(dbHelper: dbHelper);
    inventoryRepository = InventoryRepository(
      dbHelper: dbHelper,
      syncService: syncService,
    );
    repository = AuthRepository(
      dbHelper: dbHelper,
      gateway: gateway,
      prefs: prefs,
      isOnlineChecker: () async => true,
    );
    viewModel = AuthViewModel(repository: repository);
  });

  tearDown(() async {
    viewModel.dispose();
    await inventoryRepository.dispose();
    final db = await dbHelper.database;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget wrapScreen(Widget screen, {bool disableAnimations = false}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SyncService>.value(value: syncService),
        Provider<InventoryRepository>.value(value: inventoryRepository),
        ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
            ),
            child: child!,
          );
        },
        home: screen,
      ),
    );
  }

  Future<void> settleWithIo(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (!viewModel.isAnyBusy &&
          viewModel.status != AuthStatus.initializing) {
        break;
      }
    }
    if (viewModel.isAnyBusy || viewModel.status == AuthStatus.initializing) {
      fail(
        'Timed out waiting IO: status=${viewModel.status}, '
        'submitting=${viewModel.isSubmitting}, '
        'google=${viewModel.isGoogleLoading}, '
        'reset=${viewModel.isResettingPassword}, '
        'error=${viewModel.errorMessage}',
      );
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      DepotTelur36App(
        authViewModelOverride: viewModel,
        inventoryRepositoryOverride: inventoryRepository,
        splashDelay: Duration.zero,
      ),
    );
    await settleWithIo(tester);
  }

  group('Auth UI Flow & Micro-interactions', () {
    testWidgets('01 Splash menuju 02 Welcome saat belum ada sesi tersimpan', (
      tester,
    ) async {
      final seededPetugas = await tester.runAsync(() => dbHelper.getAllPetugas());
      expect(seededPetugas, isEmpty);
      await pumpApp(tester);

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Selamat Datang'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('TOKO TELUR & SEMBAKO'), findsOneWidget);
    });

    testWidgets('01 Splash langsung memulihkan sesi Owner ke DepotTelur36 Owner', (
      tester,
    ) async {
      final restoredSession = AuthSession(
        uid: 'seed-petugas-owner',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        displayName: 'Owner DepotTelur36',
        role: UserRole.owner,
        petugasRemoteId: 'seed-petugas-owner',
        provider: AuthProviderType.offlineLocal,
        signedInAt: DateTime(2026, 2, 16),
      );
      await prefs.setString(
        AuthRepository.sessionStorageKey,
        restoredSession.toJson(),
      );

      await pumpApp(tester);

      expect(find.byType(RoleHomeShellScreen), findsOneWidget);
      expect(find.text('DepotTelur36 Owner'), findsOneWidget);
      expect(find.text('Halo, Owner DepotTelur36'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });

    testWidgets(
      'Alur Sign In: validasi kosong, toggle password, login Owner -> DepotTelur36 Owner -> Sign Out',
      (tester) async {
        await tester.runAsync(
          () => dbHelper.upsertPetugas(
            Petugas(
              namaPetugas: 'Owner DepotTelur36',
              role: UserRole.owner,
              pin: '1234',
              email: 'owner@depottelur36.com',
              accountId: 'owner01',
              remoteId: 'seed-petugas-owner',
              syncStatus: SyncStatus.synced,
              updatedAt: DateTime(2026, 2, 16),
            ),
          ),
        );
        await pumpApp(tester);

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsOneWidget);

        // Tekan tombol Sign In saat kosong untuk memicu error banner & ShakeOnError pulse
        final initialPulse = viewModel.errorPulse;
        await tester.tap(
          find.widgetWithText(TactilePillButton, 'Sign In'),
        );
        await tester.pumpAndSettle();

        expect(viewModel.errorPulse, greaterThan(initialPulse));
        expect(
          find.text('Masukkan ID Akun atau Email terlebih dahulu.'),
          findsWidgets,
        );
        expect(find.text('Masukkan password terlebih dahulu.'), findsOneWidget);

        // Toggle visibilitas password
        expect(find.byIcon(Icons.visibility_off), findsOneWidget);
        await tester.tap(find.byIcon(Icons.visibility_off));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.visibility), findsOneWidget);

        // Masukkan kredensial Owner bawaan ('owner01' / '1234')
        await tester.enterText(
          find.widgetWithText(TextField, 'ID Akun atau Email'),
          'owner01',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          '1234',
        );
        await tester.tap(
          find.widgetWithText(TactilePillButton, 'Sign In'),
        );
        await settleWithIo(tester);

        expect(find.byType(RoleHomeShellScreen), findsOneWidget);
        expect(find.text('DepotTelur36 Owner'), findsOneWidget);
        expect(find.text('Owner'), findsOneWidget);

        // Sign Out kembali ke Welcome
        await tester.tap(find.widgetWithText(TactilePillButton, 'Sign Out'));
        await settleWithIo(tester);

        expect(find.byType(WelcomeScreen), findsOneWidget);
      },
    );

    testWidgets('Modal Lupa Password mengirim tautan reset via ID Akun', (
      tester,
    ) async {
      await tester.runAsync(
        () => dbHelper.upsertPetugas(
          Petugas(
            namaPetugas: 'Petugas Kasir & Gudang',
            role: UserRole.petugas,
            pin: '1111',
            email: 'kasir@depottelur36.com',
            accountId: 'kasir01',
            remoteId: 'seed-petugas-kasir-1',
            syncStatus: SyncStatus.synced,
            updatedAt: DateTime(2026, 2, 16),
          ),
        ),
      );
      await pumpApp(tester);

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lupa Password?'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        'kasir01',
      );
      await tester.tap(
        find.widgetWithText(TactilePillButton, 'Kirim Tautan Reset'),
      );
      await settleWithIo(tester);

      expect(gateway.sentResetEmails, ['kasir@depottelur36.com']);
      expect(
        find.text('Tautan reset password dikirim ke kasir@depottelur36.com.'),
        findsOneWidget,
      );
    });

    testWidgets('Alur Sign Up validasi mismatch & daftar sukses sebagai Kasir', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(find.byType(SignUpScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nama Lengkap'),
        'Siti Kasir',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'siti@depottelur36.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'rahasia123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Konfirmasi Password'),
        'tidakSama',
      );

      final signUpCta = find.widgetWithText(TactilePillButton, 'Sign Up');
      await tester.ensureVisible(signUpCta);
      await tester.tap(signUpCta);
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi password tidak sama.'), findsWidgets);

      await tester.enterText(
        find.widgetWithText(TextField, 'Konfirmasi Password'),
        'rahasia123',
      );
      await tester.ensureVisible(signUpCta);
      await tester.tap(signUpCta);
      await settleWithIo(tester);

      expect(find.byType(RoleHomeShellScreen), findsOneWidget);
      expect(find.text('DepotTelur36 Kasir'), findsOneWidget);
      expect(find.text('Kasir & Gudang'), findsOneWidget);
      expect(find.text('Halo, Siti Kasir'), findsOneWidget);
    });

    testWidgets('Continue with Google pada Sign In masuk ke halaman sesuai role', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      final googleBtn = find.widgetWithText(
        GoogleAuthButton,
        'Continue with Google',
      );
      await tester.ensureVisible(googleBtn);
      await tester.tap(googleBtn);
      await settleWithIo(tester);

      expect(find.byType(RoleHomeShellScreen), findsOneWidget);
      expect(find.text('DepotTelur36 Kasir'), findsOneWidget);
      expect(find.text('Halo, Kasir Google'), findsOneWidget);
    });

    testWidgets('Navigasi silang Sign In <-> Sign Up melalui header dan footer', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.tap(find.text('Sign Up').first);
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);

      final footerSignIn = find.text('Sign In').last;
      await tester.ensureVisible(footerSignIn);
      await tester.tap(footerSignIn);
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets(
      'Compact viewport (320x568), skala teks 1.4x & Reduce Motion tidak memicu overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        for (final screen in const [
          WelcomeScreen(),
          SignInScreen(),
          SignUpScreen(),
        ]) {
          await tester.pumpWidget(
            ChangeNotifierProvider<AuthViewModel>.value(
              value: viewModel,
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: const TextScaler.linear(1.4),
                    ),
                    child: child!,
                  );
                },
                home: screen,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'REGRESSION UI: error modal Lupa Password tidak bocor ke SignInScreen & error input hilang saat diketik ulang',
      (tester) async {
        await tester.runAsync(
          () => dbHelper.upsertPetugas(
            Petugas(
              namaPetugas: 'Owner DepotTelur36',
              role: UserRole.owner,
              pin: '1234',
              email: 'owner@depottelur36.com',
              accountId: 'owner01',
              remoteId: 'seed-petugas-owner',
              syncStatus: SyncStatus.synced,
              updatedAt: DateTime(2026, 2, 16),
            ),
          ),
        );
        await pumpApp(tester);

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        // Uji salah input di SignInScreen lalu mengetik ulang membersihkan banner
        await tester.enterText(
          find.widgetWithText(TextField, 'ID Akun atau Email'),
          'owner01',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'salah9999',
        );
        await tester.tap(find.widgetWithText(TactilePillButton, 'Sign In'));
        await settleWithIo(tester);

        expect(
          find.text('Password atau PIN offline tidak sesuai.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          '1234',
        );
        await tester.pumpAndSettle();
        expect(viewModel.errorMessage, isNull);

        // Uji error di modal Lupa Password tidak bocor saat modal ditutup
        await tester.tap(find.text('Lupa Password?'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          'id_tidak_ada',
        );
        await tester.tap(
          find.widgetWithText(TactilePillButton, 'Kirim Tautan Reset'),
        );
        await settleWithIo(tester);

        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(
              'Email untuk akun tersebut tidak ditemukan atau formatnya tidak valid.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Email untuk akun tersebut tidak ditemukan atau formatnya tidak valid.',
          ),
          findsOneWidget,
        );

        // Tutup bottom sheet dengan tap area scrim di atas modal
        await tester.tapAt(const Offset(20, 40));
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsOneWidget);
        expect(viewModel.errorMessage, isNull);
        expect(
          find.text(
            'Email untuk akun tersebut tidak ditemukan atau formatnya tidak valid.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'REGRESSION UI: tombol Kembali terkunci saat proses Sign In berlangsung',
      (tester) async {
        await pumpApp(tester);

        // Pastikan akun ada di gateway untuk melewati SignIn network gate
        await gateway.createUserWithEmailAndPassword(
          fullName: 'Kasir Cepat',
          email: 'cepat@depottelur36.com',
          password: 'password123',
        );
        await gateway.signOut();

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        final gate = Completer<void>();
        gateway.pendingSignInGate = gate;

        await tester.enterText(
          find.widgetWithText(TextField, 'ID Akun atau Email'),
          'cepat@depottelur36.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password'),
          'password123',
        );
        await tester.tap(find.widgetWithText(TactilePillButton, 'Sign In'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();

        expect(viewModel.isSubmitting, isTrue);

        // Coba tekan tombol back saat sedang memproses login
        await tester.tap(find.byTooltip('Kembali'));
        await tester.pump();
        expect(find.byType(SignInScreen), findsOneWidget);

        // Selesaikan request -> harus masuk ke RoleHomeShellScreen
        gate.complete();
        await settleWithIo(tester);

        expect(find.byType(RoleHomeShellScreen), findsOneWidget);
        expect(find.text('DepotTelur36 Kasir'), findsOneWidget);
      },
    );
  });

  group('Fungsi 2 - Dashboard Beranda RBAC, Tab, Search & Notifikasi', () {
    AuthSession sampleOwner() => AuthSession(
          uid: 'seed-owner',
          email: 'owner@depottelur36.com',
          accountId: 'owner01',
          displayName: 'Budi Owner',
          role: UserRole.owner,
          petugasRemoteId: 'seed-petugas-owner',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 16),
        );

    AuthSession sampleOperator() => AuthSession(
          uid: 'seed-kasir',
          email: 'kasir@depottelur36.com',
          accountId: 'kasir01',
          displayName: 'Siti Kasir',
          role: UserRole.petugas,
          petugasRemoteId: 'seed-petugas-kasir-1',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 16),
        );

    Future<void> pumpShell(
      WidgetTester tester,
      AuthSession session, {
      Size size = const Size(390, 844),
      double textScale = 1.0,
      bool disableAnimations = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SyncService>.value(value: syncService),
            Provider<InventoryRepository>.value(value: inventoryRepository),
            ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: disableAnimations,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              );
            },
            home: RoleHomeShellScreen(initialSession: session),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Owner menampilkan menu Manajerial, 4 tab RBAC & navigasi Lihat Semua', (
      tester,
    ) async {
      await pumpShell(tester, sampleOwner());

      expect(find.text('DepotTelur36 Owner'), findsOneWidget);
      expect(find.text('Fungsi Manajerial'), findsOneWidget);
      expect(find.text('Khusus Owner'), findsOneWidget);
      expect(find.text('Atur Harga'), findsOneWidget);
      expect(find.text('Riwayat Faktur'), findsOneWidget);
      expect(find.text('Data Supplier'), findsOneWidget);
      expect(find.text('Akun Petugas'), findsOneWidget);

      expect(find.text('Beranda'), findsOneWidget);
      expect(find.text('Omzet'), findsOneWidget);
      expect(find.text('Nota'), findsOneWidget);
      expect(find.text('Master'), findsOneWidget);

      // Pastikan stok menipis awal dari SQLite seed muncul
      expect(
        find.text('Stok Menipis · Minyak Goreng Kemasan 1 Liter'),
        findsOneWidget,
      );

      // Tap Lihat Semua -> pindah ke tab Master
      await tester.tap(find.text('Lihat Semua'));
      await tester.pumpAndSettle();
      expect(find.text('Katalog Barang & Master Entitas'), findsOneWidget);

      // Tap tab Omzet
      await tester.tap(find.text('Omzet'));
      await tester.pumpAndSettle();
      expect(find.text('Ringkasan Omzet & Arus Kas'), findsOneWidget);
    });

    testWidgets('Operator tidak memiliki akses Omzet/Atur Harga dan Restock mengarah ke Faktur', (
      tester,
    ) async {
      await pumpShell(tester, sampleOperator());

      expect(find.text('DepotTelur36 Kasir'), findsOneWidget);
      expect(find.text('Fungsi Operasional'), findsOneWidget);
      expect(find.text('Kasir & Gudang'), findsOneWidget);
      expect(find.text('Riwayat Nota'), findsOneWidget);
      expect(find.text('Pelanggan'), findsOneWidget);

      expect(find.text('Kasir'), findsOneWidget);
      expect(find.text('Faktur'), findsOneWidget);
      expect(find.text('Stok'), findsOneWidget);

      // RBAC UI Check: fitur khusus Owner tidak ada di pohon widget Operator
      expect(find.text('Omzet'), findsNothing);
      expect(find.text('Atur Harga'), findsNothing);
      expect(find.text('Akun Petugas'), findsNothing);

      // Tap Restock pada LowStockAlertCard -> pindah ke Faktur + SnackBar
      await tester.tap(find.text('Restock').first);
      await tester.pumpAndSettle();
      expect(find.text('Faktur Stok Masuk Supplier'), findsOneWidget);
      expect(
        find.textContaining('Siap restock Minyak Goreng Kemasan 1 Liter'),
        findsOneWidget,
      );
    });

    testWidgets('Pencarian live & Quick Filter menyaring barang + reset kosong', (
      tester,
    ) async {
      await pumpShell(tester, sampleOperator());

      // Buka bar filter cepat
      await tester.tap(find.byTooltip('Filter cepat'));
      await tester.pumpAndSettle();
      expect(find.text('Stok Menipis'), findsOneWidget);

      await tester.tap(find.text('Stok Menipis'));
      await tester.pumpAndSettle();
      expect(find.text('Telur Ayam Negeri'), findsNothing);
      expect(
        find.text('Stok Menipis · Minyak Goreng Kemasan 1 Liter'),
        findsOneWidget,
      );

      // Cari query tidak ditemukan
      await tester.enterText(find.byType(TextField), 'barang_tidak_ada_xyz');
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada barang yang cocok'), findsOneWidget);

      // Reset filter & pencarian
      final scrollable = find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.vertical,
      );
      await tester.drag(scrollable, const Offset(0, -250));
      await tester.pumpAndSettle();

      final resetEmptyBtn = find.text('Reset Filter & Pencarian');
      await tester.tap(resetEmptyBtn);
      await tester.pumpAndSettle();
      expect(find.text('Telur Ayam Negeri'), findsOneWidget);
    });

    testWidgets('Pusat Notifikasi menampilkan badge, Tandai Semua & Sinkron manual', (
      tester,
    ) async {
      await pumpShell(tester, sampleOwner());

      // 2 alert awal (Minyak Goreng 8 <= 10 & Beras 18 <= 20)
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byTooltip('Notifikasi & Sinkronisasi'));
      await tester.pumpAndSettle();

      expect(find.text('Notifikasi & Sinkronisasi'), findsOneWidget);
      expect(find.text('2 peringatan belum dibaca'), findsOneWidget);

      await tester.tap(find.text('Sinkron'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(syncService.manualSyncCalls, 1);

      await tester.tap(find.text('Tandai Semua'));
      await tester.pumpAndSettle();
      expect(find.text('Semua notifikasi terbaca'), findsOneWidget);

      await tester.tap(find.byTooltip('Tutup notifikasi'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
    });

    testWidgets('Compact viewport (320x568), skala teks 1.4x & Reduce Motion pada Owner dan Operator bebas overflow', (
      tester,
    ) async {
      for (final session in [sampleOwner(), sampleOperator()]) {
        await pumpShell(
          tester,
          session,
          size: const Size(320, 568),
          textScale: 1.4,
          disableAnimations: true,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('Tombol Back di tab non-Beranda kembali ke Beranda dan TextField membatasi panjang query', (
      tester,
    ) async {
      await pumpShell(tester, sampleOwner());

      await tester.tap(find.text('Master'));
      await tester.pumpAndSettle();
      expect(find.text('Katalog Barang & Master Entitas'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RoleHomeShellScreen), findsOneWidget);
      expect(find.text('Fungsi Manajerial'), findsOneWidget);
      expect(find.text('Katalog Barang & Master Entitas'), findsNothing);

      final searchField = find.byType(TextField);
      final fieldWidget = tester.widget<TextField>(searchField);
      expect(fieldWidget.maxLength, kMaxSearchQueryLength);

      await tester.enterText(searchField, 'T' * 120);
      await tester.pumpAndSettle();
      expect(
        fieldWidget.controller?.text.length,
        lessThanOrEqualTo(kMaxSearchQueryLength),
      );
    });

    testWidgets('NotificationCenterSheet menampilkan syncErrorMessage dengan aman tanpa overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      var syncTapped = 0;
      await tester.pumpWidget(
        wrapScreen(
          Scaffold(
            body: NotificationCenterSheet(
              notifications: [
                AppNotificationItem(
                  id: 'stock-low:1:8',
                  title: 'Stok Menipis · Minyak Goreng 1L',
                  message: 'Sisa 8 Pouch (batas minimum 10).',
                  severity: NotificationSeverity.warning,
                  createdAt: DateTime(2026, 2, 16),
                  isRead: false,
                  barangRemoteId: 'minyak-1l',
                  barangNama: 'Minyak Goreng 1L',
                  currentStock: 8,
                  satuan: 'Pouch',
                ),
              ],
              unreadCount: 1,
              syncState: const SyncState(isOnline: true, pendingCount: 1),
              isManualSyncing: false,
              syncErrorMessage: 'Gagal menjalankan sinkronisasi manual.',
              onMarkRead: (_) {},
              onMarkAllRead: () {},
              onTriggerSync: () => syncTapped++,
              onRestockItem: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Gagal menjalankan sinkronisasi manual.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Sinkron'));
      await tester.pumpAndSettle();
      expect(syncTapped, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('Accessibility & Contrast Audits', () {
    Future<void> auditScreen(WidgetTester tester, Widget screen) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrapScreen(screen));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    }

    testWidgets('WelcomeScreen memenuhi standar aksesibilitas', (tester) async {
      await auditScreen(tester, const WelcomeScreen());
    });

    testWidgets('SignInScreen memenuhi standar aksesibilitas', (tester) async {
      await auditScreen(tester, const SignInScreen());
    });

    testWidgets('SignUpScreen memenuhi standar aksesibilitas', (tester) async {
      await auditScreen(tester, const SignUpScreen());
    });

    testWidgets('RoleHomeShellScreen Owner memenuhi standar aksesibilitas', (
      tester,
    ) async {
      await auditScreen(
        tester,
        RoleHomeShellScreen(
          initialSession: AuthSession(
            uid: 'seed-owner',
            email: 'owner@depottelur36.com',
            accountId: 'owner01',
            displayName: 'Owner DepotTelur36',
            role: UserRole.owner,
            petugasRemoteId: 'seed-petugas-owner',
            provider: AuthProviderType.emailPassword,
            signedInAt: DateTime(2026, 2, 16),
          ),
        ),
      );
    });

    testWidgets('RoleHomeShellScreen Operator memenuhi standar aksesibilitas', (
      tester,
    ) async {
      await auditScreen(
        tester,
        RoleHomeShellScreen(
          initialSession: AuthSession(
            uid: 'seed-kasir',
            email: 'kasir@depottelur36.com',
            accountId: 'kasir01',
            displayName: 'Kasir DepotTelur36',
            role: UserRole.petugas,
            petugasRemoteId: 'seed-petugas-kasir-1',
            provider: AuthProviderType.emailPassword,
            signedInAt: DateTime(2026, 2, 16),
          ),
        ),
      );
    });
  });
}
