import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';

/// Exception validasi bisnis & integritas master data DepotTelur36.
class MasterDataValidationException implements Exception {
  const MasterDataValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Single Source of Truth untuk seluruh operasi data DepotTelur36.
/// Setiap input selalu disimpan ke SQLite lokal terlebih dahulu (100% jalan saat offline),
/// lalu dipicu untuk auto-sync ke Cloud Firestore bila koneksi internet tersedia.
class InventoryRepository {
  InventoryRepository({
    DatabaseHelper? dbHelper,
    SyncService? syncService,
    Uuid? uuid,
  })  : _dbHelper = dbHelper ?? DatabaseHelper.instance,
        syncService = syncService ?? SyncService(dbHelper: dbHelper),
        _uuid = uuid ?? const Uuid();

  final DatabaseHelper _dbHelper;
  final SyncService syncService;
  final Uuid _uuid;

  final StreamController<void> _localChangesController =
      StreamController<void>.broadcast();

  StreamSubscription<void>? _syncDataSub;
  bool _initialized = false;

  /// Stream gabungan yang memberi tahu ViewModel saat ada perubahan lokal maupun dari Cloud.
  Stream<void> get onDataChanged => _localChangesController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _dbHelper.database;
    _syncDataSub = syncService.onDataUpdated.listen((_) {
      if (!_localChangesController.isClosed) {
        _localChangesController.add(null);
      }
    });
    await syncService.start();
  }

  // ==================== BACA DATA LOKAL (INSTAN & OFFLINE) ====================

  Future<List<Barang>> getAllBarang() => _dbHelper.getAllBarang();
  Future<List<Supplier>> getAllSupplier() => _dbHelper.getAllSupplier();
  Future<List<Customer>> getAllCustomer() => _dbHelper.getAllCustomer();
  Future<List<Petugas>> getAllPetugas() => _dbHelper.getAllPetugas();
  Future<List<Faktur>> getAllFaktur() => _dbHelper.getAllFaktur();
  Future<List<Nota>> getAllNota() => _dbHelper.getAllNota();

  static final RegExp _controlCharsRegex = RegExp(
    r'[\x00-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2060\uFEFF]',
  );
  static final RegExp _multilineControlCharsRegex = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2060\uFEFF]',
  );
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _phoneSeparatorRegex = RegExp(r'[\s\-\(\)\+]');
  static final RegExp _phoneAllowedCharsRegex = RegExp(
    r'^[\d\+\(][\d\s\-\(\)\+]*\d$',
  );
  static final RegExp _digitsPhoneRegex = RegExp(r'^\d{8,15}$');
  static final RegExp _pinRegex = RegExp(r'^\d{4}$');

  static String normalizeText(String raw) =>
      raw.trim().replaceAll(_multiSpaceRegex, ' ');

  static String normalizeKey(String raw) => normalizeText(raw).toLowerCase();

  static bool hasControlChars(String raw) => _controlCharsRegex.hasMatch(raw);

  static String? _normalizeRemoteIdOverride(String? existingRemoteId) {
    if (existingRemoteId == null) return null;
    if (_controlCharsRegex.hasMatch(existingRemoteId)) {
      throw const MasterDataValidationException(
        'ID remote mengandung karakter kontrol yang tidak valid.',
      );
    }
    final trimmed = existingRemoteId.trim();
    if (trimmed.isEmpty) {
      throw const MasterDataValidationException(
        'ID remote tidak boleh kosong.',
      );
    }
    return trimmed;
  }

  static String _validatePhone(String raw) {
    if (_controlCharsRegex.hasMatch(raw)) {
      throw const MasterDataValidationException(
        'Nomor telepon mengandung karakter yang tidak valid.',
      );
    }
    final cleanTelp = raw.trim();
    if (cleanTelp.isEmpty) {
      throw const MasterDataValidationException(
        'Nomor telepon supplier wajib diisi.',
      );
    }
    if (cleanTelp.length > 24) {
      throw const MasterDataValidationException(
        'Nomor telepon supplier maksimal 24 karakter.',
      );
    }
    if (!_phoneAllowedCharsRegex.hasMatch(cleanTelp) ||
        RegExp(r'[-+]{2,}|\s{2,}|\(\s*\)').hasMatch(cleanTelp)) {
      throw const MasterDataValidationException(
        'Format nomor telepon supplier tidak valid.',
      );
    }
    final plusCount = '+'.allMatches(cleanTelp).length;
    if (plusCount > 1 ||
        (plusCount == 1 && !RegExp(r'^\(?\+\d').hasMatch(cleanTelp))) {
      throw const MasterDataValidationException(
        'Format nomor telepon supplier tidak valid.',
      );
    }
    final openParens = '('.allMatches(cleanTelp).length;
    final closeParens = ')'.allMatches(cleanTelp).length;
    if (openParens != closeParens ||
        openParens > 1 ||
        (openParens == 1 && !RegExp(r'^\(\+?\d{1,5}\)').hasMatch(cleanTelp))) {
      throw const MasterDataValidationException(
        'Format nomor telepon supplier tidak valid.',
      );
    }
    final phoneDigits = cleanTelp.replaceAll(_phoneSeparatorRegex, '');
    if (!_digitsPhoneRegex.hasMatch(phoneDigits)) {
      throw const MasterDataValidationException(
        'Nomor telepon harus terdiri dari 8 sampai 15 digit angka.',
      );
    }
    return cleanTelp;
  }

  ({T? targetExisting, String remoteId}) _resolveMasterIdentity<T>({
    required List<T> existingList,
    required int? localId,
    required String? existingRemoteId,
    required int? Function(T item) getId,
    required String Function(T item) getRemoteId,
    required String entityLabel,
    String? duplicateKey,
    String Function(T item)? getDuplicateKey,
    String? duplicateMessage,
  }) {
    final cleanRemoteOverride = _normalizeRemoteIdOverride(existingRemoteId);
    T? byId;
    T? byRemote;
    for (final existing in existingList) {
      if (localId != null && getId(existing) == localId) {
        byId = existing;
      }
      if (cleanRemoteOverride != null &&
          getRemoteId(existing) == cleanRemoteOverride) {
        byRemote = existing;
      }
    }
    if (localId != null && byId == null) {
      throw MasterDataValidationException(
        '$entityLabel tidak ditemukan di database lokal.',
      );
    }
    if (byId != null &&
        byRemote != null &&
        getId(byId) != getId(byRemote)) {
      throw MasterDataValidationException(
        'Data $entityLabel lokal tidak konsisten dengan ID remote.',
      );
    }
    final targetExisting = byId ?? byRemote;
    if (duplicateKey != null && getDuplicateKey != null) {
      for (final existing in existingList) {
        final isSelf =
            targetExisting != null && getId(existing) == getId(targetExisting);
        if (!isSelf && getDuplicateKey(existing) == duplicateKey) {
          throw MasterDataValidationException(
            duplicateMessage ?? '$entityLabel sudah terdaftar.',
          );
        }
      }
    }
    return (
      targetExisting: targetExisting,
      remoteId: cleanRemoteOverride ??
          (targetExisting != null ? getRemoteId(targetExisting) : _uuid.v4()),
    );
  }

  static String _validateSingleLineField(
    String raw,
    String fieldLabel, {
    int minLength = 2,
    int maxLength = 80,
  }) {
    if (_controlCharsRegex.hasMatch(raw)) {
      throw MasterDataValidationException(
        '$fieldLabel mengandung karakter kontrol yang tidak valid.',
      );
    }
    final clean = normalizeText(raw);
    if (clean.isEmpty) {
      throw MasterDataValidationException('$fieldLabel wajib diisi.');
    }
    if (clean.length < minLength) {
      throw MasterDataValidationException(
        '$fieldLabel minimal $minLength karakter.',
      );
    }
    if (clean.length > maxLength) {
      throw MasterDataValidationException(
        '$fieldLabel maksimal $maxLength karakter.',
      );
    }
    return clean;
  }

  static void _validatePrice(double hargaSatuan) {
    if (!hargaSatuan.isFinite || hargaSatuan <= 0 || hargaSatuan > 1000000000) {
      throw const MasterDataValidationException(
        'Harga satuan harus lebih dari Rp 0.',
      );
    }
  }

  // ==================== SIMPAN & HAPUS MASTER DATA (OFFLINE-FIRST) ====================

  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) async {
    final cleanNama = _validateSingleLineField(namaBarang, 'Nama barang');
    final cleanSatuan = _validateSingleLineField(
      satuan,
      'Satuan barang',
      minLength: 1,
      maxLength: 24,
    );
    if (stokBarang < 0 || stokBarang > 9999999) {
      throw const MasterDataValidationException(
        'Stok barang harus bernilai antara 0 hingga 9.999.999.',
      );
    }
    _validatePrice(hargaSatuan);

    final identity = _resolveMasterIdentity<Barang>(
      existingList: await _dbHelper.getAllBarang(),
      localId: idBarang,
      existingRemoteId: existingRemoteId,
      getId: (item) => item.idBarang,
      getRemoteId: (item) => item.remoteId,
      entityLabel: 'Barang',
      duplicateKey: normalizeKey(cleanNama),
      getDuplicateKey: (item) => normalizeKey(item.namaBarang),
      duplicateMessage: 'Barang "$cleanNama" sudah terdaftar di katalog.',
    );

    final barang = Barang(
      idBarang: identity.targetExisting?.idBarang ?? idBarang,
      namaBarang: cleanNama,
      stokBarang: stokBarang,
      satuan: cleanSatuan,
      hargaSatuan: hargaSatuan,
      remoteId: identity.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    try {
      await _dbHelper.upsertBarang(barang);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> updateBarangHargaBatch(Map<int, double> hargaById) async {
    if (hargaById.isEmpty) {
      throw const MasterDataValidationException(
        'Belum ada perubahan harga barang untuk disimpan.',
      );
    }
    for (final entry in hargaById.entries) {
      _validatePrice(entry.value);
    }
    final existingIds = (await _dbHelper.getAllBarang())
        .map((b) => b.idBarang)
        .whereType<int>()
        .toSet();
    for (final id in hargaById.keys) {
      if (!existingIds.contains(id)) {
        throw const MasterDataValidationException(
          'Salah satu barang tidak ditemukan di database lokal.',
        );
      }
    }
    try {
      await _dbHelper.updateBarangHargaBatch(hargaById);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> deleteBarang(int idBarang) async {
    try {
      await _dbHelper.deleteBarang(idBarang);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) async {
    final cleanNama = _validateSingleLineField(namaSupplier, 'Nama supplier');
    final cleanTelp = _validatePhone(noTelpSupplier);
    if (_multilineControlCharsRegex.hasMatch(alamatSupplier)) {
      throw const MasterDataValidationException(
        'Alamat supplier mengandung karakter kontrol yang tidak valid.',
      );
    }
    final cleanAlamat = alamatSupplier.trim();
    if (cleanAlamat.length < 5) {
      throw const MasterDataValidationException(
        'Alamat lengkap supplier minimal 5 karakter.',
      );
    }
    if (cleanAlamat.length > 240) {
      throw const MasterDataValidationException(
        'Alamat supplier maksimal 240 karakter.',
      );
    }

    final identity = _resolveMasterIdentity<Supplier>(
      existingList: await _dbHelper.getAllSupplier(),
      localId: idSupplier,
      existingRemoteId: existingRemoteId,
      getId: (item) => item.idSupplier,
      getRemoteId: (item) => item.remoteId,
      entityLabel: 'Supplier',
      duplicateKey: normalizeKey(cleanNama),
      getDuplicateKey: (item) => normalizeKey(item.namaSupplier),
      duplicateMessage: 'Supplier "$cleanNama" sudah terdaftar.',
    );

    final supplier = Supplier(
      idSupplier: identity.targetExisting?.idSupplier ?? idSupplier,
      namaSupplier: cleanNama,
      alamatSupplier: cleanAlamat,
      noTelpSupplier: cleanTelp,
      remoteId: identity.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    try {
      await _dbHelper.upsertSupplier(supplier);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> deleteSupplier(int idSupplier) async {
    try {
      await _dbHelper.deleteSupplier(idSupplier);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) async {
    final cleanNama = _validateSingleLineField(namaCustomer, 'Nama pelanggan');
    final identity = _resolveMasterIdentity<Customer>(
      existingList: await _dbHelper.getAllCustomer(),
      localId: idCustomer,
      existingRemoteId: existingRemoteId,
      getId: (item) => item.idCustomer,
      getRemoteId: (item) => item.remoteId,
      entityLabel: 'Pelanggan',
      duplicateKey: normalizeKey(cleanNama),
      getDuplicateKey: (item) => normalizeKey(item.namaCustomer),
      duplicateMessage: 'Pelanggan "$cleanNama" sudah terdaftar.',
    );

    final customer = Customer(
      idCustomer: identity.targetExisting?.idCustomer ?? idCustomer,
      namaCustomer: cleanNama,
      remoteId: identity.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    try {
      await _dbHelper.upsertCustomer(customer);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> deleteCustomer(int idCustomer) async {
    try {
      await _dbHelper.deleteCustomer(idCustomer);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> savePetugas({
    int? idPetugas,
    String? existingRemoteId,
    required String namaPetugas,
    required UserRole role,
    String pin = '1234',
    String email = '',
    String accountId = '',
    String? activeUserRemoteId,
    bool requireEmail = false,
  }) async {
    final cleanNama = _validateSingleLineField(namaPetugas, 'Nama petugas');
    if (_controlCharsRegex.hasMatch(pin)) {
      throw const MasterDataValidationException(
        'PIN kasir mengandung karakter tidak valid.',
      );
    }
    final cleanPin = pin.trim();
    if (!_pinRegex.hasMatch(cleanPin)) {
      throw const MasterDataValidationException(
        'PIN kasir harus tepat 4 digit angka.',
      );
    }
    if (_controlCharsRegex.hasMatch(email)) {
      throw const MasterDataValidationException(
        'Email mengandung karakter kontrol yang tidak valid.',
      );
    }
    final cleanEmail = email.trim().toLowerCase();
    if (requireEmail && cleanEmail.isEmpty) {
      throw const MasterDataValidationException(
        'Email akun masuk wajib diisi.',
      );
    }
    if (cleanEmail.isNotEmpty && !AuthRepository.isValidEmail(cleanEmail)) {
      throw const MasterDataValidationException(
        'Format email akun tidak valid.',
      );
    }

    final existingList = await _dbHelper.getAllPetugas();
    final identity = _resolveMasterIdentity<Petugas>(
      existingList: existingList,
      localId: idPetugas,
      existingRemoteId: existingRemoteId,
      getId: (item) => item.idPetugas,
      getRemoteId: (item) => item.remoteId,
      entityLabel: 'Petugas',
    );
    final targetExisting = identity.targetExisting;

    if (cleanEmail.isNotEmpty) {
      for (final existing in existingList) {
        final isSelf = targetExisting != null &&
            existing.idPetugas == targetExisting.idPetugas;
        if (!isSelf && existing.email.trim().toLowerCase() == cleanEmail) {
          throw MasterDataValidationException(
            'Email "$cleanEmail" sudah digunakan oleh akun lain.',
          );
        }
      }
    }

    if (targetExisting != null &&
        targetExisting.role == UserRole.owner &&
        role != UserRole.owner) {
      if (activeUserRemoteId != null &&
          activeUserRemoteId.trim().isNotEmpty &&
          targetExisting.remoteId == activeUserRemoteId.trim()) {
        throw const MasterDataValidationException(
          'Akun Owner yang sedang aktif tidak dapat diturunkan ke Petugas.',
        );
      }
      final ownerCount = existingList
          .where((item) => item.role == UserRole.owner)
          .length;
      if (ownerCount <= 1) {
        throw const MasterDataValidationException(
          'Minimal harus ada satu akun Owner yang aktif.',
        );
      }
    }

    final resolvedEmail =
        cleanEmail.isNotEmpty ? cleanEmail : (targetExisting?.email ?? '');
    final resolvedAccountId = accountId.trim().isNotEmpty
        ? accountId.trim()
        : (targetExisting?.accountId ?? '');
    final resolvedPasswordHash = targetExisting?.passwordHash ?? '';

    final petugas = Petugas(
      idPetugas: targetExisting?.idPetugas ?? idPetugas,
      namaPetugas: cleanNama,
      role: role,
      pin: cleanPin,
      email: resolvedEmail,
      accountId: resolvedAccountId,
      passwordHash: resolvedPasswordHash,
      remoteId: identity.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );
    try {
      await _dbHelper.upsertPetugas(petugas);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  Future<void> deletePetugas(
    Petugas target, {
    String? currentUserRemoteId,
  }) async {
    if (currentUserRemoteId != null &&
        currentUserRemoteId.trim().isNotEmpty &&
        target.remoteId == currentUserRemoteId.trim()) {
      throw const MasterDataValidationException(
        'Akun yang sedang Anda gunakan tidak dapat dihapus.',
      );
    }
    final id = target.idPetugas;
    if (id == null) {
      throw const MasterDataValidationException(
        'Akun petugas belum tersimpan di database lokal.',
      );
    }
    try {
      await _dbHelper.deletePetugas(id);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  // ==================== SIMPAN TRANSAKSI (BPMN TO-BE) ====================

  /// Mencatat pembelian barang masuk dari supplier (`faktur` + `detail_faktur`)
  /// dan langsung menambah stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    if (supplier.idSupplier == null || petugas.idPetugas == null) {
      throw ArgumentError('Supplier dan Petugas harus tersimpan di database.');
    }
    final now = DateTime.now();
    final details = items.map((entry) {
      final barang = entry.barang;
      if (barang.idBarang == null) {
        throw ArgumentError('Barang "${barang.namaBarang}" belum memiliki ID.');
      }
      return DetailFaktur(
        idBarang: barang.idBarang!,
        jumlah: barang.hargaSatuan * entry.quantity,
        quantity: entry.quantity,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      );
    }).toList();

    final faktur = Faktur(
      noFaktur: noFaktur.trim(),
      tanggalFaktur: tanggalFaktur,
      total: Faktur.hitungTotal(details),
      idSupplier: supplier.idSupplier!,
      idPetugas: petugas.idPetugas!,
      remoteId: _uuid.v4(),
      supplierRemoteId: supplier.remoteId,
      petugasRemoteId: petugas.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      details: details,
    );

    final idFaktur = await _dbHelper.insertFakturTransaction(faktur, details);
    await _afterLocalWrite();
    return idFaktur;
  }

  /// Mencatat penjualan kasir ke customer (`nota` + `detail_nota`)
  /// dan langsung memotong stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    if (customer.idCustomer == null || petugas.idPetugas == null) {
      throw ArgumentError('Customer dan Petugas harus tersimpan di database.');
    }
    final now = DateTime.now();
    final details = items.map((entry) {
      final barang = entry.barang;
      if (barang.idBarang == null) {
        throw ArgumentError('Barang "${barang.namaBarang}" belum memiliki ID.');
      }
      return DetailNota(
        idBarang: barang.idBarang!,
        jumlah: barang.hargaSatuan * entry.banyaknya,
        banyaknya: entry.banyaknya,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      );
    }).toList();

    final nota = Nota(
      tanggalNota: tanggalNota,
      total: Nota.hitungTotal(details),
      idPetugas: petugas.idPetugas!,
      idCustomer: customer.idCustomer!,
      remoteId: _uuid.v4(),
      petugasRemoteId: petugas.remoteId,
      customerRemoteId: customer.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: now,
      details: details,
    );

    final idNota = await _dbHelper.insertNotaTransaction(nota, details);
    await _afterLocalWrite();
    return idNota;
  }

  Future<void> _afterLocalWrite() async {
    if (!_localChangesController.isClosed) {
      _localChangesController.add(null);
    }
    await syncService.trySyncIfOnline();
  }

  Future<void> dispose() async {
    await _syncDataSub?.cancel();
    syncService.dispose();
    await _localChangesController.close();
  }
}
