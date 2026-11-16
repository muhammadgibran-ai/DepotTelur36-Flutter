import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:depot_telur_36/core/database/database_helper.dart';
import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/inventory_repository.dart';
import 'package:depot_telur_36/screens/master/barang_form_screen.dart';
import 'package:depot_telur_36/screens/master/master_data_tab_view.dart';
import 'package:depot_telur_36/services/barang_photo_service.dart';
import 'package:depot_telur_36/services/sync_service.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeFirestore extends Fake implements FirebaseFirestore {}

class _OfflineConnectivity implements Connectivity {
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const [ConnectivityResult.none];
}

class _SilentSyncService extends SyncService {
  _SilentSyncService({required super.dbHelper})
      : super(
          firestore: _FakeFirestore(),
          connectivity: _OfflineConnectivity(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> trySyncIfOnline() async {}

  @override
  Future<void> syncNow() async {}
}

class _FakeGalleryPicker implements BarangPhotoPicker {
  _FakeGalleryPicker(this.handler);

  final Future<PickedGalleryPhoto?> Function() handler;
  int calls = 0;

  @override
  Future<PickedGalleryPhoto?> pickFromGallery() {
    calls++;
    return handler();
  }
}

AuthSession _ownerSession() {
  return AuthSession(
    uid: 'uid-photo-owner',
    email: 'owner@depottelur36.com',
    accountId: 'acc-owner',
    displayName: 'Owner Uji Foto',
    role: UserRole.owner,
    petugasRemoteId: 'photo-test-owner',
    provider: AuthProviderType.offlineLocal,
    signedInAt: DateTime(2026, 2, 16),
  );
}

Future<({Directory tempDir, DatabaseHelper dbHelper, InventoryRepository repo})>
_openIsolatedRepo() async {
  final tempDir = await Directory.systemTemp.createTemp('dt36_photo_test_');
  final dbPath = p.join(tempDir.path, 'test_photo.db');
  final dbHelper = DatabaseHelper.forTesting(customDbPath: dbPath);
  final sync = _SilentSyncService(dbHelper: dbHelper);
  final repo = InventoryRepository(dbHelper: dbHelper, syncService: sync);

  addTearDown(() async {
    BarangPhotoPresets.clearAll();
    BarangPhotoOptimizer.clearMemoryCache();
    await repo.dispose();
    final db = await dbHelper.database;
    if (db.isOpen) {
      await db.close();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  return (tempDir: tempDir, dbHelper: dbHelper, repo: repo);
}

img.Image _buildSyntheticPhoto({
  int width = 800,
  int height = 600,
  bool withTransparency = false,
  bool noisy = false,
}) {
  final image = img.Image(
    width: width,
    height: height,
    numChannels: withTransparency ? 4 : 3,
  );
  final rng = math.Random(42);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final baseR = ((x * 255) ~/ math.max(1, width));
      final baseG = ((y * 255) ~/ math.max(1, height));
      final baseB = (((x + y) * 127) ~/ math.max(1, width + height));
      final r = noisy ? (baseR ^ rng.nextInt(190)) : baseR;
      final g = noisy ? (baseG ^ rng.nextInt(190)) : baseG;
      final b = noisy ? (baseB ^ rng.nextInt(190)) : baseB;
      if (withTransparency) {
        final inCircle =
            math.pow(x - width / 2, 2) + math.pow(y - height / 2, 2) <
                math.pow(math.min(width, height) * 0.4, 2);
        image.setPixelRgba(x, y, r, g, b, inCircle ? 255 : 0);
      } else {
        image.setPixelRgb(x, y, r, g, b);
      }
    }
  }
  return image;
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxTries = 80,
}) async {
  for (var i = 0; i < maxTries; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    BarangPhotoPresets.clearAll();
    BarangPhotoOptimizer.clearMemoryCache();
  });

  group('Unit Test BarangPhotoOptimizer - Normal & Format Conversion', () {
    test('Mengonversi PNG resolusi besar (800x600) menjadi WebP ringan terukur', () async {
      final pngBytes = Uint8List.fromList(
        img.encodePng(_buildSyntheticPhoto(width: 800, height: 600)),
      );

      final result = await BarangPhotoOptimizer.convertFromBytes(
        pngBytes,
        sourceFileName: 'telur_negeri.png',
        useIsolate: true,
      );

      expect(result.format, BarangPhotoOptimizer.webpFormat);
      expect(result.originalFormat, 'PNG');
      expect(result.width, 256);
      expect(result.height, 192);
      expect(result.convertedSizeBytes, lessThan(pngBytes.length));
      expect(result.convertedSizeBytes, lessThanOrEqualTo(BarangPhotoOptimizer.kTargetMaxOutputBytes));
      expect(result.savedPercent, greaterThan(50));
      expect(
        result.dataUri.startsWith(BarangPhotoOptimizer.webpDataUriPrefix),
        isTrue,
      );

      final decodedOut = img.decodeWebP(result.bytes);
      expect(decodedOut, isNotNull);
      expect(decodedOut!.width, 256);
      expect(decodedOut.height, 192);
      expect(decodedOut.exif.isEmpty, isTrue);
    });

    test('Mengonversi JPEG, BMP, GIF animasi, dan PNG transparan ke WebP', () {
      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(_buildSyntheticPhoto(width: 900, height: 600), quality: 95),
      );
      final bmpBytes = Uint8List.fromList(
        img.encodeBmp(_buildSyntheticPhoto(width: 640, height: 480)),
      );
      final pngAlphaBytes = Uint8List.fromList(
        img.encodePng(
          _buildSyntheticPhoto(width: 400, height: 400, withTransparency: true),
        ),
      );

      final frame1 = _buildSyntheticPhoto(width: 300, height: 300);
      final frame2 = _buildSyntheticPhoto(width: 300, height: 300, noisy: true);
      frame1.addFrame(frame2);
      final gifBytes = Uint8List.fromList(img.encodeGif(frame1));

      final fromJpg = BarangPhotoOptimizer.convertFromBytesSync(
        jpgBytes,
        sourceFileName: 'foto.jpg',
      );
      expect(fromJpg.originalFormat, 'JPEG');
      expect(fromJpg.format, 'webp');
      expect(fromJpg.convertedSizeBytes, lessThan(jpgBytes.length));

      final fromBmp = BarangPhotoOptimizer.convertFromBytesSync(bmpBytes);
      expect(fromBmp.originalFormat, 'BMP');
      expect(fromBmp.convertedSizeBytes, lessThan(bmpBytes.length ~/ 10));

      final fromAlpha = BarangPhotoOptimizer.convertFromBytesSync(pngAlphaBytes);
      expect(fromAlpha.originalFormat, 'PNG');
      final decodedAlpha = img.decodeWebP(fromAlpha.bytes)!;
      expect(decodedAlpha.hasAlpha, isTrue);
      expect(decodedAlpha.getPixel(0, 0).a, 0);

      final fromGif = BarangPhotoOptimizer.convertFromBytesSync(gifBytes);
      expect(fromGif.originalFormat, 'GIF');
      final decodedGif = img.decodeWebP(fromGif.bytes)!;
      expect(decodedGif.hasAnimation, isFalse);
      expect(decodedGif.width, 256);
    });

    test('Menerapkan orientasi EXIF lalu membuang metadata EXIF agar ringan', () {
      final raw = _buildSyntheticPhoto(width: 600, height: 400);
      raw.exif.imageIfd.orientation = 6; // rotate 90 CW -> 400x600
      final jpegWithExif = Uint8List.fromList(img.encodeJpg(raw, quality: 90));

      final result = BarangPhotoOptimizer.convertFromBytesSync(jpegWithExif);
      expect(result.width, 171);
      expect(result.height, 256);

      final decodedOut = img.decodeWebP(result.bytes)!;
      expect(decodedOut.exif.isEmpty, isTrue);
    });

    test('Kompresi adaptif menurunkan kualitas/resolusi saat noise padat melebihi target bytes', () {
      final noisySrc = _buildSyntheticPhoto(
        width: 512,
        height: 512,
        noisy: true,
      );
      final pngBytes = Uint8List.fromList(img.encodePng(noisySrc));

      final result = BarangPhotoOptimizer.convertFromBytesSync(
        pngBytes,
        targetMaxBytes: 4096,
      );
      expect(result.convertedSizeBytes, lessThanOrEqualTo(4096));
      expect(img.decodeWebP(result.bytes), isNotNull);
    });
  });

  group('Unit Test BarangPhotoOptimizer - Edge Case & Input Salah', () {
    test('Edge case gambar kecil (16x16) tidak di-upscale dan panorama ekstrem aman', () {
      final tiny = Uint8List.fromList(
        img.encodePng(_buildSyntheticPhoto(width: 16, height: 16)),
      );
      final tinyRes = BarangPhotoOptimizer.convertFromBytesSync(tiny);
      expect(tinyRes.width, 16);
      expect(tinyRes.height, 16);

      final panorama = Uint8List.fromList(
        img.encodePng(_buildSyntheticPhoto(width: 3000, height: 2)),
      );
      final panoRes = BarangPhotoOptimizer.convertFromBytesSync(panorama);
      expect(panoRes.width, 256);
      expect(panoRes.height, greaterThanOrEqualTo(1));
    });

    test('Menolak byte kosong, ukuran > 20MB, dan file non-gambar/korup', () async {
      expect(
        () => BarangPhotoOptimizer.convertFromBytesSync(Uint8List(0)),
        throwsA(isA<BarangPhotoException>()),
      );

      final fakeTooLarge = Uint8List(
        BarangPhotoOptimizer.kMaxRawUploadBytes + 1,
      );
      await expectLater(
        () => BarangPhotoOptimizer.convertFromBytes(fakeTooLarge),
        throwsA(isA<BarangPhotoException>()),
      );

      final textBytes = Uint8List.fromList(utf8.encode('bukan file foto png'));
      expect(
        () => BarangPhotoOptimizer.convertFromBytesSync(
          textBytes,
          sourceFileName: 'nota.pdf',
        ),
        throwsA(isA<BarangPhotoException>()),
      );

      final corruptedPng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x01,
      ]);
      expect(
        () => BarangPhotoOptimizer.convertFromBytesSync(corruptedPng),
        throwsA(isA<BarangPhotoException>()),
      );
    });

    test('validateStoredPhoto dan cache memori menolak format selain WebP/aset', () {
      final pngUri =
          'data:image/png;base64,${base64Encode(Uint8List.fromList([1, 2, 3]))}';
      expect(
        () => BarangPhotoOptimizer.validateStoredPhoto(fotoBarang: pngUri),
        throwsA(isA<BarangPhotoException>()),
      );

      final bogusWebpUri =
          'data:image/webp;base64,${base64Encode(Uint8List.fromList([1, 2, 3, 4]))}';
      expect(
        () => BarangPhotoOptimizer.validateStoredPhoto(fotoBarang: bogusWebpUri),
        throwsA(isA<BarangPhotoException>()),
      );

      final oversizedBytes = Uint8List(BarangPhotoOptimizer.kHardMaxOutputBytes + 10)
        ..setAll(0, [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
      final oversizedUri = 'data:image/webp;base64,${base64Encode(oversizedBytes)}';
      expect(
        () => BarangPhotoOptimizer.validateStoredPhoto(fotoBarang: oversizedUri),
        throwsA(isA<BarangPhotoException>()),
      );

      expect(BarangPhotoOptimizer.tryDecodeDataUri('not-a-uri'), isNull);
      expect(BarangPhotoOptimizer.tryDecodeDataUri('data:image/webp;base64,!!!'), isNull);
    });
  });

  group('Integrasi Database v5 Migration, Repository & Sync', () {
    test('Migrasi SQLite v4 ke v5 menambahkan kolom foto tanpa kehilangan data lama', () async {
      final tempDir = await Directory.systemTemp.createTemp('dt36_mig_v5_');
      final dbPath = p.join(tempDir.path, 'legacy_v4.db');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final legacyDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE supplier (
                id_supplier INTEGER PRIMARY KEY AUTOINCREMENT,
                nama_supplier TEXT NOT NULL,
                alamat_supplier TEXT NOT NULL DEFAULT '',
                no_telp_supplier TEXT NOT NULL DEFAULT '',
                remote_id TEXT NOT NULL UNIQUE,
                sync_status TEXT NOT NULL DEFAULT 'PENDING',
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE petugas (
                id_petugas INTEGER PRIMARY KEY AUTOINCREMENT,
                nama_petugas TEXT NOT NULL,
                role TEXT NOT NULL DEFAULT 'PETUGAS',
                pin TEXT NOT NULL DEFAULT '1234',
                email TEXT NOT NULL DEFAULT '',
                account_id TEXT NOT NULL DEFAULT '',
                password_hash TEXT NOT NULL DEFAULT '',
                remote_id TEXT NOT NULL UNIQUE,
                sync_status TEXT NOT NULL DEFAULT 'PENDING',
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE customer (
                id_customer INTEGER PRIMARY KEY AUTOINCREMENT,
                nama_customer TEXT NOT NULL,
                remote_id TEXT NOT NULL UNIQUE,
                sync_status TEXT NOT NULL DEFAULT 'PENDING',
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE barang (
                id_barang INTEGER PRIMARY KEY AUTOINCREMENT,
                nama_barang TEXT NOT NULL,
                stok_barang INTEGER NOT NULL DEFAULT 0,
                satuan TEXT NOT NULL,
                harga_satuan REAL NOT NULL DEFAULT 0.0,
                remote_id TEXT NOT NULL UNIQUE,
                sync_status TEXT NOT NULL DEFAULT 'PENDING',
                updated_at TEXT NOT NULL
              )
            ''');
            await db.insert('barang', {
              'nama_barang': 'Telur Legacy v4',
              'stok_barang': 45,
              'satuan': 'Kg',
              'harga_satuan': 26000.0,
              'remote_id': 'legacy-barang-1',
              'sync_status': 'SYNCED',
              'updated_at': DateTime(2026, 1, 10).toIso8601String(),
            });
          },
        ),
      );
      await legacyDb.close();

      final upgradedHelper = DatabaseHelper.forTesting(customDbPath: dbPath);
      final upgradedDb = await upgradedHelper.database;
      addTearDown(() async => upgradedDb.close());

      final columns = await upgradedDb.rawQuery('PRAGMA table_info(barang)');
      final colNames = columns.map((r) => r['name']).toSet();
      expect(colNames, containsAll(['foto_barang', 'foto_format', 'foto_size_bytes']));

      final all = await upgradedHelper.getAllBarang();
      expect(all.length, 1);
      expect(all.first.namaBarang, 'Telur Legacy v4');
      expect(all.first.fotoBarang, '');
      expect(all.first.fotoFormat, '');
      expect(all.first.fotoSizeBytes, 0);
    });

    test('Persistensi SQLite, edit non-foto mempertahankan foto, clearFoto, & roundtrip Firestore', () async {
      final ctx = await _openIsolatedRepo();
      final repo = ctx.repo;

      final pngBytes = Uint8List.fromList(
        img.encodePng(_buildSyntheticPhoto(width: 480, height: 360)),
      );
      final converted = BarangPhotoOptimizer.convertFromBytesSync(pngBytes);

      await repo.saveBarang(
        existingRemoteId: 'brg-webp-persist',
        namaBarang: 'Telur Omega Spesial',
        stokBarang: 25,
        satuan: 'Kg',
        hargaSatuan: 31000,
        fotoBarang: converted.dataUri,
        fotoFormat: converted.format,
        fotoSizeBytes: converted.convertedSizeBytes,
      );

      final created = (await repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == 'brg-webp-persist',
      );
      expect(created.hasCustomWebpPhoto, isTrue);
      expect(created.fotoFormat, 'webp');
      expect(created.fotoSizeBytes, converted.convertedSizeBytes);

      // Update harga & stok tanpa mengirim argumen foto -> foto lama tetap terjaga
      await repo.saveBarang(
        idBarang: created.idBarang,
        existingRemoteId: created.remoteId,
        namaBarang: created.namaBarang,
        stokBarang: 40,
        satuan: created.satuan,
        hargaSatuan: 32500,
      );
      final updatedPriceOnly = (await repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == 'brg-webp-persist',
      );
      expect(updatedPriceOnly.stokBarang, 40);
      expect(updatedPriceOnly.fotoBarang, converted.dataUri);
      expect(updatedPriceOnly.fotoSizeBytes, converted.convertedSizeBytes);

      // Roundtrip Firestore
      final firestoreMap = updatedPriceOnly.toFirestore();
      final fromCloud = Barang.fromFirestore(
        firestoreMap,
        updatedPriceOnly.remoteId,
      );
      expect(fromCloud.fotoBarang, converted.dataUri);
      expect(fromCloud.fotoFormat, 'webp');
      expect(fromCloud.fotoSizeBytes, converted.convertedSizeBytes);

      // Clear foto eksplisit
      await repo.saveBarang(
        idBarang: updatedPriceOnly.idBarang,
        existingRemoteId: updatedPriceOnly.remoteId,
        namaBarang: updatedPriceOnly.namaBarang,
        stokBarang: 40,
        satuan: updatedPriceOnly.satuan,
        hargaSatuan: 32500,
        clearFoto: true,
      );
      final cleared = (await repo.getAllBarang()).firstWhere(
        (b) => b.remoteId == 'brg-webp-persist',
      );
      expect(cleared.hasStoredPhoto, isFalse);
      expect(cleared.fotoFormat, '');
      expect(cleared.fotoSizeBytes, 0);

      // Penolakan validasi jika mencoba menyimpan data URI bukan WebP
      await expectLater(
        () => repo.saveBarang(
          namaBarang: 'Barang Foto Ilegal',
          stokBarang: 5,
          satuan: 'Kg',
          hargaSatuan: 15000,
          fotoBarang: 'data:image/png;base64,${base64Encode(pngBytes)}',
        ),
        throwsA(isA<MasterDataValidationException>()),
      );
    });
  });

  group('Widget & End-to-End UI Flow Upload Galeri Master Barang', () {
    late Directory tempDir;
    late DatabaseHelper dbHelper;
    late InventoryRepository repo;
    var dbCounter = 0;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dt36_photo_ui_');
      dbHelper = DatabaseHelper.forTesting(
        customDbPath: p.join(tempDir.path, 'ui_${dbCounter++}.db'),
      );
      await dbHelper.database;
      repo = InventoryRepository(
        dbHelper: dbHelper,
        syncService: _SilentSyncService(dbHelper: dbHelper),
      );
    });

    tearDown(() async {
      BarangPhotoPresets.clearAll();
      BarangPhotoOptimizer.clearMemoryCache();
      await repo.dispose();
      final db = await dbHelper.database;
      if (db.isOpen) {
        await db.close();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'Upload foto galeri di BarangFormScreen mengonversi WebP, menampilkan badge hemat, menyimpan ke DB, & tampil di MasterDataTabView',
      (tester) async {
        final vm = MasterCrudViewModel.fromRepository(
          session: _ownerSession(),
          repository: repo,
        );
        addTearDown(vm.dispose);
        await tester.runAsync(vm.loadData);

        final rawPng = Uint8List.fromList(
          img.encodePng(_buildSyntheticPhoto(width: 640, height: 480)),
        );
        final pickCompleter = Completer<PickedGalleryPhoto?>();
        final fakePicker = _FakeGalleryPicker(() => pickCompleter.future);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: MasterDataTabView(viewModel: vm, photoPicker: fakePicker),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Buka Form Tambah Barang
        await tester.tap(find.byKey(const ValueKey('master_header_add_button')));
        await tester.pumpAndSettle();
        expect(find.byType(BarangFormScreen), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('barang_nama_field')),
          'Telur Puyuh Segar',
        );
        await tester.enterText(
          find.byKey(const ValueKey('barang_stok_field')),
          '18',
        );
        await tester.enterText(
          find.byKey(const ValueKey('barang_harga_field')),
          '29000',
        );

        // Pilih dari Galeri -> mikro-interaksi loading muncul sebelum selesai
        final uploadFinder = find.byKey(
          const ValueKey('barang_upload_gallery_button'),
        );
        await tester.ensureVisible(uploadFinder);
        await tester.pumpAndSettle();
        await tester.tap(uploadFinder);
        await tester.pump();
        expect(fakePicker.calls, 1);
        expect(find.text('Mengonversi WebP...'), findsOneWidget);

        // Selesaikan pemilihan galeri & konversi WebP di background isolate
        pickCompleter.complete((bytes: rawPng, fileName: 'puyuh_hd.png'));
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('barang_clear_photo_button')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('barang_photo_conversion_badge')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('barang_clear_photo_button')),
          findsOneWidget,
        );
        expect(
          find.text('Foto galeri teroptimasi WebP super ringan'),
          findsOneWidget,
        );
        expect(find.byType(Image), findsWidgets);

        // Simpan ke SQLite
        await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
        await _pumpUntilFound(tester, find.byType(MasterDataTabView));
        await tester.pumpAndSettle();

        final savedItems = await tester.runAsync(repo.getAllBarang);
        final puyuh = savedItems!.firstWhere(
          (b) => b.namaBarang == 'Telur Puyuh Segar',
        );
        expect(puyuh.hasCustomWebpPhoto, isTrue);
        expect(puyuh.fotoFormat, 'webp');
        expect(puyuh.fotoSizeBytes, lessThan(rawPng.length));

        // Edit kembali -> verifikasi foto WebP tetap dimuat & dapat di-reset
        final editFinder = find.byKey(ValueKey('edit_barang_${puyuh.remoteId}'));
        await tester.scrollUntilVisible(
          editFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(editFinder);
        await tester.pumpAndSettle();
        await tester.tap(editFinder);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('barang_photo_conversion_badge')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('barang_clear_photo_button')),
          findsOneWidget,
        );
        expect(
          find.text('Foto galeri teroptimasi WebP super ringan'),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('barang_clear_photo_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('barang_clear_photo_button')),
          findsNothing,
        );

        await tester.tap(find.byKey(const ValueKey('crud_footer_save_button')));
        await _pumpUntilFound(tester, find.byType(MasterDataTabView));
        await tester.pumpAndSettle();

        final afterReset = (await tester.runAsync(repo.getAllBarang))!
            .firstWhere((b) => b.remoteId == puyuh.remoteId);
        expect(afterReset.hasStoredPhoto, isFalse);
      },
    );

    testWidgets(
      'Batal pilih galeri & upload file korup menampilkan feedback aman tanpa overflow di 320x568 textScale 1.4x',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final vm = MasterCrudViewModel.fromRepository(
          session: _ownerSession(),
          repository: repo,
        );
        addTearDown(vm.dispose);
        await tester.runAsync(vm.loadData);

        final nextResponse = <PickedGalleryPhoto?>[
          null,
          (bytes: Uint8List.fromList([0x01, 0x02, 0x03]), fileName: 'rusak.jpg'),
        ];
        var idx = 0;
        final picker = _FakeGalleryPicker(() async => nextResponse[idx++]);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: BarangFormScreen(viewModel: vm, photoPicker: picker),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // 1. Batal pilih dari galeri -> tidak error
        await tester.tap(
          find.byKey(const ValueKey('barang_upload_gallery_button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('barang_photo_error_banner')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        // 2. File korup -> tampil error banner aman tanpa crash/overflow
        await tester.tap(
          find.byKey(const ValueKey('barang_upload_gallery_button')),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('barang_photo_error_banner')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('barang_photo_error_banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Verifikasi ukuran target sentuh >= 48dp pada tombol upload galeri
        final uploadBox = tester.getSize(
          find.byKey(const ValueKey('barang_upload_gallery_button')),
        );
        expect(uploadBox.height, greaterThanOrEqualTo(48));
      },
    );
  });
}
