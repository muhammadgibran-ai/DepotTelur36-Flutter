import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/services/report_export_service.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';

/// ViewModel Fungsi 5: `20 Rekap Omzet` & Ekspor Laporan khusus peran Owner.
class RekapOmzetViewModel extends ChangeNotifier {
  RekapOmzetViewModel({
    required AuthSession session,
    required TransactionCrudDataSource dataSource,
    ReportExportService exportService = const ReportExportService(),
    Directory? exportDirectory,
    DateTime Function()? nowProvider,
  }) : this._(
          session: session,
          dataSource: dataSource,
          exportService: exportService,
          exportDirectory: exportDirectory,
          now: nowProvider ?? DateTime.now,
        );

  RekapOmzetViewModel._({
    required this._session,
    required this._dataSource,
    required this._exportService,
    required this._exportDirectory,
    required this._now,
  }) {
    _subscription = _dataSource.onDataChanged.listen(
      (_) => unawaited(loadData(silent: true)),
      onError: (_) {},
    );
  }

  factory RekapOmzetViewModel.fromRepository({
    required AuthSession session,
    required InventoryRepository repository,
    ReportExportService exportService = const ReportExportService(),
    Directory? exportDirectory,
    DateTime Function()? nowProvider,
  }) {
    return RekapOmzetViewModel(
      session: session,
      dataSource: RepositoryTransactionCrudDataSource(repository),
      exportService: exportService,
      exportDirectory: exportDirectory,
      nowProvider: nowProvider,
    );
  }

  final TransactionCrudDataSource _dataSource;
  final ReportExportService _exportService;
  final Directory? _exportDirectory;
  final DateTime Function() _now;

  AuthSession _session;
  StreamSubscription<void>? _subscription;
  int _loadEpoch = 0;
  bool _disposed = false;

  bool _isLoading = false;
  bool _isExporting = false;
  String? _errorMessage;
  String? _exportFeedback;
  String? _exportError;
  ExportedReportResult? _lastExportResult;

  RekapOmzetPeriod _period = RekapOmzetPeriod.hariIni;
  int _selectedBarIndex = 6;
  String? _expandedProductKey;
  OmzetExportFormat _selectedExportFormat = OmzetExportFormat.csv;

  List<Barang> _barangs = const [];
  List<Faktur> _fakturs = const [];
  List<Nota> _notas = const [];

  static const String _ownerOnlyMessage =
      'Akses ditolak: laporan Rekap Omzet dan Ekspor hanya tersedia untuk Owner.';

  AuthSession get session => _session;
  bool get isAuthorized => _session.isOwner;
  bool get isLoading => _isLoading;
  bool get isExporting => _isExporting;
  String? get errorMessage => _errorMessage;
  String? get exportFeedback => _exportFeedback;
  String? get exportError => _exportError;
  ExportedReportResult? get lastExportResult => _lastExportResult;

  RekapOmzetPeriod get period => _period;
  int get selectedBarIndex => _selectedBarIndex;
  String? get expandedProductKey => _expandedProductKey;
  OmzetExportFormat get selectedExportFormat => _selectedExportFormat;

  List<Barang> get barangs => _barangs;
  List<Faktur> get fakturs => _fakturs;
  List<Nota> get notas => _notas;

  /// Menghitung ringkasan omzet, tren 7 hari terakhir, dan kontribusi produk secara reaktif.
  OmzetSummaryReport get report {
    final current = _now();
    if (!isAuthorized) {
      return OmzetSummaryReport.empty(period: _period, now: current);
    }

    final todayStart = DateTime(current.year, current.month, current.day);
    final rangeStart = switch (_period) {
      RekapOmzetPeriod.hariIni => todayStart,
      RekapOmzetPeriod.tujuhHari => todayStart.subtract(const Duration(days: 6)),
      RekapOmzetPeriod.bulanIni => DateTime(current.year, current.month, 1),
    };
    final rangeEnd = todayStart;

    final filteredNotas = _notas.where((nota) {
      final parsed = TransactionCrudViewModel.parseIsoDate(nota.tanggalNota);
      return parsed != null &&
          !parsed.isBefore(rangeStart) &&
          !parsed.isAfter(rangeEnd);
    }).toList(growable: false);

    final filteredFakturs = _fakturs.where((faktur) {
      final parsed =
          TransactionCrudViewModel.parseIsoDate(faktur.tanggalFaktur);
      return parsed != null &&
          !parsed.isBefore(rangeStart) &&
          !parsed.isAfter(rangeEnd);
    }).toList(growable: false);

    final barangById = <int, Barang>{
      for (final b in _barangs)
        if (b.idBarang != null) b.idBarang!: b,
    };
    final barangByRemote = <String, Barang>{
      for (final b in _barangs)
        if (b.remoteId.isNotEmpty) b.remoteId: b,
    };

    var totalNota = 0.0;
    var unitTerjual = 0;
    final productAccum = <String, _ProductAccumulator>{};

    for (final nota in filteredNotas) {
      final notaIdKey = nota.idNota?.toString() ?? nota.remoteId;
      if (nota.total.isFinite && nota.total > 0) {
        totalNota += nota.total;
      }
      for (final detail in nota.details) {
        final qty = detail.banyaknya > 0 ? detail.banyaknya : 0;
        final amount =
            detail.jumlah.isFinite && detail.jumlah > 0 ? detail.jumlah : 0.0;
        unitTerjual += qty;

        final matchedBarang = barangById[detail.idBarang] ??
            (detail.barangRemoteId != null
                ? barangByRemote[detail.barangRemoteId!]
                : null);

        final effectiveId = matchedBarang?.idBarang ??
            (detail.idBarang > 0 ? detail.idBarang : null);
        final resolvedKey = effectiveId != null
            ? 'id_$effectiveId'
            : (detail.barangRemoteId?.trim().isNotEmpty == true
                ? 'remote_${detail.barangRemoteId!.trim()}'
                : 'name_${(detail.namaBarang ?? 'produk').trim().toLowerCase()}');
        final resolvedName = matchedBarang?.namaBarang ??
            (detail.namaBarang?.trim().isNotEmpty == true
                ? detail.namaBarang!.trim()
                : 'Barang #${detail.idBarang}');
        final resolvedUnit = matchedBarang?.satuan ??
            (detail.satuan?.trim().isNotEmpty == true
                ? detail.satuan!.trim()
                : 'Unit');

        final entry = productAccum.putIfAbsent(
          resolvedKey,
          () => _ProductAccumulator(
            key: resolvedKey,
            idBarang: effectiveId,
            namaBarang: resolvedName,
            satuan: resolvedUnit,
            barang: matchedBarang,
          ),
        );
        entry.totalQty += qty;
        entry.totalRevenue += amount;
        entry.notaKeys.add(notaIdKey);
      }
    }

    var totalFaktur = 0.0;
    for (final faktur in filteredFakturs) {
      if (faktur.total.isFinite && faktur.total > 0) {
        totalFaktur += faktur.total;
      }
    }

    var totalDetailRevenue = 0.0;
    for (final entry in productAccum.values) {
      totalDetailRevenue += entry.totalRevenue;
    }
    final ratioDenominator = totalNota > 0 ? totalNota : totalDetailRevenue;

    final topProducts = productAccum.values.map((e) {
      final ratio = ratioDenominator > 0
          ? (e.totalRevenue / ratioDenominator).clamp(0.0, 1.0)
          : 0.0;
      return ProductSalesContribution(
        productKey: e.key,
        idBarang: e.idBarang,
        namaBarang: e.namaBarang,
        satuan: e.satuan,
        barang: e.barang,
        totalQty: e.totalQty,
        notaCount: e.notaKeys.length,
        totalRevenue: e.totalRevenue,
        shareRatio: ratio,
      );
    }).toList()
      ..sort((a, b) {
        final revCmp = b.totalRevenue.compareTo(a.totalRevenue);
        if (revCmp != 0) return revCmp;
        final qtyCmp = b.totalQty.compareTo(a.totalQty);
        if (qtyCmp != 0) return qtyCmp;
        return a.namaBarang.compareTo(b.namaBarang);
      });

    final weekStart = todayStart.subtract(const Duration(days: 6));
    final notasByIso = <String, List<Nota>>{};
    for (final nota in _notas) {
      final parsed = TransactionCrudViewModel.parseIsoDate(nota.tanggalNota);
      if (parsed == null) continue;
      if (parsed.isBefore(weekStart) || parsed.isAfter(todayStart)) continue;
      final iso = TransactionCrudViewModel.toIsoDateString(parsed);
      notasByIso.putIfAbsent(iso, () => []).add(nota);
    }

    final weeklyTrend = <DailyOmzetBarPoint>[];
    for (var i = 0; i < 7; i++) {
      final dayDate = weekStart.add(Duration(days: i));
      final iso = TransactionCrudViewModel.toIsoDateString(dayDate);
      final dayNotas = notasByIso[iso] ?? const [];
      var dayTotal = 0.0;
      var dayUnits = 0;
      for (final nota in dayNotas) {
        if (nota.total.isFinite && nota.total > 0) {
          dayTotal += nota.total;
        }
        for (final d in nota.details) {
          if (d.banyaknya > 0) dayUnits += d.banyaknya;
        }
      }
      weeklyTrend.add(
        DailyOmzetBarPoint(
          isoDate: iso,
          dayShort: _weekdayShort(dayDate.weekday),
          dateLabel:
              TransactionCrudViewModel.formatDisplayDate(iso, short: true),
          totalOmzet: dayTotal,
          notaCount: dayNotas.length,
          unitCount: dayUnits,
          isToday: i == 6,
        ),
      );
    }

    return OmzetSummaryReport(
      period: _period,
      periodRangeLabel: _formatPeriodRangeLabel(_period, rangeStart, rangeEnd),
      weeklyRangeLabel: _formatWeeklyRangeLabel(weekStart, todayStart),
      totalPenjualanNota: totalNota,
      notaCount: filteredNotas.length,
      belanjaFaktur: totalFaktur,
      fakturCount: filteredFakturs.length,
      unitTerjual: unitTerjual,
      jenisProdukTerjual: productAccum.length,
      weeklyTrend: weeklyTrend,
      topProducts: topProducts,
      filteredNotas: filteredNotas,
      filteredFakturs: filteredFakturs,
      generatedAt: current,
    );
  }

  /// Titik grafik 7 hari yang sedang dipilih untuk sorotan aktif.
  DailyOmzetBarPoint? get selectedBarPoint {
    final points = report.weeklyTrend;
    if (points.isEmpty) return null;
    if (_selectedBarIndex < 0 || _selectedBarIndex >= points.length) {
      return points.last;
    }
    return points[_selectedBarIndex];
  }

  void updateSession(AuthSession nextSession) {
    if (_session == nextSession) return;
    final wasAuthorized = _session.isOwner;
    _session = nextSession;
    if (!nextSession.isOwner) {
      _loadEpoch++;
      _barangs = const [];
      _fakturs = const [];
      _notas = const [];
      _expandedProductKey = null;
      _lastExportResult = null;
      _exportFeedback = null;
      _exportError = null;
      _errorMessage = _ownerOnlyMessage;
      _notifySafely();
      return;
    }
    if (!wasAuthorized && nextSession.isOwner) {
      _errorMessage = null;
      unawaited(loadData());
      return;
    }
    _notifySafely();
  }

  Future<void> loadData({bool silent = false}) async {
    if (!isAuthorized) {
      _loadEpoch++;
      _barangs = const [];
      _fakturs = const [];
      _notas = const [];
      _expandedProductKey = null;
      _lastExportResult = null;
      _exportFeedback = null;
      _exportError = null;
      _isLoading = false;
      _errorMessage = _ownerOnlyMessage;
      _notifySafely();
      return;
    }

    final epoch = ++_loadEpoch;
    if (!silent) {
      _isLoading = true;
      _notifySafely();
    }

    try {
      final results = await Future.wait<dynamic>([
        _dataSource.getAllBarang(),
        _dataSource.getAllFaktur(),
        _dataSource.getAllNota(),
      ]);
      if (_disposed || epoch != _loadEpoch || !isAuthorized) return;

      _barangs = results[0] as List<Barang>;
      _fakturs = results[1] as List<Faktur>;
      _notas = results[2] as List<Nota>;
      _errorMessage = null;
    } catch (e) {
      if (_disposed || epoch != _loadEpoch) return;
      _errorMessage = 'Gagal memuat rekap omzet: $e';
    } finally {
      if (!_disposed && epoch == _loadEpoch) {
        _isLoading = false;
        _notifySafely();
      }
    }
  }

  void selectPeriod(RekapOmzetPeriod next) {
    if (!isAuthorized || _period == next) return;
    _period = next;
    _expandedProductKey = null;
    _exportFeedback = null;
    _notifySafely();
  }

  void selectChartBar(int index) {
    if (!isAuthorized) return;
    if (index < 0 || index > 6 || _selectedBarIndex == index) return;
    _selectedBarIndex = index;
    _notifySafely();
  }

  void toggleProductDetail(String productKey) {
    if (!isAuthorized || productKey.trim().isEmpty) return;
    _expandedProductKey =
        _expandedProductKey == productKey ? null : productKey;
    _notifySafely();
  }

  void selectExportFormat(OmzetExportFormat format) {
    if (_selectedExportFormat == format) return;
    _selectedExportFormat = format;
    _exportError = null;
    _notifySafely();
  }

  void clearExportMessages() {
    if (_exportFeedback == null && _exportError == null) return;
    _exportFeedback = null;
    _exportError = null;
    _notifySafely();
  }

  /// Menghasilkan pratinjau laporan ekspor untuk periode & format terpilih.
  String buildExportPreview({OmzetExportFormat? format}) {
    if (!isAuthorized) return '';
    return _exportService.buildContent(
      report,
      format: format ?? _selectedExportFormat,
      ownerName: _session.displayName,
    );
  }

  /// Mencatat status keberhasilan saat laporan disalin ke clipboard.
  ExportedReportResult? recordClipboardExport({OmzetExportFormat? format}) {
    if (!isAuthorized) {
      _exportError = _ownerOnlyMessage;
      _notifySafely();
      return null;
    }
    final activeFormat = format ?? _selectedExportFormat;
    final currentReport = report;
    final content = _exportService.buildContent(
      currentReport,
      format: activeFormat,
      ownerName: _session.displayName,
    );
    final result = ExportedReportResult(
      format: activeFormat,
      fileName: 'clipboard_${activeFormat.extension}',
      content: content,
      generatedAt: currentReport.generatedAt,
    );
    _lastExportResult = result;
    _exportError = null;
    _exportFeedback =
        'Laporan ${activeFormat.label} berhasil disalin ke clipboard.';
    _notifySafely();
    return result;
  }

  /// Mengekspor laporan rekap omzet periode aktif ke file `.csv` / `.txt` lokal.
  Future<ExportedReportResult?> exportReportToFile({
    OmzetExportFormat? format,
    Directory? targetDirectory,
  }) async {
    if (!isAuthorized) {
      _exportError = _ownerOnlyMessage;
      _notifySafely();
      return null;
    }
    if (_isExporting) return null;

    _isExporting = true;
    _exportError = null;
    _exportFeedback = null;
    _notifySafely();

    final activeFormat = format ?? _selectedExportFormat;
    try {
      final result = await _exportService.saveReportToFile(
        report,
        format: activeFormat,
        ownerName: _session.displayName,
        targetDirectory: targetDirectory ?? _exportDirectory,
      );
      if (_disposed) return result;
      _lastExportResult = result;
      _exportFeedback = 'File ${result.fileName} berhasil disimpan.';
      return result;
    } catch (e) {
      if (_disposed) return null;
      _exportError = 'Gagal mengekspor laporan: $e';
      return null;
    } finally {
      if (!_disposed) {
        _isExporting = false;
        _notifySafely();
      }
    }
  }

  static String _weekdayShort(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Sen',
      DateTime.tuesday => 'Sel',
      DateTime.wednesday => 'Rab',
      DateTime.thursday => 'Kam',
      DateTime.friday => 'Jum',
      DateTime.saturday => 'Sab',
      DateTime.sunday => 'Min',
      _ => '-',
    };
  }

  static String _formatPeriodRangeLabel(
    RekapOmzetPeriod period,
    DateTime start,
    DateTime end,
  ) {
    final endIso = TransactionCrudViewModel.toIsoDateString(end);
    switch (period) {
      case RekapOmzetPeriod.hariIni:
        return TransactionCrudViewModel.formatDisplayDate(endIso);
      case RekapOmzetPeriod.tujuhHari:
        return _formatWeeklyRangeLabel(start, end);
      case RekapOmzetPeriod.bulanIni:
        const months = [
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
        return '${months[end.month - 1]} ${end.year}';
    }
  }

  static String _formatWeeklyRangeLabel(DateTime start, DateTime end) {
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
    if (start.month == end.month && start.year == end.year) {
      return '${start.day}–${end.day} ${shortMonths[end.month - 1]}';
    }
    return '${start.day} ${shortMonths[start.month - 1]}–${end.day} ${shortMonths[end.month - 1]}';
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

class _ProductAccumulator {
  _ProductAccumulator({
    required this.key,
    required this.idBarang,
    required this.namaBarang,
    required this.satuan,
    required this.barang,
  });

  final String key;
  final int? idBarang;
  final String namaBarang;
  final String satuan;
  final Barang? barang;
  int totalQty = 0;
  double totalRevenue = 0;
  final Set<String> notaKeys = <String>{};
}
