import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/transaksi.dart';

/// Filter rentang waktu untuk layar `20 Rekap Omzet` khusus Owner.
enum RekapOmzetPeriod {
  hariIni('Hari Ini'),
  tujuhHari('7 Hari'),
  bulanIni('Bulan Ini');

  const RekapOmzetPeriod(this.label);

  final String label;
}

/// Format file laporan omzet yang didukung oleh `ReportExportService`.
enum OmzetExportFormat {
  csv('CSV (Excel)', 'csv'),
  ringkasanTeks('Ringkasan Teks', 'txt');

  const OmzetExportFormat(this.label, this.extension);

  final String label;
  final String extension;
}

/// Satu titik data harian pada grafik batang `Pemasukan 7 Hari Terakhir`.
class DailyOmzetBarPoint {
  const DailyOmzetBarPoint({
    required this.isoDate,
    required this.dayShort,
    required this.dateLabel,
    required this.totalOmzet,
    required this.notaCount,
    required this.unitCount,
    required this.isToday,
  });

  final String isoDate;
  final String dayShort;
  final String dateLabel;
  final double totalOmzet;
  final int notaCount;
  final int unitCount;
  final bool isToday;
}

/// Kontribusi penjualan teragregasi per produk pada periode aktif.
class ProductSalesContribution {
  const ProductSalesContribution({
    required this.productKey,
    this.idBarang,
    required this.namaBarang,
    required this.satuan,
    this.barang,
    required this.totalQty,
    required this.notaCount,
    required this.totalRevenue,
    required this.shareRatio,
  });

  final String productKey;
  final int? idBarang;
  final String namaBarang;
  final String satuan;
  final Barang? barang;
  final int totalQty;
  final int notaCount;
  final double totalRevenue;
  final double shareRatio;

  double get averagePricePerUnit =>
      totalQty > 0 ? totalRevenue / totalQty : 0.0;
}

/// Snapshot ringkasan omzet, tren 7 hari, kontribusi produk, dan daftar transaksi.
class OmzetSummaryReport {
  const OmzetSummaryReport({
    required this.period,
    required this.periodRangeLabel,
    required this.weeklyRangeLabel,
    required this.totalPenjualanNota,
    required this.notaCount,
    required this.belanjaFaktur,
    required this.fakturCount,
    required this.unitTerjual,
    required this.jenisProdukTerjual,
    required this.weeklyTrend,
    required this.topProducts,
    required this.filteredNotas,
    required this.filteredFakturs,
    required this.generatedAt,
  });

  factory OmzetSummaryReport.empty({
    required RekapOmzetPeriod period,
    required DateTime now,
  }) {
    return OmzetSummaryReport(
      period: period,
      periodRangeLabel: '-',
      weeklyRangeLabel: '-',
      totalPenjualanNota: 0,
      notaCount: 0,
      belanjaFaktur: 0,
      fakturCount: 0,
      unitTerjual: 0,
      jenisProdukTerjual: 0,
      weeklyTrend: const [],
      topProducts: const [],
      filteredNotas: const [],
      filteredFakturs: const [],
      generatedAt: now,
    );
  }

  final RekapOmzetPeriod period;
  final String periodRangeLabel;
  final String weeklyRangeLabel;
  final double totalPenjualanNota;
  final int notaCount;
  final double belanjaFaktur;
  final int fakturCount;
  final int unitTerjual;
  final int jenisProdukTerjual;
  final List<DailyOmzetBarPoint> weeklyTrend;
  final List<ProductSalesContribution> topProducts;
  final List<Nota> filteredNotas;
  final List<Faktur> filteredFakturs;
  final DateTime generatedAt;

  double get arusKasBersih => totalPenjualanNota - belanjaFaktur;
}

/// Hasil ekspor laporan omzet dalam bentuk konten teks/CSV dan file lokal.
class ExportedReportResult {
  const ExportedReportResult({
    required this.format,
    required this.fileName,
    this.filePath,
    required this.content,
    required this.generatedAt,
  });

  final OmzetExportFormat format;
  final String fileName;
  final String? filePath;
  final String content;
  final DateTime generatedAt;
}

/// Memformat angka nominal ke label ringkas batang grafik (contoh: `268rb`, `1,2jt`).
String formatCompactOmzetLabel(double value) {
  if (!value.isFinite || value <= 0) return '0';
  if (value >= 999950000000) {
    return '999M+';
  }
  if (value >= 999500000) {
    final m = value / 1000000000;
    return '${_trimCompactDecimal(m)}M';
  }
  if (value >= 999500) {
    final jt = value / 1000000;
    return '${_trimCompactDecimal(jt)}jt';
  }
  if (value >= 1000) {
    final rb = (value / 1000).round();
    return '${rb}rb';
  }
  return '${value.round()}';
}

String _trimCompactDecimal(double value) {
  final fixed = value >= 10 ? value.round().toString() : value.toStringAsFixed(1);
  return fixed.endsWith('.0')
      ? fixed.substring(0, fixed.length - 2)
      : fixed.replaceAll('.', ',');
}
