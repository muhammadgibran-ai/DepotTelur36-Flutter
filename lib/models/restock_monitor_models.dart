import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';

/// Filter kategori pada layar `22 Stok Menipis`.
enum StokMenipisFilter {
  kritis('Kritis (≤ 10)'),
  pantauan('Pantauan (≤ 25)'),
  semua('Semua');

  const StokMenipisFilter(this.label);

  final String label;
}

/// Tingkat urgensi pemantauan stok per barang.
enum StockAlertLevel {
  habis('Habis'),
  kritis('Kritis'),
  pantauan('Pantauan'),
  aman('Aman');

  const StockAlertLevel(this.label);

  final String label;
}

/// Item terstruktur untuk pemantauan stok menipis & rekomendasi aksi restok.
class RestockMonitorItem {
  const RestockMonitorItem({
    required this.barang,
    required this.alertLevel,
    required this.suggestedQty,
    required this.draftQty,
    required this.meterRatio,
    this.lastSupplierId,
    this.lastSupplierRemoteId,
    this.lastSupplierName,
    this.lastRestockDate,
  });

  final Barang barang;
  final StockAlertLevel alertLevel;
  final int suggestedQty;
  final int draftQty;
  final double meterRatio;
  final int? lastSupplierId;
  final String? lastSupplierRemoteId;
  final String? lastSupplierName;
  final String? lastRestockDate;

  bool get isCritical =>
      alertLevel == StockAlertLevel.habis ||
      alertLevel == StockAlertLevel.kritis;

  bool get isWatchOnly => alertLevel == StockAlertLevel.pantauan;

  bool get isSafe => alertLevel == StockAlertLevel.aman;

  int get projectedStockAfterRestock => barang.stokBarang + draftQty;
}

/// Ringkasan hasil evaluasi pemantauan stok di gudang lokal SQLite.
class RestockSummarySnapshot {
  const RestockSummarySnapshot({
    required this.filter,
    required this.lowThreshold,
    required this.watchThreshold,
    required this.outOfStockCount,
    required this.criticalCount,
    required this.watchBandCount,
    required this.totalCatalogCount,
    required this.criticalItems,
    required this.watchOnlyItems,
    required this.safeItems,
  });

  factory RestockSummarySnapshot.empty({
    StokMenipisFilter filter = StokMenipisFilter.kritis,
    int lowThreshold = kLowStockThreshold,
    int watchThreshold = kWatchMonitorThreshold,
  }) {
    return RestockSummarySnapshot(
      filter: filter,
      lowThreshold: lowThreshold,
      watchThreshold: watchThreshold,
      outOfStockCount: 0,
      criticalCount: 0,
      watchBandCount: 0,
      totalCatalogCount: 0,
      criticalItems: const [],
      watchOnlyItems: const [],
      safeItems: const [],
    );
  }

  final StokMenipisFilter filter;
  final int lowThreshold;
  final int watchThreshold;
  final int outOfStockCount;
  final int criticalCount;
  final int watchBandCount;
  final int totalCatalogCount;
  final List<RestockMonitorItem> criticalItems;
  final List<RestockMonitorItem> watchOnlyItems;
  final List<RestockMonitorItem> safeItems;

  int get watchAndCriticalCount => criticalCount + watchBandCount;

  /// Label dinamis chip filter (termasuk jumlah total pada chip `Semua (N)`).
  String labelForFilter(StokMenipisFilter target) {
    return switch (target) {
      StokMenipisFilter.kritis => 'Kritis (≤ $lowThreshold)',
      StokMenipisFilter.pantauan => 'Pantauan (≤ $watchThreshold)',
      StokMenipisFilter.semua => 'Semua ($totalCatalogCount)',
    };
  }
}
