import 'package:depot_telur_36/models/sync_status.dart';

/// Model data tabel `supplier` sesuai ERD/LRS/PDM DepotTelur36.
class Supplier {
  const Supplier({
    this.idSupplier,
    required this.namaSupplier,
    required this.alamatSupplier,
    required this.noTelpSupplier,
    required this.remoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
  });

  final int? idSupplier;
  final String namaSupplier;
  final String alamatSupplier;
  final String noTelpSupplier;
  final String remoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;

  Supplier copyWith({
    int? idSupplier,
    String? namaSupplier,
    String? alamatSupplier,
    String? noTelpSupplier,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return Supplier(
      idSupplier: idSupplier ?? this.idSupplier,
      namaSupplier: namaSupplier ?? this.namaSupplier,
      alamatSupplier: alamatSupplier ?? this.alamatSupplier,
      noTelpSupplier: noTelpSupplier ?? this.noTelpSupplier,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idSupplier != null) 'id_supplier': idSupplier,
      'nama_supplier': namaSupplier,
      'alamat_supplier': alamatSupplier,
      'no_telp_supplier': noTelpSupplier,
      'remote_id': remoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      idSupplier: (map['id_supplier'] as num?)?.toInt(),
      namaSupplier: (map['nama_supplier'] as String?) ?? '',
      alamatSupplier: (map['alamat_supplier'] as String?) ?? '',
      noTelpSupplier: (map['no_telp_supplier'] as String?) ?? '',
      remoteId: (map['remote_id'] as String?) ?? '',
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nama_supplier': namaSupplier,
      'alamat_supplier': alamatSupplier,
      'no_telp_supplier': noTelpSupplier,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Supplier.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return Supplier(
      namaSupplier: (data['nama_supplier'] as String?) ?? '',
      alamatSupplier: (data['alamat_supplier'] as String?) ?? '',
      noTelpSupplier: (data['no_telp_supplier'] as String?) ?? '',
      remoteId: (data['remote_id'] as String?) ?? documentId,
      syncStatus: SyncStatus.synced,
      updatedAt: DateTime.tryParse((data['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
