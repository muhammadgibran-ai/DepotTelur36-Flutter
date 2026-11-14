import 'package:depot_telur_36/models/sync_status.dart';

/// Model data tabel `faktur` (Pembelian Barang Masuk dari Supplier).
class Faktur {
  const Faktur({
    this.idFaktur,
    required this.noFaktur,
    required this.tanggalFaktur,
    required this.total,
    required this.idSupplier,
    required this.idPetugas,
    required this.remoteId,
    this.supplierRemoteId,
    this.petugasRemoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
    this.details = const [],
    this.namaSupplier,
    this.namaPetugas,
  });

  final int? idFaktur;
  final String noFaktur;
  final String tanggalFaktur;
  final double total;
  final int idSupplier;
  final int idPetugas;
  final String remoteId;
  final String? supplierRemoteId;
  final String? petugasRemoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;
  final List<DetailFaktur> details;

  /// Atribut bantu hasil JOIN untuk tampilan UI.
  final String? namaSupplier;
  final String? namaPetugas;

  static double hitungTotal(List<DetailFaktur> items) {
    return items.fold<double>(0.0, (sum, item) => sum + item.jumlah);
  }

  Faktur copyWith({
    int? idFaktur,
    String? noFaktur,
    String? tanggalFaktur,
    double? total,
    int? idSupplier,
    int? idPetugas,
    String? remoteId,
    String? supplierRemoteId,
    String? petugasRemoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
    List<DetailFaktur>? details,
    String? namaSupplier,
    String? namaPetugas,
  }) {
    return Faktur(
      idFaktur: idFaktur ?? this.idFaktur,
      noFaktur: noFaktur ?? this.noFaktur,
      tanggalFaktur: tanggalFaktur ?? this.tanggalFaktur,
      total: total ?? this.total,
      idSupplier: idSupplier ?? this.idSupplier,
      idPetugas: idPetugas ?? this.idPetugas,
      remoteId: remoteId ?? this.remoteId,
      supplierRemoteId: supplierRemoteId ?? this.supplierRemoteId,
      petugasRemoteId: petugasRemoteId ?? this.petugasRemoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      details: details ?? this.details,
      namaSupplier: namaSupplier ?? this.namaSupplier,
      namaPetugas: namaPetugas ?? this.namaPetugas,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idFaktur != null) 'id_faktur': idFaktur,
      'no_faktur': noFaktur,
      'tanggal_faktur': tanggalFaktur,
      'total': total,
      'id_supplier': idSupplier,
      'id_petugas': idPetugas,
      'remote_id': remoteId,
      'supplier_remote_id': supplierRemoteId,
      'petugas_remote_id': petugasRemoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Faktur.fromMap(
    Map<String, dynamic> map, {
    List<DetailFaktur> details = const [],
  }) {
    return Faktur(
      idFaktur: (map['id_faktur'] as num?)?.toInt(),
      noFaktur: (map['no_faktur'] as String?) ?? '',
      tanggalFaktur: (map['tanggal_faktur'] as String?) ?? '',
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      idSupplier: (map['id_supplier'] as num?)?.toInt() ?? 0,
      idPetugas: (map['id_petugas'] as num?)?.toInt() ?? 0,
      remoteId: (map['remote_id'] as String?) ?? '',
      supplierRemoteId: map['supplier_remote_id'] as String?,
      petugasRemoteId: map['petugas_remote_id'] as String?,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
      details: details,
      namaSupplier: map['nama_supplier'] as String?,
      namaPetugas: map['nama_petugas'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'no_faktur': noFaktur,
      'tanggal_faktur': tanggalFaktur,
      'total': total,
      'supplier_remote_id': supplierRemoteId,
      'petugas_remote_id': petugasRemoteId,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
      'details': details.map((d) => d.toFirestore()).toList(),
    };
  }
}

/// Model data tabel `detail_faktur` sesuai ERD/LRS/PDM DepotTelur36.
class DetailFaktur {
  const DetailFaktur({
    this.idFaktur,
    required this.idBarang,
    required this.jumlah,
    required this.quantity,
    this.barangRemoteId,
    this.namaBarang,
    this.satuan,
  });

  final int? idFaktur;
  final int idBarang;
  final double jumlah;
  final int quantity;
  final String? barangRemoteId;

  /// Atribut bantu hasil JOIN untuk tampilan UI.
  final String? namaBarang;
  final String? satuan;

  DetailFaktur copyWith({
    int? idFaktur,
    int? idBarang,
    double? jumlah,
    int? quantity,
    String? barangRemoteId,
    String? namaBarang,
    String? satuan,
  }) {
    return DetailFaktur(
      idFaktur: idFaktur ?? this.idFaktur,
      idBarang: idBarang ?? this.idBarang,
      jumlah: jumlah ?? this.jumlah,
      quantity: quantity ?? this.quantity,
      barangRemoteId: barangRemoteId ?? this.barangRemoteId,
      namaBarang: namaBarang ?? this.namaBarang,
      satuan: satuan ?? this.satuan,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idFaktur != null) 'id_faktur': idFaktur,
      'id_barang': idBarang,
      'jumlah': jumlah,
      'quantity': quantity,
      'barang_remote_id': barangRemoteId,
    };
  }

  factory DetailFaktur.fromMap(Map<String, dynamic> map) {
    return DetailFaktur(
      idFaktur: (map['id_faktur'] as num?)?.toInt(),
      idBarang: (map['id_barang'] as num?)?.toInt() ?? 0,
      jumlah: (map['jumlah'] as num?)?.toDouble() ?? 0.0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      barangRemoteId: map['barang_remote_id'] as String?,
      namaBarang: map['nama_barang'] as String?,
      satuan: map['satuan'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'barang_remote_id': barangRemoteId,
      'nama_barang': namaBarang,
      'jumlah': jumlah,
      'quantity': quantity,
    };
  }
}

/// Model data tabel `nota` (Penjualan Barang Keluar ke Customer).
class Nota {
  const Nota({
    this.idNota,
    required this.tanggalNota,
    required this.total,
    required this.idPetugas,
    required this.idCustomer,
    required this.remoteId,
    this.petugasRemoteId,
    this.customerRemoteId,
    this.syncStatus = SyncStatus.pending,
    required this.updatedAt,
    this.details = const [],
    this.namaCustomer,
    this.namaPetugas,
  });

  final int? idNota;
  final String tanggalNota;
  final double total;
  final int idPetugas;
  final int idCustomer;
  final String remoteId;
  final String? petugasRemoteId;
  final String? customerRemoteId;
  final SyncStatus syncStatus;
  final DateTime updatedAt;
  final List<DetailNota> details;

  /// Atribut bantu hasil JOIN untuk tampilan UI.
  final String? namaCustomer;
  final String? namaPetugas;

  static double hitungTotal(List<DetailNota> items) {
    return items.fold<double>(0.0, (sum, item) => sum + item.jumlah);
  }

  Nota copyWith({
    int? idNota,
    String? tanggalNota,
    double? total,
    int? idPetugas,
    int? idCustomer,
    String? remoteId,
    String? petugasRemoteId,
    String? customerRemoteId,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
    List<DetailNota>? details,
    String? namaCustomer,
    String? namaPetugas,
  }) {
    return Nota(
      idNota: idNota ?? this.idNota,
      tanggalNota: tanggalNota ?? this.tanggalNota,
      total: total ?? this.total,
      idPetugas: idPetugas ?? this.idPetugas,
      idCustomer: idCustomer ?? this.idCustomer,
      remoteId: remoteId ?? this.remoteId,
      petugasRemoteId: petugasRemoteId ?? this.petugasRemoteId,
      customerRemoteId: customerRemoteId ?? this.customerRemoteId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      details: details ?? this.details,
      namaCustomer: namaCustomer ?? this.namaCustomer,
      namaPetugas: namaPetugas ?? this.namaPetugas,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idNota != null) 'id_nota': idNota,
      'tanggal_nota': tanggalNota,
      'total': total,
      'id_petugas': idPetugas,
      'id_customer': idCustomer,
      'remote_id': remoteId,
      'petugas_remote_id': petugasRemoteId,
      'customer_remote_id': customerRemoteId,
      'sync_status': syncStatus.value,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Nota.fromMap(
    Map<String, dynamic> map, {
    List<DetailNota> details = const [],
  }) {
    return Nota(
      idNota: (map['id_nota'] as num?)?.toInt(),
      tanggalNota: (map['tanggal_nota'] as String?) ?? '',
      total: (map['total'] as num?)?.toDouble() ?? 0.0,
      idPetugas: (map['id_petugas'] as num?)?.toInt() ?? 0,
      idCustomer: (map['id_customer'] as num?)?.toInt() ?? 0,
      remoteId: (map['remote_id'] as String?) ?? '',
      petugasRemoteId: map['petugas_remote_id'] as String?,
      customerRemoteId: map['customer_remote_id'] as String?,
      syncStatus: SyncStatus.fromString(map['sync_status'] as String?),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
      details: details,
      namaCustomer: map['nama_customer'] as String?,
      namaPetugas: map['nama_petugas'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'tanggal_nota': tanggalNota,
      'total': total,
      'petugas_remote_id': petugasRemoteId,
      'customer_remote_id': customerRemoteId,
      'remote_id': remoteId,
      'updated_at': updatedAt.toIso8601String(),
      'details': details.map((d) => d.toFirestore()).toList(),
    };
  }
}

/// Model data tabel `detail_nota` sesuai ERD/LRS/PDM DepotTelur36.
class DetailNota {
  const DetailNota({
    this.idNota,
    required this.idBarang,
    required this.jumlah,
    required this.banyaknya,
    this.barangRemoteId,
    this.namaBarang,
    this.satuan,
  });

  final int? idNota;
  final int idBarang;
  final double jumlah;
  final int banyaknya;
  final String? barangRemoteId;

  /// Atribut bantu hasil JOIN untuk tampilan UI.
  final String? namaBarang;
  final String? satuan;

  DetailNota copyWith({
    int? idNota,
    int? idBarang,
    double? jumlah,
    int? banyaknya,
    String? barangRemoteId,
    String? namaBarang,
    String? satuan,
  }) {
    return DetailNota(
      idNota: idNota ?? this.idNota,
      idBarang: idBarang ?? this.idBarang,
      jumlah: jumlah ?? this.jumlah,
      banyaknya: banyaknya ?? this.banyaknya,
      barangRemoteId: barangRemoteId ?? this.barangRemoteId,
      namaBarang: namaBarang ?? this.namaBarang,
      satuan: satuan ?? this.satuan,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (idNota != null) 'id_nota': idNota,
      'id_barang': idBarang,
      'jumlah': jumlah,
      'banyaknya': banyaknya,
      'barang_remote_id': barangRemoteId,
    };
  }

  factory DetailNota.fromMap(Map<String, dynamic> map) {
    return DetailNota(
      idNota: (map['id_nota'] as num?)?.toInt(),
      idBarang: (map['id_barang'] as num?)?.toInt() ?? 0,
      jumlah: (map['jumlah'] as num?)?.toDouble() ?? 0.0,
      banyaknya: (map['banyaknya'] as num?)?.toInt() ?? 0,
      barangRemoteId: map['barang_remote_id'] as String?,
      namaBarang: map['nama_barang'] as String?,
      satuan: map['satuan'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'barang_remote_id': barangRemoteId,
      'nama_barang': namaBarang,
      'jumlah': jumlah,
      'banyaknya': banyaknya,
    };
  }
}
