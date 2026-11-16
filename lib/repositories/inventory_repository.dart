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
  Future<Faktur?> getFakturById(int idFaktur) =>
      _dbHelper.getFakturById(idFaktur);
  Future<List<Nota>> getAllNota() => _dbHelper.getAllNota();
  Future<Nota?> getNotaById(int idNota) => _dbHelper.getNotaById(idNota);

  static final RegExp _isoDateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');

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

  // ==================== CRUD TRANSAKSI: FAKTUR & NOTA ====================

  static const int _maxTransactionQty = 9999999;

  Future<void> _assertUniqueNoFaktur(
    String cleanNoFaktur, {
    int? excludeIdFaktur,
  }) async {
    final targetKey = normalizeKey(cleanNoFaktur);
    final existing = await _dbHelper.getAllFaktur();
    for (final faktur in existing) {
      if (faktur.idFaktur != excludeIdFaktur &&
          normalizeKey(faktur.noFaktur) == targetKey) {
        throw MasterDataValidationException(
          'Nomor faktur "$cleanNoFaktur" sudah terdaftar.',
        );
      }
    }
  }

  void _assertFiniteTotal(double total, String docName) {
    if (!total.isFinite || total < 0) {
      throw MasterDataValidationException(
        'Total nominal $docName melebihi batas perhitungan.',
      );
    }
  }

  String _validateNoFaktur(String raw) {
    if (hasControlChars(raw)) {
      throw const MasterDataValidationException(
        'Nomor faktur mengandung karakter yang tidak valid.',
      );
    }
    final clean = normalizeText(raw);
    if (clean.length < 3 || clean.length > 50) {
      throw const MasterDataValidationException(
        'Nomor faktur harus 3–50 karakter.',
      );
    }
    return clean;
  }

  String _validateTransactionDate(String raw, String fieldLabel) {
    if (hasControlChars(raw)) {
      throw MasterDataValidationException(
        '$fieldLabel mengandung karakter yang tidak valid.',
      );
    }
    final clean = normalizeText(raw);
    if (!_isoDateRegex.hasMatch(clean)) {
      throw MasterDataValidationException(
        '$fieldLabel harus berformat YYYY-MM-DD.',
      );
    }
    final parts = clean.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    if (year < 2000 || year > 2100) {
      throw MasterDataValidationException(
        '$fieldLabel harus berada pada tahun 2000–2100.',
      );
    }
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw MasterDataValidationException('$fieldLabel bukan tanggal yang valid.');
    }
    return clean;
  }

  List<T> _buildValidatedDetails<T>({
    required List<({Barang barang, int qty})> items,
    required String docName,
    required T Function(Barang barang, int qty, double subtotal) builder,
  }) {
    if (items.isEmpty) {
      throw MasterDataValidationException(
        'Detail $docName wajib berisi minimal 1 barang.',
      );
    }
    final seenBarangIds = <int>{};
    final details = <T>[];
    for (final entry in items) {
      final barang = entry.barang;
      if (barang.idBarang == null) {
        throw MasterDataValidationException(
          'Barang "${barang.namaBarang}" belum tersimpan di database.',
        );
      }
      if (!seenBarangIds.add(barang.idBarang!)) {
        throw MasterDataValidationException(
          'Barang "${barang.namaBarang}" tidak boleh duplikat dalam satu $docName.',
        );
      }
      if (entry.qty <= 0 || entry.qty > _maxTransactionQty) {
        throw MasterDataValidationException(
          'Jumlah "${barang.namaBarang}" harus antara 1 hingga 9.999.999.',
        );
      }
      if (barang.hargaSatuan.isNaN ||
          barang.hargaSatuan.isInfinite ||
          barang.hargaSatuan < 0) {
        throw MasterDataValidationException(
          'Harga satuan "${barang.namaBarang}" tidak valid.',
        );
      }
      final subtotal = barang.hargaSatuan * entry.qty;
      if (!subtotal.isFinite || subtotal < 0) {
        throw MasterDataValidationException(
          'Subtotal "${barang.namaBarang}" tidak valid.',
        );
      }
      details.add(
        builder(barang, entry.qty, subtotal),
      );
    }
    return details;
  }

  /// Menghasilkan nomor faktur bawaan dengan format `FKT-YYYYMMDD-NNN`.
  Future<String> generateNextNoFaktur({DateTime? date}) async {
    final targetDate = date ?? DateTime.now();
    final y = targetDate.year.toString().padLeft(4, '0');
    final m = targetDate.month.toString().padLeft(2, '0');
    final d = targetDate.day.toString().padLeft(2, '0');
    final dateTag = '$y$m$d';
    final prefix = 'FKT-$dateTag-';
    final existing = await getAllFaktur();
    var maxSeq = 0;
    for (final f in existing) {
      final normalized = f.noFaktur.trim().toUpperCase();
      if (normalized.startsWith(prefix)) {
        final suffix = int.tryParse(normalized.substring(prefix.length));
        if (suffix != null && suffix > maxSeq) {
          maxSeq = suffix;
        }
      }
    }
    final nextSeq = (maxSeq + 1).toString().padLeft(3, '0');
    return '$prefix$nextSeq';
  }

  /// Mencatat pembelian barang masuk dari supplier (`faktur` + `detail_faktur`)
  /// dan langsung menambah stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    final cleanNoFaktur = _validateNoFaktur(noFaktur);
    final cleanTanggal = _validateTransactionDate(
      tanggalFaktur,
      'Tanggal faktur',
    );
    if (supplier.idSupplier == null || petugas.idPetugas == null) {
      throw const MasterDataValidationException(
        'Supplier dan Petugas harus tersimpan di database.',
      );
    }
    await _assertUniqueNoFaktur(cleanNoFaktur);
    final details = _buildValidatedDetails<DetailFaktur>(
      items: items
          .map((e) => (barang: e.barang, qty: e.quantity))
          .toList(growable: false),
      docName: 'faktur',
      builder: (barang, qty, subtotal) => DetailFaktur(
        idBarang: barang.idBarang!,
        jumlah: subtotal,
        quantity: qty,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      ),
    );

    final total = Faktur.hitungTotal(details);
    _assertFiniteTotal(total, 'faktur');

    final faktur = Faktur(
      noFaktur: cleanNoFaktur,
      tanggalFaktur: cleanTanggal,
      total: total,
      idSupplier: supplier.idSupplier!,
      idPetugas: petugas.idPetugas!,
      remoteId: _uuid.v4(),
      supplierRemoteId: supplier.remoteId,
      petugasRemoteId: petugas.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
      details: details,
    );

    try {
      final idFaktur = await _dbHelper.insertFakturTransaction(faktur, details);
      await _afterLocalWrite();
      return idFaktur;
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    } on ArgumentError catch (e) {
      throw MasterDataValidationException(e.message.toString());
    }
  }

  /// Memperbarui header dan rincian `faktur` masuk serta merekonsiliasi selisih
  /// stok barang di SQLite lokal sebelum sinkronisasi Cloud.
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    if (existing.idFaktur == null) {
      throw const MasterDataValidationException(
        'Faktur belum tersimpan di database lokal.',
      );
    }
    final cleanNoFaktur = _validateNoFaktur(noFaktur);
    final cleanTanggal = _validateTransactionDate(
      tanggalFaktur,
      'Tanggal faktur',
    );
    if (supplier.idSupplier == null || petugas.idPetugas == null) {
      throw const MasterDataValidationException(
        'Supplier dan Petugas harus tersimpan di database.',
      );
    }
    await _assertUniqueNoFaktur(
      cleanNoFaktur,
      excludeIdFaktur: existing.idFaktur,
    );
    final details = _buildValidatedDetails<DetailFaktur>(
      items: items
          .map((e) => (barang: e.barang, qty: e.quantity))
          .toList(growable: false),
      docName: 'faktur',
      builder: (barang, qty, subtotal) => DetailFaktur(
        idFaktur: existing.idFaktur,
        idBarang: barang.idBarang!,
        jumlah: subtotal,
        quantity: qty,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      ),
    );

    final total = Faktur.hitungTotal(details);
    _assertFiniteTotal(total, 'faktur');

    final updated = existing.copyWith(
      noFaktur: cleanNoFaktur,
      tanggalFaktur: cleanTanggal,
      total: total,
      idSupplier: supplier.idSupplier!,
      idPetugas: petugas.idPetugas!,
      supplierRemoteId: supplier.remoteId,
      petugasRemoteId: petugas.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
      details: details,
    );

    try {
      await _dbHelper.updateFakturTransaction(updated, details);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    } on ArgumentError catch (e) {
      throw MasterDataValidationException(e.message.toString());
    }
  }

  /// Menghapus `faktur` beserta `detail_faktur` dan membalikkan stok barang masuk.
  Future<void> deleteFaktur(int idFaktur) async {
    try {
      await _dbHelper.deleteFakturTransaction(idFaktur);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
  }

  /// Mencatat penjualan kasir ke customer (`nota` + `detail_nota`)
  /// dan langsung memotong stok barang secara lokal, lalu auto-sync saat online.
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    final cleanTanggal = _validateTransactionDate(tanggalNota, 'Tanggal nota');
    if (customer.idCustomer == null || petugas.idPetugas == null) {
      throw const MasterDataValidationException(
        'Customer dan Petugas harus tersimpan di database.',
      );
    }
    final details = _buildValidatedDetails<DetailNota>(
      items: items
          .map((e) => (barang: e.barang, qty: e.banyaknya))
          .toList(growable: false),
      docName: 'nota',
      builder: (barang, qty, subtotal) => DetailNota(
        idBarang: barang.idBarang!,
        jumlah: subtotal,
        banyaknya: qty,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      ),
    );

    final total = Nota.hitungTotal(details);
    _assertFiniteTotal(total, 'nota');

    final nota = Nota(
      tanggalNota: cleanTanggal,
      total: total,
      idPetugas: petugas.idPetugas!,
      idCustomer: customer.idCustomer!,
      remoteId: _uuid.v4(),
      petugasRemoteId: petugas.remoteId,
      customerRemoteId: customer.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
      details: details,
    );

    try {
      final idNota = await _dbHelper.insertNotaTransaction(nota, details);
      await _afterLocalWrite();
      return idNota;
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    } on ArgumentError catch (e) {
      throw MasterDataValidationException(e.message.toString());
    }
  }

  /// Memperbarui header & detail `nota` kasir serta mengembalikan stok lama
  /// sebelum memotong stok baru secara atomik.
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    if (existing.idNota == null) {
      throw const MasterDataValidationException(
        'Nota belum tersimpan di database lokal.',
      );
    }
    final cleanTanggal = _validateTransactionDate(tanggalNota, 'Tanggal nota');
    if (customer.idCustomer == null || petugas.idPetugas == null) {
      throw const MasterDataValidationException(
        'Customer dan Petugas harus tersimpan di database.',
      );
    }
    final details = _buildValidatedDetails<DetailNota>(
      items: items
          .map((e) => (barang: e.barang, qty: e.banyaknya))
          .toList(growable: false),
      docName: 'nota',
      builder: (barang, qty, subtotal) => DetailNota(
        idNota: existing.idNota,
        idBarang: barang.idBarang!,
        jumlah: subtotal,
        banyaknya: qty,
        barangRemoteId: barang.remoteId,
        namaBarang: barang.namaBarang,
        satuan: barang.satuan,
      ),
    );

    final total = Nota.hitungTotal(details);
    _assertFiniteTotal(total, 'nota');

    final updated = existing.copyWith(
      tanggalNota: cleanTanggal,
      total: total,
      idPetugas: petugas.idPetugas!,
      idCustomer: customer.idCustomer!,
      petugasRemoteId: petugas.remoteId,
      customerRemoteId: customer.remoteId,
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
      details: details,
    );

    try {
      await _dbHelper.updateNotaTransaction(updated, details);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    } on ArgumentError catch (e) {
      throw MasterDataValidationException(e.message.toString());
    }
  }

  /// Menghapus `nota` beserta `detail_nota` dan mengembalikan stok barang terjual.
  Future<void> deleteNota(int idNota) async {
    try {
      await _dbHelper.deleteNotaTransaction(idNota);
      await _afterLocalWrite();
    } on StateError catch (e) {
      throw MasterDataValidationException(e.message);
    }
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
