import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/services/auth_gateway.dart';

enum AuthStatus {
  initializing,
  unauthenticated,
  authenticated,
}

/// ViewModel MVVM untuk alur Autentikasi (Splash, Sign In, Sign Up, Google, Reset Password).
class AuthViewModel extends ChangeNotifier {
  AuthViewModel({AuthRepository? repository})
      : _repository = repository ?? AuthRepository();

  final AuthRepository _repository;

  AuthStatus _status = AuthStatus.initializing;
  AuthStatus get status => _status;

  AuthSession? _session;
  AuthSession? get session => _session;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  bool _isGoogleLoading = false;
  bool get isGoogleLoading => _isGoogleLoading;

  bool _isResettingPassword = false;
  bool get isResettingPassword => _isResettingPassword;

  bool get isAnyBusy => _isSubmitting || _isGoogleLoading || _isResettingPassword;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  String? _infoMessage;
  String? get infoMessage => _infoMessage;

  /// Counter untuk memicu micro-interaction shake saat validasi/login gagal.
  int _errorPulse = 0;
  int get errorPulse => _errorPulse;

  int _authGeneration = 0;
  bool _disposed = false;

  Future<void> initialize() async {
    final opGen = _authGeneration;
    try {
      final restored = await _repository.restoreSession();
      if (_disposed ||
          opGen != _authGeneration ||
          _status == AuthStatus.authenticated) {
        return;
      }
      _session = restored;
      _status = restored != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    } catch (_) {
      if (_disposed ||
          opGen != _authGeneration ||
          _status == AuthStatus.authenticated) {
        return;
      }
      _session = null;
      _status = AuthStatus.unauthenticated;
    }
    _safeNotify();
  }

  void clearFeedback() {
    if (_errorMessage == null && _infoMessage == null) return;
    _errorMessage = null;
    _infoMessage = null;
    _safeNotify();
  }

  void registerValidationFailure([String? message]) {
    _errorMessage = message;
    _infoMessage = null;
    _errorPulse++;
    _safeNotify();
  }

  Future<bool> signIn({
    required String identifier,
    required String password,
  }) async {
    if (isAnyBusy) return false;
    final opGen = _authGeneration;
    _isSubmitting = true;
    _errorMessage = null;
    _infoMessage = null;
    _safeNotify();

    try {
      final session = await _repository.signInWithIdentifier(
        identifier: identifier,
        password: password,
      );
      if (opGen != _authGeneration) return false;
      _session = session;
      _status = AuthStatus.authenticated;
      return true;
    } on AuthGatewayException catch (e) {
      if (opGen != _authGeneration) return false;
      _errorMessage = e.message;
      _errorPulse++;
      return false;
    } catch (_) {
      if (opGen != _authGeneration) return false;
      _errorMessage = 'Terjadi kendala saat masuk. Silakan coba lagi.';
      _errorPulse++;
      return false;
    } finally {
      _isSubmitting = false;
      _safeNotify();
    }
  }

  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (isAnyBusy) return false;
    final opGen = _authGeneration;
    _isSubmitting = true;
    _errorMessage = null;
    _infoMessage = null;
    _safeNotify();

    try {
      final session = await _repository.signUpWithEmail(
        fullName: fullName,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
      );
      if (opGen != _authGeneration) return false;
      _session = session;
      _status = AuthStatus.authenticated;
      return true;
    } on AuthGatewayException catch (e) {
      if (opGen != _authGeneration) return false;
      _errorMessage = e.message;
      _errorPulse++;
      return false;
    } catch (_) {
      if (opGen != _authGeneration) return false;
      _errorMessage = 'Pendaftaran gagal diproses. Silakan coba lagi.';
      _errorPulse++;
      return false;
    } finally {
      _isSubmitting = false;
      _safeNotify();
    }
  }

  Future<bool> signInWithGoogle() async {
    if (isAnyBusy) return false;
    final opGen = _authGeneration;
    _isGoogleLoading = true;
    _errorMessage = null;
    _infoMessage = null;
    _safeNotify();

    try {
      final session = await _repository.signInWithGoogle();
      if (opGen != _authGeneration) return false;
      _session = session;
      _status = AuthStatus.authenticated;
      return true;
    } on AuthGatewayException catch (e) {
      if (opGen != _authGeneration) return false;
      if (e.code != AuthFailureCode.cancelled) {
        _errorMessage = e.message;
        _errorPulse++;
      } else {
        _infoMessage = e.message;
      }
      return false;
    } catch (_) {
      if (opGen != _authGeneration) return false;
      _errorMessage = 'Gagal masuk dengan Google. Silakan coba lagi.';
      _errorPulse++;
      return false;
    } finally {
      _isGoogleLoading = false;
      _safeNotify();
    }
  }

  Future<String?> sendPasswordReset(String identifierOrEmail) async {
    if (isAnyBusy) return null;
    final opGen = _authGeneration;
    _isResettingPassword = true;
    _errorMessage = null;
    _infoMessage = null;
    _safeNotify();

    try {
      final sentTo = await _repository.sendPasswordReset(identifierOrEmail);
      if (opGen != _authGeneration) return null;
      _infoMessage = 'Tautan reset password dikirim ke $sentTo.';
      return sentTo;
    } on AuthGatewayException catch (e) {
      if (opGen != _authGeneration) return null;
      _errorMessage = e.message;
      _errorPulse++;
      return null;
    } catch (_) {
      if (opGen != _authGeneration) return null;
      _errorMessage = 'Gagal mengirim tautan reset password.';
      _errorPulse++;
      return null;
    } finally {
      _isResettingPassword = false;
      _safeNotify();
    }
  }

  Future<void> signOut() async {
    _authGeneration++;
    _errorMessage = null;
    _infoMessage = null;
    _session = null;
    _status = AuthStatus.unauthenticated;
    await _repository.signOut();
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
