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
import 'package:depot_telur_36/models/restock_monitor_models.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
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
import 'package:depot_telur_36/viewmodels/restock_monitor_view_model.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/dashboard_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';
import 'package:flutter/services.dart';
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
      expect(find.text('Master Data Toko'), findsOneWidget);

      // Tap tab Omzet
      await tester.tap(find.text('Omzet'));
      await tester.pumpAndSettle();
      expect(find.text('Rekap Omzet'), findsOneWidget);
      expect(find.text('Pemasukan 7 Hari Terakhir'), findsOneWidget);
      expect(find.text('Ekspor'), findsOneWidget);
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
      expect(find.textContaining('Batas minimum'), findsNothing);

      // Tap Restock pada LowStockAlertCard -> pindah ke Faktur + SnackBar
      await tester.tap(find.text('Restock').first);
      await tester.pumpAndSettle();
      expect(find.text('Faktur Barang Masuk'), findsOneWidget);
      expect(find.text('Minyak Goreng Kemasan 1 Liter'), findsOneWidget);
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
      expect(find.text('Master Data Toko'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RoleHomeShellScreen), findsOneWidget);
      expect(find.text('Fungsi Manajerial'), findsOneWidget);
      expect(find.text('Master Data Toko'), findsNothing);

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
                  message: 'Sisa 8 Pouch, perlu segera restock.',
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

    Future<MasterCrudViewModel> createMasterVm(
      WidgetTester tester, {
      required bool owner,
    }) async {
      final session = AuthSession(
        uid: owner ? 'audit-owner' : 'audit-kasir',
        email: owner ? 'owner@depottelur36.com' : 'kasir@depottelur36.com',
        accountId: owner ? 'owner01' : 'kasir01',
        displayName: owner ? 'Owner Audit' : 'Kasir Audit',
        role: owner ? UserRole.owner : UserRole.petugas,
        petugasRemoteId: owner ? 'audit-owner-remote' : 'audit-kasir-remote',
        provider: AuthProviderType.emailPassword,
        signedInAt: DateTime(2026, 2, 16),
      );
      final vm = MasterCrudViewModel.fromRepository(
        session: session,
        repository: inventoryRepository,
      );
      addTearDown(vm.dispose);
      await tester.runAsync(() async {
        await inventoryRepository.savePetugas(
          existingRemoteId: 'audit-owner-remote',
          namaPetugas: 'Owner Audit',
          role: UserRole.owner,
          pin: '9999',
          email: 'owner@depottelur36.com',
        );
        await vm.loadData();
      });
      return vm;
    }

    testWidgets('MasterDataTabView, CRUD forms & AturHargaScreen memenuhi standar aksesibilitas', (
      tester,
    ) async {
      final ownerVm = await createMasterVm(tester, owner: true);

      await auditScreen(
        tester,
        Scaffold(body: MasterDataTabView(viewModel: ownerVm)),
      );
      await auditScreen(
        tester,
        BarangFormScreen(
          viewModel: ownerVm,
          initialBarang: ownerVm.allBarang.first,
        ),
      );
      await auditScreen(
        tester,
        SupplierFormScreen(
          viewModel: ownerVm,
          initialSupplier: ownerVm.allSuppliers.first,
        ),
      );
      await auditScreen(
        tester,
        PetugasFormScreen(
          viewModel: ownerVm,
          initialPetugas: ownerVm.allPetugas.first,
        ),
      );
      await auditScreen(
        tester,
        AturHargaScreen(viewModel: ownerVm),
      );
    });

    testWidgets('Layar Transaksi CRUD (07, 08, 16, 17, 18, 19) memenuhi standar aksesibilitas', (
      tester,
    ) async {
      final session = AuthSession(
        uid: 'tx-audit-kasir',
        email: 'kasir.tx@depottelur36.com',
        accountId: 'kasir_tx',
        displayName: 'Kasir Audit',
        role: UserRole.petugas,
        petugasRemoteId: 'tx-audit-petugas',
        provider: AuthProviderType.emailPassword,
        signedInAt: DateTime(2026, 2, 16),
      );
      final txVm = TransactionCrudViewModel.fromRepository(
        session: session,
        repository: inventoryRepository,
      );
      addTearDown(txVm.dispose);
      await tester.runAsync(() async {
        await inventoryRepository.savePetugas(
          existingRemoteId: 'tx-audit-petugas',
          namaPetugas: 'Kasir Audit',
          role: UserRole.petugas,
          pin: '1234',
          email: 'kasir.tx@depottelur36.com',
        );
        await txVm.loadData();
        final barang = txVm.barangs.first;
        final supplier = txVm.suppliers.first;
        final customer = txVm.customers.first;
        final petugas = txVm.activePetugas!;
        await inventoryRepository.createFaktur(
          noFaktur: 'FKT-AUDIT-01',
          tanggalFaktur: '2026-02-18',
          supplier: supplier,
          petugas: petugas,
          items: [(barang: barang, quantity: 5)],
        );
        await inventoryRepository.createNota(
          tanggalNota: '2026-02-18',
          customer: customer,
          petugas: petugas,
          items: [(barang: barang, banyaknya: 2)],
        );
        await txVm.loadData();
      });

      await auditScreen(tester, KasirNotaScreen(viewModel: txVm));
      await auditScreen(tester, FakturMasukScreen(viewModel: txVm));
      await auditScreen(tester, RiwayatNotaScreen(viewModel: txVm));
      await auditScreen(tester, RiwayatFakturScreen(viewModel: txVm));
      await auditScreen(
        tester,
        DetailNotaScreen(viewModel: txVm, nota: txVm.notas.first),
      );
      await auditScreen(
        tester,
        DetailFakturScreen(viewModel: txVm, faktur: txVm.fakturs.first),
      );

      final rekapOwnerSession = AuthSession(
        uid: 'rekap-audit-owner',
        email: 'owner.rekap@depottelur36.com',
        accountId: 'owner_rekap',
        displayName: 'Owner Audit',
        role: UserRole.owner,
        petugasRemoteId: 'tx-audit-owner',
        provider: AuthProviderType.emailPassword,
        signedInAt: DateTime(2026, 2, 18),
      );
      final rekapVm = RekapOmzetViewModel.fromRepository(
        session: rekapOwnerSession,
        repository: inventoryRepository,
        nowProvider: () => DateTime(2026, 2, 18),
      );
      addTearDown(rekapVm.dispose);
      await tester.runAsync(() => rekapVm.loadData());
      await auditScreen(tester, RekapOmzetScreen(viewModel: rekapVm));

      final restockVm = RestockMonitorViewModel.fromRepository(
        session: rekapOwnerSession,
        repository: inventoryRepository,
      );
      addTearDown(restockVm.dispose);
      await tester.runAsync(() => restockVm.loadData());
      await auditScreen(
        tester,
        StokMenipisScreen(
          viewModel: restockVm,
          onStartRestockFaktur: (_) {},
          onOpenEmptyFaktur: () {},
        ),
      );
    });
  });

  group('Fungsi 3 - UI Master Data CRUD, Atur Harga & RBAC', () {
    AuthSession ownerSession() => AuthSession(
      uid: 'ui-owner',
      email: 'owner@depottelur36.com',
      accountId: 'owner01',
      displayName: 'Budi Owner',
      role: UserRole.owner,
      petugasRemoteId: 'ui-owner-remote',
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

    AuthSession operatorSession() => AuthSession(
      uid: 'ui-kasir',
      email: 'kasir@depottelur36.com',
      accountId: 'kasir01',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: 'ui-kasir-remote',
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

    Future<void> scrollMasterToTop(WidgetTester tester) async {
      final verticalScrollable = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      if (verticalScrollable.evaluate().isNotEmpty) {
        tester
            .state<ScrollableState>(verticalScrollable.first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
      }
    }

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    Future<void> flushDb(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pumpAndSettle();
    }

    Future<void> pumpMasterShell(
      WidgetTester tester,
      AuthSession session, {
      Size size = const Size(390, 844),
      double textScale = 1.0,
      bool disableAnimations = false,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        BarangPhotoPresets.clearAll();
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
      await flushDb(tester);
    }

    testWidgets('Owner dapat melakukan CRUD Barang, Supplier, Pelanggan & Petugas end-to-end dengan SQLite nyata', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await inventoryRepository.savePetugas(
          existingRemoteId: 'ui-owner-remote',
          namaPetugas: 'Budi Owner',
          role: UserRole.owner,
          pin: '9999',
          email: 'owner@depottelur36.com',
        );
      });

      await pumpMasterShell(tester, ownerSession());

      // Buka tab Master -> kategori Barang
      await tester.tap(find.text('Master'));
      await tester.pumpAndSettle();
      expect(find.text('Master Data Toko'), findsOneWidget);
      expect(find.text('Petugas'), findsOneWidget);

      // Tambah Barang: validasi salah input dulu lalu input valid + quick unit + preset foto
      await tester.tap(find.byKey(const ValueKey('master_header_add_button')));
      await tester.pumpAndSettle();
      expect(find.text('Tambah Barang Baru'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
      await tester.pumpAndSettle();
      expect(find.text('Nama barang minimal 2 karakter.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('barang_nama_field')),
        'Telur Puyuh Organik',
      );
      await tester.enterText(
        find.byKey(const ValueKey('barang_stok_field')),
        '35',
      );
      await tapVisible(tester, find.byKey(const ValueKey('unit_chip_Tray')));
      await tester.enterText(
        find.byKey(const ValueKey('barang_harga_field')),
        '32000',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('barang_toggle_photo_picker')),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Telur Bebek'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
      await flushDb(tester);

      expect(find.text('Telur Puyuh Organik'), findsOneWidget);

      // Edit Barang -> Hapus Barang dengan DeleteConfirmCard
      final puyuhItem = (await tester.runAsync(
        () => inventoryRepository.getAllBarang(),
      ))!.firstWhere((b) => b.namaBarang == 'Telur Puyuh Organik');
      await tapVisible(
        tester,
        find.byKey(ValueKey('edit_barang_${puyuhItem.remoteId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit Data Barang'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('crud_footer_delete_button')));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi Hapus Barang?'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('delete_confirm_submit_button')),
      );
      await flushDb(tester);
      expect(find.text('Telur Puyuh Organik'), findsNothing);

      // Kategori Supplier: validasi HP salah lalu create & delete
      await scrollMasterToTop(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('master_category_tab_supplier')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('master_header_add_button')));
      await tester.pumpAndSettle();
      expect(find.text('Tambah Supplier Baru'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('supplier_nama_field')),
        'Peternakan Subur Makmur',
      );
      await tester.enterText(
        find.byKey(const ValueKey('supplier_telp_field')),
        '123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('supplier_alamat_field')),
        'Jl. Raya Bekasi No. 45',
      );
      await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
      await tester.pumpAndSettle();
      expect(find.text('Nomor telepon harus 8-15 digit angka.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('supplier_telp_field')),
        '0812-9988-7766',
      );
      await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
      await flushDb(tester);
      expect(find.text('Peternakan Subur Makmur'), findsOneWidget);

      // Kategori Pelanggan: inline QuickCustomerForm Create -> Edit -> Delete
      await scrollMasterToTop(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('master_category_tab_pelanggan')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tambah Pelanggan Baru'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('customer_quick_nama_field')),
        'Warung Bu Dewi',
      );
      await tester.tap(
        find.byKey(const ValueKey('customer_quick_save_button')),
      );
      await flushDb(tester);
      expect(find.text('Warung Bu Dewi'), findsOneWidget);

      final dewi = (await tester.runAsync(
        () => inventoryRepository.getAllCustomer(),
      ))!.firstWhere((c) => c.namaCustomer == 'Warung Bu Dewi');
      await tapVisible(
        tester,
        find.byKey(ValueKey('edit_customer_${dewi.remoteId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ubah Nama Pelanggan'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('customer_quick_nama_field')),
        'Toko Bu Dewi Raya',
      );
      await tester.tap(
        find.byKey(const ValueKey('customer_quick_save_button')),
      );
      await flushDb(tester);
      expect(find.text('Toko Bu Dewi Raya'), findsOneWidget);

      // Kategori Petugas: PIN visibility toggle + Create
      await scrollMasterToTop(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('master_category_tab_petugas')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('master_header_add_button')));
      await tester.pumpAndSettle();
      expect(find.text('Tambah Petugas Baru'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('petugas_nama_field')),
        'Andi Kasir',
      );
      await tester.enterText(
        find.byKey(const ValueKey('petugas_email_field')),
        'andi@depottelur36.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('petugas_pin_field')),
        '4567',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('petugas_pin_visibility_toggle')),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Sembunyikan PIN'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
      await flushDb(tester);
      expect(find.text('Andi Kasir'), findsOneWidget);
      expect(find.text('andi@depottelur36.com'), findsOneWidget);
    });

    testWidgets('Atur Harga Jual menyoroti perubahan draft biru, bisa Reset & simpan batch ke SQLite', (
      tester,
    ) async {
      await pumpMasterShell(tester, ownerSession());

      // Buka shortcut Atur Harga dari Beranda
      await tester.tap(find.text('Atur Harga'));
      await tester.pumpAndSettle();
      expect(find.text('Atur Harga Jual'), findsOneWidget);

      // Filter Komoditas Telur -> Beras tidak tampil
      await tester.tap(find.byKey(const ValueKey('price_filter_telur')));
      await tester.pumpAndSettle();
      expect(find.text('Beras Pandan Wangi 5 Kg'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('price_filter_semua')));
      await tester.pumpAndSettle();

      // Edit harga Telur Ayam Negeri -> harus memunculkan caption "Sebelum Rp"
      await tester.enterText(
        find.byKey(
          const ValueKey('atur_harga_input_seed-barang-telur-negeri-kg'),
        ),
        '30000',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Sebelum Rp 28.500'), findsOneWidget);
      expect(find.text('Simpan Harga Baru (1)'), findsOneWidget);

      // Uji tombol Reset mengembalikan harga awal
      await tester.tap(find.byKey(const ValueKey('atur_harga_reset_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sebelum Rp'), findsNothing);

      // Ubah lagi lalu Simpan Harga Baru
      await tester.enterText(
        find.byKey(
          const ValueKey('atur_harga_input_seed-barang-telur-negeri-kg'),
        ),
        '30500',
      );
      await tester.tap(find.byKey(const ValueKey('atur_harga_save_button')));
      await flushDb(tester);

      expect(
        find.text('1 harga jual barang berhasil diperbarui.'),
        findsOneWidget,
      );
      final updated = (await tester.runAsync(
        () => inventoryRepository.getAllBarang(),
      ))!.firstWhere((b) => b.remoteId == 'seed-barang-telur-negeri-kg');
      expect(updated.hargaSatuan, 30500);
    });

    testWidgets('Operator tidak melihat kategori Petugas/Atur Harga dan layar RBAC langsung terkunci', (
      tester,
    ) async {
      await pumpMasterShell(tester, operatorSession());

      await tester.tap(find.text('Stok'));
      await tester.pumpAndSettle();
      expect(find.text('Master Data Toko'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('master_category_tab_petugas')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('master_open_atur_harga_button')),
        findsNothing,
      );

      // Push langsung PetugasFormScreen & AturHargaScreen dengan sesi Operator -> harus terkunci
      final opVm = MasterCrudViewModel.fromRepository(
        session: operatorSession(),
        repository: inventoryRepository,
      );
      addTearDown(opVm.dispose);
      await tester.runAsync(opVm.loadData);

      await tester.pumpWidget(
        wrapScreen(PetugasFormScreen(viewModel: opVm)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Akses Dibatasi'), findsOneWidget);
      expect(find.text('Simpan Petugas'), findsNothing);

      await tester.pumpWidget(
        wrapScreen(AturHargaScreen(viewModel: opVm)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Akses Dibatasi'), findsOneWidget);
      expect(find.text('Simpan Harga Baru'), findsNothing);
    });

    testWidgets('Viewport sempit (320x568), skala teks 1.4x & Reduce Motion pada semua layar Master CRUD bebas overflow', (
      tester,
    ) async {
      final ownerVm = MasterCrudViewModel.fromRepository(
        session: ownerSession(),
        repository: inventoryRepository,
      );
      addTearDown(ownerVm.dispose);
      await tester.runAsync(() async {
        await inventoryRepository.savePetugas(
          existingRemoteId: 'ui-owner-remote',
          namaPetugas: 'Budi Owner',
          role: UserRole.owner,
          pin: '9999',
          email: 'owner@depottelur36.com',
        );
        await ownerVm.loadData();
      });

      await pumpMasterShell(
        tester,
        ownerSession(),
        size: const Size(320, 568),
        textScale: 1.4,
        disableAnimations: true,
      );
      await tester.tap(find.text('Master'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final cat in [
        MasterCategory.supplier,
        MasterCategory.pelanggan,
        MasterCategory.petugas,
      ]) {
        await tapVisible(
          tester,
          find.byKey(ValueKey('master_category_tab_${cat.name}')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // Uji AturHargaScreen pada 320x568 textScale 1.4x
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SyncService>.value(value: syncService),
            Provider<InventoryRepository>.value(value: inventoryRepository),
            ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: AturHargaScreen(viewModel: ownerVm),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Primitif micro-interaction TactilePressScale & RotatingSyncIcon bersifat finite dan patuh Reduce Motion',
      (tester) async {
        var spinning = false;
        var reduceMotion = false;
        late StateSetter setLocalState;

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              setLocalState = setState;
              return MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: reduceMotion,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TactilePressScale(
                          pressedScale: 0.92,
                          child: Container(
                            width: 140,
                            height: 48,
                            alignment: Alignment.center,
                            color: AppColors.ink,
                            child: Text(
                              'Tekan Saya',
                              style: AppTypography.body(
                                color: AppColors.surface,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        RotatingSyncIcon(
                          isSpinning: spinning,
                          color: AppColors.ink,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
        await tester.pumpAndSettle();

        final scaleFinder = find.descendant(
          of: find.byType(TactilePressScale),
          matching: find.byType(AnimatedScale),
        );
        expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Tekan Saya')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedScale>(scaleFinder).scale, 0.92);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

        // RotatingSyncIcon tidak menggunakan repeat loop sehingga pumpAndSettle selesai bersih
        setLocalState(() => spinning = true);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.byType(RotatingSyncIcon), findsOneWidget);

        // Saat disableAnimations aktif, durasi skala langsung menjadi Duration.zero
        setLocalState(() {
          spinning = false;
          reduceMotion = true;
        });
        await tester.pumpAndSettle();
        expect(tester.widget<AnimatedScale>(scaleFinder).duration, Duration.zero);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Micro-interaction Fungsi 2 & 3 (tab arah, Mode Edit pelanggan, role crossfade & Atur Harga shake) lolos normal & Reduce Motion',
      (tester) async {
        await tester.runAsync(() async {
          await inventoryRepository.savePetugas(
            existingRemoteId: 'ui-owner-remote',
            namaPetugas: 'Budi Owner',
            role: UserRole.owner,
            pin: '9999',
            email: 'owner@depottelur36.com',
          );
        });

        await pumpMasterShell(tester, ownerSession());

        // Beralih tab Beranda -> Master -> Pelanggan memicu animasi transisi arah tab & kategori
        await tester.tap(find.text('Master'));
        await tester.pumpAndSettle();
        await tapVisible(
          tester,
          find.byKey(const ValueKey('master_category_tab_pelanggan')),
        );
        await tester.pumpAndSettle();

        // Validasi QuickCustomerForm kosong memicu ShakeOnError
        await tapVisible(
          tester,
          find.byKey(const ValueKey('customer_quick_save_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate((w) => w is ShakeOnError && w.pulse > 0),
          findsOneWidget,
        );
        expect(find.text('Tambah Pelanggan Baru'), findsOneWidget);

        // Buat pelanggan lalu masuk mode edit -> badge 'Mode Edit' & judul edit muncul
        await tester.enterText(
          find.byKey(const ValueKey('customer_quick_nama_field')),
          'Warung Uji Motion',
        );
        await tester.tap(
          find.byKey(const ValueKey('customer_quick_save_button')),
        );
        await flushDb(tester);

        final createdCustomer = (await tester.runAsync(
          () => inventoryRepository.getAllCustomer(),
        ))!
            .firstWhere((c) => c.namaCustomer == 'Warung Uji Motion');
        await tapVisible(
          tester,
          find.byKey(ValueKey('edit_customer_${createdCustomer.remoteId}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ubah Nama Pelanggan'), findsOneWidget);
        expect(find.text('Mode Edit'), findsOneWidget);
        expect(find.byType(AnimatedBadgePop), findsOneWidget);

        // Simpan edit pelanggan menutup Mode Edit dengan bersih
        await tester.enterText(
          find.byKey(const ValueKey('customer_quick_nama_field')),
          'Warung Uji Motion Baru',
        );
        await tester.tap(
          find.byKey(const ValueKey('customer_quick_save_button')),
        );
        await flushDb(tester);
        expect(find.text('Mode Edit'), findsNothing);
        expect(find.text('Warung Uji Motion Baru'), findsOneWidget);

        // Uji kembali ke Beranda -> pintasan Petugas/Form & Atur Harga
        await tester.tap(find.text('Beranda'));
        await tester.pumpAndSettle();
        expect(find.text('DepotTelur36 Owner'), findsOneWidget);

        final ownerVm = MasterCrudViewModel.fromRepository(
          session: ownerSession(),
          repository: inventoryRepository,
        );
        addTearDown(ownerVm.dispose);
        await tester.runAsync(ownerVm.loadData);

        Future<void> verifyForms({required bool disableAnimations}) async {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<SyncService>.value(value: syncService),
                Provider<InventoryRepository>.value(
                  value: inventoryRepository,
                ),
                ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: disableAnimations,
                  ),
                  child: child!,
                ),
                home: PetugasFormScreen(viewModel: ownerVm),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Crossfade deskripsi role Owner <-> Petugas
          await tester.tap(
            find.byKey(ValueKey('petugas_role_${UserRole.owner.value}')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Owner dapat mengakses laporan omzet, atur harga jual, dan kelola akun.',
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(ValueKey('petugas_role_${UserRole.petugas.value}')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Petugas fokus pada transaksi kasir, faktur masuk, dan daftar master operasional.',
            ),
            findsOneWidget,
          );

          // Toggle visibility PIN beranimasi bersih
          await tapVisible(
            tester,
            find.byKey(const ValueKey('petugas_pin_visibility_toggle')),
          );
          await tester.pumpAndSettle();
          expect(find.byTooltip('Sembunyikan PIN'), findsOneWidget);

          // Submit kosong memicu ShakeOnError pada PetugasFormScreen
          await tapVisible(
            tester,
            find.byKey(const ValueKey('crud_footer_save_button')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byWidgetPredicate((w) => w is ShakeOnError && w.pulse > 0),
            findsOneWidget,
          );

          // Uji AturHargaScreen batch kosong -> ShakeOnError + error banner, lalu edit draft biru
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<SyncService>.value(value: syncService),
                Provider<InventoryRepository>.value(
                  value: inventoryRepository,
                ),
                ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: disableAnimations,
                  ),
                  child: child!,
                ),
                home: AturHargaScreen(viewModel: ownerVm),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(
            find.byKey(const ValueKey('atur_harga_save_button')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Ubah minimal satu harga barang terlebih dahulu.'),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate((w) => w is ShakeOnError && w.pulse > 0),
            findsOneWidget,
          );

          await tester.enterText(
            find.byKey(
              const ValueKey('atur_harga_input_seed-barang-telur-negeri-kg'),
            ),
            '29900',
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Sebelum Rp 28.500'), findsOneWidget);
          expect(find.text('Simpan Harga Baru (1)'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        await verifyForms(disableAnimations: false);
        await verifyForms(disableAnimations: true);
      },
    );
  });

  group('Fungsi 4 - UI Transaksi CRUD (Nota, Faktur, Riwayat & Edit Detail)', () {
    AuthSession kasirSession() => AuthSession(
      uid: 'ui-kasir-tx',
      email: 'kasir.tx@depottelur36.com',
      accountId: 'kasir01',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: 'ui-kasir-tx-remote',
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

    Future<TransactionCrudViewModel> setupTxVm(WidgetTester tester) async {
      final vm = TransactionCrudViewModel.fromRepository(
        session: kasirSession(),
        repository: inventoryRepository,
      );
      addTearDown(vm.dispose);
      await tester.runAsync(() async {
        await inventoryRepository.savePetugas(
          existingRemoteId: 'ui-kasir-tx-remote',
          namaPetugas: 'Siti Kasir',
          role: UserRole.petugas,
          pin: '1122',
          email: 'kasir.tx@depottelur36.com',
        );
        await vm.loadData();
      });
      return vm;
    }

    Future<void> flushAsync(
      WidgetTester tester, {
      bool Function()? until,
    }) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        if (until != null && until()) break;
      }
      await tester.pumpAndSettle();
    }

    Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(finder, 160, scrollable: scrollable);
      } else {
        await tester.ensureVisible(finder);
      }
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    testWidgets(
      'Alur UI Kasir Nota -> Riwayat Nota -> Detail Edit -> Hapus Nota mengembalikan stok SQLite & memicu micro-interactions',
      (tester) async {
        final vm = await setupTxVm(tester);
        final firstBarang = vm.barangs.first;
        final initialStock = firstBarang.stokBarang;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SyncService>.value(value: syncService),
              Provider<InventoryRepository>.value(value: inventoryRepository),
              ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: KasirNotaScreen(viewModel: vm),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Awalnya keranjang kosong -> FloatingTransactionTotalBar tersembunyi
        expect(
          find.byKey(const ValueKey('kasir_submit_nota_button')),
          findsNothing,
        );

        // Tap + Tambah -> morphing ke stepper & bar total gelap muncul
        await tester.tap(
          find.byKey(ValueKey('kasir_add_${firstBarang.idBarang}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('kasir_submit_nota_button')),
          findsOneWidget,
        );
        expect(find.byType(AnimatedQtyText), findsOneWidget);
        expect(find.byType(AnimatedRupiahCounter), findsWidgets);

        // Tambah qty menjadi 2
        await tester.tap(
          find.byKey(ValueKey('kasir_inc_${firstBarang.idBarang}')),
        );
        await tester.pumpAndSettle();
        expect(vm.kasirQtyFor(firstBarang), 2);

        // Simpan Nota ke SQLite
        await tester.tap(
          find.byKey(const ValueKey('kasir_submit_nota_button')),
        );
        await flushAsync(tester, until: () => vm.notas.isNotEmpty);
        expect(vm.errorMessage, isNull);
        expect(vm.notas.length, 1);
        final createdNota = vm.notas.first;
        expect(
          vm.barangs
              .firstWhere((b) => b.idBarang == firstBarang.idBarang)
              .stokBarang,
          initialStock - 2,
        );

        // Buka Riwayat Nota dari header
        await tester.tap(find.text('Riwayat'));
        await tester.pumpAndSettle();
        expect(find.text('Riwayat Nota'), findsOneWidget);
        expect(
          find.byKey(ValueKey('nota_card_${createdNota.idNota}')),
          findsOneWidget,
        );

        // Buka Detail & Edit Nota
        await tester.tap(
          find.byKey(ValueKey('nota_card_${createdNota.idNota}')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Detail Nota #${createdNota.idNota}'),
          findsOneWidget,
        );

        // Tambah qty menjadi 3 lalu Simpan Perubahan
        await scrollAndTap(
          tester,
          find.byKey(ValueKey('detail_nota_${firstBarang.idBarang}_inc')),
        );
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('detail_nota_save_button')),
        );
        await flushAsync(
          tester,
          until: () =>
              find.byType(DetailNotaScreen).evaluate().isEmpty &&
              vm.barangs
                      .firstWhere((b) => b.idBarang == firstBarang.idBarang)
                      .stokBarang ==
                  initialStock - 3,
        );
        expect(find.byType(DetailNotaScreen), findsNothing);
        expect(
          vm.barangs
              .firstWhere((b) => b.idBarang == firstBarang.idBarang)
              .stokBarang,
          initialStock - 3,
        );

        // Buka Detail lagi, uji konfirmasi hapus inline lalu Ya, Hapus -> stok kembali penuh
        await scrollAndTap(
          tester,
          find.byKey(ValueKey('nota_card_${createdNota.idNota}')),
        );
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('detail_nota_delete_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('confirm_delete_tx_button')),
          findsOneWidget,
        );

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('confirm_delete_tx_button')),
        );
        await flushAsync(tester, until: () => vm.notas.isEmpty);
        expect(vm.notas, isEmpty);
        expect(
          vm.barangs
              .firstWhere((b) => b.idBarang == firstBarang.idBarang)
              .stokBarang,
          initialStock,
        );
      },
    );

    testWidgets(
      'Alur UI Faktur Masuk -> Riwayat Faktur -> Detail Edit -> Hapus Faktur & bebas overflow 320x568 skala 1.4x',
      (tester) async {
        final vm = await setupTxVm(tester);
        final targetBarang = vm.barangs.first;
        final initialStock = targetBarang.stokBarang;

        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SyncService>.value(value: syncService),
              Provider<InventoryRepository>.value(value: inventoryRepository),
              ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.4),
                ),
                child: child!,
              ),
              home: FakturMasukScreen(viewModel: vm),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Pilih barang dari Katalog Bottom Sheet
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('faktur_add_catalog_button')),
        );
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.text(targetBarang.namaBarang).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Selesai'));
        await tester.pumpAndSettle();

        // Verifikasi preview proyeksi stok `Stok: X → X+1` tampil dan tidak overflow
        await tester.ensureVisible(
          find.text('Stok: $initialStock → ${initialStock + 1}'),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Stok: $initialStock → ${initialStock + 1}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('faktur_submit_button')));
        await flushAsync(tester, until: () => vm.fakturs.length == 1);
        expect(vm.errorMessage, isNull);
        expect(vm.fakturs.length, 1);
        final savedFaktur = vm.fakturs.first;
        expect(
          vm.barangs
              .firstWhere((b) => b.idBarang == targetBarang.idBarang)
              .stokBarang,
          initialStock + 1,
        );

        // Buka Riwayat Faktur -> Detail Edit -> Hapus Faktur
        await tester.tap(find.text('Riwayat'));
        await tester.pumpAndSettle();
        expect(find.text('Riwayat Faktur Masuk'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await scrollAndTap(
          tester,
          find.byKey(ValueKey('faktur_card_${savedFaktur.idFaktur}')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('detail_faktur_delete_button')),
        );
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('confirm_delete_tx_button')),
        );
        await flushAsync(tester, until: () => vm.fakturs.isEmpty);
        expect(vm.fakturs, isEmpty);
        expect(
          vm.barangs
              .firstWhere((b) => b.idBarang == targetBarang.idBarang)
              .stokBarang,
          initialStock,
        );
      },
    );
  });

  group('Fungsi 5 - UI Rekap Omzet & Ekspor Laporan (Pendev 20)', () {
    Future<void> flushAsyncUi(
      WidgetTester tester, {
      bool Function()? until,
    }) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        if (until != null && until()) break;
      }
      await tester.pumpAndSettle();
    }

    Future<void> scrollAndTapRekap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    testWidgets(
      'Alur lengkap Rekap Omzet: filter periode, klik grafik 7 hari, expand produk & ekspor CSV/Teks',
      (tester) async {
        final exportTemp = Directory.systemTemp.createTempSync(
          'dt36_ui_export_',
        );
        addTearDown(() {
          if (exportTemp.existsSync()) {
            exportTemp.deleteSync(recursive: true);
          }
        });

        final ownerSession = AuthSession(
          uid: 'ui-rekap-owner',
          email: 'owner.rekap@depottelur36.com',
          accountId: 'owner_rekap_1',
          displayName: 'Budi Owner',
          role: UserRole.owner,
          petugasRemoteId: 'rekap-owner-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 16),
        );

        await tester.runAsync(() async {
          await inventoryRepository.savePetugas(
            existingRemoteId: 'rekap-owner-remote',
            namaPetugas: 'Budi Owner',
            role: UserRole.owner,
            pin: '9988',
            email: 'owner.rekap@depottelur36.com',
          );
          final barangs = await inventoryRepository.getAllBarang();
          final telur = barangs.firstWhere(
            (b) => b.remoteId == 'seed-barang-telur-negeri-kg',
          );
          final minyak = barangs.firstWhere(
            (b) => b.remoteId == 'seed-barang-minyak-1l',
          );
          final supplier = (await inventoryRepository.getAllSupplier()).first;
          final customer = (await inventoryRepository.getAllCustomer()).first;
          final owner = (await inventoryRepository.getAllPetugas()).firstWhere(
            (p) => p.remoteId == 'rekap-owner-remote',
          );

          // Nota hari ini (16 Feb 2026) -> 2 Kg Telur (Rp 57.000)
          await inventoryRepository.createNota(
            tanggalNota: '2026-02-16',
            customer: customer,
            petugas: owner,
            items: [(barang: telur, banyaknya: 2)],
          );
          // Nota 3 hari lalu (13 Feb 2026) -> 4 Pouch Minyak (Rp 70.000)
          await inventoryRepository.createNota(
            tanggalNota: '2026-02-13',
            customer: customer,
            petugas: owner,
            items: [(barang: minyak, banyaknya: 4)],
          );
          // Faktur hari ini (16 Feb 2026) -> 10 Kg Telur (Rp 285.000)
          await inventoryRepository.createFaktur(
            noFaktur: 'FKT-OMZ-01',
            tanggalFaktur: '2026-02-16',
            supplier: supplier,
            petugas: owner,
            items: [(barang: telur, quantity: 10)],
          );
        });

        final vm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: inventoryRepository,
          exportDirectory: exportTemp,
          nowProvider: () => DateTime(2026, 2, 16, 10, 0),
        );
        addTearDown(vm.dispose);
        await tester.runAsync(() => vm.loadData());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SyncService>.value(value: syncService),
              Provider<InventoryRepository>.value(value: inventoryRepository),
              ChangeNotifierProvider<AuthViewModel>.value(value: viewModel),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: RekapOmzetScreen(viewModel: vm),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Rekap Omzet'), findsOneWidget);
        expect(find.text('Total Penjualan Nota'), findsOneWidget);
        expect(find.text('Rp 57.000'), findsWidgets);
        expect(find.text('2 Unit'), findsOneWidget);

        // Pindah filter ke `7 Hari` -> menggabungkan 13 Feb & 16 Feb (57.000 + 70.000 = 127.000)
        await tester.tap(find.byKey(const ValueKey('rekap_period_tujuhHari')));
        await tester.pumpAndSettle();
        expect(find.text('Rp 127.000'), findsOneWidget);
        expect(find.text('6 Unit'), findsOneWidget);

        // Ketuk batang grafik indeks 3 (13 Feb 2026 = Rp 70.000) -> callout hari aktif berubah
        await scrollAndTapRekap(
          tester,
          find.byKey(const ValueKey('rekap_chart_bar_3')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Rp 70.000 (1 Nota)'), findsOneWidget);

        // Ketuk produk untuk membuka detail porsi omzet (SoftAnimatedReveal)
        await scrollAndTapRekap(
          tester,
          find.text('Minyak Goreng Kemasan 1 Liter'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Porsi omzet:'), findsOneWidget);

        // Buka sheet Ekspor -> salin laporan -> ubah ke Teks -> simpan file nyata ke disk
        await scrollAndTapRekap(
          tester,
          find.byKey(const ValueKey('rekap_omzet_export_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ekspor Laporan Omzet'), findsOneWidget);

        String? copiedClipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedClipboardText =
                  (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await scrollAndTapRekap(
          tester,
          find.byKey(const ValueKey('rekap_export_copy_btn')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tersalin!'), findsOneWidget);
        expect(copiedClipboardText, contains('LAPORAN REKAP OMZET DEPOTELUR36'));
        expect(copiedClipboardText, contains('Telur Ayam Negeri'));

        await scrollAndTapRekap(
          tester,
          find.byKey(const ValueKey('rekap_export_format_ringkasanTeks')),
        );
        await tester.pumpAndSettle();

        await scrollAndTapRekap(
          tester,
          find.byKey(const ValueKey('rekap_export_save_btn')),
        );
        await flushAsyncUi(
          tester,
          until: () => vm.lastExportResult?.filePath != null,
        );
        final savedPath = vm.lastExportResult?.filePath;
        expect(savedPath, isNotNull);
        expect(File(savedPath!).existsSync(), isTrue);
        await tester.pump(const Duration(seconds: 3));
      },
    );

    testWidgets(
      'RBAC Operator ditolak & viewport sempit 320x568 skala 1.4x Reduce Motion bebas overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final opSession = AuthSession(
          uid: 'ui-rekap-op',
          email: 'op.rekap@depottelur36.com',
          accountId: 'op_rekap',
          displayName: 'Kasir Uji',
          role: UserRole.petugas,
          petugasRemoteId: 'op-rekap-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 16),
        );
        final opVm = RekapOmzetViewModel.fromRepository(
          session: opSession,
          repository: inventoryRepository,
        );
        addTearDown(opVm.dispose);
        await tester.runAsync(() => opVm.loadData());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: RekapOmzetScreen(viewModel: opVm),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Akses Ditolak (Khusus Owner)'), findsOneWidget);
        expect(find.byKey(const ValueKey('rekap_omzet_export_btn')), findsNothing);
        expect(tester.takeException(), isNull);

        // Sekarang uji akun Owner pada 320x568 skala 1.4x beserta dialog Ekspor
        final ownerSession = AuthSession(
          uid: 'ui-rekap-owner-compact',
          email: 'owner.compact@depottelur36.com',
          accountId: 'owner_compact',
          displayName: 'Owner Uji',
          role: UserRole.owner,
          petugasRemoteId: 'owner-compact-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 16),
        );
        final ownerVm = RekapOmzetViewModel.fromRepository(
          session: ownerSession,
          repository: inventoryRepository,
          nowProvider: () => DateTime(2026, 2, 16),
        );
        addTearDown(ownerVm.dispose);
        await tester.runAsync(() => ownerVm.loadData());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: RekapOmzetScreen(viewModel: ownerVm),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Rekap Omzet'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('rekap_omzet_export_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Ekspor Laporan Omzet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Fungsi 6 - UI Pemantauan & Aksi Restok (Pendev 22)', () {
    Future<void> flushAsyncUi(
      WidgetTester tester, {
      bool Function()? until,
    }) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        if (until != null && until()) break;
      }
      await tester.pumpAndSettle();
    }

    Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    testWidgets(
      'Navigasi Beranda & Notifikasi ke Stok Menipis, switch filter, stepper micro-interaction & prefill Faktur',
      (tester) async {
        final ownerSession = AuthSession(
          uid: 'ui-restock-owner',
          email: 'owner.restock@depottelur36.com',
          accountId: 'owner_restock',
          displayName: 'Owner Restok',
          role: UserRole.owner,
          petugasRemoteId: 'restock-owner-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 18),
        );

        await tester.runAsync(() async {
          await inventoryRepository.savePetugas(
            existingRemoteId: 'restock-owner-remote',
            namaPetugas: 'Owner Restok',
            role: UserRole.owner,
            pin: '1122',
            email: 'owner.restock@depottelur36.com',
          );
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-crit-puyuh',
            namaBarang: 'Telur Puyuh Kemasan',
            hargaSatuan: 17500,
            satuan: 'Pouch',
            stokBarang: 1,
          );
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-watch-bebek',
            namaBarang: 'Telur Bebek Asin',
            hargaSatuan: 42000,
            satuan: 'Tray',
            stokBarang: 18,
          );
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-safe-jagung',
            namaBarang: 'Pakan Jagung Halus',
            hargaSatuan: 95000,
            satuan: 'Sak',
            stokBarang: 45,
          );
          await inventoryRepository.saveSupplier(
            existingRemoteId: 'mon-sup-berkah',
            namaSupplier: 'Berkah Sentosa',
            noTelpSupplier: '081299900011',
            alamatSupplier: 'Jl. Gudang Raya 9',
          );
          final crit = (await inventoryRepository.getAllBarang()).firstWhere(
            (b) => b.remoteId == 'mon-crit-puyuh',
          );
          final supplier =
              (await inventoryRepository.getAllSupplier()).firstWhere(
            (s) => s.remoteId == 'mon-sup-berkah',
          );
          final petugas = (await inventoryRepository.getAllPetugas()).firstWhere(
            (p) => p.remoteId == 'restock-owner-remote',
          );
          await inventoryRepository.createFaktur(
            noFaktur: 'FKT-RST-01',
            tanggalFaktur: '2026-02-15',
            supplier: supplier,
            petugas: petugas,
            items: [(barang: crit, quantity: 5)],
          );
        });

        await tester.pumpWidget(
          Provider<InventoryRepository>.value(
            value: inventoryRepository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: RoleHomeShellScreen(initialSession: ownerSession),
            ),
          ),
        );
        await flushAsyncUi(
          tester,
          until: () =>
              find
                  .byKey(const ValueKey('home_open_restock_monitor_btn'))
                  .evaluate()
                  .isNotEmpty,
        );

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('home_open_restock_monitor_btn')),
        );
        await flushAsyncUi(
          tester,
          until: () => find.text('Stok Menipis').evaluate().isNotEmpty,
        );
        expect(find.text('Stok Menipis'), findsOneWidget);
        expect(find.text('Telur Puyuh Kemasan'), findsOneWidget);
        expect(find.textContaining('Berkah Sentosa'), findsWidgets);

        // Kembali lalu uji jalur kedua lewat NotificationCenterSheet
        await tester.tap(find.byKey(const ValueKey('stok_menipis_back_btn')));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Notifikasi & Sinkronisasi'));
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('notif_open_restock_monitor_btn')),
        );
        await flushAsyncUi(
          tester,
          until: () => find.text('Stok Menipis').evaluate().isNotEmpty,
        );

        // Stepper micro-interaction (+2 => 16, -1 => 15)
        expect(
          find.text('Saran restok +14 Pouch ke faktur'),
          findsOneWidget,
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_inc_mon-crit-puyuh')),
        );
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_inc_mon-crit-puyuh')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Saran restok +16 Pouch ke faktur'),
          findsOneWidget,
        );
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_dec_mon-crit-puyuh')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Saran restok +15 Pouch ke faktur'),
          findsOneWidget,
        );

        // Switch filter Pantauan (<= 25) dan Semua
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_filter_pantauan')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Pantauan Stok (11–25)'), findsOneWidget);
        expect(find.text('Telur Bebek Asin'), findsOneWidget);

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_filter_semua')),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Pakan Jagung Halus'));
        await tester.pumpAndSettle();
        expect(find.text('Stok Aman (> 25)'), findsOneWidget);
        expect(find.text('Pakan Jagung Halus'), findsOneWidget);

        // Balik ke filter Kritis dan klik Buat Faktur
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_filter_kritis')),
        );
        await tester.pumpAndSettle();
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_create_faktur_mon-crit-puyuh')),
        );
        await flushAsyncUi(
          tester,
          until: () =>
              find.text('Faktur Barang Masuk').evaluate().isNotEmpty,
        );
        expect(find.text('Faktur Barang Masuk'), findsOneWidget);
        expect(find.text('Telur Puyuh Kemasan'), findsWidgets);
        expect(find.text('15'), findsOneWidget);
        expect(find.textContaining('Berkah Sentosa'), findsWidgets);
      },
    );

    testWidgets(
      'Validasi batas bawah qty=1 memicu ShakeOnError, QuickFaktur & 320x568 1.4x bebas overflow',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final opSession = AuthSession(
          uid: 'ui-restock-op',
          email: 'op.restock@depottelur36.com',
          accountId: 'op_restock',
          displayName: 'Operator Gudang',
          role: UserRole.petugas,
          petugasRemoteId: 'restock-op-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 18),
        );

        await tester.runAsync(() async {
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-empty-tray',
            namaBarang: 'Egg Tray Karton Tebal',
            hargaSatuan: 1200,
            satuan: 'Lembar',
            stokBarang: 0,
          );
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-watch-sak',
            namaBarang: 'Dedak Halus 50kg',
            hargaSatuan: 115000,
            satuan: 'Sak',
            stokBarang: 19,
          );
        });

        final restockVm = RestockMonitorViewModel.fromRepository(
          session: opSession,
          repository: inventoryRepository,
        );
        addTearDown(restockVm.dispose);
        await tester.runAsync(() => restockVm.loadData());
        final emptyBarang = restockVm.snapshot.criticalItems
            .firstWhere((i) => i.barang.remoteId == 'mon-empty-tray')
            .barang;
        restockVm.setDraftQty(emptyBarang, 1);

        RestockMonitorItem? triggeredItem;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: StokMenipisScreen(
              viewModel: restockVm,
              onStartRestockFaktur: (item) => triggeredItem = item,
              onOpenEmptyFaktur: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Habis'), findsOneWidget);

        // Tekan decrement saat draftQty = 1 -> validasi shake banner muncul
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_dec_mon-empty-tray')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('minimal 1 Lembar'),
          findsOneWidget,
        );

        // Quick Faktur pada baris Pantauan
        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_quick_faktur_mon-watch-sak')),
        );
        await tester.pumpAndSettle();
        expect(triggeredItem?.barang.remoteId, 'mon-watch-sak');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Operator ketuk kartu LowStockAlertCard -> Stok Menipis -> Buat Faktur otomatis pindah ke tab Faktur + snackbar',
      (tester) async {
        final opSession = AuthSession(
          uid: 'ui-restock-op-route',
          email: 'op.route@depottelur36.com',
          accountId: 'op_route',
          displayName: 'Operator Kasir',
          role: UserRole.petugas,
          petugasRemoteId: 'restock-op-route-remote',
          provider: AuthProviderType.emailPassword,
          signedInAt: DateTime(2026, 2, 18),
        );

        await tester.runAsync(() async {
          await inventoryRepository.savePetugas(
            existingRemoteId: 'restock-op-route-remote',
            namaPetugas: 'Operator Kasir',
            role: UserRole.petugas,
            pin: '3344',
            email: 'op.route@depottelur36.com',
          );
          await inventoryRepository.saveBarang(
            existingRemoteId: 'mon-op-crit-item',
            namaBarang: 'Telur Omega Pack',
            hargaSatuan: 31000,
            satuan: 'Pack',
            stokBarang: 5,
          );
        });

        await tester.pumpWidget(
          Provider<InventoryRepository>.value(
            value: inventoryRepository,
            child: MaterialApp(
              theme: AppTheme.light(),
              home: RoleHomeShellScreen(initialSession: opSession),
            ),
          ),
        );
        await flushAsyncUi(
          tester,
          until: () =>
              find.textContaining('Telur Omega Pack').evaluate().isNotEmpty,
        );

        // Ketuk badan kartu LowStockAlertCard (bukan tombol 'Restock')
        await scrollAndTap(tester, find.textContaining('Telur Omega Pack').first);
        await flushAsyncUi(
          tester,
          until: () => find.text('Stok Menipis').evaluate().isNotEmpty,
        );
        expect(find.text('Stok Menipis'), findsOneWidget);

        await scrollAndTap(
          tester,
          find.byKey(const ValueKey('restock_create_faktur_mon-op-crit-item')),
        );
        await tester.pumpAndSettle();
        // Tab berpindah ke Faktur Masuk (tertanam di shell Operator) & snackbar muncul
        expect(find.text('Faktur Barang Masuk'), findsOneWidget);
        expect(
          find.textContaining('Siap restock Telur Omega Pack (+15 Pack)'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4));
      },
    );
  });
}
