import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';

/// Pengelola database lokal SQLite (`depottelur36.db`) untuk mode Offline-First.
/// Mengimplementasikan 8 tabel relasional sesuai ERD, LRS, dan PDM DepotTelur36:
/// 1. `supplier`
/// 2. `petugas`
/// 3. `customer`
/// 4. `barang`
/// 5. `faktur`
/// 6. `detail_faktur`
/// 7. `nota`
/// 8. `detail_nota`
class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// Konstruktor khusus unit testing dengan path database terisolasi.
  @visibleForTesting
  DatabaseHelper.forTesting({required this.customDbPath});

  static const String databaseName = 'depottelur36.db';
  static const int databaseVersion = 1;

  String? customDbPath;
  Database? _database;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = customDbPath ?? p.join(await getDatabasesPath(), databaseName);
    return openDatabase(
      dbPath,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Tabel Master: supplier
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

    // 2. Tabel Master: petugas
    await db.execute('''
      CREATE TABLE petugas (
        id_petugas INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_petugas TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'PETUGAS',
        pin TEXT NOT NULL DEFAULT '1234',
        remote_id TEXT NOT NULL UNIQUE,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        updated_at TEXT NOT NULL
      )
    ''');

    // 3. Tabel Master: customer
    await db.execute('''
      CREATE TABLE customer (
        id_customer INTEGER PRIMARY KEY AUTOINCREMENT,
        nama_customer TEXT NOT NULL,
        remote_id TEXT NOT NULL UNIQUE,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        updated_at TEXT NOT NULL
      )
    ''');

    // 4. Tabel Master: barang
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

    // 5. Tabel Transaksi Masuk: faktur (Pembelian ke Supplier)
    await db.execute('''
      CREATE TABLE faktur (
        id_faktur INTEGER PRIMARY KEY AUTOINCREMENT,
        no_faktur TEXT NOT NULL,
        tanggal_faktur TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0.0,
        id_supplier INTEGER NOT NULL,
        id_petugas INTEGER NOT NULL,
        remote_id TEXT NOT NULL UNIQUE,
        supplier_remote_id TEXT,
        petugas_remote_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        updated_at TEXT NOT NULL,
        FOREIGN KEY (id_supplier) REFERENCES supplier (id_supplier) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (id_petugas) REFERENCES petugas (id_petugas) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    // 6. Tabel Detail Transaksi Masuk: detail_faktur (Composite PK)
    await db.execute('''
      CREATE TABLE detail_faktur (
        id_faktur INTEGER NOT NULL,
        id_barang INTEGER NOT NULL,
        jumlah REAL NOT NULL DEFAULT 0.0,
        quantity INTEGER NOT NULL,
        barang_remote_id TEXT,
        PRIMARY KEY (id_faktur, id_barang),
        FOREIGN KEY (id_faktur) REFERENCES faktur (id_faktur) ON UPDATE CASCADE ON DELETE CASCADE,
        FOREIGN KEY (id_barang) REFERENCES barang (id_barang) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    // 7. Tabel Transaksi Keluar: nota (Penjualan ke Customer)
    await db.execute('''
      CREATE TABLE nota (
        id_nota INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal_nota TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0.0,
        id_petugas INTEGER NOT NULL,
        id_customer INTEGER NOT NULL,
        remote_id TEXT NOT NULL UNIQUE,
        petugas_remote_id TEXT,
        customer_remote_id TEXT,
        sync_status TEXT NOT NULL DEFAULT 'PENDING',
        updated_at TEXT NOT NULL,
        FOREIGN KEY (id_petugas) REFERENCES petugas (id_petugas) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (id_customer) REFERENCES customer (id_customer) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    // 8. Tabel Detail Transaksi Keluar: detail_nota (Composite PK)
    await db.execute('''
      CREATE TABLE detail_nota (
        id_nota INTEGER NOT NULL,
        id_barang INTEGER NOT NULL,
        jumlah REAL NOT NULL DEFAULT 0.0,
        banyaknya INTEGER NOT NULL,
        barang_remote_id TEXT,
        PRIMARY KEY (id_nota, id_barang),
        FOREIGN KEY (id_nota) REFERENCES nota (id_nota) ON UPDATE CASCADE ON DELETE CASCADE,
        FOREIGN KEY (id_barang) REFERENCES barang (id_barang) ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');

    // Indeks untuk mempercepat antrean Auto-Sync & pencarian nama barang
    await db.execute('CREATE INDEX idx_barang_sync ON barang(sync_status)');
    await db.execute('CREATE INDEX idx_supplier_sync ON supplier(sync_status)');
    await db.execute('CREATE INDEX idx_customer_sync ON customer(sync_status)');
    await db.execute('CREATE INDEX idx_petugas_sync ON petugas(sync_status)');
    await db.execute('CREATE INDEX idx_faktur_sync ON faktur(sync_status)');
    await db.execute('CREATE INDEX idx_nota_sync ON nota(sync_status)');

    await _seedInitialData(db);
  }

  /// Mengisi data awal standar DepotTelur36 dengan `remote_id` deterministik
  /// agar langsung siap pakai saat offline dan tidak menduplikasi data di Cloud.
  Future<void> _seedInitialData(Database db) async {
    final now = DateTime(2026, 2, 16).toIso8601String();

    final petugasSeed = [
      {
        'nama_petugas': 'Owner DepotTelur36',
        'role': UserRole.owner.value,
        'pin': '1234',
        'remote_id': 'seed-petugas-owner',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_petugas': 'Petugas Kasir & Gudang',
        'role': UserRole.petugas.value,
        'pin': '1111',
        'remote_id': 'seed-petugas-kasir-1',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
    ];
    for (final row in petugasSeed) {
      await db.insert('petugas', row);
    }

    final supplierSeed = [
      {
        'nama_supplier': 'Peternakan Ayam Makmur Jaya',
        'alamat_supplier': 'Jl. Raya Kandang No. 12',
        'no_telp_supplier': '081234567890',
        'remote_id': 'seed-supplier-1',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_supplier': 'Agen Sembako Berkah Sentosa',
        'alamat_supplier': 'Pasar Induk Blok B-05',
        'no_telp_supplier': '081298765432',
        'remote_id': 'seed-supplier-2',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
    ];
    for (final row in supplierSeed) {
      await db.insert('supplier', row);
    }

    await db.insert('customer', {
      'nama_customer': 'Pelanggan Umum (Eceran)',
      'remote_id': 'seed-customer-umum',
      'sync_status': SyncStatus.synced.value,
      'updated_at': now,
    });

    final barangSeed = [
      {
        'nama_barang': 'Telur Ayam Negeri',
        'stok_barang': 120,
        'satuan': 'Kg',
        'harga_satuan': 28500.0,
        'remote_id': 'seed-barang-telur-negeri-kg',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_barang': 'Telur Ayam Negeri (1 Tray / 30 Btr)',
        'stok_barang': 25,
        'satuan': 'Tray',
        'harga_satuan': 52000.0,
        'remote_id': 'seed-barang-telur-negeri-tray',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_barang': 'Telur Ayam Kampung',
        'stok_barang': 90,
        'satuan': 'Butir',
        'harga_satuan': 2500.0,
        'remote_id': 'seed-barang-telur-kampung',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_barang': 'Telur Bebek Asin / Mentah',
        'stok_barang': 60,
        'satuan': 'Butir',
        'harga_satuan': 3000.0,
        'remote_id': 'seed-barang-telur-bebek',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_barang': 'Beras Pandan Wangi 5 Kg',
        'stok_barang': 18,
        'satuan': 'Sak',
        'harga_satuan': 74000.0,
        'remote_id': 'seed-barang-beras-5kg',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
      {
        'nama_barang': 'Minyak Goreng Kemasan 1 Liter',
        'stok_barang': 8,
        'satuan': 'Pouch',
        'harga_satuan': 17500.0,
        'remote_id': 'seed-barang-minyak-1l',
        'sync_status': SyncStatus.synced.value,
        'updated_at': now,
      },
    ];
    for (final row in barangSeed) {
      await db.insert('barang', row);
    }
  }

  /// Menghitung total antrean data yang belum tersinkron ke Cloud (`PENDING`).
  Future<int> getPendingSyncCount() async {
    final db = await database;
    const tables = [
      'supplier',
      'petugas',
      'customer',
      'barang',
      'faktur',
      'nota',
    ];
    var total = 0;
    for (final table in tables) {
      final result = await db.rawQuery(
        "SELECT COUNT(*) AS cnt FROM $table WHERE sync_status = 'PENDING'",
      );
      total += Sqflite.firstIntValue(result) ?? 0;
    }
    return total;
  }

  // ==================== CRUD MASTER: BARANG ====================

  Future<List<Barang>> getAllBarang() async {
    final db = await database;
    final rows = await db.query('barang', orderBy: 'nama_barang ASC');
    return rows.map(Barang.fromMap).toList();
  }

  Future<Barang?> getBarangByRemoteId(String remoteId) async {
    final db = await database;
    final rows = await db.query(
      'barang',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Barang.fromMap(rows.first);
  }

  Future<int> upsertBarang(Barang barang) async {
    final db = await database;
    final existing = await getBarangByRemoteId(barang.remoteId);
    if (existing == null) {
      return db.insert('barang', barang.toMap());
    }
    return db.update(
      'barang',
      barang.copyWith(idBarang: existing.idBarang).toMap(),
      where: 'id_barang = ?',
      whereArgs: [existing.idBarang],
    );
  }

  // ==================== CRUD MASTER: SUPPLIER ====================

  Future<List<Supplier>> getAllSupplier() async {
    final db = await database;
    final rows = await db.query('supplier', orderBy: 'nama_supplier ASC');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> getSupplierByRemoteId(String remoteId) async {
    final db = await database;
    final rows = await db.query(
      'supplier',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Supplier.fromMap(rows.first);
  }

  Future<int> upsertSupplier(Supplier supplier) async {
    final db = await database;
    final existing = await getSupplierByRemoteId(supplier.remoteId);
    if (existing == null) {
      return db.insert('supplier', supplier.toMap());
    }
    return db.update(
      'supplier',
      supplier.copyWith(idSupplier: existing.idSupplier).toMap(),
      where: 'id_supplier = ?',
      whereArgs: [existing.idSupplier],
    );
  }

  // ==================== CRUD MASTER: CUSTOMER ====================

  Future<List<Customer>> getAllCustomer() async {
    final db = await database;
    final rows = await db.query('customer', orderBy: 'nama_customer ASC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> getCustomerByRemoteId(String remoteId) async {
    final db = await database;
    final rows = await db.query(
      'customer',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<int> upsertCustomer(Customer customer) async {
    final db = await database;
    final existing = await getCustomerByRemoteId(customer.remoteId);
    if (existing == null) {
      return db.insert('customer', customer.toMap());
    }
    return db.update(
      'customer',
      customer.copyWith(idCustomer: existing.idCustomer).toMap(),
      where: 'id_customer = ?',
      whereArgs: [existing.idCustomer],
    );
  }

  // ==================== CRUD MASTER: PETUGAS ====================

  Future<List<Petugas>> getAllPetugas() async {
    final db = await database;
    final rows = await db.query('petugas', orderBy: 'id_petugas ASC');
    return rows.map(Petugas.fromMap).toList();
  }

  Future<Petugas?> getPetugasByRemoteId(String remoteId) async {
    final db = await database;
    final rows = await db.query(
      'petugas',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Petugas.fromMap(rows.first);
  }

  Future<int> upsertPetugas(Petugas petugas) async {
    final db = await database;
    final existing = await getPetugasByRemoteId(petugas.remoteId);
    if (existing == null) {
      return db.insert('petugas', petugas.toMap());
    }
    return db.update(
      'petugas',
      petugas.copyWith(idPetugas: existing.idPetugas).toMap(),
      where: 'id_petugas = ?',
      whereArgs: [existing.idPetugas],
    );
  }

  // ==================== TRANSAKSI ATOMIK: FAKTUR & NOTA ====================

  /// Menyimpan `faktur` beserta `detail_faktur` dan otomatis MENAMBAH `stok_barang`
  /// dalam satu transaksi SQLite atomik (berfungsi penuh saat offline).
  Future<int> insertFakturTransaction(
    Faktur faktur,
    List<DetailFaktur> details,
  ) async {
    if (details.isEmpty) {
      throw ArgumentError('Detail faktur tidak boleh kosong.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final fakturId = await txn.insert('faktur', faktur.toMap());
      for (final item in details) {
        if (item.quantity <= 0) {
          throw ArgumentError('Quantity barang masuk harus lebih dari 0.');
        }
        await txn.insert(
          'detail_faktur',
          item.copyWith(idFaktur: fakturId).toMap(),
        );
        await txn.rawUpdate(
          'UPDATE barang SET stok_barang = stok_barang + ?, updated_at = ? WHERE id_barang = ?',
          [item.quantity, faktur.updatedAt.toIso8601String(), item.idBarang],
        );
      }
      return fakturId;
    });
  }

  /// Menyimpan `nota` beserta `detail_nota` dan otomatis MENGURANGI `stok_barang`
  /// dalam satu transaksi SQLite atomik dengan validasi stok mencukupi.
  Future<int> insertNotaTransaction(
    Nota nota,
    List<DetailNota> details,
  ) async {
    if (details.isEmpty) {
      throw ArgumentError('Detail nota tidak boleh kosong.');
    }
    final db = await database;
    return db.transaction((txn) async {
      for (final item in details) {
        if (item.banyaknya <= 0) {
          throw ArgumentError('Banyaknya pembelian harus lebih dari 0.');
        }
        final rows = await txn.query(
          'barang',
          columns: ['nama_barang', 'stok_barang'],
          where: 'id_barang = ?',
          whereArgs: [item.idBarang],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Barang dengan id ${item.idBarang} tidak ditemukan.');
        }
        final stokSaatIni = (rows.first['stok_barang'] as num).toInt();
        final namaBarang = rows.first['nama_barang'] as String;
        if (stokSaatIni < item.banyaknya) {
          throw StateError(
            'Stok "$namaBarang" tidak cukup (tersisa $stokSaatIni, diminta ${item.banyaknya}).',
          );
        }
      }

      final notaId = await txn.insert('nota', nota.toMap());
      for (final item in details) {
        await txn.insert(
          'detail_nota',
          item.copyWith(idNota: notaId).toMap(),
        );
        await txn.rawUpdate(
          'UPDATE barang SET stok_barang = stok_barang - ?, updated_at = ? WHERE id_barang = ?',
          [item.banyaknya, nota.updatedAt.toIso8601String(), item.idBarang],
        );
      }
      return notaId;
    });
  }

  /// Mengambil daftar `faktur` lengkap dengan nama supplier & petugas.
  Future<List<Faktur>> getAllFaktur() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT f.*, s.nama_supplier, p.nama_petugas
      FROM faktur f
      LEFT JOIN supplier s ON f.id_supplier = s.id_supplier
      LEFT JOIN petugas p ON f.id_petugas = p.id_petugas
      ORDER BY f.id_faktur DESC
    ''');
    final list = <Faktur>[];
    for (final row in rows) {
      final idFaktur = (row['id_faktur'] as num).toInt();
      final detailRows = await db.rawQuery('''
        SELECT df.*, b.nama_barang, b.satuan
        FROM detail_faktur df
        LEFT JOIN barang b ON df.id_barang = b.id_barang
        WHERE df.id_faktur = ?
      ''', [idFaktur]);
      list.add(
        Faktur.fromMap(
          row,
          details: detailRows.map(DetailFaktur.fromMap).toList(),
        ),
      );
    }
    return list;
  }

  /// Mengambil daftar `nota` lengkap dengan nama customer & petugas.
  Future<List<Nota>> getAllNota() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT n.*, c.nama_customer, p.nama_petugas
      FROM nota n
      LEFT JOIN customer c ON n.id_customer = c.id_customer
      LEFT JOIN petugas p ON n.id_petugas = p.id_petugas
      ORDER BY n.id_nota DESC
    ''');
    final list = <Nota>[];
    for (final row in rows) {
      final idNota = (row['id_nota'] as num).toInt();
      final detailRows = await db.rawQuery('''
        SELECT dn.*, b.nama_barang, b.satuan
        FROM detail_nota dn
        LEFT JOIN barang b ON dn.id_barang = b.id_barang
        WHERE dn.id_nota = ?
      ''', [idNota]);
      list.add(
        Nota.fromMap(
          row,
          details: detailRows.map(DetailNota.fromMap).toList(),
        ),
      );
    }
    return list;
  }

  Future<void> markSynced(String table, String remoteId) async {
    final db = await database;
    await db.update(
      table,
      {'sync_status': SyncStatus.synced.value},
      where: 'remote_id = ?',
      whereArgs: [remoteId],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
