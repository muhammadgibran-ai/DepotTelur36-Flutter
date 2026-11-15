import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';

/// Pemetaan aset gambar lokal untuk produk & ilustrasi banner `.pen`.
class DashboardAssets {
  DashboardAssets._();

  static const String bannerOwner = 'assets/images/banner_owner.png';
  static const String bannerOperator = 'assets/images/banner_operator.png';
  static const String thumbTelurNegeri = 'assets/images/thumb_telur_negeri.png';
  static const String thumbTelurTray = 'assets/images/thumb_telur_tray.png';
  static const String thumbTelurKampung = 'assets/images/thumb_telur_kampung.png';
  static const String thumbTelurBebek = 'assets/images/thumb_telur_bebek.png';
  static const String thumbBeras = 'assets/images/thumb_beras.png';
  static const String thumbMinyak = 'assets/images/thumb_minyak.png';

  /// Mengembalikan path aset thumbnail paling sesuai untuk [barang].
  static String? assetPathForBarang(Barang barang) {
    switch (barang.remoteId) {
      case 'seed-barang-telur-negeri-kg':
        return thumbTelurNegeri;
      case 'seed-barang-telur-negeri-tray':
        return thumbTelurTray;
      case 'seed-barang-telur-kampung':
        return thumbTelurKampung;
      case 'seed-barang-telur-bebek':
        return thumbTelurBebek;
      case 'seed-barang-beras-5kg':
        return thumbBeras;
      case 'seed-barang-minyak-1l':
        return thumbMinyak;
    }

    final lower = barang.namaBarang.toLowerCase();
    if (lower.contains('tray')) return thumbTelurTray;
    if (lower.contains('kampung')) return thumbTelurKampung;
    if (lower.contains('bebek')) return thumbTelurBebek;
    if (lower.contains('telur')) return thumbTelurNegeri;
    if (lower.contains('beras')) return thumbBeras;
    if (lower.contains('minyak')) return thumbMinyak;
    return null;
  }
}

/// Ilustrasi banner peran pada kartu sambutan gelap (`05 Home - Owner` / `06 Home - Operator`).
class RoleBannerIllustration extends StatelessWidget {
  const RoleBannerIllustration({
    super.key,
    required this.isOwner,
    this.size = 104,
  });

  final bool isOwner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final assetPath =
        isOwner ? DashboardAssets.bannerOwner : DashboardAssets.bannerOperator;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Icon(
              isOwner ? Icons.egg_rounded : Icons.shopping_basket_rounded,
              size: size * 0.44,
              color: AppColors.yolk,
            ),
          );
        },
      ),
    );
  }
}

/// Thumbnail produk 44x44 pada kartu stok menipis & daftar ketersediaan barang.
class BarangThumbnail extends StatelessWidget {
  const BarangThumbnail({
    super.key,
    required this.barang,
    this.size = 44,
    this.radius = 12,
  });

  final Barang barang;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final assetPath = DashboardAssets.assetPathForBarang(barang);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: assetPath == null
          ? _fallbackIcon()
          : Image.asset(
              assetPath,
              width: size,
              height: size,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
            ),
    );
  }

  Widget _fallbackIcon() {
    final isEgg = barang.namaBarang.toLowerCase().contains('telur');
    return Center(
      child: Icon(
        isEgg ? Icons.egg_rounded : Icons.inventory_2_rounded,
        size: size * 0.5,
        color: AppColors.yolkPressed,
      ),
    );
  }
}
