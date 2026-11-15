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
  static const int databaseVersion = 3;

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
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE petugas ADD COLUMN email TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE petugas ADD COLUMN account_id TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE petugas ADD COLUMN password_hash TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('CREATE INDEX IF NOT EXISTS idx_petugas_email ON petugas(email)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_petugas_account_id ON petugas(account_id)');
    }
    if (oldVersion < 3) {
      // Hapus transaksi contoh yang masih merujuk akun testing seed yang belum termigrasi
      // agar pembersihan tabel `petugas` tidak melanggar FK ON DELETE RESTRICT.
      const testingPetugasIds = '''
        SELECT id_petugas FROM petugas
        WHERE remote_id IN ('seed-petugas-owner', 'seed-petugas-kasir-1')
          AND password_hash = ''
      ''';
      await db.execute(
        'DELETE FROM faktur WHERE id_petugas IN ($testingPetugasIds)',
      );
      await db.execute(
        'DELETE FROM nota WHERE id_petugas IN ($testingPetugasIds)',
      );
      await db.delete(
        'petugas',
        where:
            "remote_id IN ('seed-petugas-owner', 'seed-petugas-kasir-1') AND password_hash = ''",
      );
    }
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
        email TEXT NOT NULL DEFAULT '',
        account_id TEXT NOT NULL DEFAULT '',
        password_hash TEXT NOT NULL DEFAULT '',
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
    await db.execute('CREATE INDEX idx_petugas_email ON petugas(email)');
    await db.execute('CREATE INDEX idx_petugas_account_id ON petugas(account_id)');
    await db.execute('CREATE INDEX idx_faktur_sync ON faktur(sync_status)');
    await db.execute('CREATE INDEX idx_nota_sync ON nota(sync_status)');

    await _seedInitialData(db);
  }

  /// Mengisi data master awal DepotTelur36 dengan `remote_id` deterministik
  /// agar siap pakai saat offline tanpa menyertakan akun testing pada tabel `petugas`.
  Future<void> _seedInitialData(Database db) async {
    final now = DateTime(2026, 2, 16).toIso8601String();

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

  Future<Petugas?> getPetugasByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'petugas',
      where: 'LOWER(email) = ?',
      whereArgs: [normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Petugas.fromMap(rows.first);
  }

  Future<Petugas?> findPetugasByIdentifier(String identifier) async {
    final normalized = identifier.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'petugas',
      where: 'LOWER(email) = ? OR LOWER(account_id) = ? OR LOWER(remote_id) = ?',
      whereArgs: [normalized, normalized, normalized],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Petugas.fromMap(rows.first);
  }

  Future<int> upsertPetugas(Petugas petugas) async {
    final db = await database;
    var existing = await getPetugasByRemoteId(petugas.remoteId);
    existing ??= petugas.email.trim().isNotEmpty
        ? await getPetugasByEmail(petugas.email)
        : null;
    if (existing == null) {
      return db.insert('petugas', petugas.toMap());
    }
    final merged = petugas.copyWith(
      idPetugas: existing.idPetugas,
      email: petugas.email.isEmpty ? existing.email : petugas.email,
      accountId:
          petugas.accountId.isEmpty ? existing.accountId : petugas.accountId,
      passwordHash: petugas.passwordHash.isEmpty
          ? existing.passwordHash
          : petugas.passwordHash,
    );
    return db.update(
      'petugas',
      merged.toMap(),
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
  Future<List<Faktur>> getAllFaktur() => _fetchFaktur();

  /// Mengambil antrean `faktur` yang belum tersinkron (`PENDING`).
  Future<List<Faktur>> getPendingFaktur() =>
      _fetchFaktur(whereClause: "WHERE f.sync_status = 'PENDING'");

  Future<List<Faktur>> _fetchFaktur({String whereClause = ''}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT f.*, s.nama_supplier, p.nama_petugas,
             COALESCE(f.supplier_remote_id, s.remote_id) AS resolved_supplier_remote_id,
             COALESCE(f.petugas_remote_id, p.remote_id) AS resolved_petugas_remote_id
      FROM faktur f
      LEFT JOIN supplier s ON f.id_supplier = s.id_supplier
      LEFT JOIN petugas p ON f.id_petugas = p.id_petugas
      $whereClause
      ORDER BY f.id_faktur DESC
    ''');
    final list = <Faktur>[];
    for (final row in rows) {
      final idFaktur = (row['id_faktur'] as num).toInt();
      final detailRows = await db.rawQuery('''
        SELECT df.*, b.nama_barang, b.satuan,
               COALESCE(df.barang_remote_id, b.remote_id) AS resolved_barang_remote_id
        FROM detail_faktur df
        LEFT JOIN barang b ON df.id_barang = b.id_barang
        WHERE df.id_faktur = ?
      ''', [idFaktur]);
      final details = detailRows.map((d) {
        final item = DetailFaktur.fromMap(d);
        return item.copyWith(
          barangRemoteId: d['resolved_barang_remote_id'] as String?,
        );
      }).toList();
      final faktur = Faktur.fromMap(row, details: details);
      list.add(
        faktur.copyWith(
          supplierRemoteId: row['resolved_supplier_remote_id'] as String?,
          petugasRemoteId: row['resolved_petugas_remote_id'] as String?,
        ),
      );
    }
    return list;
  }

  /// Mengambil daftar `nota` lengkap dengan nama customer & petugas.
  Future<List<Nota>> getAllNota() => _fetchNota();

  /// Mengambil antrean `nota` yang belum tersinkron (`PENDING`).
  Future<List<Nota>> getPendingNota() =>
      _fetchNota(whereClause: "WHERE n.sync_status = 'PENDING'");

  Future<List<Nota>> _fetchNota({String whereClause = ''}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT n.*, c.nama_customer, p.nama_petugas,
             COALESCE(n.customer_remote_id, c.remote_id) AS resolved_customer_remote_id,
             COALESCE(n.petugas_remote_id, p.remote_id) AS resolved_petugas_remote_id
      FROM nota n
      LEFT JOIN customer c ON n.id_customer = c.id_customer
      LEFT JOIN petugas p ON n.id_petugas = p.id_petugas
      $whereClause
      ORDER BY n.id_nota DESC
    ''');
    final list = <Nota>[];
    for (final row in rows) {
      final idNota = (row['id_nota'] as num).toInt();
      final detailRows = await db.rawQuery('''
        SELECT dn.*, b.nama_barang, b.satuan,
               COALESCE(dn.barang_remote_id, b.remote_id) AS resolved_barang_remote_id
        FROM detail_nota dn
        LEFT JOIN barang b ON dn.id_barang = b.id_barang
        WHERE dn.id_nota = ?
      ''', [idNota]);
      final details = detailRows.map((d) {
        final item = DetailNota.fromMap(d);
        return item.copyWith(
          barangRemoteId: d['resolved_barang_remote_id'] as String?,
        );
      }).toList();
      final nota = Nota.fromMap(row, details: details);
      list.add(
        nota.copyWith(
          customerRemoteId: row['resolved_customer_remote_id'] as String?,
          petugasRemoteId: row['resolved_petugas_remote_id'] as String?,
        ),
      );
    }
    return list;
  }

  // ==================== HELPER SINKRONISASI CLOUD ====================

  Future<List<Supplier>> getPendingSuppliers() async {
    final db = await database;
    final rows = await db.query(
      'supplier',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Supplier.fromMap).toList();
  }

  Future<List<Petugas>> getPendingPetugas() async {
    final db = await database;
    final rows = await db.query(
      'petugas',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Petugas.fromMap).toList();
  }

  Future<List<Customer>> getPendingCustomers() async {
    final db = await database;
    final rows = await db.query(
      'customer',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<List<Barang>> getPendingBarang() async {
    final db = await database;
    final rows = await db.query(
      'barang',
      where: "sync_status = 'PENDING'",
    );
    return rows.map(Barang.fromMap).toList();
  }

  /// Menghitung selisih stok dari faktur/nota lokal yang masih `PENDING`
  /// agar sinkronisasi tidak menggandakan atau menimpa mutasi offline.
  Future<({int pendingIn, int pendingOut})> getPendingStockDeltaForBarang(
    int idBarang,
  ) async {
    final db = await database;
    final inRows = await db.rawQuery('''
      SELECT COALESCE(SUM(df.quantity), 0) AS qty
      FROM detail_faktur df
      INNER JOIN faktur f ON df.id_faktur = f.id_faktur
      WHERE df.id_barang = ? AND f.sync_status = 'PENDING'
    ''', [idBarang]);
    final outRows = await db.rawQuery('''
      SELECT COALESCE(SUM(dn.banyaknya), 0) AS qty
      FROM detail_nota dn
      INNER JOIN nota n ON dn.id_nota = n.id_nota
      WHERE dn.id_barang = ? AND n.sync_status = 'PENDING'
    ''', [idBarang]);
    return (
      pendingIn: Sqflite.firstIntValue(inRows) ?? 0,
      pendingOut: Sqflite.firstIntValue(outRows) ?? 0,
    );
  }

  Future<void> applyCloudSupplier(Supplier cloudSupplier) async {
    final existing = await getSupplierByRemoteId(cloudSupplier.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertSupplier(cloudSupplier.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudPetugas(Petugas cloudPetugas) async {
    final existing = await getPetugasByRemoteId(cloudPetugas.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertPetugas(cloudPetugas.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudCustomer(Customer cloudCustomer) async {
    final existing = await getCustomerByRemoteId(cloudCustomer.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertCustomer(cloudCustomer.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudBarang(Barang cloudBarang) async {
    final existing = await getBarangByRemoteId(cloudBarang.remoteId);
    if (existing == null) {
      await upsertBarang(cloudBarang.copyWith(syncStatus: SyncStatus.synced));
      return;
    }
    if (existing.syncStatus == SyncStatus.pending) {
      return;
    }
    final delta = await getPendingStockDeltaForBarang(existing.idBarang!);
    final effectiveStock =
        cloudBarang.stokBarang + delta.pendingIn - delta.pendingOut;
    await upsertBarang(
      cloudBarang.copyWith(
        idBarang: existing.idBarang,
        stokBarang: effectiveStock < 0 ? 0 : effectiveStock,
        syncStatus: SyncStatus.synced,
      ),
    );
  }

  /// Menyimpan `faktur` dari Cloud Firestore jika belum ada di SQLite lokal
  /// (tanpa memodifikasi `stok_barang` karena stok diambil dari koleksi `barang`).
  Future<bool> insertCloudFakturIfMissing({
    required String remoteId,
    required Map<String, dynamic> data,
  }) async {
    final db = await database;
    final existing = await db.query(
      'faktur',
      columns: ['id_faktur'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return false;
    }

    final supplierRemoteId = data['supplier_remote_id'] as String?;
    final petugasRemoteId = data['petugas_remote_id'] as String?;
    if (supplierRemoteId == null || petugasRemoteId == null) return false;

    final supplier = await getSupplierByRemoteId(supplierRemoteId);
    final petugas = await getPetugasByRemoteId(petugasRemoteId);
    if (supplier?.idSupplier == null || petugas?.idPetugas == null) {
      return false;
    }

    final rawDetails = (data['details'] as List<dynamic>?) ?? const [];
    final resolvedDetails = <DetailFaktur>[];
    for (final raw in rawDetails) {
      final map = Map<String, dynamic>.from(raw as Map);
      final barangRemoteId = map['barang_remote_id'] as String?;
      if (barangRemoteId == null) return false;
      final barang = await getBarangByRemoteId(barangRemoteId);
      if (barang?.idBarang == null) return false;
      resolvedDetails.add(
        DetailFaktur(
          idBarang: barang!.idBarang!,
          jumlah: (map['jumlah'] as num?)?.toDouble() ?? 0.0,
          quantity: (map['quantity'] as num?)?.toInt() ?? 0,
          barangRemoteId: barangRemoteId,
        ),
      );
    }
    if (resolvedDetails.isEmpty) return false;

    await db.transaction((txn) async {
      final fakturId = await txn.insert('faktur', {
        'no_faktur': (data['no_faktur'] as String?) ?? '',
        'tanggal_faktur': (data['tanggal_faktur'] as String?) ?? '',
        'total': (data['total'] as num?)?.toDouble() ?? 0.0,
        'id_supplier': supplier!.idSupplier!,
        'id_petugas': petugas!.idPetugas!,
        'remote_id': remoteId,
        'supplier_remote_id': supplierRemoteId,
        'petugas_remote_id': petugasRemoteId,
        'sync_status': SyncStatus.synced.value,
        'updated_at': (data['updated_at'] as String?) ??
            DateTime.now().toIso8601String(),
      });
      for (final item in resolvedDetails) {
        await txn.insert(
          'detail_faktur',
          item.copyWith(idFaktur: fakturId).toMap(),
        );
      }
    });
    return true;
  }

  /// Menyimpan `nota` dari Cloud Firestore jika belum ada di SQLite lokal
  /// (tanpa memodifikasi `stok_barang` karena stok diambil dari koleksi `barang`).
  Future<bool> insertCloudNotaIfMissing({
    required String remoteId,
    required Map<String, dynamic> data,
  }) async {
    final db = await database;
    final existing = await db.query(
      'nota',
      columns: ['id_nota'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return false;
    }

    final petugasRemoteId = data['petugas_remote_id'] as String?;
    final customerRemoteId = data['customer_remote_id'] as String?;
    if (petugasRemoteId == null || customerRemoteId == null) return false;

    final petugas = await getPetugasByRemoteId(petugasRemoteId);
    final customer = await getCustomerByRemoteId(customerRemoteId);
    if (petugas?.idPetugas == null || customer?.idCustomer == null) {
      return false;
    }

    final rawDetails = (data['details'] as List<dynamic>?) ?? const [];
    final resolvedDetails = <DetailNota>[];
    for (final raw in rawDetails) {
      final map = Map<String, dynamic>.from(raw as Map);
      final barangRemoteId = map['barang_remote_id'] as String?;
      if (barangRemoteId == null) return false;
      final barang = await getBarangByRemoteId(barangRemoteId);
      if (barang?.idBarang == null) return false;
      resolvedDetails.add(
        DetailNota(
          idBarang: barang!.idBarang!,
          jumlah: (map['jumlah'] as num?)?.toDouble() ?? 0.0,
          banyaknya: (map['banyaknya'] as num?)?.toInt() ?? 0,
          barangRemoteId: barangRemoteId,
        ),
      );
    }
    if (resolvedDetails.isEmpty) return false;

    await db.transaction((txn) async {
      final notaId = await txn.insert('nota', {
        'tanggal_nota': (data['tanggal_nota'] as String?) ?? '',
        'total': (data['total'] as num?)?.toDouble() ?? 0.0,
        'id_petugas': petugas!.idPetugas!,
        'id_customer': customer!.idCustomer!,
        'remote_id': remoteId,
        'petugas_remote_id': petugasRemoteId,
        'customer_remote_id': customerRemoteId,
        'sync_status': SyncStatus.synced.value,
        'updated_at': (data['updated_at'] as String?) ??
            DateTime.now().toIso8601String(),
      });
      for (final item in resolvedDetails) {
        await txn.insert(
          'detail_nota',
          item.copyWith(idNota: notaId).toMap(),
        );
      }
    });
    return true;
  }

  Future<bool> hasRemoteRecord(String table, String remoteId) async {
    const allowed = {
      'supplier',
      'petugas',
      'customer',
      'barang',
      'faktur',
      'nota',
    };
    if (!allowed.contains(table)) {
      throw ArgumentError('Tabel tidak valid: $table');
    }
    final db = await database;
    final rows = await db.query(
      table,
      columns: ['remote_id'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    return rows.isNotEmpty;
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
