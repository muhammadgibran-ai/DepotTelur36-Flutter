import 'package:depot_telur_36/models/sync_status.dart';
import 'package:intl/intl.dart';

/// Threshold standar stok menipis (selaras dengan `Barang.isLowStock`).
const int kLowStockThreshold = 10;

/// Threshold pantauan stok menjelang menipis untuk notifikasi dini.
const int kWatchStockThreshold = 20;

/// Batas maksimum panjang query pencarian agar aman dari input berlebihan.
const int kMaxSearchQueryLength = 80;

/// Tab navigasi berbasis peran (RBAC) pada shell beranda DepotTelur36.
enum DashboardTabId {
  beranda,
  omzet,
  nota,
  master,
  kasir,
  faktur,
  stok,
}

/// Spesifikasi tampilan dan hak akses sebuah tab pada [FloatingTabBar].
class DashboardTabSpec {
  const DashboardTabSpec({
    required this.id,
    required this.label,
    required this.semanticLabel,
    required this.ownerOnly,
  });

  final DashboardTabId id;
  final String label;
  final String semanticLabel;
  final bool ownerOnly;
}

/// Daftar aksi cepat (shortcut) di grid Beranda.
enum DashboardShortcutId {
  aturHarga,
  riwayatFaktur,
  dataSupplier,
  akunPetugas,
  riwayatNota,
  pelanggan,
  supplier,
}

/// Spesifikasi shortcut beranda beserta aturan akses peran.
class DashboardShortcutSpec {
  const DashboardShortcutSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.ownerOnly,
    this.targetTab,
  });

  final DashboardShortcutId id;
  final String label;
  final String description;
  final bool ownerOnly;
  final DashboardTabId? targetTab;
}

/// Filter cepat untuk daftar barang pada Beranda dan tab Stok/Master.
enum DashboardQuickFilter {
  semua('Semua'),
  stokMenipis('Stok Menipis'),
  stokAman('Stok Aman'),
  telur('Telur'),
  sembako('Sembako');

  const DashboardQuickFilter(this.label);

  final String label;
}

/// Tingkat urgensi item pada Pusat Notifikasi & Sinkronisasi.
enum NotificationSeverity {
  critical,
  warning,
  info,
}

/// Item notifikasi terstruktur untuk stok kritis/menipis maupun status sinkronisasi.
class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.createdAt,
    this.isRead = false,
    this.barangRemoteId,
    this.barangNama,
    this.currentStock,
    this.satuan,
    this.isSyncAlert = false,
  });

  final String id;
  final String title;
  final String message;
  final NotificationSeverity severity;
  final DateTime createdAt;
  final bool isRead;
  final String? barangRemoteId;
  final String? barangNama;
  final int? currentStock;
  final String? satuan;
  final bool isSyncAlert;

  bool get isStockAlert => barangNama != null && !isSyncAlert;

  AppNotificationItem copyWith({
    bool? isRead,
  }) {
    return AppNotificationItem(
      id: id,
      title: title,
      message: message,
      severity: severity,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      barangRemoteId: barangRemoteId,
      barangNama: barangNama,
      currentStock: currentStock,
      satuan: satuan,
      isSyncAlert: isSyncAlert,
    );
  }
}

/// Ringkasan metrik beranda & tab modul dari database lokal SQLite.
class DashboardSummaryMetrics {
  const DashboardSummaryMetrics({
    this.totalBarang = 0,
    this.lowStockCount = 0,
    this.outOfStockCount = 0,
    this.totalSupplier = 0,
    this.totalCustomer = 0,
    this.totalPetugas = 0,
    this.totalNotaCount = 0,
    this.totalNotaOmzet = 0,
    this.totalFakturCount = 0,
    this.totalFakturBelanja = 0,
    this.totalStokUnit = 0,
  });

  final int totalBarang;
  final int lowStockCount;
  final int outOfStockCount;
  final int totalSupplier;
  final int totalCustomer;
  final int totalPetugas;
  final int totalNotaCount;
  final double totalNotaOmzet;
  final int totalFakturCount;
  final double totalFakturBelanja;
  final int totalStokUnit;
}

const List<DashboardTabSpec> _ownerTabs = [
  DashboardTabSpec(
    id: DashboardTabId.beranda,
    label: 'Beranda',
    semanticLabel: 'Tab Beranda Owner',
    ownerOnly: false,
  ),
  DashboardTabSpec(
    id: DashboardTabId.omzet,
    label: 'Omzet',
    semanticLabel: 'Tab Omzet khusus Owner',
    ownerOnly: true,
  ),
  DashboardTabSpec(
    id: DashboardTabId.nota,
    label: 'Nota',
    semanticLabel: 'Tab Riwayat Nota Owner',
    ownerOnly: true,
  ),
  DashboardTabSpec(
    id: DashboardTabId.master,
    label: 'Master',
    semanticLabel: 'Tab Master Data Owner',
    ownerOnly: true,
  ),
];

const List<DashboardTabSpec> _operatorTabs = [
  DashboardTabSpec(
    id: DashboardTabId.beranda,
    label: 'Beranda',
    semanticLabel: 'Tab Beranda Kasir',
    ownerOnly: false,
  ),
  DashboardTabSpec(
    id: DashboardTabId.kasir,
    label: 'Kasir',
    semanticLabel: 'Tab Kasir Penjualan',
    ownerOnly: false,
  ),
  DashboardTabSpec(
    id: DashboardTabId.faktur,
    label: 'Faktur',
    semanticLabel: 'Tab Faktur Stok Masuk',
    ownerOnly: false,
  ),
  DashboardTabSpec(
    id: DashboardTabId.stok,
    label: 'Stok',
    semanticLabel: 'Tab Daftar Stok Gudang',
    ownerOnly: false,
  ),
];

const List<DashboardShortcutSpec> _ownerShortcuts = [
  DashboardShortcutSpec(
    id: DashboardShortcutId.aturHarga,
    label: 'Atur Harga',
    description:
        'Kelola harga jual eceran & grosir barang (khusus Owner). Modul editor harga penuh hadir pada tahap berikutnya.',
    ownerOnly: true,
    targetTab: DashboardTabId.master,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.riwayatFaktur,
    label: 'Riwayat Faktur',
    description:
        'Audit riwayat faktur barang masuk dari supplier. Modul detail faktur penuh hadir pada tahap berikutnya.',
    ownerOnly: false,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.dataSupplier,
    label: 'Data Supplier',
    description:
        'Kelola daftar pemasok telur & sembako terdaftar pada tab Master.',
    ownerOnly: false,
    targetTab: DashboardTabId.master,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.akunPetugas,
    label: 'Akun Petugas',
    description:
        'Pantau akun Kasir/Gudang dan peran aktif (khusus Owner). Manajemen akun penuh hadir pada tahap berikutnya.',
    ownerOnly: true,
    targetTab: DashboardTabId.master,
  ),
];

const List<DashboardShortcutSpec> _operatorShortcuts = [
  DashboardShortcutSpec(
    id: DashboardShortcutId.riwayatNota,
    label: 'Riwayat Nota',
    description:
        'Pantau nota penjualan kasir terkini. Pencatatan kasir penuh hadir pada tahap berikutnya.',
    ownerOnly: false,
    targetTab: DashboardTabId.kasir,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.riwayatFaktur,
    label: 'Riwayat Faktur',
    description:
        'Pantau faktur pembelian stok masuk dari supplier pada tab Faktur.',
    ownerOnly: false,
    targetTab: DashboardTabId.faktur,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.pelanggan,
    label: 'Pelanggan',
    description:
        'Lihat daftar pelanggan tetap & eceran DepotTelur36 yang tersimpan lokal.',
    ownerOnly: false,
  ),
  DashboardShortcutSpec(
    id: DashboardShortcutId.supplier,
    label: 'Supplier',
    description:
        'Lihat daftar kontak supplier untuk kebutuhan restock barang.',
    ownerOnly: false,
    targetTab: DashboardTabId.stok,
  ),
];

/// Mengembalikan 4 tab navigasi sesuai peran [role].
List<DashboardTabSpec> dashboardTabsForRole(UserRole role) {
  return role == UserRole.owner ? _ownerTabs : _operatorTabs;
}

/// Mengembalikan 4 shortcut grid beranda sesuai peran [role].
List<DashboardShortcutSpec> dashboardShortcutsForRole(UserRole role) {
  return role == UserRole.owner ? _ownerShortcuts : _operatorShortcuts;
}

/// Validasi RBAC apakah [role] diizinkan membuka [tabId].
bool isTabAllowedForRole(DashboardTabId tabId, UserRole role) {
  return dashboardTabsForRole(role).any((tab) => tab.id == tabId);
}

/// Validasi RBAC apakah [role] diizinkan mengeksekusi [shortcutId].
bool isShortcutAllowedForRole(DashboardShortcutId shortcutId, UserRole role) {
  return dashboardShortcutsForRole(role).any(
    (shortcut) => shortcut.id == shortcutId,
  );
}

final NumberFormat _idrNumberFormat = NumberFormat.decimalPattern('id_ID');

/// Batas aman integer presisi double IEEE-754 untuk pemformatan Rupiah.
const double kMaxSafeRupiahMagnitude = 900000000000000;

/// Memformat angka menjadi string Rupiah bersih (`Rp 28.500`), aman dari NaN/negatif ekstrem/overflow.
String formatRupiah(num value) {
  if (!value.isFinite) return 'Rp 0';
  final double bounded = value.toDouble();
  if (bounded.abs() > kMaxSafeRupiahMagnitude) {
    final clamped = bounded.isNegative
        ? -kMaxSafeRupiahMagnitude.round()
        : kMaxSafeRupiahMagnitude.round();
    final prefix = clamped < 0 ? '-Rp ' : 'Rp ';
    return '$prefix${_idrNumberFormat.format(clamped.abs())}+';
  }
  final rounded = bounded.round();
  final prefix = rounded < 0 ? '-Rp ' : 'Rp ';
  return '$prefix${_idrNumberFormat.format(rounded.abs())}';
}

/// Menormalkan dan membatasi panjang query pencarian agar aman diproses UI & filter.
String sanitizeSearchQuery(String raw) {
  final withoutInvisible = raw
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');
  final collapsed = withoutInvisible.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= kMaxSearchQueryLength) {
    return collapsed;
  }
  return collapsed.substring(0, kMaxSearchQueryLength).trimRight();
}
