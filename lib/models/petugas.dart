import 'package:depot_telur_36/models/sync_status.dart';

/// Model data tabel `petugas` sesuai ERD/LRS/PDM DepotTelur36
/// dengan dukungan role RBAC (`OWNER` dan `PETUGAS`).
class Petugas {
  const Petugas({
    this.idPetugas,
    required this.namaPetugas,
    this.role = UserRole.petugas,
    this.pin = '1234',
    this.email = '',
    this.accountId = '',
    this.passwordHash = '',
    required this.remoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
  });

  final int? idPetugas;
  final String namaPetugas;
  final UserRole role;
  final String pin;
  final String email;
  final String accountId;

  /// Hash kredensial lokal saja untuk verifikasi offline; tidak dikirim ke Firestore.
  final String passwordHash;
  final String remoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;

  bool get isOwner => role == UserRole.owner;

  Petugas copyWith({
    int? idPetugas,
    String? namaPetugas,
    UserRole? role,
    String? pin,
    String? email,
    String? accountId,
    String? passwordHash,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return Petugas(
      idPetugas: idPetugas ?? this.idPetugas,
      namaPetugas: namaPetugas ?? this.namaPetugas,
      role: role ?? this.role,
      pin: pin ?? this.pin,
      email: email ?? this.email,
      accountId: accountId ?? this.accountId,
      passwordHash: passwordHash ?? this.passwordHash,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idPetugas != null) 'id_petugas': idPetugas,
      'nama_petugas': namaPetugas,
      'role': role.value,
      'pin': pin,
      'email': email,
      'account_id': accountId,
      'password_hash': passwordHash,
      'remote_id': remoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Petugas.fromMap(Map<String, dynamic> map) {
    return Petugas(
      idPetugas: (map['id_petugas'] as num?)?.toInt(),
      namaPetugas: (map['nama_petugas'] as String?) ?? '',
      role: UserRole.fromString(map['role'] as String?),
      pin: (map['pin'] as String?) ?? '1234',
      email: (map['email'] as String?) ?? '',
      accountId: (map['account_id'] as String?) ?? '',
      passwordHash: (map['password_hash'] as String?) ?? '',
      remoteId: (map['remote_id'] as String?) ?? '',
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nama_petugas': namaPetugas,
      'role': role.value,
      'pin': pin,
      'email': email,
      'account_id': accountId,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Petugas.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return Petugas(
      namaPetugas: (data['nama_petugas'] as String?) ?? '',
      role: UserRole.fromString(data['role'] as String?),
      pin: (data['pin'] as String?) ?? '1234',
      email: (data['email'] as String?) ?? '',
      accountId: (data['account_id'] as String?) ?? '',
      remoteId: (data['remote_id'] as String?) ?? documentId,
      syncStatus: SyncStatus.synced,
      updatedAt: DateTime.tryParse((data['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
