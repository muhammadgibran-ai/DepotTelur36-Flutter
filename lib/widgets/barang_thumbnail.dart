import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/services/barang_photo_service.dart';

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
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final cachePx = (size * dpr).round().clamp(48, 512);

    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: BarangPhotoPresets.customAssetsListenable,
      builder: (context, overrides, _) {
        final memoryBytes = barang.hasCustomWebpPhoto
            ? BarangPhotoOptimizer.tryDecodeDataUri(barang.fotoBarang)
            : null;
        final fallbackAssetPath = overrides[barang.remoteId] ??
            (barang.hasPersistedPresetPhoto ? barang.fotoBarang.trim() : null) ??
            DashboardAssets.assetPathForBarang(barang);

        Widget child;
        if (memoryBytes != null) {
          child = Image.memory(
            memoryBytes,
            width: size,
            height: size,
            cacheWidth: cachePx,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => _assetOrFallback(
              fallbackAssetPath,
              cachePx: cachePx,
            ),
          );
        } else {
          child = _assetOrFallback(fallbackAssetPath, cachePx: cachePx);
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }

  Widget _assetOrFallback(String? assetPath, {required int cachePx}) {
    if (assetPath == null) return _fallbackIcon();
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      cacheWidth: cachePx,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => _fallbackIcon(),
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

/// Pilihan preset foto lokal untuk barang tanpa mengubah skema kolom PDM SQLite.
class BarangPhotoPresets {
  BarangPhotoPresets._();

  static const List<({String label, String assetPath})> options = [
    (label: 'Telur Negeri', assetPath: DashboardAssets.thumbTelurNegeri),
    (label: 'Telur 1 Tray', assetPath: DashboardAssets.thumbTelurTray),
    (label: 'Telur Kampung', assetPath: DashboardAssets.thumbTelurKampung),
    (label: 'Telur Bebek', assetPath: DashboardAssets.thumbTelurBebek),
    (label: 'Beras', assetPath: DashboardAssets.thumbBeras),
    (label: 'Minyak Goreng', assetPath: DashboardAssets.thumbMinyak),
  ];

  static final ValueNotifier<Map<String, String>> customAssetsListenable =
      ValueNotifier<Map<String, String>>(<String, String>{});

  static String? resolveAssetPath(Barang barang) {
    return customAssetsListenable.value[barang.remoteId] ??
        (barang.hasPersistedPresetPhoto ? barang.fotoBarang.trim() : null) ??
        DashboardAssets.assetPathForBarang(barang);
  }

  static void setAssetForRemoteId(String remoteId, String? assetPath) {
    final trimmedId = remoteId.trim();
    if (trimmedId.isEmpty) return;
    final next = Map<String, String>.from(customAssetsListenable.value);
    if (assetPath == null || assetPath.trim().isEmpty) {
      next.remove(trimmedId);
    } else {
      next[trimmedId] = assetPath;
    }
    customAssetsListenable.value = Map.unmodifiable(next);
  }

  static void clearAll() {
    customAssetsListenable.value = <String, String>{};
  }
}
