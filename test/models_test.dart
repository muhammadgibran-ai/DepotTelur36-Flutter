import 'package:flutter_test/flutter_test.dart';

import 'package:depot_telur_36/models/auth_session.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';

void main() {
  final fixedTime = DateTime(2026, 2, 16, 8, 30);

  group('SyncStatus & UserRole', () {
    test('parses valid and fallback enum values', () {
      expect(SyncStatus.fromString('SYNCED'), SyncStatus.synced);
      expect(SyncStatus.fromString('PENDING'), SyncStatus.pending);
      expect(SyncStatus.fromString(null), SyncStatus.pending);

      expect(UserRole.fromString('OWNER'), UserRole.owner);
      expect(UserRole.fromString('PETUGAS'), UserRole.petugas);
      expect(UserRole.fromString('unknown'), UserRole.petugas);
    });
  });

  group('Master Models (SQLite & Firestore serialization)', () {
    test('Barang roundtrip & low stock detection', () {
      final barang = Barang(
        idBarang: 1,
        namaBarang: 'Telur Ayam Negeri',
        stokBarang: 8,
        satuan: 'Kg',
        hargaSatuan: 28500.0,
        remoteId: 'brg-1',
        syncStatus: SyncStatus.pending,
        updatedAt: fixedTime,
      );

      expect(barang.isLowStock, isTrue);

      final fromSqlite = Barang.fromMap(barang.toMap());
      expect(fromSqlite.idBarang, 1);
      expect(fromSqlite.namaBarang, 'Telur Ayam Negeri');
      expect(fromSqlite.stokBarang, 8);
      expect(fromSqlite.hargaSatuan, 28500.0);
      expect(fromSqlite.syncStatus, SyncStatus.pending);

      final fromCloud = Barang.fromFirestore(barang.toFirestore(), 'brg-1');
      expect(fromCloud.remoteId, 'brg-1');
      expect(fromCloud.syncStatus, SyncStatus.synced);
      expect(fromCloud.copyWith(stokBarang: 20).isLowStock, isFalse);
    });

    test('Supplier, Petugas, & Customer roundtrip', () {
      final supplier = Supplier(
        idSupplier: 2,
        namaSupplier: 'Peternakan Makmur',
        alamatSupplier: 'Jl. Raya 1',
        noTelpSupplier: '08123',
        remoteId: 'sup-2',
        updatedAt: fixedTime,
      );
      expect(Supplier.fromMap(supplier.toMap()).namaSupplier, 'Peternakan Makmur');
      expect(
        Supplier.fromFirestore(supplier.toFirestore(), 'sup-2').syncStatus,
        SyncStatus.synced,
      );

      final petugas = Petugas(
        idPetugas: 1,
        namaPetugas: 'Owner DepotTelur36',
        role: UserRole.owner,
        pin: '1234',
        remoteId: 'ptg-1',
        updatedAt: fixedTime,
      );
      expect(petugas.isOwner, isTrue);
      expect(Petugas.fromMap(petugas.toMap()).role, UserRole.owner);

      final customer = Customer(
        idCustomer: 5,
        namaCustomer: 'Warung Bu Siti',
        remoteId: 'cst-5',
        updatedAt: fixedTime,
      );
      expect(Customer.fromMap(customer.toMap()).namaCustomer, 'Warung Bu Siti');
    });
  });

  group('Transaction Models (Faktur & Nota)', () {
    test('Faktur total calculation & map conversion', () {
      final details = [
        const DetailFaktur(
          idBarang: 1,
          jumlah: 285000.0,
          quantity: 10,
          barangRemoteId: 'brg-1',
          namaBarang: 'Telur Ayam Negeri',
        ),
        const DetailFaktur(
          idBarang: 2,
          jumlah: 104000.0,
          quantity: 2,
          barangRemoteId: 'brg-2',
          namaBarang: 'Telur Tray',
        ),
      ];

      final total = Faktur.hitungTotal(details);
      expect(total, 389000.0);

      final faktur = Faktur(
        idFaktur: 10,
        noFaktur: 'FKT-001',
        tanggalFaktur: '2026-02-16',
        total: total,
        idSupplier: 1,
        idPetugas: 2,
        remoteId: 'fkt-10',
        details: details,
        updatedAt: fixedTime,
      );

      final parsed = Faktur.fromMap(faktur.toMap(), details: details);
      expect(parsed.noFaktur, 'FKT-001');
      expect(parsed.details.length, 2);
      expect(faktur.toFirestore()['details'], hasLength(2));
    });

    test('Nota total calculation & map conversion', () {
      final details = [
        const DetailNota(
          idBarang: 1,
          jumlah: 57000.0,
          banyaknya: 2,
          barangRemoteId: 'brg-1',
        ),
      ];

      final total = Nota.hitungTotal(details);
      expect(total, 57000.0);

      final nota = Nota(
        idNota: 3,
        tanggalNota: '2026-02-16',
        total: total,
        idPetugas: 2,
        idCustomer: 1,
        remoteId: 'nta-3',
        details: details,
        updatedAt: fixedTime,
      );

      final parsed = Nota.fromMap(nota.toMap(), details: details);
      expect(parsed.total, 57000.0);
      expect(parsed.details.first.banyaknya, 2);
      expect(nota.toFirestore()['details'], hasLength(1));
    });

    test('Petugas auth fields SQLite & Firestore serialization omits passwordHash', () {
      final petugas = Petugas(
        idPetugas: 7,
        namaPetugas: 'Budi Owner',
        role: UserRole.owner,
        pin: '1234',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        passwordHash: 'salt:hashedSecret',
        remoteId: 'ptg-owner-1',
        syncStatus: SyncStatus.synced,
        updatedAt: fixedTime,
      );

      final sqliteMap = petugas.toMap();
      expect(sqliteMap['email'], 'owner@depottelur36.com');
      expect(sqliteMap['account_id'], 'owner01');
      expect(sqliteMap['password_hash'], 'salt:hashedSecret');

      final parsedLocal = Petugas.fromMap(sqliteMap);
      expect(parsedLocal.email, 'owner@depottelur36.com');
      expect(parsedLocal.accountId, 'owner01');
      expect(parsedLocal.passwordHash, 'salt:hashedSecret');
      expect(parsedLocal.isOwner, isTrue);

      final firestoreMap = petugas.toFirestore();
      expect(firestoreMap['email'], 'owner@depottelur36.com');
      expect(firestoreMap['account_id'], 'owner01');
      expect(firestoreMap.containsKey('password_hash'), isFalse);

      final parsedCloud = Petugas.fromFirestore(firestoreMap, 'ptg-owner-1');
      expect(parsedCloud.email, 'owner@depottelur36.com');
      expect(parsedCloud.accountId, 'owner01');
      expect(parsedCloud.passwordHash, isEmpty);
      expect(parsedCloud.syncStatus, SyncStatus.synced);
    });
  });

  group('AuthSession Serialization, Edge Cases & Invalid Payloads', () {
    test('roundtrip JSON mempertahankan seluruh field dan status isOwner', () {
      final session = AuthSession(
        uid: 'uid-owner-1',
        email: 'owner@depottelur36.com',
        accountId: 'owner01',
        displayName: 'Pak Owner',
        role: UserRole.owner,
        petugasRemoteId: 'ptg-owner-1',
        provider: AuthProviderType.google,
        signedInAt: fixedTime,
      );

      expect(session.isOwner, isTrue);
      final parsed = AuthSession.tryParseJson(session.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.uid, 'uid-owner-1');
      expect(parsed.email, 'owner@depottelur36.com');
      expect(parsed.accountId, 'owner01');
      expect(parsed.displayName, 'Pak Owner');
      expect(parsed.role, UserRole.owner);
      expect(parsed.petugasRemoteId, 'ptg-owner-1');
      expect(parsed.provider, AuthProviderType.google);
      expect(parsed.signedInAt, fixedTime);

      final updated = parsed.copyWith(role: UserRole.petugas);
      expect(updated.isOwner, isFalse);
      expect(updated.accountId, 'owner01');
    });

    test('tryParseJson menolak payload null, kosong, bukan object, atau ID spasi saja', () {
      expect(AuthSession.tryParseJson(null), isNull);
      expect(AuthSession.tryParseJson(''), isNull);
      expect(AuthSession.tryParseJson('   '), isNull);
      expect(AuthSession.tryParseJson('{bukan-json'), isNull);
      expect(AuthSession.tryParseJson('[1, 2, 3]'), isNull);
      expect(AuthSession.tryParseJson('{"email":"a@b.com"}'), isNull);
      expect(
        AuthSession.tryParseJson('{"uid":"   ","petugas_remote_id":"  "}'),
        isNull,
      );
      expect(
        AuthSession.tryParseJson('{"uid":123,"petugas_remote_id":"ptg-1"}'),
        isNull,
      );
    });

    test('tryParseJson menerima sesi bila minimal salah satu uid atau petugasRemoteId valid & memfallback enum tak dikenal', () {
      final parsed = AuthSession.tryParseJson(
        '{"uid":"","petugas_remote_id":"seed-1","role":"SUPERADMIN","provider":"UNKNOWN","signed_in_at":"invalid-date"}',
      );
      expect(parsed, isNotNull);
      expect(parsed!.role, UserRole.petugas);
      expect(parsed.provider, AuthProviderType.emailPassword);
      expect(parsed.petugasRemoteId, 'seed-1');
    });
  });
}
