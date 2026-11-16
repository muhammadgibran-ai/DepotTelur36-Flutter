import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';

/// Filter rentang tanggal pada layar `Riwayat Nota Penjualan`.
enum NotaHistoryDateFilter {
  semua('Semua'),
  hariIni('Hari Ini'),
  tujuhHari('7 Hari');

  const NotaHistoryDateFilter(this.label);

  final String label;
}

/// Baris draft item transaksi yang aktif pada keranjang Nota/Faktur.
class CartLineDraft {
  const CartLineDraft({
    required this.barang,
    required this.qty,
  });

  final Barang barang;
  final int qty;

  double get subtotal => barang.hargaSatuan * qty;
}

/// Abstraksi sumber data transaksi agar ViewModel dapat diuji terisolasi.
abstract class TransactionCrudDataSource {
  Stream<void> get onDataChanged;

  Future<List<Barang>> getAllBarang();
  Future<List<Supplier>> getAllSupplier();
  Future<List<Customer>> getAllCustomer();
  Future<List<Petugas>> getAllPetugas();
  Future<List<Faktur>> getAllFaktur();
  Future<List<Nota>> getAllNota();
  Future<Faktur?> getFakturById(int idFaktur);
  Future<Nota?> getNotaById(int idNota);
  Future<String> generateNextNoFaktur({DateTime? date});

  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  });

  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  });

  Future<void> deleteFaktur(int idFaktur);

  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  });

  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  });

  Future<void> deleteNota(int idNota);
}

/// Implementasi sumber data transaksi terhubung langsung ke [InventoryRepository].
class RepositoryTransactionCrudDataSource
    implements TransactionCrudDataSource {
  RepositoryTransactionCrudDataSource(this._repository);

  final InventoryRepository _repository;

  @override
  Stream<void> get onDataChanged => _repository.onDataChanged;

  @override
  Future<List<Barang>> getAllBarang() => _repository.getAllBarang();

  @override
  Future<List<Supplier>> getAllSupplier() => _repository.getAllSupplier();

  @override
  Future<List<Customer>> getAllCustomer() => _repository.getAllCustomer();

  @override
  Future<List<Petugas>> getAllPetugas() => _repository.getAllPetugas();

  @override
  Future<List<Faktur>> getAllFaktur() => _repository.getAllFaktur();

  @override
  Future<List<Nota>> getAllNota() => _repository.getAllNota();

  @override
  Future<Faktur?> getFakturById(int idFaktur) =>
      _repository.getFakturById(idFaktur);

  @override
  Future<Nota?> getNotaById(int idNota) => _repository.getNotaById(idNota);

  @override
  Future<String> generateNextNoFaktur({DateTime? date}) =>
      _repository.generateNextNoFaktur(date: date);

  @override
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) {
    return _repository.createFaktur(
      noFaktur: noFaktur,
      tanggalFaktur: tanggalFaktur,
      supplier: supplier,
      petugas: petugas,
      items: items,
    );
  }

  @override
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) {
    return _repository.updateFaktur(
      existing: existing,
      noFaktur: noFaktur,
      tanggalFaktur: tanggalFaktur,
      supplier: supplier,
      petugas: petugas,
      items: items,
    );
  }

  @override
  Future<void> deleteFaktur(int idFaktur) => _repository.deleteFaktur(idFaktur);

  @override
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) {
    return _repository.createNota(
      tanggalNota: tanggalNota,
      customer: customer,
      petugas: petugas,
      items: items,
    );
  }

  @override
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) {
    return _repository.updateNota(
      existing: existing,
      tanggalNota: tanggalNota,
      customer: customer,
      petugas: petugas,
      items: items,
    );
  }

  @override
  Future<void> deleteNota(int idNota) => _repository.deleteNota(idNota);
}

/// Sumber data read-only dari [DashboardViewModel] untuk mode uji UI tanpa repo.
class ReadOnlyTransactionBridgeDataSource implements TransactionCrudDataSource {
  ReadOnlyTransactionBridgeDataSource(this._dashboardVm);

  final DashboardViewModel _dashboardVm;

  @override
  Stream<void> get onDataChanged => const Stream<void>.empty();

  @override
  Future<List<Barang>> getAllBarang() async => _dashboardVm.allBarang;

  @override
  Future<List<Supplier>> getAllSupplier() async => _dashboardVm.allSuppliers;

  @override
  Future<List<Customer>> getAllCustomer() async => _dashboardVm.allCustomers;

  @override
  Future<List<Petugas>> getAllPetugas() async => _dashboardVm.allPetugas;

  @override
  Future<List<Faktur>> getAllFaktur() async => _dashboardVm.allFakturs;

  @override
  Future<List<Nota>> getAllNota() async => _dashboardVm.allNotas;

  @override
  Future<Faktur?> getFakturById(int idFaktur) async {
    for (final f in _dashboardVm.allFakturs) {
      if (f.idFaktur == idFaktur) return f;
    }
    return null;
  }

  @override
  Future<Nota?> getNotaById(int idNota) async {
    for (final n in _dashboardVm.allNotas) {
      if (n.idNota == idNota) return n;
    }
    return null;
  }

  @override
  Future<String> generateNextNoFaktur({DateTime? date}) async {
    final now = date ?? DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'FKT-$y$m$d-${(_dashboardVm.allFakturs.length + 1).toString().padLeft(3, '0')}';
  }

  Never _unsupported() {
    throw const MasterDataValidationException(
      'Penyimpanan transaksi belum tersedia pada mode pratinjau.',
    );
  }

  @override
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async =>
      _unsupported();

  @override
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async =>
      _unsupported();

  @override
  Future<void> deleteFaktur(int idFaktur) async => _unsupported();

  @override
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async =>
      _unsupported();

  @override
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async =>
      _unsupported();

  @override
  Future<void> deleteNota(int idNota) async => _unsupported();
}

/// ViewModel CRUD Transaksi untuk Kasir Nota, Faktur Masuk, Riwayat, dan Edit Detail.
class TransactionCrudViewModel extends ChangeNotifier {
  TransactionCrudViewModel({
    required AuthSession session,
    required TransactionCrudDataSource dataSource,
    DateTime Function()? nowProvider,
  }) : this._(
          session: session,
          dataSource: dataSource,
          now: nowProvider ?? DateTime.now,
        );

  TransactionCrudViewModel._({
    required this._session,
    required this._dataSource,
    required this._now,
  }) {
    final todayIso = toIsoDateString(_now());
    _selectedNotaDate = todayIso;
    _selectedFakturDate = todayIso;
    _noFakturInput = _fallbackNoFaktur(_now());
    _subscription = _dataSource.onDataChanged.listen((_) {
      unawaited(loadData(silent: true));
    });
  }

  factory TransactionCrudViewModel.fromRepository({
    required AuthSession session,
    required InventoryRepository repository,
    DateTime Function()? nowProvider,
  }) {
    return TransactionCrudViewModel(
      session: session,
      dataSource: RepositoryTransactionCrudDataSource(repository),
      nowProvider: nowProvider,
    );
  }

  final TransactionCrudDataSource _dataSource;
  final DateTime Function() _now;
  AuthSession _session;

  StreamSubscription<void>? _subscription;
  int _loadEpoch = 0;
  bool _disposed = false;

  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _successMessage;
  int _errorShakePulse = 0;

  List<Barang> _barangs = const [];
  List<Supplier> _suppliers = const [];
  List<Customer> _customers = const [];
  List<Petugas> _petugasList = const [];
  List<Faktur> _fakturs = const [];
  List<Nota> _notas = const [];

  // Draft Kasir Nota (Screen 07)
  String _kasirSearchQuery = '';
  int? _selectedNotaCustomerId;
  late String _selectedNotaDate;
  final Map<int, int> _kasirCart = <int, int>{};

  // Draft Faktur Masuk (Screen 08)
  String _noFakturInput = '';
  bool _noFakturEditedByUser = false;
  int? _selectedFakturSupplierId;
  late String _selectedFakturDate;
  final Map<int, int> _fakturCart = <int, int>{};
  String? _pendingRestockBarangName;

  // Filter Riwayat Nota (Screen 16) & Riwayat Faktur (Screen 18)
  String _notaHistoryQuery = '';
  NotaHistoryDateFilter _notaDateFilter = NotaHistoryDateFilter.semua;
  String _fakturHistoryQuery = '';
  String? _fakturSupplierFilterRemoteId;

  // Getters
  AuthSession get session => _session;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  int get errorShakePulse => _errorShakePulse;

  List<Barang> get barangs => _barangs;
  List<Supplier> get suppliers => _suppliers;
  List<Customer> get customers => _customers;
  List<Petugas> get petugasList => _petugasList;
  List<Faktur> get fakturs => _fakturs;
  List<Nota> get notas => _notas;

  String get kasirSearchQuery => _kasirSearchQuery;
  int? get selectedNotaCustomerId => _selectedNotaCustomerId;
  String get selectedNotaDate => _selectedNotaDate;

  String get noFakturInput => _noFakturInput;
  int? get selectedFakturSupplierId => _selectedFakturSupplierId;
  String get selectedFakturDate => _selectedFakturDate;

  String get notaHistoryQuery => _notaHistoryQuery;
  NotaHistoryDateFilter get notaDateFilter => _notaDateFilter;
  String get fakturHistoryQuery => _fakturHistoryQuery;
  String? get fakturSupplierFilterRemoteId => _fakturSupplierFilterRemoteId;

  Customer? get selectedNotaCustomer => _findCustomer(_selectedNotaCustomerId);
  Supplier? get selectedFakturSupplier =>
      _findSupplier(_selectedFakturSupplierId);

  Petugas? get activePetugas {
    if (_petugasList.isEmpty) return null;
    final remoteId = _session.petugasRemoteId.trim();
    if (remoteId.isNotEmpty) {
      for (final p in _petugasList) {
        if (p.remoteId == remoteId && p.idPetugas != null) return p;
      }
    }
    final email = _session.email.trim().toLowerCase();
    if (email.isNotEmpty) {
      for (final p in _petugasList) {
        if (p.email.trim().toLowerCase() == email && p.idPetugas != null) {
          return p;
        }
      }
    }
    for (final p in _petugasList) {
      if (p.role == _session.role && p.idPetugas != null) return p;
    }
    for (final p in _petugasList) {
      if (p.idPetugas != null) return p;
    }
    return null;
  }

  List<Barang> get filteredKasirBarangs {
    final query = sanitizeSearchQuery(_kasirSearchQuery).toLowerCase();
    if (query.isEmpty) return _barangs;
    return _barangs.where((b) {
      return b.namaBarang.toLowerCase().contains(query) ||
          b.satuan.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  int kasirQtyFor(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return 0;
    return _kasirCart[id] ?? 0;
  }

  List<CartLineDraft> get kasirCartLines => _buildDraftLines(_kasirCart);

  int get kasirTotalUnits =>
      kasirCartLines.fold(0, (sum, line) => sum + line.qty);

  int get kasirItemCount => kasirCartLines.length;

  double get kasirGrandTotal =>
      kasirCartLines.fold(0.0, (sum, line) => sum + line.subtotal);

  int fakturQtyFor(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return 0;
    return _fakturCart[id] ?? 0;
  }

  List<CartLineDraft> get fakturCartLines => _buildDraftLines(_fakturCart);

  int get fakturItemCount => fakturCartLines.length;

  double get fakturGrandTotal =>
      fakturCartLines.fold(0.0, (sum, line) => sum + line.subtotal);

  List<Nota> get filteredNotas {
    final query = sanitizeSearchQuery(_notaHistoryQuery).toLowerCase();
    final today = _now();
    final todayIso = toIsoDateString(today);
    final sevenDaysStart = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));

    return _notas.where((nota) {
      final matchesDate = switch (_notaDateFilter) {
        NotaHistoryDateFilter.semua => true,
        NotaHistoryDateFilter.hariIni => nota.tanggalNota == todayIso,
        NotaHistoryDateFilter.tujuhHari => _isIsoDateOnOrAfter(
            nota.tanggalNota,
            sevenDaysStart,
          ),
      };
      if (!matchesDate) return false;
      if (query.isEmpty) return true;
      final idStr = nota.idNota?.toString() ?? '';
      final customerName = (nota.namaCustomer ?? '').toLowerCase();
      final petugasName = (nota.namaPetugas ?? '').toLowerCase();
      final itemsJoined = nota.details
          .map((d) => (d.namaBarang ?? '').toLowerCase())
          .join(' ');
      return idStr.contains(query) ||
          'nota #$idStr'.contains(query) ||
          customerName.contains(query) ||
          petugasName.contains(query) ||
          nota.tanggalNota.toLowerCase().contains(query) ||
          itemsJoined.contains(query);
    }).toList(growable: false);
  }

  List<Faktur> get filteredFakturs {
    final query = sanitizeSearchQuery(_fakturHistoryQuery).toLowerCase();
    final supplierFilter = _fakturSupplierFilterRemoteId;

    return _fakturs.where((faktur) {
      if (supplierFilter != null &&
          supplierFilter.isNotEmpty &&
          faktur.supplierRemoteId != supplierFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final supplierName = (faktur.namaSupplier ?? '').toLowerCase();
      final petugasName = (faktur.namaPetugas ?? '').toLowerCase();
      final itemsJoined = faktur.details
          .map((d) => (d.namaBarang ?? '').toLowerCase())
          .join(' ');
      return faktur.noFaktur.toLowerCase().contains(query) ||
          supplierName.contains(query) ||
          petugasName.contains(query) ||
          faktur.tanggalFaktur.toLowerCase().contains(query) ||
          itemsJoined.contains(query);
    }).toList(growable: false);
  }

  static String toIsoDateString(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String formatDisplayDate(String isoDate, {bool short = false}) {
    final parsed = _parseIsoDate(isoDate);
    if (parsed == null) return isoDate;
    const shortMonths = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    const fullMonths = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    final monthLabel = short
        ? shortMonths[parsed.month - 1]
        : fullMonths[parsed.month - 1];
    return short
        ? '${parsed.day} $monthLabel'
        : '${parsed.day} $monthLabel ${parsed.year}';
  }

  static DateTime? _parseIsoDate(String raw) {
    final parts = raw.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final dt = DateTime(y, m, d);
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return dt;
  }

  static bool _isIsoDateOnOrAfter(String isoDate, DateTime minDate) {
    final parsed = _parseIsoDate(isoDate);
    if (parsed == null) return false;
    return !parsed.isBefore(minDate);
  }

  static String _fallbackNoFaktur(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return 'FKT-$y$m$d-001';
  }

  void updateSession(AuthSession nextSession) {
    if (_session == nextSession) return;
    _session = nextSession;
    _notifySafely();
  }

  void clearMessages() {
    if (_errorMessage == null && _successMessage == null) return;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();
  }

  Future<void> loadData({bool silent = false}) async {
    final epoch = ++_loadEpoch;
    if (!silent) {
      _isLoading = true;
      _notifySafely();
    }
    try {
      final results = await Future.wait<dynamic>([
        _dataSource.getAllBarang(),
        _dataSource.getAllSupplier(),
        _dataSource.getAllCustomer(),
        _dataSource.getAllPetugas(),
        _dataSource.getAllFaktur(),
        _dataSource.getAllNota(),
        _dataSource.generateNextNoFaktur(date: _now()),
      ]);
      if (_disposed || epoch != _loadEpoch) return;

      _barangs = results[0] as List<Barang>;
      _suppliers = results[1] as List<Supplier>;
      _customers = results[2] as List<Customer>;
      _petugasList = results[3] as List<Petugas>;
      _fakturs = results[4] as List<Faktur>;
      _notas = results[5] as List<Nota>;
      final suggestedNoFaktur = results[6] as String;

      _syncDefaultsAfterLoad(suggestedNoFaktur);
      _errorMessage = null;
    } catch (e) {
      if (_disposed || epoch != _loadEpoch) return;
      _errorMessage = 'Gagal memuat data transaksi: $e';
    } finally {
      if (!_disposed && epoch == _loadEpoch) {
        _isLoading = false;
        _notifySafely();
      }
    }
  }

  void _syncDefaultsAfterLoad(String suggestedNoFaktur) {
    if (_selectedNotaCustomerId == null ||
        _findCustomer(_selectedNotaCustomerId) == null) {
      _selectedNotaCustomerId = _firstValidCustomerId();
    }
    if (_selectedFakturSupplierId == null ||
        _findSupplier(_selectedFakturSupplierId) == null) {
      _selectedFakturSupplierId = _firstValidSupplierId();
    }
    if (!_noFakturEditedByUser || _noFakturInput.trim().isEmpty) {
      _noFakturInput = suggestedNoFaktur;
    }

    final validBarangIds = <int>{
      for (final b in _barangs)
        if (b.idBarang != null) b.idBarang!,
    };
    _kasirCart.removeWhere((id, _) => !validBarangIds.contains(id));
    for (final b in _barangs) {
      final id = b.idBarang;
      if (id != null && _kasirCart.containsKey(id)) {
        final qty = _kasirCart[id]!;
        if (b.stokBarang <= 0) {
          _kasirCart.remove(id);
        } else if (qty > b.stokBarang) {
          _kasirCart[id] = b.stokBarang;
        }
      }
    }
    _fakturCart.removeWhere((id, _) => !validBarangIds.contains(id));

    if (_pendingRestockBarangName != null && _barangs.isNotEmpty) {
      final pending = _pendingRestockBarangName!;
      _pendingRestockBarangName = null;
      _applyRestockDraft(pending, defaultQty: 12);
    }
  }

  int? _firstValidCustomerId() {
    for (final c in _customers) {
      if (c.idCustomer != null) return c.idCustomer;
    }
    return null;
  }

  int? _firstValidSupplierId() {
    for (final s in _suppliers) {
      if (s.idSupplier != null) return s.idSupplier;
    }
    return null;
  }

  Customer? _findCustomer(int? id) {
    if (id == null) return null;
    for (final c in _customers) {
      if (c.idCustomer == id) return c;
    }
    return null;
  }

  Supplier? _findSupplier(int? id) {
    if (id == null) return null;
    for (final s in _suppliers) {
      if (s.idSupplier == id) return s;
    }
    return null;
  }

  Barang? _findBarang(int id) {
    for (final b in _barangs) {
      if (b.idBarang == id) return b;
    }
    return null;
  }

  List<CartLineDraft> _buildDraftLines(Map<int, int> source) {
    final lines = <CartLineDraft>[];
    for (final entry in source.entries) {
      if (entry.value <= 0) continue;
      final barang = _findBarang(entry.key);
      if (barang != null) {
        lines.add(CartLineDraft(barang: barang, qty: entry.value));
      }
    }
    return lines;
  }

  // ==================== DRAFT KASIR NOTA (SCREEN 07) ====================

  void setKasirSearchQuery(String query) {
    _kasirSearchQuery = query;
    _notifySafely();
  }

  void selectNotaCustomer(int? idCustomer) {
    _selectedNotaCustomerId = idCustomer;
    _errorMessage = null;
    _notifySafely();
  }

  void selectNotaDate(DateTime date) {
    _selectedNotaDate = toIsoDateString(date);
    _errorMessage = null;
    _notifySafely();
  }

  bool incrementKasirQty(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return false;
    final current = _kasirCart[id] ?? 0;
    if (current + 1 > barang.stokBarang) {
      _errorMessage =
          'Stok "${barang.namaBarang}" tersisa ${barang.stokBarang} ${barang.satuan}.';
      _errorShakePulse++;
      _notifySafely();
      return false;
    }
    _kasirCart[id] = current + 1;
    _errorMessage = null;
    _notifySafely();
    return true;
  }

  void decrementKasirQty(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return;
    final current = _kasirCart[id] ?? 0;
    if (current <= 1) {
      _kasirCart.remove(id);
    } else {
      _kasirCart[id] = current - 1;
    }
    _errorMessage = null;
    _notifySafely();
  }

  bool setKasirQty(Barang barang, int qty) {
    final id = barang.idBarang;
    if (id == null) return false;
    if (qty <= 0) {
      _kasirCart.remove(id);
      _errorMessage = null;
      _notifySafely();
      return true;
    }
    if (qty > barang.stokBarang) {
      _errorMessage =
          'Stok "${barang.namaBarang}" tersisa ${barang.stokBarang} ${barang.satuan}.';
      _errorShakePulse++;
      _notifySafely();
      return false;
    }
    if (qty > _maxTransactionQty) {
      _failValidation(
        'Jumlah "${barang.namaBarang}" maksimal $_maxTransactionQty.',
      );
      return false;
    }
    _kasirCart[id] = qty;
    _errorMessage = null;
    _notifySafely();
    return true;
  }

  void resetKasirDraft() {
    _kasirCart.clear();
    _kasirSearchQuery = '';
    _errorMessage = null;
    _notifySafely();
  }

  Future<int?> submitKasirNota() async {
    if (_isSubmitting) return null;
    final lines = kasirCartLines;
    if (lines.isEmpty) {
      _failValidation('Pilih minimal 1 barang untuk membuat Nota.');
      return null;
    }
    final customer = selectedNotaCustomer;
    if (customer == null || customer.idCustomer == null) {
      _failValidation('Pilih pelanggan terlebih dahulu.');
      return null;
    }
    final petugas = activePetugas;
    if (petugas == null || petugas.idPetugas == null) {
      _failValidation('Data petugas aktif tidak ditemukan.');
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      final idNota = await _dataSource.createNota(
        tanggalNota: _selectedNotaDate,
        customer: customer,
        petugas: petugas,
        items: lines
            .map((e) => (barang: e.barang, banyaknya: e.qty))
            .toList(growable: false),
      );
      if (_disposed) return idNota;
      _kasirCart.clear();
      _successMessage = 'Nota #$idNota berhasil disimpan.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return idNota;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return null;
      _isSubmitting = false;
      _failValidation(e.message);
      return null;
    } catch (e) {
      if (_disposed) return null;
      _isSubmitting = false;
      _failValidation('Gagal menyimpan nota: $e');
      return null;
    }
  }

  // ==================== DRAFT FAKTUR MASUK (SCREEN 08) ====================

  void setNoFakturInput(String raw) {
    _noFakturInput = raw;
    _noFakturEditedByUser = raw.trim().isNotEmpty;
    _errorMessage = null;
    _notifySafely();
  }

  void selectFakturSupplier(int? idSupplier) {
    _selectedFakturSupplierId = idSupplier;
    _errorMessage = null;
    _notifySafely();
  }

  void selectFakturDate(DateTime date) {
    _selectedFakturDate = toIsoDateString(date);
    _errorMessage = null;
    _notifySafely();
  }

  static const int _maxTransactionQty = 9999999;

  void addOrIncrementFakturBarang(Barang barang, {int delta = 1}) {
    final id = barang.idBarang;
    if (id == null || delta <= 0) return;
    final current = _fakturCart[id] ?? 0;
    if (delta > _maxTransactionQty || current + delta > _maxTransactionQty) {
      _failValidation(
        'Jumlah "${barang.namaBarang}" maksimal $_maxTransactionQty.',
      );
      return;
    }
    _fakturCart[id] = current + delta;
    _errorMessage = null;
    _notifySafely();
  }

  void decrementFakturQty(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return;
    final current = _fakturCart[id] ?? 0;
    if (current <= 1) {
      _fakturCart.remove(id);
    } else {
      _fakturCart[id] = current - 1;
    }
    _errorMessage = null;
    _notifySafely();
  }

  void removeFakturItem(int idBarang) {
    _fakturCart.remove(idBarang);
    _errorMessage = null;
    _notifySafely();
  }

  void setFakturQty(Barang barang, int qty) {
    final id = barang.idBarang;
    if (id == null) return;
    if (qty <= 0) {
      _fakturCart.remove(id);
    } else if (qty > _maxTransactionQty) {
      _failValidation(
        'Jumlah "${barang.namaBarang}" maksimal $_maxTransactionQty.',
      );
      return;
    } else {
      _fakturCart[id] = qty;
    }
    _errorMessage = null;
    _notifySafely();
  }

  /// Menyiapkan item restock otomatis ketika pengguna menekan tombol `Restock`.
  void prefillFakturRestock(String barangName, {int defaultQty = 12}) {
    if (barangName.trim().isEmpty) return;
    if (_barangs.isEmpty) {
      _pendingRestockBarangName = barangName;
      return;
    }
    _applyRestockDraft(barangName, defaultQty: defaultQty);
    _notifySafely();
  }

  void _applyRestockDraft(String barangName, {required int defaultQty}) {
    final key = barangName.trim().toLowerCase();
    if (key.isEmpty) return;
    Barang? match;
    for (final b in _barangs) {
      if (b.namaBarang.trim().toLowerCase() == key) {
        match = b;
        break;
      }
    }
    match ??= _barangs.cast<Barang?>().firstWhere(
          (b) => b!.namaBarang.trim().toLowerCase().contains(key),
          orElse: () => null,
        );
    final id = match?.idBarang;
    if (id != null && !_fakturCart.containsKey(id)) {
      _fakturCart[id] = defaultQty > 0 ? defaultQty : 10;
    }
  }

  Future<int?> submitFakturMasuk() async {
    if (_isSubmitting) return null;
    final lines = fakturCartLines;
    if (lines.isEmpty) {
      _failValidation('Tambahkan minimal 1 barang untuk menyimpan Faktur.');
      return null;
    }
    final supplier = selectedFakturSupplier;
    if (supplier == null || supplier.idSupplier == null) {
      _failValidation('Pilih supplier terlebih dahulu.');
      return null;
    }
    final petugas = activePetugas;
    if (petugas == null || petugas.idPetugas == null) {
      _failValidation('Data petugas penerima tidak ditemukan.');
      return null;
    }

    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      final idFaktur = await _dataSource.createFaktur(
        noFaktur: _noFakturInput,
        tanggalFaktur: _selectedFakturDate,
        supplier: supplier,
        petugas: petugas,
        items: lines
            .map((e) => (barang: e.barang, quantity: e.qty))
            .toList(growable: false),
      );
      if (_disposed) return idFaktur;
      final savedNo = _noFakturInput.trim();
      _fakturCart.clear();
      _noFakturEditedByUser = false;
      _successMessage = 'Faktur $savedNo berhasil disimpan & stok bertambah.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return idFaktur;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return null;
      _isSubmitting = false;
      _failValidation(e.message);
      return null;
    } catch (e) {
      if (_disposed) return null;
      _isSubmitting = false;
      _failValidation('Gagal menyimpan faktur: $e');
      return null;
    }
  }

  // ==================== FILTER RIWAYAT (SCREEN 16 & 18) ====================

  void setNotaHistoryQuery(String query) {
    _notaHistoryQuery = query;
    _notifySafely();
  }

  void setNotaDateFilter(NotaHistoryDateFilter filter) {
    _notaDateFilter = filter;
    _notifySafely();
  }

  void setFakturHistoryQuery(String query) {
    _fakturHistoryQuery = query;
    _notifySafely();
  }

  void setFakturSupplierFilter(String? supplierRemoteId) {
    _fakturSupplierFilterRemoteId = supplierRemoteId;
    _notifySafely();
  }

  // ==================== EDIT & DELETE DETAIL (SCREEN 17 & 19) ====================

  Future<Nota?> reloadNotaById(int idNota) async {
    try {
      return await _dataSource.getNotaById(idNota);
    } catch (_) {
      return null;
    }
  }

  Future<Faktur?> reloadFakturById(int idFaktur) async {
    try {
      return await _dataSource.getFakturById(idFaktur);
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateNotaRecord({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      await _dataSource.updateNota(
        existing: existing,
        tanggalNota: tanggalNota,
        customer: customer,
        petugas: petugas,
        items: items,
      );
      if (_disposed) return true;
      _successMessage = 'Nota #${existing.idNota ?? '-'} berhasil diperbarui.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return true;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation(e.message);
      return false;
    } catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation('Gagal memperbarui nota: $e');
      return false;
    }
  }

  Future<bool> deleteNotaRecord(int idNota) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      await _dataSource.deleteNota(idNota);
      if (_disposed) return true;
      _successMessage = 'Nota #$idNota dihapus dan stok dikembalikan.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return true;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation(e.message);
      return false;
    } catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation('Gagal menghapus nota: $e');
      return false;
    }
  }

  Future<bool> updateFakturRecord({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      await _dataSource.updateFaktur(
        existing: existing,
        noFaktur: noFaktur,
        tanggalFaktur: tanggalFaktur,
        supplier: supplier,
        petugas: petugas,
        items: items,
      );
      if (_disposed) return true;
      _successMessage = 'Faktur ${noFaktur.trim()} berhasil diperbarui.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return true;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation(e.message);
      return false;
    } catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation('Gagal memperbarui faktur: $e');
      return false;
    }
  }

  Future<bool> deleteFakturRecord(int idFaktur) async {
    if (_isSubmitting) return false;
    _isSubmitting = true;
    _errorMessage = null;
    _successMessage = null;
    _notifySafely();

    try {
      await _dataSource.deleteFaktur(idFaktur);
      if (_disposed) return true;
      _successMessage = 'Faktur berhasil dihapus dan stok disesuaikan.';
      _isSubmitting = false;
      _notifySafely();
      unawaited(loadData(silent: true));
      return true;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation(e.message);
      return false;
    } catch (e) {
      if (_disposed) return false;
      _isSubmitting = false;
      _failValidation('Gagal menghapus faktur: $e');
      return false;
    }
  }

  void _failValidation(String message) {
    _errorMessage = message;
    _errorShakePulse++;
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
