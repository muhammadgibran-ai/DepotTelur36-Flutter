import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/dashboard_view_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeSyncNotifier extends ChangeNotifier {
  SyncState state = const SyncState(isOnline: true);

  void emitState(SyncState next) {
    state = next;
    notifyListeners();
  }
}

class _FakeDashboardDataSource implements DashboardDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final _FakeSyncNotifier syncNotifier = _FakeSyncNotifier();

  List<Barang> barang = [];
  List<Supplier> suppliers = [];
  List<Customer> customers = [];
  List<Petugas> petugas = [];
  List<Faktur> fakturs = [];
  List<Nota> notas = [];

  Object? loadError;
  Object? syncError;
  bool clearPendingOnSync = true;
  int syncCalls = 0;
  int getPetugasCalls = 0;
  Future<List<Barang>> Function()? onGetAllBarang;
  Future<void> Function()? onSyncNow;

  void emitDataChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  Future<void> dispose() async {
    await _changes.close();
    syncNotifier.dispose();
  }

  @override
  Future<List<Barang>> getAllBarang() async {
    if (loadError != null) throw loadError!;
    if (onGetAllBarang != null) return onGetAllBarang!();
    return barang;
  }

  @override
  Future<List<Supplier>> getAllSupplier() async {
    if (loadError != null) throw loadError!;
    return suppliers;
  }

  @override
  Future<List<Customer>> getAllCustomer() async {
    if (loadError != null) throw loadError!;
    return customers;
  }

  @override
  Future<List<Petugas>> getAllPetugas() async {
    getPetugasCalls++;
    if (loadError != null) throw loadError!;
    return petugas;
  }

  @override
  Future<List<Faktur>> getAllFaktur() async {
    if (loadError != null) throw loadError!;
    return fakturs;
  }

  @override
  Future<List<Nota>> getAllNota() async {
    if (loadError != null) throw loadError!;
    return notas;
  }

  @override
  Stream<void> get onDataChanged => _changes.stream;

  @override
  SyncState get syncState => syncNotifier.state;

  @override
  Listenable? get syncListenable => syncNotifier;

  @override
  Future<void> syncNow() async {
    syncCalls++;
    if (onSyncNow != null) {
      await onSyncNow!();
      return;
    }
    if (syncError != null) throw syncError!;
    if (clearPendingOnSync) {
      syncNotifier.emitState(
        syncNotifier.state.copyWith(
          isOnline: true,
          isSyncing: false,
          pendingCount: 0,
          clearError: true,
        ),
      );
    }
  }
}

class _SilentSyncService extends SyncService {
  _SilentSyncService({required super.dbHelper})
      : super(
          firestore: _DummyFirestore(),
          connectivity: _DummyConnectivity(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> trySyncIfOnline() async {}

  @override
  Future<void> syncNow() async {}
}

class _DummyFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DummyConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.none];
}

AuthSession _ownerSession() => AuthSession(
      uid: 'uid-owner',
      email: 'owner@depottelur36.com',
      accountId: 'owner01',
      displayName: 'Budi Owner',
      role: UserRole.owner,
      petugasRemoteId: 'seed-petugas-owner',
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

AuthSession _operatorSession() => AuthSession(
      uid: 'uid-kasir',
      email: 'kasir@depottelur36.com',
      accountId: 'kasir01',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: 'seed-petugas-kasir-1',
      provider: AuthProviderType.emailPassword,
      signedInAt: DateTime(2026, 2, 16),
    );

List<Barang> _sampleBarang() => [
      Barang(
        idBarang: 1,
        namaBarang: 'Telur Ayam Negeri',
        stokBarang: 120,
        satuan: 'Kg',
        hargaSatuan: 28500,
        remoteId: 'seed-barang-telur-negeri-kg',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      ),
      Barang(
        idBarang: 2,
        namaBarang: 'Telur Ayam Negeri (1 Tray / 30 Btr)',
        stokBarang: 25,
        satuan: 'Tray',
        hargaSatuan: 52000,
        remoteId: 'seed-barang-telur-negeri-tray',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      ),
      Barang(
        idBarang: 3,
        namaBarang: 'Beras Pandan Wangi 5 Kg',
        stokBarang: 18,
        satuan: 'Sak',
        hargaSatuan: 74000,
        remoteId: 'seed-barang-beras-5kg',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      ),
      Barang(
        idBarang: 4,
        namaBarang: 'Minyak Goreng Kemasan 1 Liter',
        stokBarang: 8,
        satuan: 'Pouch',
        hargaSatuan: 17500,
        remoteId: 'seed-barang-minyak-1l',
        syncStatus: SyncStatus.synced,
        updatedAt: DateTime(2026, 2, 16),
      ),
    ];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Fungsi 2 - Skenario Normal & RBAC', () {
    test('Owner mendapat tab Beranda/Omzet/Nota/Master dan shortcut Manajerial', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = _sampleBarang()
        ..suppliers = [
          Supplier(
            idSupplier: 1,
            namaSupplier: 'Peternakan Ayam Makmur Jaya',
            alamatSupplier: 'Jl. Raya Kandang No. 12',
            noTelpSupplier: '081234567890',
            remoteId: 'seed-supplier-1',
            syncStatus: SyncStatus.synced,
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..notas = [
          Nota(
            idNota: 1,
            tanggalNota: '2026-02-16',
            total: 114000,
            idPetugas: 1,
            idCustomer: 1,
            remoteId: 'nota-001',
            namaCustomer: 'Bu Sari',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..fakturs = [
          Faktur(
            idFaktur: 1,
            noFaktur: 'FKT-001',
            tanggalFaktur: '2026-02-16',
            total: 520000,
            idSupplier: 1,
            idPetugas: 1,
            remoteId: 'faktur-001',
            namaSupplier: 'Peternakan Ayam Makmur Jaya',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();

      expect(vm.isOwner, isTrue);
      expect(
        vm.tabs.map((t) => t.id),
        [
          DashboardTabId.beranda,
          DashboardTabId.omzet,
          DashboardTabId.nota,
          DashboardTabId.master,
        ],
      );
      expect(
        vm.shortcuts.map((s) => s.id),
        [
          DashboardShortcutId.aturHarga,
          DashboardShortcutId.riwayatFaktur,
          DashboardShortcutId.dataSupplier,
          DashboardShortcutId.akunPetugas,
        ],
      );
      expect(vm.metrics.totalBarang, 4);
      expect(vm.metrics.lowStockCount, 1);
      expect(vm.metrics.totalNotaOmzet, 114000);
      expect(vm.metrics.totalFakturBelanja, 520000);
      expect(vm.selectTab(DashboardTabId.omzet), isTrue);
      expect(vm.activeTab, DashboardTabId.omzet);
      expect(
        vm.activateShortcut(DashboardShortcutId.aturHarga)?.label,
        'Atur Harga',
      );
    });

    test('Operator mendapat tab Beranda/Kasir/Faktur/Stok & shortcut Operasional', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      final vm = DashboardViewModel(session: _operatorSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();

      expect(vm.isOwner, isFalse);
      expect(
        vm.tabs.map((t) => t.id),
        [
          DashboardTabId.beranda,
          DashboardTabId.kasir,
          DashboardTabId.faktur,
          DashboardTabId.stok,
        ],
      );
      expect(
        vm.shortcuts.map((s) => s.id),
        [
          DashboardShortcutId.riwayatNota,
          DashboardShortcutId.riwayatFaktur,
          DashboardShortcutId.pelanggan,
          DashboardShortcutId.supplier,
        ],
      );
      expect(vm.selectTab(DashboardTabId.kasir), isTrue);
      expect(vm.selectTab(DashboardTabId.faktur), isTrue);
      expect(vm.selectTab(DashboardTabId.stok), isTrue);
      expect(vm.activeTabIndex, 3);
    });

    test('Search & Quick Filter menyaring barang + kecocokan data lain akurat', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = _sampleBarang()
        ..suppliers = [
          Supplier(
            idSupplier: 1,
            namaSupplier: 'Peternakan Ayam Makmur Jaya',
            alamatSupplier: 'Pasar Induk',
            noTelpSupplier: '081234567890',
            remoteId: 'sup-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      vm.setQuickFilter(DashboardQuickFilter.stokMenipis);
      expect(vm.filteredBarang.map((b) => b.namaBarang), [
        'Minyak Goreng Kemasan 1 Liter',
      ]);

      vm.setQuickFilter(DashboardQuickFilter.telur);
      expect(vm.filteredBarang.length, 2);

      vm.setQuickFilter(DashboardQuickFilter.sembako);
      expect(vm.filteredBarang.map((b) => b.namaBarang), [
        'Beras Pandan Wangi 5 Kg',
        'Minyak Goreng Kemasan 1 Liter',
      ]);

      vm.setQuickFilter(DashboardQuickFilter.semua);
      vm.setSearchQuery('Makmur');
      expect(vm.filteredBarang, isEmpty);
      expect(vm.filteredSuppliers.length, 1);
      expect(vm.secondaryMatchCount, 1);

      vm.resetSearchAndFilter();
      expect(vm.hasActiveSearchOrFilter, isFalse);
      expect(vm.filteredBarang.length, 4);
    });

    test('Pusat Notifikasi membaca stok menipis/pantauan, mark read, dan sync manual', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      ds.syncNotifier.state = const SyncState(
        isOnline: false,
        pendingCount: 2,
      );

      final vm = DashboardViewModel(session: _operatorSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      // 1 offline pending + 1 low stock (Minyak 8) + 1 watch stock (Beras 18)
      expect(vm.notifications.length, 3);
      expect(vm.unreadCount, 3);
      expect(vm.unreadBadgeText, '3');

      final firstId = vm.notifications.first.id;
      vm.markNotificationRead(firstId);
      expect(vm.unreadCount, 2);

      vm.markAllNotificationsRead();
      expect(vm.unreadCount, 0);
      expect(vm.unreadBadgeText, isEmpty);

      await vm.triggerManualSync();
      expect(ds.syncCalls, 1);
      expect(vm.syncState.isOnline, isTrue);
      expect(vm.syncState.pendingCount, 0);
    });

    test('Integrasi Repository SQLite nyata memicu reload otomatis saat data berubah', () async {
      final tempDir = await Directory.systemTemp.createTemp('dt36_dash_test_');
      final dbPath = p.join(tempDir.path, 'dash_test.db');
      final dbHelper = DatabaseHelper.forTesting(customDbPath: dbPath);
      final syncService = _SilentSyncService(dbHelper: dbHelper);
      final repo = InventoryRepository(
        dbHelper: dbHelper,
        syncService: syncService,
      );

      addTearDown(() async {
        await repo.dispose();
        final db = await dbHelper.database;
        await db.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final vm = DashboardViewModel.fromRepository(
        session: _ownerSession(),
        repository: repo,
      );
      addTearDown(vm.dispose);

      await vm.loadDashboardData();
      expect(vm.metrics.totalBarang, 6);
      expect(vm.lowStockItems.single.namaBarang, 'Minyak Goreng Kemasan 1 Liter');

      await repo.saveBarang(
        namaBarang: 'Gula Pasir 1 Kg',
        stokBarang: 4,
        satuan: 'Kg',
        hargaSatuan: 16500,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vm.metrics.totalBarang, 7);
      expect(vm.lowStockItems.first.namaBarang, 'Gula Pasir 1 Kg');
    });

    test('Pencarian lintas entitas (Nota, Faktur, Customer, Harga), filter stokAman & secondaryMatchCount RBAC', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = [
          ..._sampleBarang(),
          Barang(
            idBarang: 5,
            namaBarang: 'Telur Puyuh Segar',
            stokBarang: 40,
            satuan: 'Pack',
            hargaSatuan: 22000,
            remoteId: 'brg-puyuh',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 6,
            namaBarang: 'Gula Pasir 1 Kg',
            stokBarang: 30,
            satuan: 'Kg',
            hargaSatuan: 17000,
            remoteId: 'brg-gula',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..suppliers = [
          Supplier(
            idSupplier: 1,
            namaSupplier: 'Peternakan Ayam Makmur Jaya',
            alamatSupplier: 'Pasar Induk',
            noTelpSupplier: '081234567890',
            remoteId: 'sup-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..customers = [
          Customer(
            idCustomer: 1,
            namaCustomer: 'Bu Sari Catering',
            remoteId: 'cust-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..notas = [
          Nota(
            idNota: 7,
            tanggalNota: '2026-02-16',
            total: 114000,
            idPetugas: 2,
            idCustomer: 1,
            remoteId: 'nota-007',
            namaCustomer: 'Bu Sari Catering',
            namaPetugas: 'Siti Kasir',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..fakturs = [
          Faktur(
            idFaktur: 9,
            noFaktur: 'FKT-2026-09',
            tanggalFaktur: '2026-02-16',
            total: 520000,
            idSupplier: 1,
            idPetugas: 1,
            remoteId: 'faktur-009',
            namaSupplier: 'Peternakan Ayam Makmur Jaya',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      // Default preview normal stock max 4 (saat tidak search/filter), padahal total normal 5
      expect(vm.normalStockItems.length, 5);
      expect(vm.previewNormalStockItems.length, 4);

      vm.setQuickFilter(DashboardQuickFilter.stokAman);
      expect(vm.filteredBarang.length, 5);
      expect(vm.filteredBarang.every((b) => b.stokBarang > kLowStockThreshold), isTrue);
      // Saat filter aktif, previewNormalStockItems menampilkan seluruh kecocokan
      expect(vm.previewNormalStockItems.length, 5);

      vm.setQuickFilter(DashboardQuickFilter.sembako);
      expect(
        vm.filteredBarang.map((b) => b.namaBarang),
        contains('Gula Pasir 1 Kg'),
      );

      vm.setQuickFilter(DashboardQuickFilter.semua);
      vm.setSearchQuery('FKT-2026-09');
      expect(vm.filteredFakturs.single.noFaktur, 'FKT-2026-09');
      expect(vm.secondaryMatchCount, 1);

      // Search harga & customer -> Owner menghitung Nota dalam secondaryMatchCount
      vm.setSearchQuery('Bu Sari');
      expect(vm.filteredCustomers.length, 1);
      expect(vm.filteredNotas.length, 1);
      expect(vm.secondaryMatchCount, 2);

      // Operator tidak menyertakan Nota pada secondaryMatchCount ringkas beranda
      vm.updateSession(_operatorSession());
      vm.setSearchQuery('Bu Sari');
      expect(vm.filteredCustomers.length, 1);
      expect(vm.secondaryMatchCount, 1);

      var notifyCount = 0;
      vm.addListener(() => notifyCount++);
      vm.setQuickFilter(DashboardQuickFilter.semua);
      vm.setSearchQuery('  Bu   Sari\t');
      expect(notifyCount, 0);

      // Ubah kapitalisasi memicu pembaruan query, namun tetap mencocokkan case-insensitive
      vm.setSearchQuery('bu sari');
      expect(vm.filteredCustomers.length, 1);
      expect(notifyCount, 1);

      vm.toggleFilterBar();
      expect(vm.isFilterBarExpanded, isTrue);
      expect(notifyCount, 2);
      vm.clearSearch();
      expect(vm.searchQuery, isEmpty);
    });

    test('Notifikasi memprioritaskan error sync di urutan teratas dan menampilkan antrean online pending', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      ds.syncNotifier.state = const SyncState(
        isOnline: true,
        pendingCount: 3,
        lastError: 'Firestore permission-denied',
      );

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      expect(vm.notifications.length, 4);
      expect(vm.notifications[0].severity, NotificationSeverity.critical);
      expect(vm.notifications[0].isSyncAlert, isTrue);
      expect(vm.notifications[0].id, startsWith('sync-error:'));
      expect(vm.notifications[1].isSyncAlert, isTrue);
      expect(vm.notifications[1].title, contains('3 Data Belum Tersinkron'));

      var notifyCount = 0;
      vm.addListener(() => notifyCount++);
      vm.markAllNotificationsRead();
      expect(notifyCount, 1);
      vm.markAllNotificationsRead();
      expect(notifyCount, 1);
    });
  });

  group('Fungsi 2 - Edge Case & Skenario Salah Input', () {
    test('Repository kosong tidak crash & menghasilkan 0 notifikasi', () async {
      final ds = _FakeDashboardDataSource();
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();
      expect(vm.allBarang, isEmpty);
      expect(vm.notifications, isEmpty);
      expect(vm.unreadCount, 0);
      expect(vm.previewLowStockItems, isEmpty);
      expect(vm.previewNormalStockItems, isEmpty);
    });

    test('Lebih dari 99 notifikasi memformat badge menjadi 99+', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = List.generate(
          105,
          (i) => Barang(
            idBarang: i + 1,
            namaBarang: 'Item Kritis $i',
            stokBarang: 1,
            satuan: 'Kg',
            hargaSatuan: 10000,
            remoteId: 'item-$i',
            updatedAt: DateTime(2026, 2, 16),
          ),
        );
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();
      expect(vm.unreadCount, 105);
      expect(vm.unreadBadgeText, '99+');
      // Pratinjau Beranda tetap ringkas (maks 2 kartu saat mode default)
      expect(vm.previewLowStockItems.length, 2);
    });

    test('Stok habis/negatif korup diurutkan lebih prioritas dan memicu notifikasi critical', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = [
          Barang(
            idBarang: 1,
            namaBarang: 'Barang Hampir Habis',
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 10000,
            remoteId: 'r-5',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 2,
            namaBarang: 'Barang Kosong Ekstrem',
            stokBarang: -2,
            satuan: 'Kg',
            hargaSatuan: double.nan,
            remoteId: 'r-0',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..notas = [
          Nota(
            tanggalNota: '2026-02-16',
            total: double.infinity,
            idPetugas: 1,
            idCustomer: 1,
            remoteId: 'n-nan',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();
      expect(vm.lowStockItems.first.namaBarang, 'Barang Kosong Ekstrem');
      expect(vm.notifications.first.severity, NotificationSeverity.critical);
      expect(vm.notifications.first.title, contains('Stok Habis'));
      expect(vm.metrics.totalNotaOmzet, 0);
      expect(formatRupiah(double.nan), 'Rp 0');
      expect(formatRupiah(-2500), '-Rp 2.500');
    });

    test('Sanitasi query mengabaikan control char, spasi berlebih, dan panjang > 80 karakter', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      final rawLong = '  \x00Telur\n\t   Ayam   ${'x' * 120}';
      vm.setSearchQuery(rawLong);
      expect(vm.searchQuery.length, lessThanOrEqualTo(kMaxSearchQueryLength));
      expect(vm.searchQuery.startsWith('Telur Ayam'), isTrue);
      expect(vm.searchQuery.contains('\n'), isFalse);
      expect(vm.searchQuery.contains('\x00'), isFalse);
    });

    test('RBAC: Operator ditolak mengakses tab/shortcut Owner dan indeks out-of-bounds ditolak aman', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      final vm = DashboardViewModel(session: _operatorSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();

      expect(vm.selectTab(DashboardTabId.omzet), isFalse);
      expect(vm.activeTab, DashboardTabId.beranda);
      expect(vm.accessDeniedMessage, contains('khusus untuk Owner'));

      expect(vm.selectTab(DashboardTabId.master), isFalse);
      expect(vm.selectTab(DashboardTabId.nota), isFalse);

      expect(vm.activateShortcut(DashboardShortcutId.aturHarga), isNull);
      expect(vm.activateShortcut(DashboardShortcutId.akunPetugas), isNull);

      expect(vm.selectTabIndex(-1), isFalse);
      expect(vm.selectTabIndex(99), isFalse);
      expect(vm.activeTab, DashboardTabId.beranda);

      // Update sesi dari Owner tab Omzet ke Operator harus reset ke Beranda
      vm.updateSession(_ownerSession());
      expect(vm.selectTab(DashboardTabId.omzet), isTrue);
      vm.updateSession(_operatorSession());
      expect(vm.activeTab, DashboardTabId.beranda);
    });

    test('Gagal load SQLite dan gagal sync tertangani terpisah tanpa menimpa status lokal', () async {
      final ds = _FakeDashboardDataSource()
        ..loadError = StateError('SQLite corrupt')
        ..syncError = Exception('Network timeout');
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });

      await vm.loadDashboardData();
      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, contains('Gagal memuat data lokal'));
      expect(vm.syncErrorMessage, isNull);

      ds.loadError = null;
      await vm.loadDashboardData();
      expect(vm.errorMessage, isNull);

      await vm.triggerManualSync();
      expect(vm.isManualSyncing, isFalse);
      expect(vm.syncErrorMessage, contains('Gagal menjalankan sinkronisasi manual'));
      expect(vm.errorMessage, isNull);

      ds.syncError = null;
      await vm.triggerManualSync();
      expect(vm.syncErrorMessage, isNull);
    });

    test('Boundary formatRupiah, ambang stok (0/10/11/20/21) & tie-breaker alfabetis', () async {
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(-0.0), 'Rp 0');
      expect(formatRupiah(28500), 'Rp 28.500');
      expect(formatRupiah(double.infinity), 'Rp 0');
      expect(formatRupiah(double.negativeInfinity), 'Rp 0');
      expect(formatRupiah(1e20), 'Rp 900.000.000.000.000+');
      expect(formatRupiah(-1e20), '-Rp 900.000.000.000.000+');

      final ds = _FakeDashboardDataSource()
        ..barang = [
          Barang(
            idBarang: 1,
            namaBarang: 'Zebra Tepung',
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 10000,
            remoteId: 'r-z',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 2,
            namaBarang: 'Ayam Telur Kampong',
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 30000,
            remoteId: 'r-a',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 3,
            namaBarang: 'Batas Kritis 10',
            stokBarang: kLowStockThreshold,
            satuan: 'Unit',
            hargaSatuan: 5000,
            remoteId: 'r-10',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 4,
            namaBarang: 'Batas Pantauan 11',
            stokBarang: 11,
            satuan: 'Unit',
            hargaSatuan: 5000,
            remoteId: 'r-11',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 5,
            namaBarang: 'Batas Pantauan 20',
            stokBarang: kWatchStockThreshold,
            satuan: 'Unit',
            hargaSatuan: 5000,
            remoteId: 'r-20',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 6,
            namaBarang: 'Stok Aman 21',
            stokBarang: 21,
            satuan: 'Unit',
            hargaSatuan: 5000,
            remoteId: 'r-21',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      expect(vm.lowStockItems.map((b) => b.namaBarang), [
        'Ayam Telur Kampong',
        'Zebra Tepung',
        'Batas Kritis 10',
      ]);
      expect(vm.normalStockItems.length, 3);
      // 21 tidak memicu notifikasi sama sekali
      expect(vm.notifications.length, 5);
      expect(
        vm.notifications.any((n) => n.barangNama == 'Stok Aman 21'),
        isFalse,
      );
    });

    test('Sanitasi query membersihkan zero-width Unicode dan string tersembunyi saja tidak memicu filter', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      vm.setSearchQuery('\u200B\uFEFF   \u200C\n\t');
      expect(vm.searchQuery, isEmpty);
      expect(vm.hasActiveSearchOrFilter, isFalse);

      vm.setSearchQuery('\u200BTelur\uFEFF \u200DAyam');
      expect(vm.searchQuery, 'Telur Ayam');
      expect(vm.filteredBarang.length, 2);
    });

    test('Regresi Bug #1: Pencarian pada double NaN, Infinity, dan 1e20 tidak melempar UnsupportedError', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = [
          Barang(
            idBarang: 1,
            namaBarang: 'Telur Omega Korup',
            stokBarang: 3,
            satuan: 'Tray',
            hargaSatuan: double.nan,
            remoteId: 'brg-nan',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            idBarang: 2,
            namaBarang: 'Beras Ekstrem',
            stokBarang: 12,
            satuan: 'Sak',
            hargaSatuan: 1e20,
            remoteId: 'brg-huge',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..notas = [
          Nota(
            idNota: 1,
            tanggalNota: '2026-02-16',
            total: double.infinity,
            idPetugas: 1,
            idCustomer: 1,
            remoteId: 'nota-inf',
            namaCustomer: 'Telur Customer',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..fakturs = [
          Faktur(
            idFaktur: 1,
            noFaktur: 'FKT-INF',
            tanggalFaktur: '2026-02-16',
            total: -double.infinity,
            idSupplier: 1,
            idPetugas: 1,
            remoteId: 'faktur-inf',
            namaSupplier: 'Telur Supplier',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      vm.setSearchQuery('Telur');
      expect(vm.filteredBarang.single.namaBarang, 'Telur Omega Korup');
      expect(vm.filteredNotas.length, 1);
      expect(vm.filteredFakturs.length, 1);
      expect(vm.secondaryMatchCount, 2);
    });

    test('Regresi Bug #2: Isolasi Sesi & Kebocoran PII Operator / Ganti Akun', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = _sampleBarang()
        ..petugas = [
          Petugas(
            idPetugas: 1,
            namaPetugas: 'Budi Owner',
            role: UserRole.owner,
            email: 'owner@depottelur36.com',
            accountId: 'owner01',
            remoteId: 'p-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..notas = [
          Nota(
            idNota: 1,
            tanggalNota: '2026-02-16',
            total: 250000,
            idPetugas: 1,
            idCustomer: 1,
            remoteId: 'n-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ]
        ..fakturs = [
          Faktur(
            idFaktur: 1,
            noFaktur: 'FKT-1',
            tanggalFaktur: '2026-02-16',
            total: 600000,
            idSupplier: 1,
            idPetugas: 1,
            remoteId: 'f-1',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _operatorSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      // Operator tidak boleh memanggil getAllPetugas maupun mengekspos PII & omzet total
      expect(ds.getPetugasCalls, 0);
      expect(vm.allPetugas, isEmpty);
      expect(vm.metrics.totalPetugas, 0);
      expect(vm.metrics.totalNotaOmzet, 0);
      expect(vm.metrics.totalFakturBelanja, 0);

      // Promosi Operator -> Owner memicu reload agar data Owner terisi
      vm.updateSession(_ownerSession());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ds.getPetugasCalls, 1);
      expect(vm.allPetugas.length, 1);
      expect(vm.metrics.totalPetugas, 1);
      expect(vm.metrics.totalNotaOmzet, 250000);
      expect(vm.metrics.totalFakturBelanja, 600000);

      // Tandai notifikasi, pasang filter, buka search -> lalu ganti ke Owner B
      vm.markAllNotificationsRead();
      expect(vm.unreadCount, 0);
      vm.setSearchQuery('Minyak');
      vm.setQuickFilter(DashboardQuickFilter.sembako);
      vm.toggleFilterBar();
      vm.selectTab(DashboardTabId.master);

      final ownerB = _ownerSession().copyWith(
        uid: 'uid-owner-b',
        displayName: 'Owner Kedua',
      );
      vm.updateSession(ownerB);

      expect(vm.activeTab, DashboardTabId.beranda);
      expect(vm.searchQuery, isEmpty);
      expect(vm.activeFilter, DashboardQuickFilter.semua);
      expect(vm.isFilterBarExpanded, isFalse);
      expect(vm.unreadCount, 2);

      // updateSession dengan data identik harus no-op
      var calls = 0;
      vm.addListener(() => calls++);
      vm.updateSession(ownerB);
      expect(calls, 0);
    });

    test('Regresi Bug #3: ID Notifikasi unik untuk item anonim & pruning read cache saat stok pulih', () async {
      final ds = _FakeDashboardDataSource()
        ..barang = [
          Barang(
            namaBarang: '',
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 10000,
            remoteId: '',
            updatedAt: DateTime(2026, 2, 16),
          ),
          Barang(
            namaBarang: '',
            stokBarang: 5,
            satuan: 'Kg',
            hargaSatuan: 10000,
            remoteId: '',
            updatedAt: DateTime(2026, 2, 16),
          ),
        ];

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      addTearDown(() async {
        vm.dispose();
        await ds.dispose();
      });
      await vm.loadDashboardData();

      expect(vm.notifications.length, 2);
      expect(vm.notifications.map((n) => n.id).toSet().length, 2);
      vm.markNotificationRead(vm.notifications.first.id);
      expect(vm.unreadCount, 1);

      // Uji pruning _readNotificationIds: Minyak stok 8 -> dibaca -> restock 25 -> turun ke 8 lagi
      ds.barang = [
        Barang(
          idBarang: 4,
          namaBarang: 'Minyak Goreng 1L',
          stokBarang: 8,
          satuan: 'Pouch',
          hargaSatuan: 17500,
          remoteId: 'seed-minyak',
          updatedAt: DateTime(2026, 2, 16),
        ),
      ];
      await vm.loadDashboardData();
      expect(vm.unreadCount, 1);
      vm.markNotificationRead(vm.notifications.single.id);
      expect(vm.unreadCount, 0);

      // Pulih ke stok sehat > 20 -> cache ID lama harus dipruning
      ds.barang = [ds.barang.single.copyWith(stokBarang: 25)];
      await vm.loadDashboardData();
      expect(vm.notifications, isEmpty);

      // Turun lagi ke stok 8 -> harus muncul sebagai belum dibaca
      ds.barang = [ds.barang.single.copyWith(stokBarang: 8)];
      await vm.loadDashboardData();
      expect(vm.unreadCount, 1);
      expect(vm.notifications.single.isRead, isFalse);
    });

    test('Race condition concurrent loadDashboardData & re-entrancy/dispose/invalid ID guards', () async {
      final ds = _FakeDashboardDataSource()..barang = _sampleBarang();
      final slowLoad = Completer<List<Barang>>();
      var loadInvocation = 0;

      ds.onGetAllBarang = () async {
        loadInvocation++;
        if (loadInvocation == 1) {
          return slowLoad.future;
        }
        return [
          Barang(
            idBarang: 99,
            namaBarang: 'Telur Segar Terbaru',
            stokBarang: 30,
            satuan: 'Kg',
            hargaSatuan: 29000,
            remoteId: 'new-item',
            updatedAt: DateTime(2026, 2, 17),
          ),
        ];
      };

      final vm = DashboardViewModel(session: _ownerSession(), dataSource: ds);
      final slowFuture = vm.loadDashboardData();
      final fastFuture = vm.loadDashboardData();

      await fastFuture;
      expect(vm.allBarang.single.namaBarang, 'Telur Segar Terbaru');

      // Resolve request lama dengan data usang -> tidak boleh menimpa state baru
      slowLoad.complete(_sampleBarang());
      await slowFuture;
      expect(vm.allBarang.single.namaBarang, 'Telur Segar Terbaru');

      // Salah input markNotificationRead ID kosong / palsu
      var notifies = 0;
      vm.addListener(() => notifies++);
      vm.markNotificationRead('');
      vm.markNotificationRead('   ');
      vm.markNotificationRead('id-tidak-dikenal');
      expect(notifies, 0);

      // Re-entrancy guard pada triggerManualSync
      final syncGate = Completer<void>();
      ds.onSyncNow = () => syncGate.future;
      final s1 = vm.triggerManualSync();
      final s2 = vm.triggerManualSync();
      expect(ds.syncCalls, 1);
      syncGate.complete();
      await Future.wait([s1, s2]);

      // Dispose harus memblokir event listener & reload selanjutnya tanpa crash
      vm.dispose();
      ds.emitDataChanged();
      ds.syncNotifier.emitState(const SyncState(isOnline: false, pendingCount: 5));
      await vm.loadDashboardData();
      await vm.triggerManualSync();
      await ds.dispose();
    });
  });
}
