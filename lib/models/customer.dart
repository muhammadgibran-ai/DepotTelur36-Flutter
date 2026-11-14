import 'package:depot_telur_36/models/sync_status.dart';

/// Model data tabel `customer` sesuai ERD/LRS/PDM DepotTelur36.
class Customer {
  const Customer({
    this.idCustomer,
    required this.namaCustomer,
    required this.remoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
  });

  final int? idCustomer;
  final String namaCustomer;
  final String remoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;

  Customer copyWith({
    int? idCustomer,
    String? namaCustomer,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return Customer(
      idCustomer: idCustomer ?? this.idCustomer,
      namaCustomer: namaCustomer ?? this.namaCustomer,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idCustomer != null) 'id_customer': idCustomer,
      'nama_customer': namaCustomer,
      'remote_id': remoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      idCustomer: (map['id_customer'] as num?)?.toInt(),
      namaCustomer: (map['nama_customer'] as String?) ?? '',
      remoteId: (map['remote_id'] as String?) ?? '',
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nama_customer': namaCustomer,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Customer.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return Customer(
      namaCustomer: (data['nama_customer'] as String?) ?? '',
      remoteId: (data['remote_id'] as String?) ?? documentId,
      syncStatus: SyncStatus.synced,
      updatedAt: DateTime.tryParse((data['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
