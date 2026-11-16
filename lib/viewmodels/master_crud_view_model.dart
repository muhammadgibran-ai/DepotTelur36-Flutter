import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';

/// Kategori entitas pada layar Master Data Toko.
enum MasterCategory {
  barang(
    label: 'Barang',
    headerTitle: 'Master Data Toko',
    headerSubtitle: 'Kelola katalog stok dan mitra toko',
    addButtonLabel: '+ Tambah',
    searchHint: 'Cari nama barang atau satuan...',
  ),
  supplier(
    label: 'Supplier',
    headerTitle: 'Master Data Toko',
    headerSubtitle: 'Lihat dan perbarui daftar supplier toko',
    addButtonLabel: '+ Supplier',
    searchHint: 'Cari nama, nomor telepon, atau alamat...',
  ),
  pelanggan(
    label: 'Pelanggan',
    headerTitle: 'Master Data Toko',
    headerSubtitle: 'Lihat dan kelola daftar pelanggan kasir',
    addButtonLabel: '+ Pelanggan',
    searchHint: 'Cari nama pelanggan...',
  ),
  petugas(
    label: 'Petugas',
    headerTitle: 'Master Data Toko',
    headerSubtitle: 'Kelola akun dan peran owner maupun petugas',
    addButtonLabel: '+ Petugas',
    searchHint: 'Cari nama petugas, email, atau peran...',
  );

  const MasterCategory({
    required this.label,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.addButtonLabel,
    required this.searchHint,
  });

  final String label;
  final String headerTitle;
  final String headerSubtitle;
  final String addButtonLabel;
  final String searchHint;
}

/// Filter komoditas pada halaman khusus Owner `Atur Harga Jual`.
enum PriceFilterCategory {
  semua('Semua'),
  telur('Komoditas Telur'),
  sembako('Sembako');

  const PriceFilterCategory(this.label);

  final String label;
}

/// Mengembalikan kategori master yang diizinkan untuk peran pengguna (RBAC).
List<MasterCategory> allowedMasterCategories(UserRole role) {
  if (role == UserRole.owner) {
    return const [
      MasterCategory.barang,
      MasterCategory.supplier,
      MasterCategory.pelanggan,
      MasterCategory.petugas,
    ];
  }
  return const [
    MasterCategory.barang,
    MasterCategory.supplier,
    MasterCategory.pelanggan,
  ];
}

/// Abstraksi sumber data untuk [MasterCrudViewModel] agar dapat diuji terisolasi.
abstract class MasterCrudDataSource {
  Stream<void> get onDataChanged;

  Future<List<Barang>> getAllBarang();
  Future<List<Supplier>> getAllSupplier();
  Future<List<Customer>> getAllCustomer();
  Future<List<Petugas>> getAllPetugas();

  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  });

  Future<void> updateBarangHargaBatch(Map<int, double> hargaById);

  Future<void> deleteBarang(int idBarang);

  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  });

  Future<void> deleteSupplier(int idSupplier);

  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  });

  Future<void> deleteCustomer(int idCustomer);

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
  });

  Future<void> deletePetugas(Petugas target, {String? currentUserRemoteId});
}

/// Adaptor produksi yang menghubungkan [MasterCrudViewModel] ke [InventoryRepository].
class RepositoryMasterCrudDataSource implements MasterCrudDataSource {
  RepositoryMasterCrudDataSource(this._repository);

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
  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) {
    return _repository.saveBarang(
      idBarang: idBarang,
      existingRemoteId: existingRemoteId,
      namaBarang: namaBarang,
      stokBarang: stokBarang,
      satuan: satuan,
      hargaSatuan: hargaSatuan,
    );
  }

  @override
  Future<void> updateBarangHargaBatch(Map<int, double> hargaById) {
    return _repository.updateBarangHargaBatch(hargaById);
  }

  @override
  Future<void> deleteBarang(int idBarang) => _repository.deleteBarang(idBarang);

  @override
  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) {
    return _repository.saveSupplier(
      idSupplier: idSupplier,
      existingRemoteId: existingRemoteId,
      namaSupplier: namaSupplier,
      alamatSupplier: alamatSupplier,
      noTelpSupplier: noTelpSupplier,
    );
  }

  @override
  Future<void> deleteSupplier(int idSupplier) =>
      _repository.deleteSupplier(idSupplier);

  @override
  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) {
    return _repository.saveCustomer(
      idCustomer: idCustomer,
      existingRemoteId: existingRemoteId,
      namaCustomer: namaCustomer,
    );
  }

  @override
  Future<void> deleteCustomer(int idCustomer) =>
      _repository.deleteCustomer(idCustomer);

  @override
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
  }) {
    return _repository.savePetugas(
      idPetugas: idPetugas,
      existingRemoteId: existingRemoteId,
      namaPetugas: namaPetugas,
      role: role,
      pin: pin,
      email: email,
      accountId: accountId,
      activeUserRemoteId: activeUserRemoteId,
      requireEmail: requireEmail,
    );
  }

  @override
  Future<void> deletePetugas(Petugas target, {String? currentUserRemoteId}) {
    return _repository.deletePetugas(
      target,
      currentUserRemoteId: currentUserRemoteId,
    );
  }
}

/// Adaptor fallback read-only dari [DashboardViewModel] saat repository tidak disuntikkan.
class ReadOnlyDashboardBridgeDataSource implements MasterCrudDataSource {
  ReadOnlyDashboardBridgeDataSource(this._dashboardViewModel);

  final DashboardViewModel _dashboardViewModel;

  @override
  Stream<void> get onDataChanged => const Stream<void>.empty();

  @override
  Future<List<Barang>> getAllBarang() async => _dashboardViewModel.allBarang;

  @override
  Future<List<Supplier>> getAllSupplier() async =>
      _dashboardViewModel.allSuppliers;

  @override
  Future<List<Customer>> getAllCustomer() async =>
      _dashboardViewModel.allCustomers;

  @override
  Future<List<Petugas>> getAllPetugas() async => _dashboardViewModel.allPetugas;

  Never _readOnlyError() => throw const MasterDataValidationException(
    'Penyimpanan lokal belum diinisialisasi.',
  );

  @override
  Future<void> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) async => _readOnlyError();

  @override
  Future<void> updateBarangHargaBatch(Map<int, double> hargaById) async =>
      _readOnlyError();

  @override
  Future<void> deleteBarang(int idBarang) async => _readOnlyError();

  @override
  Future<void> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) async => _readOnlyError();

  @override
  Future<void> deleteSupplier(int idSupplier) async => _readOnlyError();

  @override
  Future<void> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) async => _readOnlyError();

  @override
  Future<void> deleteCustomer(int idCustomer) async => _readOnlyError();

  @override
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
  }) async => _readOnlyError();

  @override
  Future<void> deletePetugas(
    Petugas target, {
    String? currentUserRemoteId,
  }) async => _readOnlyError();
}

/// ViewModel untuk mengelola operasi CRUD 4 tabel master + Atur Harga Jual (RBAC).
class MasterCrudViewModel extends ChangeNotifier {
  MasterCrudViewModel({
    required this._session,
    required this._dataSource,
  }) {
    _dataSub = _dataSource.onDataChanged.listen((_) {
      if (!_isSaving) {
        loadData(silent: true);
      }
    });
  }

  factory MasterCrudViewModel.fromRepository({
    required AuthSession session,
    required InventoryRepository repository,
  }) {
    return MasterCrudViewModel(
      session: session,
      dataSource: RepositoryMasterCrudDataSource(repository),
    );
  }

  AuthSession _session;
  final MasterCrudDataSource _dataSource;

  StreamSubscription<void>? _dataSub;
  bool _disposed = false;
  int _loadEpoch = 0;

  MasterCategory _activeCategory = MasterCategory.barang;
  String _searchQuery = '';
  PriceFilterCategory _priceFilter = PriceFilterCategory.semua;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _accessDeniedMessage;

  List<Barang> _barang = const [];
  List<Supplier> _suppliers = const [];
  List<Customer> _customers = const [];
  List<Petugas> _petugas = const [];

  AuthSession get session => _session;
  bool get isOwner => _session.isOwner;
  MasterCategory get activeCategory => _activeCategory;
  String get searchQuery => _searchQuery;
  PriceFilterCategory get priceFilter => _priceFilter;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  String? get accessDeniedMessage => _accessDeniedMessage;

  List<MasterCategory> get categories =>
      allowedMasterCategories(_session.role);

  List<Barang> get allBarang => _barang;
  List<Supplier> get allSuppliers => _suppliers;
  List<Customer> get allCustomers => _customers;
  List<Petugas> get allPetugas => isOwner ? _petugas : const [];

  bool _matchesBarangQuery(Barang item, String q) {
    return item.namaBarang.toLowerCase().contains(q) ||
        item.satuan.toLowerCase().contains(q) ||
        formatRupiah(item.hargaSatuan).toLowerCase().contains(q);
  }

  List<Barang> get filteredBarang {
    if (_searchQuery.isEmpty) return _barang;
    final q = _searchQuery.toLowerCase();
    return _barang
        .where((item) => _matchesBarangQuery(item, q))
        .toList(growable: false);
  }

  List<Barang> get filteredBarangForPrice {
    final q = _searchQuery.toLowerCase();
    return _barang.where((item) {
      final isEgg = item.namaBarang.toLowerCase().contains('telur');
      switch (_priceFilter) {
        case PriceFilterCategory.semua:
          break;
        case PriceFilterCategory.telur:
          if (!isEgg) return false;
        case PriceFilterCategory.sembako:
          if (isEgg) return false;
      }
      if (q.isEmpty) return true;
      return _matchesBarangQuery(item, q);
    }).toList(growable: false);
  }

  List<Supplier> get filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliers;
    final q = _searchQuery.toLowerCase();
    return _suppliers.where((item) {
      return item.namaSupplier.toLowerCase().contains(q) ||
          item.noTelpSupplier.toLowerCase().contains(q) ||
          item.alamatSupplier.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<Customer> get filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final q = _searchQuery.toLowerCase();
    return _customers.where((item) {
      return item.namaCustomer.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  List<Petugas> get filteredPetugas {
    if (!isOwner) return const [];
    if (_searchQuery.isEmpty) return _petugas;
    final q = _searchQuery.toLowerCase();
    return _petugas.where((item) {
      return item.namaPetugas.toLowerCase().contains(q) ||
          item.email.toLowerCase().contains(q) ||
          item.role.label.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> loadData({bool silent = false}) async {
    if (_disposed) return;
    final epoch = ++_loadEpoch;
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      _notify();
    }
    try {
      final results = await Future.wait<dynamic>([
        _dataSource.getAllBarang(),
        _dataSource.getAllSupplier(),
        _dataSource.getAllCustomer(),
        isOwner
            ? _dataSource.getAllPetugas()
            : Future<List<Petugas>>.value(const []),
      ]);
      if (_disposed || epoch != _loadEpoch) return;

      _barang = List<Barang>.unmodifiable(results[0] as List<Barang>);
      _suppliers = List<Supplier>.unmodifiable(results[1] as List<Supplier>);
      _customers = List<Customer>.unmodifiable(results[2] as List<Customer>);
      _petugas = List<Petugas>.unmodifiable(results[3] as List<Petugas>);
      _errorMessage = null;
    } catch (_) {
      if (_disposed || epoch != _loadEpoch) return;
      _errorMessage = 'Gagal memuat data master dari database lokal.';
    } finally {
      if (!_disposed && epoch == _loadEpoch) {
        _isLoading = false;
        _notify();
      }
    }
  }

  void updateSession(AuthSession nextSession) {
    if (_disposed) return;
    if (_session.role == nextSession.role &&
        _session.petugasRemoteId == nextSession.petugasRemoteId &&
        _session.uid == nextSession.uid &&
        _session.email == nextSession.email &&
        _session.accountId == nextSession.accountId &&
        _session.displayName == nextSession.displayName) {
      return;
    }
    final roleChanged = _session.role != nextSession.role;
    _session = nextSession;
    _accessDeniedMessage = null;
    _errorMessage = null;
    if (!categories.contains(_activeCategory)) {
      _activeCategory = MasterCategory.barang;
    }
    if (!isOwner) {
      _petugas = const [];
    }
    _notify();
    if (roleChanged) {
      loadData(silent: true);
    }
  }

  void selectCategory(MasterCategory category) {
    if (!categories.contains(category)) {
      _accessDeniedMessage =
          'Akses ditolak: hanya Owner yang dapat mengelola akun Petugas.';
      _notify();
      return;
    }
    if (_activeCategory == category && _accessDeniedMessage == null) return;
    _activeCategory = category;
    _accessDeniedMessage = null;
    _errorMessage = null;
    _notify();
  }

  void setSearchQuery(String raw) {
    final sanitized = sanitizeSearchQuery(raw);
    if (sanitized == _searchQuery) return;
    _searchQuery = sanitized;
    _notify();
  }

  void clearSearch() {
    if (_searchQuery.isEmpty) return;
    _searchQuery = '';
    _notify();
  }

  void setPriceFilter(PriceFilterCategory filter) {
    if (_priceFilter == filter) return;
    _priceFilter = filter;
    _notify();
  }

  void clearMessages() {
    if (_errorMessage == null && _accessDeniedMessage == null) return;
    _errorMessage = null;
    _accessDeniedMessage = null;
    _notify();
  }

  Future<bool> saveBarang({
    int? idBarang,
    String? existingRemoteId,
    required String namaBarang,
    required int stokBarang,
    required String satuan,
    required double hargaSatuan,
  }) {
    return _runMutation(
      () => _dataSource.saveBarang(
        idBarang: idBarang,
        existingRemoteId: existingRemoteId,
        namaBarang: namaBarang,
        stokBarang: stokBarang,
        satuan: satuan,
        hargaSatuan: hargaSatuan,
      ),
    );
  }

  Future<bool> deleteBarang(Barang target) {
    final id = target.idBarang;
    if (id == null) {
      _errorMessage = 'Barang belum tersimpan di database lokal.';
      _notify();
      return Future.value(false);
    }
    return _runMutation(() => _dataSource.deleteBarang(id));
  }

  Future<bool> saveHargaBatch(Map<int, double> hargaById) {
    if (!isOwner) {
      _accessDeniedMessage =
          'Akses ditolak: hanya Owner yang dapat mengatur harga jual.';
      _errorMessage = _accessDeniedMessage;
      _notify();
      return Future.value(false);
    }
    return _runMutation(() => _dataSource.updateBarangHargaBatch(hargaById));
  }

  Future<bool> saveSupplier({
    int? idSupplier,
    String? existingRemoteId,
    required String namaSupplier,
    required String alamatSupplier,
    required String noTelpSupplier,
  }) {
    return _runMutation(
      () => _dataSource.saveSupplier(
        idSupplier: idSupplier,
        existingRemoteId: existingRemoteId,
        namaSupplier: namaSupplier,
        alamatSupplier: alamatSupplier,
        noTelpSupplier: noTelpSupplier,
      ),
    );
  }

  Future<bool> deleteSupplier(Supplier target) {
    final id = target.idSupplier;
    if (id == null) {
      _errorMessage = 'Supplier belum tersimpan di database lokal.';
      _notify();
      return Future.value(false);
    }
    return _runMutation(() => _dataSource.deleteSupplier(id));
  }

  Future<bool> saveCustomer({
    int? idCustomer,
    String? existingRemoteId,
    required String namaCustomer,
  }) {
    return _runMutation(
      () => _dataSource.saveCustomer(
        idCustomer: idCustomer,
        existingRemoteId: existingRemoteId,
        namaCustomer: namaCustomer,
      ),
    );
  }

  Future<bool> deleteCustomer(Customer target) {
    final id = target.idCustomer;
    if (id == null) {
      _errorMessage = 'Pelanggan belum tersimpan di database lokal.';
      _notify();
      return Future.value(false);
    }
    return _runMutation(() => _dataSource.deleteCustomer(id));
  }

  Future<bool> savePetugas({
    int? idPetugas,
    String? existingRemoteId,
    required String namaPetugas,
    required UserRole role,
    String pin = '1234',
    String email = '',
    String accountId = '',
    bool requireEmail = false,
  }) {
    if (!isOwner) {
      _accessDeniedMessage =
          'Akses ditolak: hanya Owner yang dapat mengelola akun Petugas.';
      _errorMessage = _accessDeniedMessage;
      _notify();
      return Future.value(false);
    }
    return _runMutation(
      () => _dataSource.savePetugas(
        idPetugas: idPetugas,
        existingRemoteId: existingRemoteId,
        namaPetugas: namaPetugas,
        role: role,
        pin: pin,
        email: email,
        accountId: accountId,
        activeUserRemoteId: _session.petugasRemoteId,
        requireEmail: requireEmail,
      ),
    );
  }

  Future<bool> deletePetugas(Petugas target) {
    if (!isOwner) {
      _accessDeniedMessage =
          'Akses ditolak: hanya Owner yang dapat menghapus akun Petugas.';
      _errorMessage = _accessDeniedMessage;
      _notify();
      return Future.value(false);
    }
    return _runMutation(
      () => _dataSource.deletePetugas(
        target,
        currentUserRemoteId: _session.petugasRemoteId,
      ),
    );
  }

  Future<bool> _runMutation(Future<void> Function() action) async {
    if (_disposed || _isSaving) return false;
    _isSaving = true;
    _errorMessage = null;
    _accessDeniedMessage = null;
    _notify();

    try {
      await action();
      if (_disposed) return false;
      await loadData(silent: true);
      return true;
    } on MasterDataValidationException catch (e) {
      if (_disposed) return false;
      _errorMessage = e.message;
      return false;
    } catch (_) {
      if (_disposed) return false;
      _errorMessage = 'Terjadi kesalahan saat memproses data master.';
      return false;
    } finally {
      if (!_disposed) {
        _isSaving = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _dataSub?.cancel();
    super.dispose();
  }
}
