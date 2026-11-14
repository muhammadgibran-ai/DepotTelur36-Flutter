/// Status sinkronisasi data lokal SQLite terhadap Cloud Firestore.
enum SyncStatus {
  pending('PENDING'),
  synced('SYNCED');

  const SyncStatus(this.value);

  final String value;

  static SyncStatus fromString(String? raw) {
    if (raw == SyncStatus.synced.value) {
      return SyncStatus.synced;
    }
    return SyncStatus.pending;
  }
}

/// Hak akses pengguna sesuai alur BPMN DepotTelur36.
enum UserRole {
  owner('OWNER', 'Owner DepotTelur36'),
  petugas('PETUGAS', 'Petugas Toko / Kasir');

  const UserRole(this.value, this.label);

  final String value;
  final String label;

  static UserRole fromString(String? raw) {
    if (raw == UserRole.owner.value) {
      return UserRole.owner;
    }
    return UserRole.petugas;
  }
}
