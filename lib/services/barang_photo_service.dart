import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Hasil media mentah yang dipilih pengguna dari galeri perangkat.
typedef PickedGalleryPhoto = ({Uint8List bytes, String fileName});

/// Pengecualian khusus saat memilih, memvalidasi, atau mengonversi foto barang.
class BarangPhotoException implements Exception {
  const BarangPhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Kontrak pemilih media galeri agar mudah diuji secara deterministik.
abstract class BarangPhotoPicker {
  Future<PickedGalleryPhoto?> pickFromGallery();
}

/// Implementasi produksi pemilih media galeri via Android/iOS/Desktop System Photo Picker.
class ImagePickerBarangPhotoPicker implements BarangPhotoPicker {
  ImagePickerBarangPhotoPicker({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedGalleryPhoto?> pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Batasi pembacaan bitmap awal agar foto 48MP tidak membebani memori VM
        // sebelum dikonversi ulang menjadi WebP ringan oleh BarangPhotoOptimizer.
        maxWidth: 1024,
        maxHeight: 1024,
        requestFullMetadata: false,
      );
      if (picked == null) return null;

      final bytes = await picked.readAsBytes();
      return (bytes: bytes, fileName: picked.name);
    } on PlatformException catch (e) {
      throw BarangPhotoException(
        e.message?.trim().isNotEmpty == true
            ? 'Gagal mengakses galeri: ${e.message}'
            : 'Izin akses galeri ditolak atau tidak tersedia.',
      );
    } catch (_) {
      throw const BarangPhotoException(
        'Gagal membaca media yang dipilih dari galeri.',
      );
    }
  }
}

/// Metadata & payload hasil konversi foto galeri ke format WebP paling ringan.
class ConvertedBarangPhoto {
  const ConvertedBarangPhoto({
    required this.bytes,
    required this.dataUri,
    required this.format,
    required this.originalFormat,
    required this.originalSizeBytes,
    required this.convertedSizeBytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String dataUri;
  final String format;
  final String originalFormat;
  final int originalSizeBytes;
  final int convertedSizeBytes;
  final int width;
  final int height;

  double get savedRatio {
    if (originalSizeBytes <= 0 || convertedSizeBytes >= originalSizeBytes) {
      return 0;
    }
    return ((originalSizeBytes - convertedSizeBytes) / originalSizeBytes)
        .clamp(0.0, 1.0);
  }

  int get savedPercent => (savedRatio * 100).round();

  String get telemetryLabel {
    final sizeText = BarangPhotoOptimizer.formatByteSize(convertedSizeBytes);
    final saved = savedPercent;
    if (saved > 0) {
      return 'WebP $width×$height · $sizeText (hemat $saved% dari $originalFormat)';
    }
    return 'WebP $width×$height · $sizeText';
  }
}

/// Konverter, validator, & cache memori foto produk agar aplikasi tetap ringan & 60fps.
class BarangPhotoOptimizer {
  BarangPhotoOptimizer._();

  static const String webpFormat = 'webp';
  static const String assetFormat = 'asset';
  static const String webpDataUriPrefix = 'data:image/webp;base64,';

  /// Batas mentah maksimal 20 MB agar berkas korup/terlampau besar tidak memicu OOM.
  static const int kMaxRawUploadBytes = 20 * 1024 * 1024;

  /// Batas dimensi dekode awal untuk mencegah decompression bomb.
  static const int kMaxInputDimension = 8192;
  static const int kMaxInputPixels = 36000000;

  /// Resolusi optimal thumbnail & preview produk (cukup tajam hingga 3x DPR pada 64dp).
  static const int kTargetMaxDimension = 256;

  /// Target anggaran ukuran ringan per foto (~24 KB) dan batas keras (~64 KB)
  /// agar query SQLite massal dan sinkronisasi Firestore tetap cepat & hemat kuota.
  static const int kTargetMaxOutputBytes = 24 * 1024;
  static const int kHardMaxOutputBytes = 64 * 1024;

  static const int _maxCacheEntries = 128;
  static final LinkedHashMap<String, Uint8List> _decodedCache =
      LinkedHashMap<String, Uint8List>();

  /// Mengonversi foto galeri dari format apa pun (PNG/JPG/BMP/GIF/TIFF/WebP/dll)
  /// ke lossy WebP terkompresi di isolate terpisah agar UI tetap responsif.
  static Future<ConvertedBarangPhoto> convertFromBytes(
    Uint8List rawBytes, {
    String? sourceFileName,
    bool useIsolate = true,
    int maxDimension = kTargetMaxDimension,
    int targetMaxBytes = kTargetMaxOutputBytes,
  }) async {
    _validateRawInputBytes(rawBytes);

    final request = _ConversionRequest(
      rawBytes: rawBytes,
      sourceFileName: sourceFileName,
      maxDimension: maxDimension,
      targetMaxBytes: targetMaxBytes,
    );

    if (useIsolate && !kIsWeb) {
      return compute(_runConversionInIsolate, request);
    }
    return convertFromBytesSync(
      rawBytes,
      sourceFileName: sourceFileName,
      maxDimension: maxDimension,
      targetMaxBytes: targetMaxBytes,
    );
  }

  /// Versi sinkron untuk eksekusi langsung maupun dalam background isolate.
  static ConvertedBarangPhoto convertFromBytesSync(
    Uint8List rawBytes, {
    String? sourceFileName,
    int maxDimension = kTargetMaxDimension,
    int targetMaxBytes = kTargetMaxOutputBytes,
  }) {
    _validateRawInputBytes(rawBytes);
    if (maxDimension < 32 || targetMaxBytes < 1024) {
      throw const BarangPhotoException('Parameter konversi foto tidak valid.');
    }

    final decoder = img.findDecoderForData(rawBytes);
    if (decoder == null) {
      throw const BarangPhotoException(
        'Format media tidak didukung atau file rusak. Pilih gambar JPG, PNG, WebP, GIF, BMP, atau TIFF.',
      );
    }

    final originalFormat = _resolveFormatLabel(
      decoder.format,
      sourceFileName: sourceFileName,
    );

    final img.DecodeInfo? info;
    try {
      info = decoder.startDecode(rawBytes);
    } catch (_) {
      throw const BarangPhotoException(
        'File gambar tidak dapat dibaca atau rusak.',
      );
    }

    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > kMaxInputDimension ||
        info.height > kMaxInputDimension ||
        info.width * info.height > kMaxInputPixels) {
      throw const BarangPhotoException(
        'Dimensi gambar tidak valid atau melebihi batas aman pemrosesan.',
      );
    }

    final img.Image? decoded;
    try {
      // Dekode frame 0 saja agar GIF/WebP animasi tidak memboroskan RAM.
      decoded = decoder.decode(rawBytes, frame: 0);
    } catch (_) {
      throw const BarangPhotoException(
        'Gagal mendekode isi file foto. Pastikan file gambar tidak korup.',
      );
    }

    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw const BarangPhotoException(
        'File gambar kosong atau tidak memiliki piksel valid.',
      );
    }

    img.Image normalized = img.bakeOrientation(decoded);
    // Konversi ke 8-bit RGB/RGBA standar sebelum resize & VP8 encoding agar
    // gambar palette/grayscale/16-bit terkompresi konsisten tanpa artefak.
    if (normalized.hasPalette ||
        normalized.format != img.Format.uint8 ||
        normalized.numChannels < 3) {
      normalized = normalized.convert(
        format: img.Format.uint8,
        numChannels: normalized.hasAlpha ? 4 : 3,
      );
    }

    final passes = <({int dimension, int quality, int alphaQuality})>[
      (dimension: maxDimension, quality: 72, alphaQuality: 70),
      (dimension: maxDimension, quality: 54, alphaQuality: 55),
      (dimension: math.min(maxDimension, 192), quality: 46, alphaQuality: 45),
      (dimension: math.min(maxDimension, 128), quality: 34, alphaQuality: 35),
      (dimension: math.min(maxDimension, 96), quality: 22, alphaQuality: 25),
    ];

    Uint8List? bestBytes;
    int finalWidth = normalized.width;
    int finalHeight = normalized.height;

    for (final pass in passes) {
      final candidateImage = _resizeIfLarger(normalized, pass.dimension);
      // Hapus seluruh metadata EXIF & ICC agar ukuran payload WebP minimal.
      candidateImage.exif = img.ExifData();
      candidateImage.iccProfile = null;

      final encoded = img.WebPEncoder(
        lossless: false,
        exact: false,
        quality: pass.quality,
        method: 4,
        alphaQuality: pass.alphaQuality,
      ).encode(candidateImage, singleFrame: true);

      if (encoded.isEmpty) continue;

      bestBytes = encoded;
      finalWidth = candidateImage.width;
      finalHeight = candidateImage.height;

      if (encoded.length <= targetMaxBytes) {
        break;
      }
    }

    if (bestBytes == null || bestBytes.isEmpty) {
      throw const BarangPhotoException(
        'Gagal mengonversi foto ke format WebP ringan.',
      );
    }
    if (bestBytes.length > kHardMaxOutputBytes) {
      throw const BarangPhotoException(
        'Ukuran hasil kompresi foto masih melebihi batas 64 KB. Pilih foto lain yang lebih sederhana.',
      );
    }

    final dataUri = '$webpDataUriPrefix${base64Encode(bestBytes)}';
    _putInCache(dataUri, bestBytes);

    return ConvertedBarangPhoto(
      bytes: bestBytes,
      dataUri: dataUri,
      format: webpFormat,
      originalFormat: originalFormat,
      originalSizeBytes: rawBytes.length,
      convertedSizeBytes: bestBytes.length,
      width: finalWidth,
      height: finalHeight,
    );
  }

  /// Memvalidasi nilai kolom `foto_barang` sebelum disimpan ke database lokal/cloud.
  static ({String fotoBarang, String fotoFormat, int fotoSizeBytes})
      validateStoredPhoto({
    required String fotoBarang,
    String? fotoFormat,
    int? fotoSizeBytes,
  }) {
    final trimmed = fotoBarang.trim();
    if (trimmed.isEmpty) {
      return (fotoBarang: '', fotoFormat: '', fotoSizeBytes: 0);
    }

    if (trimmed.startsWith('assets/')) {
      if (trimmed.length > 256 || trimmed.contains('\n') || trimmed.contains('\r')) {
        throw const BarangPhotoException('Path preset foto barang tidak valid.');
      }
      return (
        fotoBarang: trimmed,
        fotoFormat: assetFormat,
        fotoSizeBytes: 0,
      );
    }

    if (!trimmed.startsWith('data:image/')) {
      throw const BarangPhotoException(
        'Format foto barang tersimpan harus berupa WebP ringan atau preset aset.',
      );
    }

    final commaIdx = trimmed.indexOf(',');
    if (commaIdx <= 0 || !trimmed.substring(0, commaIdx).contains(';base64')) {
      throw const BarangPhotoException('Encoding data foto barang tidak valid.');
    }

    final mimeLower = trimmed
        .substring('data:image/'.length, commaIdx)
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (mimeLower != webpFormat) {
      throw const BarangPhotoException(
        'Foto galeri harus dikonversi ke format WebP ringan sebelum disimpan.',
      );
    }

    final payload = trimmed.substring(commaIdx + 1).trim();
    if (payload.isEmpty) {
      throw const BarangPhotoException('Data foto WebP kosong.');
    }

    final Uint8List decodedBytes;
    try {
      decodedBytes = base64Decode(payload);
    } catch (_) {
      throw const BarangPhotoException('Data base64 foto barang rusak.');
    }

    if (decodedBytes.isEmpty || decodedBytes.length > kHardMaxOutputBytes) {
      throw const BarangPhotoException(
        'Ukuran foto WebP melebihi batas ringan maksimal 64 KB.',
      );
    }

    if (!_looksLikeRiffWebp(decodedBytes)) {
      throw const BarangPhotoException('Header biner WebP foto tidak valid.');
    }

    _putInCache(trimmed, decodedBytes);
    return (
      fotoBarang: trimmed,
      fotoFormat: webpFormat,
      fotoSizeBytes: fotoSizeBytes != null && fotoSizeBytes > 0
          ? fotoSizeBytes
          : decodedBytes.length,
    );
  }

  /// Mengambil byte foto dari Data URI dengan cache LRU agar ListView scroll mulus.
  static Uint8List? tryDecodeDataUri(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('data:image/')) return null;

    final cached = _decodedCache.remove(trimmed);
    if (cached != null) {
      _decodedCache[trimmed] = cached;
      return cached;
    }

    final commaIdx = trimmed.indexOf(',');
    if (commaIdx <= 0 || commaIdx >= trimmed.length - 1) return null;

    try {
      final bytes = base64Decode(trimmed.substring(commaIdx + 1));
      if (bytes.isEmpty) return null;
      _putInCache(trimmed, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static void clearMemoryCache() {
    _decodedCache.clear();
  }

  static String formatByteSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 10) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    if (kb < 1024) {
      return '${kb.round()} KB';
    }
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  static void _validateRawInputBytes(Uint8List rawBytes) {
    if (rawBytes.isEmpty) {
      throw const BarangPhotoException('File foto kosong atau gagal dibaca.');
    }
    if (rawBytes.length > kMaxRawUploadBytes) {
      throw const BarangPhotoException(
        'Ukuran file foto terlalu besar (maksimal 20 MB).',
      );
    }
  }

  static img.Image _resizeIfLarger(img.Image source, int maxDimension) {
    final longest = math.max(source.width, source.height);
    if (longest <= maxDimension) {
      return source.clone(noAnimation: true);
    }
    final scale = maxDimension / longest;
    final targetWidth = math.max(1, (source.width * scale).round());
    final targetHeight = math.max(1, (source.height * scale).round());
    return img.copyResize(
      source,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
  }

  static String _resolveFormatLabel(
    img.ImageFormat format, {
    String? sourceFileName,
  }) {
    switch (format) {
      case img.ImageFormat.jpg:
        return 'JPEG';
      case img.ImageFormat.png:
        return 'PNG';
      case img.ImageFormat.webp:
        return 'WebP';
      case img.ImageFormat.gif:
        return 'GIF';
      case img.ImageFormat.bmp:
        return 'BMP';
      case img.ImageFormat.tiff:
        return 'TIFF';
      case img.ImageFormat.tga:
        return 'TGA';
      case img.ImageFormat.ico:
        return 'ICO';
      case img.ImageFormat.psd:
        return 'PSD';
      case img.ImageFormat.pvr:
        return 'PVR';
      case img.ImageFormat.exr:
        return 'EXR';
      case img.ImageFormat.cur:
        return 'CUR';
      case img.ImageFormat.pnm:
        return 'PNM';
      case img.ImageFormat.custom:
      case img.ImageFormat.invalid:
        final ext = sourceFileName?.split('.').last.trim().toUpperCase();
        if (ext != null && ext.isNotEmpty && ext.length <= 6) {
          return ext;
        }
        return 'Media';
    }
  }

  static bool _looksLikeRiffWebp(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50; // P
  }

  static void _putInCache(String key, Uint8List bytes) {
    _decodedCache.remove(key);
    _decodedCache[key] = bytes;
    while (_decodedCache.length > _maxCacheEntries) {
      _decodedCache.remove(_decodedCache.keys.first);
    }
  }
}

class _ConversionRequest {
  const _ConversionRequest({
    required this.rawBytes,
    required this.sourceFileName,
    required this.maxDimension,
    required this.targetMaxBytes,
  });

  final Uint8List rawBytes;
  final String? sourceFileName;
  final int maxDimension;
  final int targetMaxBytes;
}

ConvertedBarangPhoto _runConversionInIsolate(_ConversionRequest request) {
  return BarangPhotoOptimizer.convertFromBytesSync(
    request.rawBytes,
    sourceFileName: request.sourceFileName,
    maxDimension: request.maxDimension,
    targetMaxBytes: request.targetMaxBytes,
  );
}
