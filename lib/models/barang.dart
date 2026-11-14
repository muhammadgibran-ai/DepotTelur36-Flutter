import 'package:depot_telur_36/models/sync_status.dart';

/// Model data tabel `barang` sesuai ERD/LRS/PDM DepotTelur36.
class Barang {
  const Barang({
    this.idBarang,
    required this.namaBarang,
    required this.stokBarang,
    required this.satuan,
    required this.hargaSatuan,
    required this.remoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
  });

  final int? idBarang;
  final String namaBarang;
  final int stokBarang;
  final String satuan;
  final double hargaSatuan;
  final String remoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;

  /// Menandai barang yang stoknya perlu segera dipesan ke supplier.
  bool get isLowStock => stokBarang <= 10;

  Barang copyWith({
    int? idBarang,
    String? namaBarang,
    int? stokBarang,
    String? satuan,
    double? hargaSatuan,
    String? remoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
  }) {
    return Barang(
      idBarang: idBarang ?? this.idBarang,
      namaBarang: namaBarang ?? this.namaBarang,
      stokBarang: stokBarang ?? this.stokBarang,
      satuan: satuan ?? this.satuan,
      hargaSatuan: hargaSatuan ?? this.hargaSatuan,
      remoteId: remoteId ?? this.remoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idBarang != null) 'id_barang': idBarang,
      'nama_barang': namaBarang,
      'stok_barang': stokBarang,
      'satuan': satuan,
      'harga_satuan': hargaSatuan,
      'remote_id': remoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Barang.fromMap(Map<String, dynamic> map) {
    return Barang(
      idBarang: (map['id_barang'] as num?)?.toInt(),
      namaBarang: (map['nama_barang'] as String?) ?? '',
      stokBarang: (map['stok_barang'] as num?)?.toInt() ?? 0,
      satuan: (map['satuan'] as String?) ?? 'Kg',
      hargaSatuan: (map['harga_satuan'] as num?)?.toDouble() ?? 0.0,
      remoteId: (map['remote_id'] as String?) ?? '',
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'nama_barang': namaBarang,
      'stok_barang': stokBarang,
      'satuan': satuan,
      'harga_satuan': hargaSatuan,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Barang.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return Barang(
      namaBarang: (data['nama_barang'] as String?) ?? '',
      stokBarang: (data['stok_barang'] as num?)?.toInt() ?? 0,
      satuan: (data['satuan'] as String?) ?? 'Kg',
      hargaSatuan: (data['harga_satuan'] as num?)?.toDouble() ?? 0.0,
      remoteId: (data['remote_id'] as String?) ?? documentId,
      syncStatus: SyncStatus.synced,
      updatedAt: DateTime.tryParse((data['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
