import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/rekap_omzet_models.dart';

/// Pembantu pembentukan & penyimpanan laporan Rekap Omzet DepotTelur36 secara offline.
class ReportExportService {
  const ReportExportService();

  static final RegExp _controlCharsRegex = RegExp(
    r'[\x00-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2060\uFEFF]',
  );
  static final RegExp _pureSignedNumberRegex = RegExp(r'^-?\d+(\.\d+)?$');

  static String _sanitizeSingleLine(Object? raw) {
    return (raw ?? '')
        .toString()
        .replaceAll(_controlCharsRegex, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _formatFiniteInt(double value) =>
      value.isFinite ? value.toStringAsFixed(0) : '0';

  /// Menghasilkan isi laporan dalam format yang dipilih (`CSV` atau `Ringkasan Teks`).
  String buildContent(
    OmzetSummaryReport report, {
    required OmzetExportFormat format,
    required String ownerName,
  }) {
    return switch (format) {
      OmzetExportFormat.csv => buildCsvContent(report, ownerName: ownerName),
      OmzetExportFormat.ringkasanTeks =>
        buildTextSummaryContent(report, ownerName: ownerName),
    };
  }

  /// Membentuk CSV standar RFC-4180 yang aman dari CSV formula injection.
  String buildCsvContent(
    OmzetSummaryReport report, {
    required String ownerName,
  }) {
    final cleanOwner = _sanitizeSingleLine(ownerName).isEmpty
        ? 'Owner DepotTelur36'
        : _sanitizeSingleLine(ownerName);
    final buffer = StringBuffer();

    void writeRow(List<Object?> cells) {
      buffer.writeln(cells.map(_escapeCsvCell).join(','));
    }

    writeRow(['LAPORAN REKAP OMZET DEPOTELUR36']);
    writeRow(['Periode', report.period.label]);
    writeRow(['Rentang Tanggal', report.periodRangeLabel]);
    writeRow(['Dicetak Oleh', cleanOwner]);
    writeRow(['Waktu Ekspor', report.generatedAt.toIso8601String()]);
    writeRow([
      'Total Penjualan Nota',
      _formatFiniteInt(report.totalPenjualanNota),
    ]);
    writeRow(['Jumlah Nota', report.notaCount]);
    writeRow(['Belanja Faktur', _formatFiniteInt(report.belanjaFaktur)]);
    writeRow(['Jumlah Faktur', report.fakturCount]);
    writeRow(['Unit Terjual', report.unitTerjual]);
    writeRow(['Jenis Produk Terjual', report.jenisProdukTerjual]);
    writeRow(['Selisih Arus Kas', _formatFiniteInt(report.arusKasBersih)]);
    buffer.writeln();

    writeRow(['TREN PEMASUKAN 7 HARI TERAKHIR (${report.weeklyRangeLabel})']);
    writeRow(['Tanggal', 'Hari', 'Total Pemasukan', 'Jumlah Nota', 'Unit Terjual']);
    for (final day in report.weeklyTrend) {
      writeRow([
        day.isoDate,
        day.dayShort,
        _formatFiniteInt(day.totalOmzet),
        day.notaCount,
        day.unitCount,
      ]);
    }
    buffer.writeln();

    writeRow(['KONTRIBUSI PENJUALAN PER PRODUK']);
    writeRow([
      'Peringkat',
      'Nama Produk',
      'Satuan',
      'Unit Terjual',
      'Jumlah Nota',
      'Total Pendapatan',
      'Porsi (%)',
    ]);
    for (var i = 0; i < report.topProducts.length; i++) {
      final prod = report.topProducts[i];
      writeRow([
        i + 1,
        prod.namaBarang,
        prod.satuan,
        prod.totalQty,
        prod.notaCount,
        _formatFiniteInt(prod.totalRevenue),
        (prod.shareRatio.isFinite ? prod.shareRatio * 100 : 0.0)
            .toStringAsFixed(1),
      ]);
    }
    buffer.writeln();

    writeRow(['RINCIAN NOTA PENJUALAN']);
    writeRow(['ID Nota', 'Tanggal', 'Pelanggan', 'Kasir', 'Total', 'Daftar Item']);
    for (final nota in report.filteredNotas) {
      final itemsText = nota.details
          .map((d) => '${d.namaBarang ?? 'Barang #${d.idBarang}'} x${d.banyaknya}')
          .join('; ');
      writeRow([
        nota.idNota ?? nota.remoteId,
        nota.tanggalNota,
        nota.namaCustomer ?? 'Customer #${nota.idCustomer}',
        nota.namaPetugas ?? 'Petugas #${nota.idPetugas}',
        _formatFiniteInt(nota.total),
        itemsText,
      ]);
    }
    buffer.writeln();

    writeRow(['RINCIAN FAKTUR PEMBELIAN']);
    writeRow([
      'No Faktur',
      'Tanggal',
      'Supplier',
      'Penerima',
      'Total',
      'Daftar Item',
    ]);
    for (final faktur in report.filteredFakturs) {
      final itemsText = faktur.details
          .map((d) => '${d.namaBarang ?? 'Barang #${d.idBarang}'} x${d.quantity}')
          .join('; ');
      writeRow([
        faktur.noFaktur,
        faktur.tanggalFaktur,
        faktur.namaSupplier ?? 'Supplier #${faktur.idSupplier}',
        faktur.namaPetugas ?? 'Petugas #${faktur.idPetugas}',
        _formatFiniteInt(faktur.total),
        itemsText,
      ]);
    }

    return buffer.toString();
  }

  /// Membentuk laporan teks ringkas siap salin/bagikan untuk Owner.
  String buildTextSummaryContent(
    OmzetSummaryReport report, {
    required String ownerName,
  }) {
    final cleanOwner = _sanitizeSingleLine(ownerName).isEmpty
        ? 'Owner DepotTelur36'
        : _sanitizeSingleLine(ownerName);
    final buffer = StringBuffer()
      ..writeln('=== REKAP OMZET DEPOTELUR36 ===')
      ..writeln('Periode : ${report.period.label} (${report.periodRangeLabel})')
      ..writeln('Owner   : $cleanOwner')
      ..writeln('---------------------------------')
      ..writeln(
        'Total Penjualan Nota : ${formatRupiah(report.totalPenjualanNota)} (${report.notaCount} Nota)',
      )
      ..writeln(
        'Belanja Faktur Masuk : ${formatRupiah(report.belanjaFaktur)} (${report.fakturCount} Faktur)',
      )
      ..writeln(
        'Total Unit Terjual   : ${report.unitTerjual} Unit (${report.jenisProdukTerjual} jenis produk)',
      )
      ..writeln(
        'Selisih Arus Kas     : ${formatRupiah(report.arusKasBersih)}',
      );

    if (report.weeklyTrend.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Pemasukan 7 Hari (${report.weeklyRangeLabel}):');
      for (final point in report.weeklyTrend) {
        buffer.writeln(
          '- ${point.dayShort} (${point.dateLabel}): ${formatRupiah(point.totalOmzet)} · ${point.notaCount} Nota',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('Kontribusi Penjualan per Produk:');
    if (report.topProducts.isEmpty) {
      buffer.writeln('- Belum ada penjualan produk pada periode ini.');
    } else {
      for (var i = 0; i < report.topProducts.length; i++) {
        final item = report.topProducts[i];
        final pct =
            (item.shareRatio.isFinite ? item.shareRatio * 100 : 0.0)
                .toStringAsFixed(1);
        final cleanName = _sanitizeSingleLine(item.namaBarang);
        final cleanUnit = _sanitizeSingleLine(item.satuan);
        buffer.writeln(
          '${i + 1}. $cleanName: ${item.totalQty} $cleanUnit · ${item.notaCount} Nota · ${formatRupiah(item.totalRevenue)} ($pct%)',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  /// Menyimpan file laporan ke penyimpanan lokal perangkat atau [targetDirectory].
  Future<ExportedReportResult> saveReportToFile(
    OmzetSummaryReport report, {
    required OmzetExportFormat format,
    required String ownerName,
    Directory? targetDirectory,
  }) async {
    final content = buildContent(report, format: format, ownerName: ownerName);
    final dir = targetDirectory ??
        Directory(p.join(Directory.systemTemp.path, 'depottelur36_exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = await _allocateUniqueExportFile(
      dir: dir,
      period: report.period,
      now: report.generatedAt,
      format: format,
    );
    await file.writeAsString(content, flush: true);

    return ExportedReportResult(
      format: format,
      fileName: p.basename(file.path),
      filePath: file.path,
      content: content,
      generatedAt: report.generatedAt,
    );
  }

  Future<File> _allocateUniqueExportFile({
    required Directory dir,
    required RekapOmzetPeriod period,
    required DateTime now,
    required OmzetExportFormat format,
  }) async {
    final base = _buildFileStem(period, now);
    var candidate = File(p.join(dir.path, '$base.${format.extension}'));
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        p.join(dir.path, '${base}_$suffix.${format.extension}'),
      );
      suffix++;
    }
    return candidate;
  }

  String _buildFileStem(
    RekapOmzetPeriod period,
    DateTime now,
  ) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    return 'rekap_omzet_${period.name}_$y$m${d}_$hh$mm${ss}_$ms';
  }

  static String _escapeCsvCell(Object? raw) {
    var text = _sanitizeSingleLine(raw);
    if (text.isNotEmpty &&
        !_pureSignedNumberRegex.hasMatch(text) &&
        (text.startsWith('=') ||
            text.startsWith('+') ||
            text.startsWith('-') ||
            text.startsWith('@'))) {
      text = "'$text";
    }
    final needsQuote =
        text.contains(',') || text.contains('"') || text.contains('\n');
    if (!needsQuote) return text;
    return '"${text.replaceAll('"', '""')}"';
  }
}
