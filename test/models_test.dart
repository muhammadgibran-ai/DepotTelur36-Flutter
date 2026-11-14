import 'package:flutter_test/flutter_test.dart';

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
  });
}
