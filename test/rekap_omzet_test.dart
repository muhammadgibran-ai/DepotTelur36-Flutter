import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/report_export_service.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/rekap_omzet_view_model.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SilentSyncService extends SyncService {
  _SilentSyncService({required super.dbHelper})
      : super(
          firestore: _NoopFirestore(),
          connectivity: _OfflineConnectivity(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> trySyncIfOnline() async {}

  @override
  Future<void> syncNow() async {}
}

class _NoopFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OfflineConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.none];
}

class _FakeRekapDataSource implements TransactionCrudDataSource {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Barang> barang = [];
  List<Supplier> suppliers = [];
  List<Customer> customers = [];
  List<Petugas> petugas = [];
  List<Faktur> fakturs = [];
  List<Nota> notas = [];

  int getAllNotaCalls = 0;
  Future<List<Barang>> Function()? onGetAllBarang;

  void emitChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  @override
  Stream<void> get onDataChanged => _changes.stream;

  @override
  Future<List<Barang>> getAllBarang() async =>
      onGetAllBarang != null ? onGetAllBarang!() : barang;

  @override
  Future<List<Supplier>> getAllSupplier() async => suppliers;

  @override
  Future<List<Customer>> getAllCustomer() async => customers;

  @override
  Future<List<Petugas>> getAllPetugas() async => petugas;

  @override
  Future<List<Faktur>> getAllFaktur() async => fakturs;

  @override
  Future<List<Nota>> getAllNota() async {
    getAllNotaCalls++;
    return notas;
  }

  @override
  Future<Faktur?> getFakturById(int idFaktur) async => null;

  @override
  Future<Nota?> getNotaById(int idNota) async => null;

  @override
  Future<String> generateNextNoFaktur({DateTime? date}) async => 'FKT-1';

  @override
  Future<int> createFaktur({
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async =>
      1;

  @override
  Future<void> updateFaktur({
    required Faktur existing,
    required String noFaktur,
    required String tanggalFaktur,
    required Supplier supplier,
    required Petugas petugas,
    required List<({Barang barang, int quantity})> items,
  }) async {}

  @override
  Future<void> deleteFaktur(int idFaktur) async {}

  @override
  Future<int> createNota({
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async =>
      1;

  @override
  Future<void> updateNota({
    required Nota existing,
    required String tanggalNota,
    required Customer customer,
    required Petugas petugas,
    required List<({Barang barang, int banyaknya})> items,
  }) async {}

  @override
  Future<void> deleteNota(int idNota) async {}
}

class _SlowReportExportService extends ReportExportService {
  _SlowReportExportService(this._gate);

  final Completer<void> _gate;
  int saveCalls = 0;

  @override
  Future<ExportedReportResult> saveReportToFile(
    OmzetSummaryReport report, {
    required OmzetExportFormat format,
    required String ownerName,
    Directory? targetDirectory,
  }) async {
    saveCalls++;
    await _gate.future;
    return super.saveReportToFile(
      report,
      format: format,
      ownerName: ownerName,
      targetDirectory: targetDirectory,
    );
  }
}

final _baseTime = DateTime(2026, 11, 16, 10, 30);

AuthSession _ownerSession({String name = 'Budi Owner'}) => AuthSession(
      uid: 'owner-uid',
      email: 'owner@depottelur36.com',
      accountId: 'owner_1',
      displayName: name,
      role: UserRole.owner,
      petugasRemoteId: 'pet-owner',
      provider: AuthProviderType.emailPassword,
      signedInAt: _baseTime,
    );

AuthSession _operatorSession() => AuthSession(
      uid: 'op-uid',
      email: 'kasir@depottelur36.com',
      accountId: 'op_1',
      displayName: 'Siti Kasir',
      role: UserRole.petugas,
      petugasRemoteId: 'pet-kasir',
      provider: AuthProviderType.emailPassword,
      signedInAt: _baseTime,
    );

Future<({
  Directory tempDir,
  DatabaseHelper dbHelper,
  InventoryRepository repo,
})> _openIsolatedRepo() async {
  final tempDir = Directory.systemTemp.createTempSync('dt36_rekap_test_');
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final dbHelper = DatabaseHelper.forTesting(
    customDbPath: p.join(tempDir.path, 'rekap_test.db'),
  );
  addTearDown(dbHelper.close);
  final repo = InventoryRepository(
    dbHelper: dbHelper,
    syncService: _SilentSyncService(dbHelper: dbHelper),
  );
  addTearDown(repo.dispose);
  await repo.initialize();
  return (tempDir: tempDir, dbHelper: dbHelper, repo: repo);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Model & Formatter Rekap Omzet (Normal, Edge Case & Salah Input)', () {
    test('formatCompactOmzetLabel memformat ribuan, jutaan, miliaran & batas pembulatan dengan benar', () {
      expect(formatCompactOmzetLabel(0), '0');
      expect(formatCompactOmzetLabel(750), '750');
      expect(formatCompactOmzetLabel(1000), '1rb');
      expect(formatCompactOmzetLabel(268500), '269rb');
      expect(formatCompactOmzetLabel(999600), '1jt');
      expect(formatCompactOmzetLabel(1500000), '1,5jt');
      expect(formatCompactOmzetLabel(12000000), '12jt');
      expect(formatCompactOmzetLabel(999500000), '1M');
      expect(formatCompactOmzetLabel(1250000000), '1,3M');
      expect(formatCompactOmzetLabel(999960000000), '999M+');

      // Kasus salah input: negatif, NaN, Infinity
      expect(formatCompactOmzetLabel(-50000), '0');
      expect(formatCompactOmzetLabel(double.nan), '0');
      expect(formatCompactOmzetLabel(double.infinity), '0');
      expect(formatCompactOmzetLabel(double.negativeInfinity), '0');
    });

    test('OmzetSummaryReport & ProductSalesContribution menghitung arusKasBersih dan averagePricePerUnit aman', () {
      final empty = OmzetSummaryReport.empty(
        period: RekapOmzetPeriod.hariIni,
        now: _baseTime,
      );
      expect(empty.arusKasBersih, 0);
      expect(empty.topProducts, isEmpty);
      expect(empty.weeklyTrend, isEmpty);

      const zeroQtyProduct = ProductSalesContribution(
        productKey: 'p0',
        namaBarang: 'Produk Kosong',
        satuan: 'Kg',
        totalQty: 0,
        notaCount: 0,
        totalRevenue: 50000,
        shareRatio: 0,
      );
      expect(zeroQtyProduct.averagePricePerUnit, 0.0);

      const normalProduct = ProductSalesContribution(
        productKey: 'p1',
        namaBarang: 'Telur Ayam Negeri',
        satuan: 'Kg',
        totalQty: 4,
        notaCount: 2,
        totalRevenue: 114000,
        shareRatio: 0.5,
      );
      expect(normalProduct.averagePricePerUnit, 28500);
    });
  });

  group('ReportExportService Ekspor CSV & Ringkasan Teks (Normal, Edge Case & Keamanan Input)', () {
    const service = ReportExportService();

    OmzetSummaryReport buildSampleReport({
      double totalNota = 285000,
      double belanjaFaktur = 150000,
      String customerName = 'Toko Berkah, Jaya "Utama"',
      String productName = 'Telur Ayam Negeri',
      String supplierName = 'CV Ternak Makmur',
      List<ProductSalesContribution>? topProducts,
    }) {
      return OmzetSummaryReport(
        period: RekapOmzetPeriod.tujuhHari,
        periodRangeLabel: '10–16 Nov',
        weeklyRangeLabel: '10–16 Nov',
        totalPenjualanNota: totalNota,
        notaCount: 1,
        belanjaFaktur: belanjaFaktur,
        fakturCount: 1,
        unitTerjual: 10,
        jenisProdukTerjual: topProducts?.length ?? 1,
        weeklyTrend: const [
          DailyOmzetBarPoint(
            isoDate: '2026-11-16',
            dayShort: 'Min',
            dateLabel: '16 Nov',
            totalOmzet: 285000,
            notaCount: 1,
            unitCount: 10,
            isToday: true,
          ),
        ],
        topProducts: topProducts ??
            [
              ProductSalesContribution(
                productKey: 'id_1',
                idBarang: 1,
                namaBarang: productName,
                satuan: 'Kg',
                totalQty: 10,
                notaCount: 1,
                totalRevenue: 285000,
                shareRatio: 1.0,
              ),
            ],
        filteredNotas: [
          Nota(
            idNota: 7,
            tanggalNota: '2026-11-16',
            total: totalNota,
            idPetugas: 1,
            idCustomer: 1,
            remoteId: 'nota-7',
            updatedAt: _baseTime,
            namaCustomer: customerName,
            namaPetugas: 'Budi Kasir',
            details: [
              DetailNota(
                idNota: 7,
                idBarang: 1,
                jumlah: 285000,
                banyaknya: 10,
                namaBarang: productName,
                satuan: 'Kg',
              ),
            ],
          ),
        ],
        filteredFakturs: [
          Faktur(
            idFaktur: 3,
            noFaktur: 'FKT-20261116-001',
            tanggalFaktur: '2026-11-16',
            total: belanjaFaktur,
            idSupplier: 1,
            idPetugas: 1,
            remoteId: 'fkt-3',
            updatedAt: _baseTime,
            namaSupplier: supplierName,
            namaPetugas: 'Budi Owner',
            details: const [
              DetailFaktur(
                idFaktur: 3,
                idBarang: 1,
                jumlah: 150000,
                quantity: 5,
                namaBarang: 'Telur Ayam Negeri',
                satuan: 'Kg',
              ),
            ],
          ),
        ],
        generatedAt: DateTime(2026, 11, 16, 10, 35, 12, 45),
      );
    }

    test('buildCsvContent dan buildTextSummaryContent menyusun laporan lengkap & RFC-4180', () {
      final report = buildSampleReport();
      final csv = service.buildCsvContent(report, ownerName: 'Pak Hendra');
      expect(csv, contains('LAPORAN REKAP OMZET DEPOTELUR36'));
      expect(csv, contains('Periode,7 Hari'));
      expect(csv, contains('Dicetak Oleh,Pak Hendra'));
      expect(csv, contains('Total Penjualan Nota,285000'));
      expect(csv, contains('TREN PEMASUKAN 7 HARI TERAKHIR (10–16 Nov)'));
      expect(csv, contains('2026-11-16,Min,285000,1,10'));
      expect(csv, contains('1,Telur Ayam Negeri,Kg,10,1,285000,100.0'));
      // Koma dan tanda kutip ganda ter-escape sesuai RFC-4180
      expect(csv, contains('"Toko Berkah, Jaya ""Utama"""'));
      expect(csv, contains('FKT-20261116-001,2026-11-16,CV Ternak Makmur'));

      final text = service.buildTextSummaryContent(
        report,
        ownerName: 'Pak Hendra',
      );
      expect(text, contains('=== REKAP OMZET DEPOTELUR36 ==='));
      expect(text, contains('Total Penjualan Nota : Rp 285.000 (1 Nota)'));
      expect(text, contains('Belanja Faktur Masuk : Rp 150.000 (1 Faktur)'));
      expect(text, contains('1. Telur Ayam Negeri: 10 Kg · 1 Nota · Rp 285.000 (100.0%)'));
    });

    test('saveReportToFile membuat direktori otomatis dan mencegah timpa file saat ekspor di milidetik sama', () async {
      final parent = Directory.systemTemp.createTempSync('dt36_export_svc_');
      addTearDown(() {
        if (parent.existsSync()) parent.deleteSync(recursive: true);
      });
      final nestedDir = Directory(p.join(parent.path, 'nested', 'reports'));
      final report = buildSampleReport();

      final first = await service.saveReportToFile(
        report,
        format: OmzetExportFormat.csv,
        ownerName: 'Owner',
        targetDirectory: nestedDir,
      );
      final second = await service.saveReportToFile(
        report,
        format: OmzetExportFormat.csv,
        ownerName: 'Owner',
        targetDirectory: nestedDir,
      );

      expect(first.filePath, isNotNull);
      expect(second.filePath, isNotNull);
      expect(first.filePath, isNot(second.filePath));
      expect(second.fileName, endsWith('_1.csv'));
      expect(await File(first.filePath!).readAsString(), first.content);
      expect(await File(second.filePath!).readAsString(), second.content);
    });

    test('Keamanan & salah input ekspor: blokir CSV formula injection (termasuk awalan Unicode tersembunyi), jaga angka negatif sah, sanitasi newline & NaN', () {
      final dangerousReport = buildSampleReport(
        totalNota: 100000,
        belanjaFaktur: 250000, // arusKasBersih = -150000 (angka negatif sah!)
        customerName: '\u200B=CMD|\' /C calc\'!A0',
        productName: '+SUM(1;2)\nBaris Palsu',
        supplierName: '@HYPERLINK("http://x")',
      );

      final csv = service.buildCsvContent(
        dangerousReport,
        ownerName: '   ',
      );
      expect(csv, contains('Dicetak Oleh,Owner DepotTelur36'));
      // Angka negatif murni TIDAK diawali kutip tunggal
      expect(csv, contains('Selisih Arus Kas,-150000'));
      // Payload berbahaya diawali ' meskipun sebelumnya diawali zero-width char
      expect(csv, contains("'=CMD|' /C calc'!A0"));
      expect(csv, contains("'+SUM(1;2) Baris Palsu"));
      expect(csv, contains("'@HYPERLINK("));

      final text = service.buildTextSummaryContent(
        dangerousReport,
        ownerName: 'Owner\nInjected',
      );
      expect(text, contains('Owner   : Owner Injected'));
      expect(text, contains('+SUM(1;2) Baris Palsu'));
      expect(text, isNot(contains('\nBaris Palsu')));

      // Angka NaN / Infinity tidak memicu crash toStringAsFixed
      final nanReport = OmzetSummaryReport(
        period: RekapOmzetPeriod.hariIni,
        periodRangeLabel: '16 Nov 2026',
        weeklyRangeLabel: '10–16 Nov',
        totalPenjualanNota: double.nan,
        notaCount: 0,
        belanjaFaktur: double.infinity,
        fakturCount: 0,
        unitTerjual: 0,
        jenisProdukTerjual: 0,
        weeklyTrend: const [],
        topProducts: const [],
        filteredNotas: const [],
        filteredFakturs: const [],
        generatedAt: _baseTime,
      );
      final safeCsv = service.buildCsvContent(nanReport, ownerName: 'Owner');
      expect(safeCsv, contains('Total Penjualan Nota,0'));
      expect(safeCsv, contains('Belanja Faktur,0'));
      expect(
        service.buildTextSummaryContent(nanReport, ownerName: 'Owner'),
        contains('Belum ada penjualan produk pada periode ini.'),
      );
    });
  });

  group('RekapOmzetViewModel Logika, RBAC, Edge Case & Integrasi SQLite', () {
    test('Agregasi Hari Ini vs 7 Hari vs Bulan Ini, tren 7 hari Sen–Min, & ranking produk bekerja akurat', () async {
      final fake = _FakeRekapDataSource();
      addTearDown(fake.dispose);

      final telur = Barang(
        idBarang: 1,
        namaBarang: 'Telur Ayam Negeri',
        stokBarang: 100,
        satuan: 'Kg',
        hargaSatuan: 28500,
        remoteId: 'brg-telur',
        updatedAt: _baseTime,
      );
      final puyuh = Barang(
        idBarang: 2,
        namaBarang: 'Telur Puyuh',
        stokBarang: 40,
        satuan: 'Pack',
        hargaSatuan: 15000,
        remoteId: 'brg-puyuh',
        updatedAt: _baseTime,
      );
      fake.barang = [telur, puyuh];

      // 16 Nov 2026 adalah Senin (`Sen`)
      fake.notas = [
        // Hari ini (16 Nov): 2 Kg Telur = 57.000
        Nota(
          idNota: 1,
          tanggalNota: '2026-11-16',
          total: 57000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n1',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 1, idBarang: 1, jumlah: 57000, banyaknya: 2),
          ],
        ),
        // 6 hari lalu inklusif (10 Nov): 3 Pack Puyuh = 45.000 + 1 Kg Telur = 28.500 (73.500)
        Nota(
          idNota: 2,
          tanggalNota: '2026-11-10',
          total: 73500,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n2',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 2, idBarang: 2, jumlah: 45000, banyaknya: 3),
            DetailNota(idNota: 2, idBarang: 1, jumlah: 28500, banyaknya: 1),
          ],
        ),
        // 7 hari lalu (9 Nov -> di luar 7 Hari, MASUK Bulan Ini): 4 Pack Puyuh = 60.000
        Nota(
          idNota: 3,
          tanggalNota: '2026-11-09',
          total: 60000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n3',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 3, idBarang: 2, jumlah: 60000, banyaknya: 4),
          ],
        ),
        // Bulan lalu (31 Okt -> di luar semua filter November)
        Nota(
          idNota: 4,
          tanggalNota: '2026-10-31',
          total: 999000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n4',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 4, idBarang: 1, jumlah: 999000, banyaknya: 30),
          ],
        ),
        // Tanggal masa depan (17 Nov -> di luar rangeEnd hari ini)
        Nota(
          idNota: 5,
          tanggalNota: '2026-11-17',
          total: 500000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n5',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 5, idBarang: 1, jumlah: 500000, banyaknya: 10),
          ],
        ),
      ];
      fake.fakturs = [
        Faktur(
          idFaktur: 1,
          noFaktur: 'FKT-1',
          tanggalFaktur: '2026-11-16',
          total: 100000,
          idSupplier: 1,
          idPetugas: 1,
          remoteId: 'f1',
          updatedAt: _baseTime,
        ),
        Faktur(
          idFaktur: 2,
          noFaktur: 'FKT-2',
          tanggalFaktur: '2026-11-03',
          total: 250000,
          idSupplier: 1,
          idPetugas: 1,
          remoteId: 'f2',
          updatedAt: _baseTime,
        ),
      ];

      final vm = RekapOmzetViewModel(
        session: _ownerSession(),
        dataSource: fake,
        nowProvider: () => _baseTime,
      );
      addTearDown(vm.dispose);
      await vm.loadData();

      // 1. Default periode: Hari Ini
      var r = vm.report;
      expect(r.period, RekapOmzetPeriod.hariIni);
      expect(r.totalPenjualanNota, 57000);
      expect(r.notaCount, 1);
      expect(r.belanjaFaktur, 100000);
      expect(r.fakturCount, 1);
      expect(r.unitTerjual, 2);
      expect(r.jenisProdukTerjual, 1);
      expect(r.arusKasBersih, -43000);

      // Tren 7 hari: tepat 7 titik dari 10 Nov (Sel) hingga 16 Nov (Sen)
      expect(r.weeklyTrend.length, 7);
      expect(r.weeklyRangeLabel, '10–16 Nov');
      expect(r.weeklyTrend.first.isoDate, '2026-11-10');
      expect(r.weeklyTrend.first.dayShort, 'Sel');
      expect(r.weeklyTrend.first.totalOmzet, 73500);
      expect(r.weeklyTrend.last.isoDate, '2026-11-16');
      expect(r.weeklyTrend.last.dayShort, 'Sen');
      expect(r.weeklyTrend.last.totalOmzet, 57000);

      vm.selectChartBar(0);
      expect(vm.selectedBarPoint?.isoDate, '2026-11-10');

      // 2. Pindah ke 7 Hari (10..16 Nov -> 57.000 + 73.500 = 130.500, Puyuh 45.000 vs Telur 85.500)
      vm.selectPeriod(RekapOmzetPeriod.tujuhHari);
      r = vm.report;
      expect(r.totalPenjualanNota, 130500);
      expect(r.notaCount, 2);
      expect(r.unitTerjual, 6);
      expect(r.jenisProdukTerjual, 2);
      expect(r.topProducts.first.namaBarang, 'Telur Ayam Negeri');
      expect(r.topProducts.first.totalRevenue, 85500);
      expect(r.topProducts.first.notaCount, 2);
      expect(r.topProducts.last.namaBarang, 'Telur Puyuh');
      expect(r.topProducts.last.totalRevenue, 45000);

      // 3. Pindah ke Bulan Ini (telur 85.500 vs puyuh 45.000 + 60.000 = 105.000 -> Puyuh jadi #1!)
      vm.selectPeriod(RekapOmzetPeriod.bulanIni);
      r = vm.report;
      expect(r.totalPenjualanNota, 190500);
      expect(r.notaCount, 3);
      expect(r.belanjaFaktur, 350000);
      expect(r.fakturCount, 2);
      expect(r.topProducts.first.namaBarang, 'Telur Puyuh');
      expect(r.topProducts.first.totalRevenue, 105000);
      expect(r.topProducts.first.notaCount, 2);
      expect(r.periodRangeLabel, 'November 2026');
    });

    test('Rentang 7 Hari lintas tahun (29 Des–4 Jan), penggabungan idBarang/barangRemoteId, dan toggleProductDetail aman', () async {
      final fake = _FakeRekapDataSource();
      addTearDown(fake.dispose);
      final crossYearNow = DateTime(2027, 1, 4, 15, 0);
      final telur = Barang(
        idBarang: 11,
        namaBarang: 'Telur Kampung',
        stokBarang: 30,
        satuan: 'Butir',
        hargaSatuan: 2500,
        remoteId: 'brg-kmp',
        updatedAt: crossYearNow,
      );
      fake.barang = [telur];
      // Nota 1 memakai idBarang=11; Nota 2 memakai idBarang=0 + barangRemoteId='brg-kmp';
      // Nota 3 memakai produk yang tidak ada di katalog lagi + nota.total = 0 sementara detail = 5000
      fake.notas = [
        Nota(
          idNota: 1,
          tanggalNota: '2026-12-30',
          total: 25000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'nc1',
          updatedAt: crossYearNow,
          details: const [
            DetailNota(idNota: 1, idBarang: 11, jumlah: 25000, banyaknya: 10),
          ],
        ),
        Nota(
          idNota: 2,
          tanggalNota: '2027-01-04',
          total: 0,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'nc2',
          updatedAt: crossYearNow,
          details: const [
            DetailNota(
              idNota: 2,
              idBarang: 0,
              barangRemoteId: 'brg-kmp',
              jumlah: 15000,
              banyaknya: 6,
            ),
            DetailNota(
              idNota: 2,
              idBarang: 999,
              namaBarang: 'Plastik Assoy',
              satuan: 'Pack',
              jumlah: 5000,
              banyaknya: 1,
            ),
          ],
        ),
      ];

      final vm = RekapOmzetViewModel(
        session: _ownerSession(),
        dataSource: fake,
        nowProvider: () => crossYearNow,
      );
      addTearDown(vm.dispose);
      await vm.loadData();

      vm.selectPeriod(RekapOmzetPeriod.tujuhHari);
      final r = vm.report;
      expect(r.weeklyRangeLabel, '29 Des–4 Jan');
      expect(r.topProducts.length, 2);
      // Kedua detail brg-kmp tergabung menjadi 1 produk (10 + 6 = 16 Butir, Rp 40.000)
      expect(r.topProducts.first.productKey, 'id_11');
      expect(r.topProducts.first.totalQty, 16);
      expect(r.topProducts.first.totalRevenue, 40000);
      expect(r.topProducts.first.notaCount, 2);

      // Produk tanpa katalog tetap aman memakai fallback nama & shareRatio dari totalDetailRevenue
      expect(r.topProducts.last.namaBarang, 'Plastik Assoy');
      expect(r.topProducts.last.shareRatio, closeTo(0.2, 0.01));

      vm.toggleProductDetail('id_11');
      expect(vm.expandedProductKey, 'id_11');
      vm.toggleProductDetail('id_11');
      expect(vm.expandedProductKey, isNull);
    });

    test('RBAC & Bug Regression: non-Owner ditolak total dan downgrade Owner -> Operator membersihkan cache ekspor & membatalkan load in-flight', () async {
      final exportDir = Directory.systemTemp.createTempSync('dt36_rbac_rekap_');
      addTearDown(() {
        if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
      });

      final fake = _FakeRekapDataSource();
      addTearDown(fake.dispose);
      fake.notas = [
        Nota(
          idNota: 1,
          tanggalNota: '2026-11-16',
          total: 85000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'n1',
          updatedAt: _baseTime,
          details: const [
            DetailNota(
              idNota: 1,
              idBarang: 1,
              namaBarang: 'Telur Rahasia',
              jumlah: 85000,
              banyaknya: 3,
            ),
          ],
        ),
      ];

      // 1. Inisialisasi langsung sebagai Operator -> tidak boleh memanggil dataSource
      final vm = RekapOmzetViewModel(
        session: _operatorSession(),
        dataSource: fake,
        exportDirectory: exportDir,
        nowProvider: () => _baseTime,
      );
      addTearDown(vm.dispose);

      await vm.loadData();
      expect(vm.isAuthorized, isFalse);
      expect(fake.getAllNotaCalls, 0);
      expect(vm.report.totalPenjualanNota, 0);
      expect(vm.buildExportPreview(), '');
      expect(vm.recordClipboardExport(), isNull);
      expect(await vm.exportReportToFile(), isNull);
      expect(vm.exportError, contains('hanya tersedia untuk Owner'));

      // 2. Naik ke Owner -> data dimuat dan ekspor file berhasil
      vm.updateSession(_ownerSession());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(vm.isAuthorized, isTrue);
      expect(vm.report.totalPenjualanNota, 85000);
      final exported = await vm.exportReportToFile(format: OmzetExportFormat.csv);
      expect(exported, isNotNull);
      expect(vm.lastExportResult, isNotNull);
      expect(vm.exportFeedback, isNotNull);

      // 3. Downgrade kembali ke Operator SAAT loadData sedang in-flight
      final raceGate = Completer<List<Barang>>();
      fake.onGetAllBarang = () => raceGate.future;
      final pendingLoad = vm.loadData();
      vm.updateSession(_operatorSession());
      raceGate.complete(const []);
      await pendingLoad;

      expect(vm.isAuthorized, isFalse);
      expect(vm.notas, isEmpty);
      expect(vm.report.totalPenjualanNota, 0);
      // Regresi fix: cache hasil ekspor Owner sebelumnya HARUS dibersihkan!
      expect(vm.lastExportResult, isNull);
      expect(vm.exportFeedback, isNull);
      expect(vm.exportError, isNull);
    });

    test('Salah input & failure handling: tanggal korup, NaN/negatif, out-of-range chart/toggle, ekspor file gagal, & re-entrancy', () async {
      final exportDir = Directory.systemTemp.createTempSync('dt36_err_rekap_');
      addTearDown(() {
        if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
      });
      final regularFile = File(p.join(exportDir.path, 'bukan_folder.txt'))
        ..writeAsStringSync('occupied');

      final fake = _FakeRekapDataSource();
      addTearDown(fake.dispose);
      fake.notas = [
        Nota(
          idNota: 1,
          tanggalNota: '2026-02-30', // tanggal kalender tidak valid
          total: 50000,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'bad-date',
          updatedAt: _baseTime,
          details: const [
            DetailNota(idNota: 1, idBarang: 1, jumlah: 50000, banyaknya: 2),
          ],
        ),
        Nota(
          idNota: 2,
          tanggalNota: '2026-11-16',
          total: double.nan,
          idPetugas: 1,
          idCustomer: 1,
          remoteId: 'bad-amounts',
          updatedAt: _baseTime,
          details: const [
            DetailNota(
              idNota: 2,
              idBarang: 1,
              namaBarang: 'Telur',
              jumlah: double.infinity,
              banyaknya: -4,
            ),
          ],
        ),
      ];

      final gate = Completer<void>();
      final slowService = _SlowReportExportService(gate);
      final vm = RekapOmzetViewModel(
        session: _ownerSession(),
        dataSource: fake,
        exportService: slowService,
        exportDirectory: exportDir,
        nowProvider: () => _baseTime,
      );
      addTearDown(vm.dispose);
      await vm.loadData();

      final report = vm.report;
      expect(report.totalPenjualanNota, 0);
      expect(report.notaCount, 1); // hanya tanggal valid 2026-11-16 yang masuk
      expect(report.unitTerjual, 0);

      // Out of bounds / empty controls diabaikan aman
      vm.selectChartBar(-1);
      vm.selectChartBar(99);
      expect(vm.selectedBarIndex, 6);
      vm.toggleProductDetail('   ');
      expect(vm.expandedProductKey, isNull);

      // Re-entrancy guard saat exportReportToFile masih berjalan
      final firstExport = vm.exportReportToFile();
      final secondExport = vm.exportReportToFile();
      expect(await secondExport, isNull);
      gate.complete();
      expect(await firstExport, isNotNull);
      expect(slowService.saveCalls, 1);

      // Target direktori yang ternyata file reguler -> gagal terkelola (exportError != null)
      final failExport = await vm.exportReportToFile(
        targetDirectory: Directory(regularFile.path),
      );
      expect(failExport, isNull);
      expect(vm.isExporting, isFalse);
      expect(vm.exportError, contains('Gagal mengekspor laporan'));
      vm.clearExportMessages();
      expect(vm.exportError, isNull);

      // Gagal fetch dataSource tidak men-crash VM
      fake.onGetAllBarang = () async => throw StateError('disk error');
      await vm.loadData();
      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, contains('Gagal memuat rekap omzet'));
    });

    test('Integrasi SQLite nyata via InventoryRepository & reactive auto-reload saat Nota/Faktur ditambah/diubah', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      await repo.savePetugas(
        existingRemoteId: 'pet-rekap-owner',
        namaPetugas: 'Owner SQLite',
        role: UserRole.owner,
        pin: '9988',
        email: 'owner.sqlite@depottelur36.com',
      );
      final owner = (await repo.getAllPetugas()).firstWhere(
        (p) => p.remoteId == 'pet-rekap-owner',
      );
      final telur = (await repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == 'seed-barang-telur-negeri-kg',
      );
      final customer = (await repo.getAllCustomer()).first;
      final supplier = (await repo.getAllSupplier()).first;

      final vm = RekapOmzetViewModel.fromRepository(
        session: _ownerSession(name: 'Owner SQLite'),
        repository: repo,
        exportDirectory: ctx.tempDir,
        nowProvider: () => _baseTime,
      );
      addTearDown(vm.dispose);
      await vm.loadData();
      expect(vm.report.totalPenjualanNota, 0);

      // Buat Nota & Faktur nyata di SQLite -> onDataChanged otomatis memicu reload ViewModel
      final idNota = await repo.createNota(
        tanggalNota: '2026-11-16',
        customer: customer,
        petugas: owner,
        items: [(barang: telur, banyaknya: 5)],
      );
      await repo.createFaktur(
        noFaktur: 'FKT-INT-01',
        tanggalFaktur: '2026-11-16',
        supplier: supplier,
        petugas: owner,
        items: [(barang: telur, quantity: 10)],
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(vm.report.totalPenjualanNota, 5 * 28500);
      expect(vm.report.belanjaFaktur, 10 * 28500);
      expect(vm.report.unitTerjual, 5);
      expect(vm.report.topProducts.first.namaBarang, 'Telur Ayam Negeri');

      // Hapus Nota di SQLite -> omzet otomatis turun kembali ke 0
      await repo.deleteNota(idNota);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(vm.report.totalPenjualanNota, 0);

      // Ekspor file nyata dari hasil agregasi SQLite
      final saved = await vm.exportReportToFile(
        format: OmzetExportFormat.ringkasanTeks,
      );
      expect(saved, isNotNull);
      expect(File(saved!.filePath!).existsSync(), isTrue);
    });

    test('Concurrent loadData epoch guard & dispose aman saat operasi berjalan', () async {
      final fake = _FakeRekapDataSource();
      addTearDown(fake.dispose);
      final gate1 = Completer<List<Barang>>();
      final gate2 = Completer<List<Barang>>();
      var count = 0;
      fake.onGetAllBarang = () {
        count++;
        return count == 1 ? gate1.future : gate2.future;
      };

      final vm = RekapOmzetViewModel(
        session: _ownerSession(),
        dataSource: fake,
        nowProvider: () => _baseTime,
      );

      final f1 = vm.loadData();
      final f2 = vm.loadData();

      gate2.complete([
        Barang(
          idBarang: 1,
          namaBarang: 'Barang Baru',
          stokBarang: 20,
          satuan: 'Kg',
          hargaSatuan: 30000,
          remoteId: 'b-new',
          updatedAt: _baseTime,
        ),
      ]);
      await f2;

      gate1.complete([
        Barang(
          idBarang: 1,
          namaBarang: 'Barang Lama',
          stokBarang: 1,
          satuan: 'Kg',
          hargaSatuan: 1000,
          remoteId: 'b-old',
          updatedAt: _baseTime,
        ),
      ]);
      await f1;

      expect(vm.barangs.single.namaBarang, 'Barang Baru');

      vm.dispose();
      fake.emitChanged();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  });
}
