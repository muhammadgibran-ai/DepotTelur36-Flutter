import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/services/sync_service.dart';

/// Kode klasifikasi kegagalan autentikasi untuk pesan & penanganan konsisten.
enum AuthFailureCode {
  validation,
  invalidCredentials,
  userNotFound,
  emailAlreadyInUse,
  weakPassword,
  networkUnavailable,
  cancelled,
  tooManyRequests,
  configuration,
  unknown,
}

class AuthGatewayException implements Exception {
  const AuthGatewayException(this.code, this.message);

  final AuthFailureCode code;
  final String message;

  @override
  String toString() => 'AuthGatewayException($code): $message';
}

/// Snapshot hasil autentikasi dari penyedia identitas (Firebase / Fake testing).
class AuthAccountSnapshot {
  const AuthAccountSnapshot({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.provider,
  });

  final String uid;
  final String email;
  final String displayName;
  final AuthProviderType provider;
}

/// Abstraksi gateway autentikasi & profil cloud agar repository dapat diuji
/// secara deterministik tanpa bergantung pada jaringan atau Firebase asli.
abstract class AuthGateway {
  AuthAccountSnapshot? get currentUser;

  Future<AuthAccountSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  });

  Future<AuthAccountSnapshot> signInWithGoogle();

  Future<void> sendPasswordResetEmail(String email);

  Future<void> signOut();

  Future<Petugas?> findPetugasByEmail(String email);

  Future<Petugas?> findPetugasByIdentifier(String identifier);

  Future<void> upsertPetugasProfile(Petugas petugas);
}

/// Implementasi produksi menggunakan Firebase Auth, Google Sign-In 7.2+,
/// dan Cloud Firestore koleksi `petugas`.
class FirebaseAuthGateway implements AuthGateway {
  FirebaseAuthGateway({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  })  : _firebaseAuthOverride = firebaseAuth,
        _firestoreOverride = firestore;

  final FirebaseAuth? _firebaseAuthOverride;
  final FirebaseFirestore? _firestoreOverride;
  bool _googleInitialized = false;

  bool get _hasFirebaseApp =>
      _firebaseAuthOverride != null || Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth => _firebaseAuthOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @override
  AuthAccountSnapshot? get currentUser {
    if (!_hasFirebaseApp) return null;
    final user = _auth.currentUser;
    if (user == null) return null;
    final isGoogle =
        user.providerData.any((info) => info.providerId == 'google.com');
    return AuthAccountSnapshot(
      uid: user.uid,
      email: (user.email ?? '').trim().toLowerCase(),
      displayName: (user.displayName ?? '').trim(),
      provider:
          isGoogle ? AuthProviderType.google : AuthProviderType.emailPassword,
    );
  }

  @override
  Future<AuthAccountSnapshot> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _ensureFirebaseReady();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return _snapshotFromCredential(
        credential,
        fallbackEmail: email,
        provider: AuthProviderType.emailPassword,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Gagal masuk ke akun: $e',
      );
    }
  }

  @override
  Future<AuthAccountSnapshot> createUserWithEmailAndPassword({
    required String fullName,
    required String email,
    required String password,
  }) async {
    _ensureFirebaseReady();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user != null && fullName.trim().isNotEmpty) {
        await user.updateDisplayName(fullName.trim());
        await user.reload();
      }
      final refreshed = _auth.currentUser ?? credential.user;
      return AuthAccountSnapshot(
        uid: refreshed?.uid ?? '',
        email: (refreshed?.email ?? email).trim().toLowerCase(),
        displayName: (refreshed?.displayName ?? fullName).trim(),
        provider: AuthProviderType.emailPassword,
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Gagal mendaftarkan akun: $e',
      );
    }
  }

  @override
  Future<AuthAccountSnapshot> signInWithGoogle() async {
    _ensureFirebaseReady();
    try {
      if (kIsWeb) {
        final credential = await _auth.signInWithPopup(GoogleAuthProvider());
        return _snapshotFromCredential(
          credential,
          fallbackEmail: credential.user?.email ?? '',
          provider: AuthProviderType.google,
        );
      }

      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize();
        _googleInitialized = true;
      }

      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthGatewayException(
          AuthFailureCode.configuration,
          'Token Google tidak tersedia. Periksa konfigurasi Firebase OAuth aplikasi.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final userCred = await _auth.signInWithCredential(credential);
      return _snapshotFromCredential(
        userCred,
        fallbackEmail: googleUser.email,
        fallbackName: googleUser.displayName ?? '',
        provider: AuthProviderType.google,
      );
    } on AuthGatewayException {
      rethrow;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthGatewayException(
          AuthFailureCode.cancelled,
          'Masuk dengan Google dibatalkan.',
        );
      }
      throw AuthGatewayException(
        AuthFailureCode.configuration,
        'Gagal masuk dengan Google (${e.code.name}).',
      );
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Terjadi kendala saat masuk dengan Google: $e',
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    _ensureFirebaseReady();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _mapFirebaseAuthException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Gagal mengirim email reset password: $e',
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!_hasFirebaseApp) return;
    if (!kIsWeb && _googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  @override
  Future<Petugas?> findPetugasByEmail(String email) async {
    if (!_hasFirebaseApp && _firestoreOverride == null) return null;
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    try {
      final snap = await _firestore
          .collection(SyncService.colPetugas)
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        return Petugas.fromFirestore(doc.data(), doc.id);
      }

      // Fallback cek case-insensitive tanpa index komposit bila ada data lama
      final allSnap =
          await _firestore.collection(SyncService.colPetugas).limit(100).get();
      for (final doc in allSnap.docs) {
        final data = doc.data();
        final docEmail = ((data['email'] as String?) ?? '').trim().toLowerCase();
        if (docEmail == normalized) {
          return Petugas.fromFirestore(data, doc.id);
        }
      }
      return null;
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Gagal membaca profil akun di cloud: $e',
      );
    }
  }

  @override
  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    if (!_hasFirebaseApp && _firestoreOverride == null) return null;
    final normalized = identifier.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    try {
      final allSnap =
          await _firestore.collection(SyncService.colPetugas).limit(100).get();
      for (final doc in allSnap.docs) {
        final data = doc.data();
        final email = ((data['email'] as String?) ?? '').trim().toLowerCase();
        final accountId =
            ((data['account_id'] as String?) ?? '').trim().toLowerCase();
        final remoteId =
            ((data['remote_id'] as String?) ?? doc.id).trim().toLowerCase();
        if (email == normalized ||
            accountId == normalized ||
            remoteId == normalized) {
          return Petugas.fromFirestore(data, doc.id);
        }
      }
      return null;
    } on FirebaseException catch (e) {
      throw _mapFirestoreException(e);
    } catch (e) {
      throw AuthGatewayException(
        AuthFailureCode.unknown,
        'Gagal mencari ID Akun di cloud: $e',
      );
    }
  }

  AuthGatewayException _mapFirestoreException(FirebaseException e) {
    switch (e.code) {
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
      case 'aborted':
        return const AuthGatewayException(
          AuthFailureCode.networkUnavailable,
          'Koneksi ke server database sedang tidak tersedia.',
        );
      case 'permission-denied':
        return const AuthGatewayException(
          AuthFailureCode.configuration,
          'Akses profil cloud belum diizinkan. Gunakan Email atau periksa aturan Firestore.',
        );
      default:
        return AuthGatewayException(
          AuthFailureCode.unknown,
          e.message ?? 'Gagal mengakses database cloud (${e.code}).',
        );
    }
  }

  @override
  Future<void> upsertPetugasProfile(Petugas petugas) async {
    if (!_hasFirebaseApp && _firestoreOverride == null) return;
    await _firestore
        .collection(SyncService.colPetugas)
        .doc(petugas.remoteId)
        .set(petugas.toFirestore(), SetOptions(merge: true));
  }

  void _ensureFirebaseReady() {
    if (!_hasFirebaseApp) {
      throw const AuthGatewayException(
        AuthFailureCode.networkUnavailable,
        'Layanan autentikasi cloud belum siap.',
      );
    }
  }

  AuthAccountSnapshot _snapshotFromCredential(
    UserCredential credential, {
    required String fallbackEmail,
    String fallbackName = '',
    required AuthProviderType provider,
  }) {
    final user = credential.user;
    return AuthAccountSnapshot(
      uid: user?.uid ?? '',
      email: (user?.email ?? fallbackEmail).trim().toLowerCase(),
      displayName: (user?.displayName ?? fallbackName).trim(),
      provider: provider,
    );
  }

  AuthGatewayException _mapFirebaseAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return const AuthGatewayException(
          AuthFailureCode.validation,
          'Format email tidak valid. Periksa kembali alamat email Anda.',
        );
      case 'wrong-password':
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
        return const AuthGatewayException(
          AuthFailureCode.invalidCredentials,
          'ID Akun/Email atau password tidak sesuai.',
        );
      case 'user-not-found':
      case 'user-disabled':
        return const AuthGatewayException(
          AuthFailureCode.userNotFound,
          'Akun tidak ditemukan atau sudah dinonaktifkan.',
        );
      case 'email-already-in-use':
        return const AuthGatewayException(
          AuthFailureCode.emailAlreadyInUse,
          'Email ini sudah terdaftar. Silakan Sign In dengan akun tersebut.',
        );
      case 'weak-password':
        return const AuthGatewayException(
          AuthFailureCode.weakPassword,
          'Password terlalu lemah. Gunakan minimal 6 karakter.',
        );
      case 'too-many-requests':
        return const AuthGatewayException(
          AuthFailureCode.tooManyRequests,
          'Terlalu banyak percobaan login. Tunggu beberapa saat lalu coba lagi.',
        );
      case 'network-request-failed':
        return const AuthGatewayException(
          AuthFailureCode.networkUnavailable,
          'Koneksi internet tidak tersedia.',
        );
      default:
        return AuthGatewayException(
          AuthFailureCode.unknown,
          e.message ?? 'Gagal memproses autentikasi (${e.code}).',
        );
    }
  }
}
