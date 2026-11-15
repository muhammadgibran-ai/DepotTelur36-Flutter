import 'dart:async';
import 'dart:io';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/main.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/screens/auth/sign_in_screen.dart';
import 'package:depot_telur_36/screens/auth/sign_up_screen.dart';
import 'package:depot_telur_36/screens/auth/welcome_screen.dart';
import 'package:depot_telur_36/screens/home/role_home_stub_screen.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
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

void main() {
  late Directory tempDir;
  late DatabaseHelper dbHelper;
  late _WidgetFakeAuthGateway gateway;
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
    final db = await dbHelper.database;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget wrapScreen(Widget screen, {bool disableAnimations = false}) {
    return ChangeNotifierProvider<AuthViewModel>.value(
      value: viewModel,
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

      expect(find.byType(RoleHomeStubScreen), findsOneWidget);
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

        expect(find.byType(RoleHomeStubScreen), findsOneWidget);
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

      expect(find.byType(RoleHomeStubScreen), findsOneWidget);
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

      expect(find.byType(RoleHomeStubScreen), findsOneWidget);
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

        // Selesaikan request -> harus masuk ke RoleHomeStubScreen
        gate.complete();
        await settleWithIo(tester);

        expect(find.byType(RoleHomeStubScreen), findsOneWidget);
        expect(find.text('DepotTelur36 Kasir'), findsOneWidget);
      },
    );
  });

  group('Accessibility & Contrast Audits', () {
    Future<void> auditScreen(WidgetTester tester, Widget screen) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(wrapScreen(screen));
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

    testWidgets('RoleHomeStubScreen memenuhi standar aksesibilitas', (
      tester,
    ) async {
      await auditScreen(
        tester,
        RoleHomeStubScreen(
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
  });
}
