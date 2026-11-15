import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/utils/password_hasher.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';
import 'package:depot_telur_36/services/sync_service.dart';

/// Repository autentikasi Hybrid Offline-First untuk DepotTelur36:
/// - Online: Firebase Auth & Google Sign-In + sinkronisasi profil `petugas` ke Firestore & SQLite.
/// - Offline: lookup ID Akun/Email & verifikasi hash password/PIN ter-cache di SQLite
///   serta pemulihan sesi otomatis di `SharedPreferences`.
class AuthRepository {
  AuthRepository({
    DatabaseHelper? dbHelper,
    AuthGateway? gateway,
    SharedPreferences? prefs,
    Connectivity? connectivity,
    this._isOnlineChecker,
    this._syncService,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        _gateway = gateway ?? FirebaseAuthGateway(),
        _prefsOverride = prefs,
        _connectivity = connectivity ?? Connectivity();

  static const String sessionStorageKey = 'depot_telur_36_auth_session_v1';

  /// Penanda lokal non-hash untuk akun seed yang sudah tertaut ke Google OAuth,
  /// sehingga tidak lagi lolos fallback PIN default (`1234`/`1111`) offline/online.
  static const String _oauthLinkedPasswordSentinel = '__OAUTH_GOOGLE_LINKED__';

  static final RegExp _emailRegex = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
  );

  static final RegExp _controlCharsRegex = RegExp(r'[\x00-\x1F\x7F]');

  final DatabaseHelper _dbHelper;
  final AuthGateway _gateway;
  final SharedPreferences? _prefsOverride;
  final Connectivity _connectivity;
  final Future<bool> Function()? _isOnlineChecker;
  final SyncService? _syncService;

  Future<SharedPreferences> _getPrefs() async {
    return _prefsOverride ?? await SharedPreferences.getInstance();
  }

  static bool isValidEmail(String raw) {
    return _emailRegex.hasMatch(raw.trim());
  }

  static String? validateSignInIdentifier(String raw) {
    if (raw.trim().isEmpty) {
      return 'Masukkan ID Akun atau Email terlebih dahulu.';
    }
    if (_controlCharsRegex.hasMatch(raw)) {
      return 'ID Akun atau Email mengandung karakter tidak valid.';
    }
    return null;
  }

  static String? validatePassword(String raw) {
    if (raw.trim().isEmpty) {
      return 'Masukkan password terlebih dahulu.';
    }
    return null;
  }

  static String? validateSignUpFullName(String raw) {
    if (_controlCharsRegex.hasMatch(raw)) {
      return 'Nama lengkap mengandung karakter tidak valid.';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Masukkan nama lengkap Anda.';
    }
    if (trimmed.length < 2) {
      return 'Nama lengkap minimal 2 karakter.';
    }
    return null;
  }

  static String? validateSignUpEmail(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'Masukkan alamat email.';
    }
    if (!isValidEmail(trimmed)) {
      return 'Format email tidak valid.';
    }
    return null;
  }

  static String? validateNewPassword(String raw) {
    if (raw.trim().isEmpty) {
      return 'Masukkan password.';
    }
    if (raw.length < 6) {
      return 'Password minimal 6 karakter.';
    }
    return null;
  }

  static String? validateConfirmPassword(String password, String confirm) {
    if (confirm.trim().isEmpty) {
      return 'Masukkan konfirmasi password.';
    }
    if (password != confirm) {
      return 'Konfirmasi password tidak sama.';
    }
    return null;
  }

  /// Memulihkan sesi tersimpan lokal saat aplikasi dibuka (`01 Splash Screen`),
  /// lalu menyegarkan peran terbaru dari SQLite apabila ada pembaruan data petugas.
  Future<AuthSession?> restoreSession() async {
    final prefs = await _getPrefs();
    final stored = AuthSession.tryParseJson(prefs.getString(sessionStorageKey));
    if (stored == null) return null;

    Petugas? latestPetugas;
    if (stored.petugasRemoteId.isNotEmpty) {
      latestPetugas =
          await _dbHelper.getPetugasByRemoteId(stored.petugasRemoteId);
    }
    latestPetugas ??= stored.email.isNotEmpty
        ? await _dbHelper.getPetugasByEmail(stored.email)
        : null;

    if (latestPetugas == null) return stored;

    final updated = stored.copyWith(
      role: latestPetugas.role,
      displayName: latestPetugas.namaPetugas.isNotEmpty
          ? latestPetugas.namaPetugas
          : stored.displayName,
      accountId: latestPetugas.accountId.isNotEmpty
          ? latestPetugas.accountId
          : stored.accountId,
    );
    if (updated.role != stored.role ||
        updated.displayName != stored.displayName ||
        updated.accountId != stored.accountId) {
      await _persistSession(updated);
    }
    return updated;
  }

  /// Masuk dengan ID Akun atau Email dan Password (Online via Firebase Auth + Offline Fallback SQLite).
  Future<AuthSession> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final idErr = validateSignInIdentifier(identifier);
    if (idErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, idErr);
    }
    final passErr = validatePassword(password);
    if (passErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, passErr);
    }

    final cleanId = identifier.trim();
    var localMatch = await _dbHelper.findPetugasByIdentifier(cleanId);
    final online = await _isOnline();

    if (!online) {
      return _signInOffline(
        petugas: localMatch,
        rawPassword: password,
      );
    }

    Petugas? remoteMatch;
    if (!isValidEmail(cleanId) &&
        (localMatch == null || localMatch.email.isEmpty)) {
      try {
        remoteMatch = await _gateway.findPetugasByIdentifier(cleanId);
      } on AuthGatewayException catch (e) {
        if (e.code == AuthFailureCode.networkUnavailable) {
          if (localMatch != null) {
            return _signInOffline(petugas: localMatch, rawPassword: password);
          }
          rethrow;
        }
        if (localMatch == null) {
          rethrow;
        }
      }
    }

    final resolvedEmail = isValidEmail(cleanId)
        ? cleanId.toLowerCase()
        : (remoteMatch?.email.isNotEmpty == true
                ? remoteMatch!.email
                : (localMatch?.email ?? ''))
            .trim()
            .toLowerCase();

    if (resolvedEmail.isEmpty) {
      if (localMatch != null) {
        return _signInOffline(petugas: localMatch, rawPassword: password);
      }
      throw const AuthGatewayException(
        AuthFailureCode.userNotFound,
        'ID Akun tidak ditemukan di perangkat maupun cloud.',
      );
    }

    try {
      final account = await _gateway.signInWithEmailAndPassword(
        email: resolvedEmail,
        password: password,
      );
      localMatch ??= await _dbHelper.getPetugasByEmail(account.email);
      final remoteLookup = remoteMatch != null
          ? (petugas: remoteMatch, failed: false)
          : await _findRemotePetugasByEmailSafe(account.email);
      remoteMatch = remoteLookup.petugas;

      final role = _resolveRole(
        localPetugas: localMatch,
        remotePetugas: remoteMatch,
      );
      final remoteId = _resolveRemoteId(
        uid: account.uid,
        localPetugas: localMatch,
        remotePetugas: remoteMatch,
      );
      final displayName = _resolveDisplayName(
        accountName: account.displayName,
        localPetugas: localMatch,
        remotePetugas: remoteMatch,
        email: account.email,
      );
      final accountId = await _resolveAccountId(
        localPetugas: localMatch,
        remotePetugas: remoteMatch,
        email: account.email,
      );

      final canSyncCloud = localMatch != null || !remoteLookup.failed;
      final savedPetugas = Petugas(
        idPetugas: localMatch?.idPetugas,
        namaPetugas: displayName,
        role: role,
        pin: localMatch?.pin ?? remoteMatch?.pin ?? '1234',
        email: account.email,
        accountId: accountId,
        passwordHash: PasswordHasher.hashPassword(password),
        remoteId: remoteId,
        syncStatus: canSyncCloud ? SyncStatus.pending : SyncStatus.synced,
        updatedAt: DateTime.now(),
      );
      if (canSyncCloud) {
        await _savePetugasLocallyAndCloud(savedPetugas);
      } else {
        await _dbHelper.upsertPetugas(savedPetugas);
      }

      final session = AuthSession(
        uid: account.uid,
        email: account.email,
        accountId: accountId,
        displayName: displayName,
        role: role,
        petugasRemoteId: remoteId,
        provider: AuthProviderType.emailPassword,
        signedInAt: DateTime.now(),
      );
      await _persistSession(session);
      return session;
    } on AuthGatewayException catch (e) {
      if (e.code == AuthFailureCode.networkUnavailable) {
        return _signInOffline(petugas: localMatch, rawPassword: password);
      }
      // Hanya izinkan fallback PIN bawaan bila akun seed memang belum terdaftar
      // di Firestore/cloud; cegah bypass PIN default saat akun sudah teregistrasi.
      final isSeedAccount = localMatch != null &&
          localMatch.remoteId.startsWith('seed-petugas-') &&
          localMatch.passwordHash.isEmpty;
      if ((e.code == AuthFailureCode.userNotFound ||
              e.code == AuthFailureCode.invalidCredentials) &&
          isSeedAccount) {
        final cloudProfile = remoteMatch != null
            ? (petugas: remoteMatch, failed: false)
            : await _findRemotePetugasByEmailSafe(resolvedEmail);
        if (!cloudProfile.failed && cloudProfile.petugas == null) {
          if (localMatch.pin == password) {
            return _completeLocalSeedSession(localMatch);
          }
          throw const AuthGatewayException(
            AuthFailureCode.invalidCredentials,
            'Password atau PIN offline tidak sesuai.',
          );
        }
      }
      rethrow;
    }
  }

  /// Mendaftarkan akun baru melalui `04 Sign Up` dengan role default `PETUGAS`,
  /// kecuali email tersebut sudah tercatat sebagai `OWNER` di database toko.
  Future<AuthSession> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    final nameErr = validateSignUpFullName(fullName);
    if (nameErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, nameErr);
    }
    final emailErr = validateSignUpEmail(email);
    if (emailErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, emailErr);
    }
    final passErr = validateNewPassword(password);
    if (passErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, passErr);
    }
    final confirmErr = validateConfirmPassword(password, confirmPassword);
    if (confirmErr != null) {
      throw AuthGatewayException(AuthFailureCode.validation, confirmErr);
    }

    if (!await _isOnline()) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Pendaftaran akun baru membutuhkan koneksi internet. Silakan coba saat terhubung.',
      );
    }

    final cleanName = fullName.trim();
    final normalizedEmail = email.trim().toLowerCase();

    final localMatch = await _dbHelper.getPetugasByEmail(normalizedEmail);
    final account = await _gateway.createUserWithEmailAndPassword(
      fullName: cleanName,
      email: normalizedEmail,
      password: password,
    );
    final remoteLookup = await _findRemotePetugasByEmailSafe(account.email);
    final remoteMatch = remoteLookup.petugas;

    final role = _resolveRole(
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
    );
    final remoteId = _resolveRemoteId(
      uid: account.uid,
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
    );
    final accountId = await _resolveAccountId(
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
      email: account.email,
    );

    final petugas = Petugas(
      idPetugas: localMatch?.idPetugas,
      namaPetugas: cleanName,
      role: role,
      pin: localMatch?.pin ?? remoteMatch?.pin ?? '1111',
      email: account.email,
      accountId: accountId,
      passwordHash: PasswordHasher.hashPassword(password),
      remoteId: remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    await _savePetugasLocallyAndCloud(petugas);

    final session = AuthSession(
      uid: account.uid,
      email: account.email,
      accountId: accountId,
      displayName: cleanName,
      role: role,
      petugasRemoteId: remoteId,
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime.now(),
    );
    await _persistSession(session);
    return session;
  }

  /// Masuk atau daftar cepat dengan Google OAuth, mempertahankan role `OWNER` bila
  /// email sudah tercatat sebagai Owner atau default `PETUGAS` untuk akun baru.
  Future<AuthSession> signInWithGoogle() async {
    if (!await _isOnline()) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Masuk dengan Google membutuhkan koneksi internet.',
      );
    }

    final account = await _gateway.signInWithGoogle();
    final normalizedEmail = account.email.trim().toLowerCase();
    if (account.uid.trim().isEmpty || !isValidEmail(normalizedEmail)) {
      throw const AuthGatewayException(
        AuthFailureCode.configuration,
        'Data akun Google tidak lengkap atau email tidak tersedia.',
      );
    }

    final localMatch = await _dbHelper.getPetugasByEmail(normalizedEmail);
    final remoteLookup = await _findRemotePetugasByEmailSafe(normalizedEmail);
    final remoteMatch = remoteLookup.petugas;

    final role = _resolveRole(
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
    );
    final remoteId = _resolveRemoteId(
      uid: account.uid,
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
    );
    final displayName = _resolveDisplayName(
      accountName: account.displayName,
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
      email: normalizedEmail,
    );
    final accountId = await _resolveAccountId(
      localPetugas: localMatch,
      remotePetugas: remoteMatch,
      email: normalizedEmail,
    );

    final existingHash = localMatch?.passwordHash ?? '';
    final passwordHash = existingHash.isNotEmpty
        ? existingHash
        : _oauthLinkedPasswordSentinel;
    final canSyncCloud = localMatch != null || !remoteLookup.failed;

    final petugas = Petugas(
      idPetugas: localMatch?.idPetugas,
      namaPetugas: displayName,
      role: role,
      pin: localMatch?.pin ?? remoteMatch?.pin ?? '1111',
      email: normalizedEmail,
      accountId: accountId,
      passwordHash: passwordHash,
      remoteId: remoteId,
      syncStatus: canSyncCloud ? SyncStatus.pending : SyncStatus.synced,
      updatedAt: DateTime.now(),
    );
    if (canSyncCloud) {
      await _savePetugasLocallyAndCloud(petugas);
    } else {
      await _dbHelper.upsertPetugas(petugas);
    }

    final session = AuthSession(
      uid: account.uid,
      email: normalizedEmail,
      accountId: accountId,
      displayName: displayName,
      role: role,
      petugasRemoteId: remoteId,
      provider: AuthProviderType.google,
      signedInAt: DateTime.now(),
    );
    await _persistSession(session);
    return session;
  }

  /// Mengirim tautan reset password ke email yang diketik atau di-resolve dari ID Akun.
  Future<String> sendPasswordReset(String identifierOrEmail) async {
    final trimmed = identifierOrEmail.trim();
    if (trimmed.isEmpty) {
      throw const AuthGatewayException(
        AuthFailureCode.validation,
        'Masukkan ID Akun atau Email untuk reset password.',
      );
    }
    if (!await _isOnline()) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Reset password membutuhkan koneksi internet.',
      );
    }

    var targetEmail = isValidEmail(trimmed) ? trimmed.toLowerCase() : '';
    if (targetEmail.isEmpty) {
      final local = await _dbHelper.findPetugasByIdentifier(trimmed);
      final remote = local?.email.isNotEmpty == true
          ? null
          : await _gateway.findPetugasByIdentifier(trimmed);
      targetEmail = (local?.email.isNotEmpty == true
              ? local!.email
              : (remote?.email ?? ''))
          .trim()
          .toLowerCase();
    }

    if (!isValidEmail(targetEmail)) {
      throw const AuthGatewayException(
        AuthFailureCode.validation,
        'Email untuk akun tersebut tidak ditemukan atau formatnya tidak valid.',
      );
    }

    await _gateway.sendPasswordResetEmail(targetEmail);
    return targetEmail;
  }

  Future<void> signOut() async {
    final prefs = await _getPrefs();
    await prefs.remove(sessionStorageKey);
    await _gateway.signOut();
  }

  Future<AuthSession> _signInOffline({
    required Petugas? petugas,
    required String rawPassword,
  }) async {
    if (petugas == null) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Sedang offline dan akun belum tersimpan di perangkat. Hubungkan ke internet untuk login pertama kali.',
      );
    }

    final validHash = petugas.passwordHash.isNotEmpty &&
        PasswordHasher.verify(rawPassword, petugas.passwordHash);
    final validSeedPin = _isUnmigratedSeedMatch(petugas, rawPassword);

    if (!validHash && !validSeedPin) {
      throw const AuthGatewayException(
        AuthFailureCode.invalidCredentials,
        'Password atau PIN offline tidak sesuai.',
      );
    }

    final session = AuthSession(
      uid: petugas.remoteId,
      email: petugas.email.toLowerCase(),
      accountId: petugas.accountId,
      displayName: petugas.namaPetugas,
      role: petugas.role,
      petugasRemoteId: petugas.remoteId,
      provider: AuthProviderType.offlineLocal,
      signedInAt: DateTime.now(),
    );
    await _persistSession(session);
    return session;
  }

  bool _isUnmigratedSeedMatch(Petugas? petugas, String rawPassword) {
    if (petugas == null) return false;
    return petugas.remoteId.startsWith('seed-petugas-') &&
        petugas.passwordHash.isEmpty &&
        petugas.pin == rawPassword;
  }

  Future<AuthSession> _completeLocalSeedSession(Petugas petugas) async {
    final session = AuthSession(
      uid: petugas.remoteId,
      email: petugas.email.toLowerCase(),
      accountId: petugas.accountId,
      displayName: petugas.namaPetugas,
      role: petugas.role,
      petugasRemoteId: petugas.remoteId,
      provider: AuthProviderType.offlineLocal,
      signedInAt: DateTime.now(),
    );
    await _persistSession(session);
    return session;
  }

  Future<({Petugas? petugas, bool failed})> _findRemotePetugasByEmailSafe(
    String email,
  ) async {
    try {
      final result = await _gateway.findPetugasByEmail(email);
      return (petugas: result, failed: false);
    } catch (_) {
      return (petugas: null, failed: true);
    }
  }

  UserRole _resolveRole({
    Petugas? localPetugas,
    Petugas? remotePetugas,
  }) {
    if (remotePetugas?.role == UserRole.owner ||
        localPetugas?.role == UserRole.owner) {
      return UserRole.owner;
    }
    return remotePetugas?.role ?? localPetugas?.role ?? UserRole.petugas;
  }

  String _resolveRemoteId({
    required String uid,
    Petugas? localPetugas,
    Petugas? remotePetugas,
  }) {
    if (remotePetugas != null && remotePetugas.remoteId.isNotEmpty) {
      return remotePetugas.remoteId;
    }
    if (localPetugas != null && localPetugas.remoteId.isNotEmpty) {
      return localPetugas.remoteId;
    }
    return uid;
  }

  String _resolveDisplayName({
    required String accountName,
    Petugas? localPetugas,
    Petugas? remotePetugas,
    required String email,
  }) {
    if (accountName.trim().isNotEmpty) return accountName.trim();
    if (remotePetugas != null && remotePetugas.namaPetugas.trim().isNotEmpty) {
      return remotePetugas.namaPetugas.trim();
    }
    if (localPetugas != null && localPetugas.namaPetugas.trim().isNotEmpty) {
      return localPetugas.namaPetugas.trim();
    }
    final localPart = email.split('@').first;
    return localPart.isNotEmpty ? localPart : 'Petugas DepotTelur36';
  }

  Future<String> _resolveAccountId({
    Petugas? localPetugas,
    Petugas? remotePetugas,
    required String email,
  }) async {
    if (localPetugas != null && localPetugas.accountId.trim().isNotEmpty) {
      return localPetugas.accountId.trim();
    }
    if (remotePetugas != null && remotePetugas.accountId.trim().isNotEmpty) {
      return remotePetugas.accountId.trim();
    }
    final normalizedEmail = email.trim().toLowerCase();
    final prefix = normalizedEmail.split('@').first.trim().toLowerCase();
    final basePrefix = prefix.isNotEmpty ? prefix : 'petugas';
    return _ensureUniqueAccountId(basePrefix, ownerEmail: normalizedEmail);
  }

  Future<String> _ensureUniqueAccountId(
    String basePrefix, {
    required String ownerEmail,
  }) async {
    Future<bool> isTakenByOther(String candidate) async {
      final local = await _dbHelper.findPetugasByIdentifier(candidate);
      if (local != null &&
          local.email.trim().toLowerCase() != ownerEmail) {
        return true;
      }
      try {
        final remote = await _gateway.findPetugasByIdentifier(candidate);
        if (remote != null &&
            remote.email.trim().toLowerCase() != ownerEmail) {
          return true;
        }
      } catch (_) {}
      return false;
    }

    if (!await isTakenByOther(basePrefix)) {
      return basePrefix;
    }
    for (var suffix = 2; suffix < 1000; suffix++) {
      final candidate = '${basePrefix}_$suffix';
      if (!await isTakenByOther(candidate)) {
        return candidate;
      }
    }
    return '${basePrefix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _savePetugasLocallyAndCloud(Petugas petugas) async {
    await _dbHelper.upsertPetugas(petugas);
    try {
      await _gateway.upsertPetugasProfile(petugas);
      await _dbHelper.markSynced('petugas', petugas.remoteId);
    } catch (_) {
      // Tetap biarkan PENDING di SQLite bila sync gagal agar otomatis terkirim oleh SyncService.
    }
    await _syncService?.refreshPendingCount();
  }

  Future<void> _persistSession(AuthSession session) async {
    final prefs = await _getPrefs();
    await prefs.setString(sessionStorageKey, session.toJson());
  }

  Future<bool> _isOnline() async {
    if (_isOnlineChecker != null) {
      return _isOnlineChecker();
    }
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
