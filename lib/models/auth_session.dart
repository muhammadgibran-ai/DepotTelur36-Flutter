import 'dart:convert';

import 'package:depot_telur_36/models/sync_status.dart';

/// Sumber metode autentikasi untuk sesi pengguna yang aktif.
enum AuthProviderType {
  emailPassword('EMAIL_PASSWORD'),
  google('GOOGLE'),
  offlineLocal('OFFLINE_LOCAL');

  const AuthProviderType(this.value);

  final String value;

  static AuthProviderType fromString(String? raw) {
    for (final item in AuthProviderType.values) {
      if (item.value == raw) return item;
    }
    return AuthProviderType.emailPassword;
  }
}

/// Representasi sesi pengguna yang tersimpan lokal untuk mode Offline-First.
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.email,
    required this.accountId,
    required this.displayName,
    required this.role,
    required this.petugasRemoteId,
    required this.provider,
    required this.signedInAt,
  });

  final String uid;
  final String email;
  final String accountId;
  final String displayName;
  final UserRole role;
  final String petugasRemoteId;
  final AuthProviderType provider;
  final DateTime signedInAt;

  bool get isOwner => role == UserRole.owner;

  AuthSession copyWith({
    String? uid,
    String? email,
    String? accountId,
    String? displayName,
    UserRole? role,
    String? petugasRemoteId,
    AuthProviderType? provider,
    DateTime? signedInAt,
  }) {
    return AuthSession(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      accountId: accountId ?? this.accountId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      petugasRemoteId: petugasRemoteId ?? this.petugasRemoteId,
      provider: provider ?? this.provider,
      signedInAt: signedInAt ?? this.signedInAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'account_id': accountId,
      'display_name': displayName,
      'role': role.value,
      'petugas_remote_id': petugasRemoteId,
      'provider': provider.value,
      'signed_in_at': signedInAt.toIso8601String(),
    };
  }

  factory AuthSession.fromMap(Map<String, dynamic> map) {
    return AuthSession(
      uid: (map['uid'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      accountId: (map['account_id'] as String?) ?? '',
      displayName: (map['display_name'] as String?) ?? '',
      role: UserRole.fromString(map['role'] as String?),
      petugasRemoteId: (map['petugas_remote_id'] as String?) ?? '',
      provider: AuthProviderType.fromString(map['provider'] as String?),
      signedInAt: DateTime.tryParse((map['signed_in_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  String toJson() => jsonEncode(toMap());

  static AuthSession? tryParseJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final session = AuthSession.fromMap(Map<String, dynamic>.from(decoded));
      if (session.uid.trim().isEmpty &&
          session.petugasRemoteId.trim().isEmpty) {
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }
}
