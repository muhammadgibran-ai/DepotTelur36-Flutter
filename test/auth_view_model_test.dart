import 'dart:async';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/viewmodels/auth_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopAuthGateway implements AuthGateway {
  @override
  AuthAccountSnapshot? get currentUser => null;

  @override
  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<Petugas?> findPetugasByEmail(String email) async => null;

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async => null;

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<AuthAccountSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {}
}

class _ControllableAuthRepository extends AuthRepository {
  _ControllableAuthRepository(SharedPreferences prefs)
      : super(
          dbHelper: DatabaseHelper.forTesting(customDbPath: ':memory:'),
          gateway: _NoopAuthGateway(),
          prefs: prefs,
          isOnlineChecker: () async => true,
        );

  Future<AuthSession?> Function()? onRestoreSession;
  Future<AuthSession> Function(String identifier, String password)? onSignIn;
  Future<AuthSession> Function(
    String fullName,
    String email,
    String password,
    String confirmPassword,
  )? onSignUp;
  Future<AuthSession> Function()? onGoogleSignIn;
  Future<String> Function(String identifierOrEmail)? onSendPasswordReset;
  Future<void> Function()? onSignOut;

  int signInCalls = 0;
  int signUpCalls = 0;
  int googleCalls = 0;
  int resetCalls = 0;
  int signOutCalls = 0;

  @override
  Future<AuthSession?> restoreSession() async {
    return onRestoreSession?.call();
  }

  @override
  Future<AuthSession> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    signInCalls++;
    return onSignIn!(identifier, password);
  }

  @override
  Future<AuthSession> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    signUpCalls++;
    return onSignUp!(fullName, email, password, confirmPassword);
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    googleCalls++;
    return onGoogleSignIn!();
  }

  @override
  Future<String> sendPasswordReset(String identifierOrEmail) async {
    resetCalls++;
    return onSendPasswordReset!(identifierOrEmail);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await onSignOut?.call();
  }
}

AuthSession _sampleSession({
  UserRole role = UserRole.owner,
  AuthProviderType provider = AuthProviderType.emailPassword,
}) {
  return AuthSession(
    uid: 'uid-sample-1',
    email: 'owner@depottelur36.com',
    accountId: 'owner01',
    displayName: 'Owner Toko',
    role: role,
    petugasRemoteId: 'ptg-owner-1',
    provider: provider,
    signedInAt: DateTime(2026, 2, 16),
  );
}

void main() {
  late _ControllableAuthRepository repo;
  late AuthViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    repo = _ControllableAuthRepository(prefs);
    viewModel = AuthViewModel(repository: repo);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('AuthViewModel Normal Scenarios', () {
    test('initialize tanpa sesi menghasilkan status unauthenticated & dengan sesi menghasilkan authenticated', () async {
      expect(viewModel.status, AuthStatus.initializing);

      await viewModel.initialize();
      expect(viewModel.status, AuthStatus.unauthenticated);
      expect(viewModel.session, isNull);

      final expected = _sampleSession();
      repo.onRestoreSession = () async => expected;
      await viewModel.initialize();
      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.session?.accountId, 'owner01');
    });

    test('signIn, sendPasswordReset, dan signOut mengatur status, pesan, serta state loading secara akurat', () async {
      final expected = _sampleSession();
      repo.onSignIn = (_, _) async => expected;
      repo.onSendPasswordReset = (id) async => '$id@depottelur36.com';

      final resetSent = await viewModel.sendPasswordReset('owner01');
      expect(resetSent, 'owner01@depottelur36.com');
      expect(
        viewModel.infoMessage,
        'Tautan reset password dikirim ke owner01@depottelur36.com.',
      );
      expect(viewModel.errorPulse, 0);

      final ok = await viewModel.signIn(
        identifier: 'owner01',
        password: 'password123',
      );
      expect(ok, isTrue);
      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.session, same(expected));
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.infoMessage, isNull);
      expect(viewModel.isAnyBusy, isFalse);

      await viewModel.signOut();
      expect(repo.signOutCalls, 1);
      expect(viewModel.status, AuthStatus.unauthenticated);
      expect(viewModel.session, isNull);
    });

    test('signUp dan signInWithGoogle sukses masuk ke status authenticated', () async {
      final kasirSession = _sampleSession(
        role: UserRole.petugas,
        provider: AuthProviderType.emailPassword,
      );
      repo.onSignUp = (_, _, _, _) async => kasirSession;

      final signedUp = await viewModel.signUp(
        fullName: 'Siti Kasir',
        email: 'siti@depottelur36.com',
        password: 'password123',
        confirmPassword: 'password123',
      );
      expect(signedUp, isTrue);
      expect(viewModel.session?.role, UserRole.petugas);

      await viewModel.signOut();

      final googleSession = _sampleSession(provider: AuthProviderType.google);
      repo.onGoogleSignIn = () async => googleSession;
      final googleOk = await viewModel.signInWithGoogle();
      expect(googleOk, isTrue);
      expect(viewModel.session?.provider, AuthProviderType.google);
    });
  });

  group('AuthViewModel Edge Cases, Concurrency & Race Conditions', () {
    test('menolak submit ganda maupun sendPasswordReset saat isAnyBusy bernilai true', () async {
      final completer = Completer<AuthSession>();
      repo.onSignIn = (_, _) => completer.future;

      final firstFuture = viewModel.signIn(
        identifier: 'owner01',
        password: 'password123',
      );
      expect(viewModel.isSubmitting, isTrue);
      expect(viewModel.isAnyBusy, isTrue);

      // Panggilan tumpang tindih wajib diabaikan
      expect(
        await viewModel.signIn(identifier: 'owner01', password: 'password123'),
        isFalse,
      );
      expect(
        await viewModel.signUp(
          fullName: 'Test',
          email: 'a@b.com',
          password: 'password123',
          confirmPassword: 'password123',
        ),
        isFalse,
      );
      expect(await viewModel.signInWithGoogle(), isFalse);
      expect(await viewModel.sendPasswordReset('owner01'), isNull);

      expect(repo.signInCalls, 1);
      expect(repo.signUpCalls, 0);
      expect(repo.googleCalls, 0);
      expect(repo.resetCalls, 0);

      completer.complete(_sampleSession());
      expect(await firstFuture, isTrue);
      expect(viewModel.isAnyBusy, isFalse);
    });

    test('signOut saat signIn masih pending mencegah hasil signIn lama menghidupkan sesi kembali', () async {
      final completer = Completer<AuthSession>();
      repo.onSignIn = (_, _) => completer.future;

      final signInFuture = viewModel.signIn(
        identifier: 'owner01',
        password: 'password123',
      );
      await viewModel.signOut();

      completer.complete(_sampleSession());
      final result = await signInFuture;

      expect(result, isFalse);
      expect(viewModel.status, AuthStatus.unauthenticated);
      expect(viewModel.session, isNull);
    });

    test('initialize yang lambat tidak menimpa sesi jika user sudah login duluan', () async {
      final restoreCompleter = Completer<AuthSession?>();
      repo.onRestoreSession = () => restoreCompleter.future;
      final freshSession = _sampleSession();
      repo.onSignIn = (_, _) async => freshSession;

      final initFuture = viewModel.initialize();
      await viewModel.signIn(identifier: 'owner01', password: 'password123');
      restoreCompleter.complete(null);
      await initFuture;

      expect(viewModel.status, AuthStatus.authenticated);
      expect(viewModel.session, same(freshSession));
    });

    test('Google Sign-In dibatalkan mengisi infoMessage tanpa menaikkan errorPulse atau errorMessage', () async {
      repo.onGoogleSignIn = () async {
        throw const AuthGatewayException(
          AuthFailureCode.cancelled,
          'Masuk dengan Google dibatalkan.',
        );
      };

      final ok = await viewModel.signInWithGoogle();
      expect(ok, isFalse);
      expect(viewModel.infoMessage, 'Masuk dengan Google dibatalkan.');
      expect(viewModel.errorMessage, isNull);
      expect(viewModel.errorPulse, 0);
    });

    test('clearFeedback menghemat notifyListeners bila kosong & menghapus pesan bila terisi', () {
      var notifyCount = 0;
      viewModel.addListener(() => notifyCount++);

      viewModel.clearFeedback();
      expect(notifyCount, 0);

      viewModel.registerValidationFailure('Email salah');
      expect(notifyCount, 1);
      expect(viewModel.errorMessage, 'Email salah');
      expect(viewModel.errorPulse, 1);

      viewModel.clearFeedback();
      expect(notifyCount, 2);
      expect(viewModel.errorMessage, isNull);
    });

    test('dispose saat operasi async berjalan tidak memicu error ChangeNotifier disposed', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final localRepo = _ControllableAuthRepository(prefs);
      final localVm = AuthViewModel(repository: localRepo);

      final completer = Completer<AuthSession>();
      localRepo.onSignIn = (_, _) => completer.future;

      final pending = localVm.signIn(
        identifier: 'owner01',
        password: 'password123',
      );
      localVm.dispose();

      completer.complete(_sampleSession());
      await expectLater(pending, completion(isTrue));
    });
  });

  group('AuthViewModel Invalid Input & Unexpected Exceptions', () {
    test('menangkap AuthGatewayException dan exception tak terduga dengan reset loading flag', () async {
      repo.onSignIn = (_, _) async {
        throw const AuthGatewayException(
          AuthFailureCode.invalidCredentials,
          'Password salah.',
        );
      };
      expect(
        await viewModel.signIn(identifier: 'owner01', password: 'salah'),
        isFalse,
      );
      expect(viewModel.errorMessage, 'Password salah.');
      expect(viewModel.errorPulse, 1);
      expect(viewModel.isAnyBusy, isFalse);

      repo.onSignUp = (_, _, _, _) async => throw StateError('Unexpected');
      expect(
        await viewModel.signUp(
          fullName: 'Kasir',
          email: 'k@depottelur36.com',
          password: 'password123',
          confirmPassword: 'password123',
        ),
        isFalse,
      );
      expect(
        viewModel.errorMessage,
        'Pendaftaran gagal diproses. Silakan coba lagi.',
      );
      expect(viewModel.errorPulse, 2);
      expect(viewModel.isAnyBusy, isFalse);

      repo.onGoogleSignIn = () async => throw StateError('Google crash');
      expect(await viewModel.signInWithGoogle(), isFalse);
      expect(
        viewModel.errorMessage,
        'Gagal masuk dengan Google. Silakan coba lagi.',
      );
      expect(viewModel.errorPulse, 3);
      expect(viewModel.isAnyBusy, isFalse);

      repo.onSendPasswordReset = (_) async => throw StateError('Reset crash');
      expect(await viewModel.sendPasswordReset('k@depottelur36.com'), isNull);
      expect(
        viewModel.errorMessage,
        'Gagal mengirim tautan reset password.',
      );
      expect(viewModel.errorPulse, 4);
      expect(viewModel.isAnyBusy, isFalse);
    });

    test('initialize saat restoreSession melempar error tetap aman jatuh ke unauthenticated', () async {
      repo.onRestoreSession = () async => throw Exception('Prefs korup');
      await viewModel.initialize();
      expect(viewModel.status, AuthStatus.unauthenticated);
      expect(viewModel.session, isNull);
    });
  });
}
