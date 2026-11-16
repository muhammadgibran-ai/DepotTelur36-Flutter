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
  static const int databaseVersion = 5;

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
    if (oldVersion < 4) {
      await _createPendingDeletesTable(db);
    }
    if (oldVersion < 5) {
      await _addBarangPhotoColumnsIfMissing(db);
    }
  }

  Future<void> _addBarangPhotoColumnsIfMissing(DatabaseExecutor db) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info(barang)');
    final existingColumns = tableInfo
        .map((row) => (row['name'] as String?)?.toLowerCase())
        .whereType<String>()
        .toSet();

    if (!existingColumns.contains('foto_barang')) {
      await db.execute(
        "ALTER TABLE barang ADD COLUMN foto_barang TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!existingColumns.contains('foto_format')) {
      await db.execute(
        "ALTER TABLE barang ADD COLUMN foto_format TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!existingColumns.contains('foto_size_bytes')) {
      await db.execute(
        'ALTER TABLE barang ADD COLUMN foto_size_bytes INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _createPendingDeletesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_deletes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        remote_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        UNIQUE(table_name, remote_id)
      )
    ''');
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
        foto_barang TEXT NOT NULL DEFAULT '',
        foto_format TEXT NOT NULL DEFAULT '',
        foto_size_bytes INTEGER NOT NULL DEFAULT 0,
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

    await _createPendingDeletesTable(db);

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
    final deleteResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM pending_deletes',
    );
    total += Sqflite.firstIntValue(deleteResult) ?? 0;
    return total;
  }

  Future<List<({String tableName, String remoteId})>> getPendingDeletes() async {
    final db = await database;
    final rows = await db.query(
      'pending_deletes',
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (row) => (
            tableName: (row['table_name'] as String?) ?? '',
            remoteId: (row['remote_id'] as String?) ?? '',
          ),
        )
        .toList();
  }

  Future<bool> hasPendingDelete(String tableName, String remoteId) async {
    if (remoteId.trim().isEmpty) return false;
    final db = await database;
    final rows = await db.query(
      'pending_deletes',
      columns: ['id'],
      where: 'table_name = ? AND remote_id = ?',
      whereArgs: [tableName, remoteId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> removePendingDelete(String tableName, String remoteId) async {
    final db = await database;
    await db.delete(
      'pending_deletes',
      where: 'table_name = ? AND remote_id = ?',
      whereArgs: [tableName, remoteId],
    );
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

  Future<int?> _resolveMasterUpdateId(
    Transaction txn, {
    required String tableName,
    required String idColumn,
    required int? localId,
    required String remoteId,
    required String entityLabel,
  }) async {
    final byRemoteRows = await txn.query(
      tableName,
      columns: [idColumn],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    final byRemoteId = byRemoteRows.isEmpty
        ? null
        : (byRemoteRows.first[idColumn] as num).toInt();

    if (localId != null) {
      final byPkRows = await txn.query(
        tableName,
        columns: [idColumn],
        where: '$idColumn = ?',
        whereArgs: [localId],
        limit: 1,
      );
      if (byPkRows.isEmpty) {
        throw StateError('$entityLabel tidak ditemukan di database lokal.');
      }
      if (byRemoteId != null && byRemoteId != localId) {
        throw StateError(
          'Data $entityLabel lokal tidak konsisten dengan ID remote.',
        );
      }
      return localId;
    }

    return byRemoteId;
  }

  Future<int> _upsertSimpleMaster({
    required String tableName,
    required String idColumn,
    required String entityLabel,
    required int? localId,
    required String remoteId,
    required Map<String, Object?> Function(int? resolvedId) buildMap,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final idMatch = await _resolveMasterUpdateId(
        txn,
        tableName: tableName,
        idColumn: idColumn,
        localId: localId,
        remoteId: remoteId,
        entityLabel: entityLabel,
      );
      await _clearPendingDelete(txn, tableName, remoteId);
      if (idMatch == null) {
        return txn.insert(tableName, buildMap(null));
      }
      return txn.update(
        tableName,
        buildMap(idMatch),
        where: '$idColumn = ?',
        whereArgs: [idMatch],
      );
    });
  }

  Future<int> upsertBarang(Barang barang) {
    return _upsertSimpleMaster(
      tableName: 'barang',
      idColumn: 'id_barang',
      entityLabel: 'Barang',
      localId: barang.idBarang,
      remoteId: barang.remoteId,
      buildMap: (resolvedId) => resolvedId == null
          ? barang.toMap()
          : barang.copyWith(idBarang: resolvedId).toMap(),
    );
  }

  Future<void> updateBarangHargaBatch(Map<int, double> hargaById) async {
    if (hargaById.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in hargaById.entries) {
        final updatedRows = await txn.update(
          'barang',
          {
            'harga_satuan': entry.value,
            'sync_status': SyncStatus.pending.value,
            'updated_at': now,
          },
          where: 'id_barang = ?',
          whereArgs: [entry.key],
        );
        if (updatedRows == 0) {
          throw StateError(
            'Barang dengan ID ${entry.key} tidak ditemukan saat memperbarui harga.',
          );
        }
      }
    });
  }

  Future<void> deleteBarang(int idBarang) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'barang',
        columns: ['remote_id'],
        where: 'id_barang = ?',
        whereArgs: [idBarang],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Barang tidak ditemukan atau sudah dihapus.');
      }
      final refFaktur = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM detail_faktur WHERE id_barang = ?',
              [idBarang],
            ),
          ) ??
          0;
      final refNota = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM detail_nota WHERE id_barang = ?',
              [idBarang],
            ),
          ) ??
          0;
      if (refFaktur > 0 || refNota > 0) {
        throw StateError(
          'Barang tidak dapat dihapus karena masih tercatat pada transaksi Faktur/Nota.',
        );
      }
      final remoteId = (rows.first['remote_id'] as String?) ?? '';
      await _recordPendingDelete(txn, 'barang', remoteId);
      await txn.delete('barang', where: 'id_barang = ?', whereArgs: [idBarang]);
    });
  }

  Future<void> _recordPendingDelete(
    DatabaseExecutor db,
    String tableName,
    String remoteId,
  ) async {
    if (remoteId.trim().isEmpty) return;
    await db.insert(
      'pending_deletes',
      {
        'table_name': tableName,
        'remote_id': remoteId,
        'deleted_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _clearPendingDelete(
    DatabaseExecutor db,
    String tableName,
    String remoteId,
  ) async {
    if (remoteId.trim().isEmpty) return;
    await db.delete(
      'pending_deletes',
      where: 'table_name = ? AND remote_id = ?',
      whereArgs: [tableName, remoteId],
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

  Future<int> upsertSupplier(Supplier supplier) {
    return _upsertSimpleMaster(
      tableName: 'supplier',
      idColumn: 'id_supplier',
      entityLabel: 'Supplier',
      localId: supplier.idSupplier,
      remoteId: supplier.remoteId,
      buildMap: (resolvedId) => resolvedId == null
          ? supplier.toMap()
          : supplier.copyWith(idSupplier: resolvedId).toMap(),
    );
  }

  Future<void> deleteSupplier(int idSupplier) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'supplier',
        columns: ['remote_id'],
        where: 'id_supplier = ?',
        whereArgs: [idSupplier],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Supplier tidak ditemukan atau sudah dihapus.');
      }
      final refFaktur = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM faktur WHERE id_supplier = ?',
              [idSupplier],
            ),
          ) ??
          0;
      if (refFaktur > 0) {
        throw StateError(
          'Supplier tidak dapat dihapus karena masih memiliki riwayat Faktur masuk.',
        );
      }
      final remoteId = (rows.first['remote_id'] as String?) ?? '';
      await _recordPendingDelete(txn, 'supplier', remoteId);
      await txn.delete(
        'supplier',
        where: 'id_supplier = ?',
        whereArgs: [idSupplier],
      );
    });
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

  Future<int> upsertCustomer(Customer customer) {
    return _upsertSimpleMaster(
      tableName: 'customer',
      idColumn: 'id_customer',
      entityLabel: 'Pelanggan',
      localId: customer.idCustomer,
      remoteId: customer.remoteId,
      buildMap: (resolvedId) => resolvedId == null
          ? customer.toMap()
          : customer.copyWith(idCustomer: resolvedId).toMap(),
    );
  }

  Future<void> deleteCustomer(int idCustomer) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'customer',
        columns: ['remote_id'],
        where: 'id_customer = ?',
        whereArgs: [idCustomer],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Pelanggan tidak ditemukan atau sudah dihapus.');
      }
      final refNota = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM nota WHERE id_customer = ?',
              [idCustomer],
            ),
          ) ??
          0;
      if (refNota > 0) {
        throw StateError(
          'Pelanggan tidak dapat dihapus karena masih tercatat pada riwayat Nota.',
        );
      }
      final remoteId = (rows.first['remote_id'] as String?) ?? '';
      await _recordPendingDelete(txn, 'customer', remoteId);
      await txn.delete(
        'customer',
        where: 'id_customer = ?',
        whereArgs: [idCustomer],
      );
    });
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
    return db.transaction((txn) async {
      final byRemoteRows = await txn.query(
        'petugas',
        where: 'remote_id = ?',
        whereArgs: [petugas.remoteId],
        limit: 1,
      );
      final byRemote =
          byRemoteRows.isEmpty ? null : Petugas.fromMap(byRemoteRows.first);

      final normalizedEmail = petugas.email.trim().toLowerCase();
      Petugas? byEmail;
      if (normalizedEmail.isNotEmpty) {
        final byEmailRows = await txn.query(
          'petugas',
          where: 'LOWER(email) = ?',
          whereArgs: [normalizedEmail],
          limit: 1,
        );
        if (byEmailRows.isNotEmpty) {
          byEmail = Petugas.fromMap(byEmailRows.first);
        }
      }

      Petugas? existing;
      if (petugas.idPetugas != null) {
        final byPkRows = await txn.query(
          'petugas',
          where: 'id_petugas = ?',
          whereArgs: [petugas.idPetugas],
          limit: 1,
        );
        if (byPkRows.isEmpty) {
          throw StateError('Petugas tidak ditemukan di database lokal.');
        }
        final byPk = Petugas.fromMap(byPkRows.first);
        if (byRemote != null && byRemote.idPetugas != byPk.idPetugas) {
          throw StateError(
            'Data Petugas lokal tidak konsisten dengan ID remote.',
          );
        }
        if (byEmail != null && byEmail.idPetugas != byPk.idPetugas) {
          throw StateError(
            'Email "$normalizedEmail" sudah digunakan oleh akun lain.',
          );
        }
        existing = byPk;
      } else {
        existing = byRemote ?? byEmail;
      }

      await _clearPendingDelete(txn, 'petugas', petugas.remoteId);

      if (existing == null) {
        return txn.insert('petugas', petugas.toMap());
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
      return txn.update(
        'petugas',
        merged.toMap(),
        where: 'id_petugas = ?',
        whereArgs: [existing.idPetugas],
      );
    });
  }

  Future<void> deletePetugas(int idPetugas) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'petugas',
        where: 'id_petugas = ?',
        whereArgs: [idPetugas],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Akun petugas tidak ditemukan atau sudah dihapus.');
      }
      final target = Petugas.fromMap(rows.first);
      if (target.role == UserRole.owner) {
        final ownerCount = Sqflite.firstIntValue(
              await txn.rawQuery(
                "SELECT COUNT(*) FROM petugas WHERE role = 'OWNER'",
              ),
            ) ??
            0;
        if (ownerCount <= 1) {
          throw StateError('Akun Owner terakhir tidak dapat dihapus.');
        }
      }
      final refFaktur = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM faktur WHERE id_petugas = ?',
              [idPetugas],
            ),
          ) ??
          0;
      final refNota = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM nota WHERE id_petugas = ?',
              [idPetugas],
            ),
          ) ??
          0;
      if (refFaktur > 0 || refNota > 0) {
        throw StateError(
          'Petugas tidak dapat dihapus karena masih tercatat pada transaksi Faktur/Nota.',
        );
      }
      await _recordPendingDelete(txn, 'petugas', target.remoteId);
      await txn.delete(
        'petugas',
        where: 'id_petugas = ?',
        whereArgs: [idPetugas],
      );
    });
  }

  // ==================== TRANSAKSI ATOMIK: FAKTUR & NOTA ====================

  static const int _maxTransactionQty = 9999999;
  static const String _cloudFallbackUpdatedAt = '1970-01-01T00:00:00.000Z';

  void _assertUniqueDetailBarangIds(Iterable<int> ids, String docName) {
    final seen = <int>{};
    for (final id in ids) {
      if (!seen.add(id)) {
        throw ArgumentError('Terdapat barang duplikat dalam satu $docName.');
      }
    }
  }

  void _assertValidTransactionAmounts({
    required String docName,
    required double total,
    required Iterable<({int qty, double jumlah})> items,
    required String emptyQtyMessage,
  }) {
    if (!total.isFinite || total < 0) {
      throw ArgumentError('Total $docName tidak valid.');
    }
    for (final item in items) {
      if (item.qty <= 0) {
        throw ArgumentError(emptyQtyMessage);
      }
      if (item.qty > _maxTransactionQty) {
        throw ArgumentError(
          'Jumlah barang $docName maksimal $_maxTransactionQty.',
        );
      }
      if (!item.jumlah.isFinite || item.jumlah < 0) {
        throw ArgumentError('Subtotal detail $docName tidak valid.');
      }
    }
  }

  Future<void> _assertRowExists(
    Transaction txn, {
    required String table,
    required String idColumn,
    required int id,
    required String entityLabel,
  }) async {
    final rows = await txn.query(
      table,
      columns: [idColumn],
      where: '$idColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('$entityLabel dengan id $id tidak ditemukan.');
    }
  }

  Future<void> _applyStockDeltas(
    Transaction txn,
    Map<int, int> stockDeltas, {
    required String updatedAtIso,
    required bool markBarangPending,
    bool useInsertNotaMessage = false,
  }) async {
    for (final entry in stockDeltas.entries) {
      final rows = await txn.query(
        'barang',
        columns: ['nama_barang', 'stok_barang'],
        where: 'id_barang = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Barang dengan id ${entry.key} tidak ditemukan.');
      }
      final currentStock = (rows.first['stok_barang'] as num).toInt();
      final namaBarang = rows.first['nama_barang'] as String;
      final nextStock = currentStock + entry.value;
      if (nextStock < 0) {
        if (useInsertNotaMessage) {
          throw StateError(
            'Stok "$namaBarang" tidak cukup (tersisa $currentStock, diminta ${-entry.value}).',
          );
        }
        throw StateError(
          'Stok "$namaBarang" tidak cukup untuk perubahan transaksi (tersisa $currentStock, selisih ${entry.value}).',
        );
      }
      if (nextStock > _maxTransactionQty) {
        throw StateError(
          'Stok "$namaBarang" melebihi batas maksimum ($_maxTransactionQty).',
        );
      }
      final updateValues = <String, Object?>{
        'stok_barang': nextStock,
        'updated_at': updatedAtIso,
      };
      if (markBarangPending) {
        updateValues['sync_status'] = SyncStatus.pending.value;
      }
      await txn.update(
        'barang',
        updateValues,
        where: 'id_barang = ?',
        whereArgs: [entry.key],
      );
    }
  }

  /// Menyimpan `faktur` beserta `detail_faktur` dan otomatis MENAMBAH `stok_barang`
  /// dalam satu transaksi SQLite atomik (berfungsi penuh saat offline).
  Future<int> insertFakturTransaction(
    Faktur faktur,
    List<DetailFaktur> details,
  ) async {
    if (details.isEmpty) {
      throw ArgumentError('Detail faktur tidak boleh kosong.');
    }
    _assertUniqueDetailBarangIds(details.map((e) => e.idBarang), 'faktur');
    _assertValidTransactionAmounts(
      docName: 'faktur',
      total: faktur.total,
      items: details.map((e) => (qty: e.quantity, jumlah: e.jumlah)),
      emptyQtyMessage: 'Quantity barang masuk harus lebih dari 0.',
    );
    final stockDeltas = <int, int>{};
    for (final item in details) {
      stockDeltas[item.idBarang] = item.quantity;
    }

    final db = await database;
    return db.transaction((txn) async {
      await _assertRowExists(
        txn,
        table: 'supplier',
        idColumn: 'id_supplier',
        id: faktur.idSupplier,
        entityLabel: 'Supplier',
      );
      await _assertRowExists(
        txn,
        table: 'petugas',
        idColumn: 'id_petugas',
        id: faktur.idPetugas,
        entityLabel: 'Petugas',
      );

      final updatedIso = faktur.updatedAt.toIso8601String();
      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: updatedIso,
        markBarangPending: false,
      );

      final fakturId = await txn.insert('faktur', faktur.toMap());
      for (final item in details) {
        await txn.insert(
          'detail_faktur',
          item.copyWith(idFaktur: fakturId).toMap(),
        );
      }
      return fakturId;
    });
  }

  /// Memperbarui header & detail `faktur` secara atomik dengan rekonsiliasi
  /// selisih stok barang masuk serta penandaan sinkronisasi Cloud.
  Future<void> updateFakturTransaction(
    Faktur updated,
    List<DetailFaktur> details,
  ) async {
    final idFaktur = updated.idFaktur;
    if (idFaktur == null) {
      throw ArgumentError('ID faktur wajib diisi untuk pembaruan.');
    }
    if (details.isEmpty) {
      throw ArgumentError('Detail faktur tidak boleh kosong.');
    }
    _assertUniqueDetailBarangIds(details.map((e) => e.idBarang), 'faktur');
    _assertValidTransactionAmounts(
      docName: 'faktur',
      total: updated.total,
      items: details.map((e) => (qty: e.quantity, jumlah: e.jumlah)),
      emptyQtyMessage: 'Quantity barang masuk harus lebih dari 0.',
    );

    final db = await database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
        limit: 1,
      );
      if (existingRows.isEmpty) {
        throw StateError('Faktur tidak ditemukan atau sudah dihapus.');
      }
      final existingRemoteId =
          (existingRows.first['remote_id'] as String?) ?? updated.remoteId;

      await _assertRowExists(
        txn,
        table: 'supplier',
        idColumn: 'id_supplier',
        id: updated.idSupplier,
        entityLabel: 'Supplier',
      );
      await _assertRowExists(
        txn,
        table: 'petugas',
        idColumn: 'id_petugas',
        id: updated.idPetugas,
        entityLabel: 'Petugas',
      );

      final oldDetailRows = await txn.query(
        'detail_faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
      final stockDeltas = <int, int>{};
      for (final row in oldDetailRows) {
        final idBarang = (row['id_barang'] as num).toInt();
        final oldQty = (row['quantity'] as num).toInt();
        stockDeltas[idBarang] = (stockDeltas[idBarang] ?? 0) - oldQty;
      }
      for (final item in details) {
        stockDeltas[item.idBarang] =
            (stockDeltas[item.idBarang] ?? 0) + item.quantity;
      }

      final updatedIso = updated.updatedAt.toIso8601String();
      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: updatedIso,
        markBarangPending: true,
      );

      final normalized = updated.copyWith(
        idFaktur: idFaktur,
        remoteId: existingRemoteId,
        syncStatus: SyncStatus.pending,
      );
      await txn.update(
        'faktur',
        normalized.toMap(),
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
      await txn.delete(
        'detail_faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
      for (final item in details) {
        await txn.insert(
          'detail_faktur',
          item.copyWith(idFaktur: idFaktur).toMap(),
        );
      }
    });
  }

  /// Menghapus `faktur` beserta detailnya secara atomik dan membalikkan
  /// penambahan stok barang jika stok gudang masih mencukupi.
  Future<void> deleteFakturTransaction(int idFaktur) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'faktur',
        columns: ['remote_id'],
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Faktur tidak ditemukan atau sudah dihapus.');
      }
      final remoteId = (rows.first['remote_id'] as String?) ?? '';
      final detailRows = await txn.query(
        'detail_faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
      final stockDeltas = <int, int>{};
      for (final row in detailRows) {
        final idBarang = (row['id_barang'] as num).toInt();
        final qty = (row['quantity'] as num).toInt();
        stockDeltas[idBarang] = (stockDeltas[idBarang] ?? 0) - qty;
      }

      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: DateTime.now().toIso8601String(),
        markBarangPending: true,
      );
      await _recordPendingDelete(txn, 'faktur', remoteId);
      await txn.delete(
        'faktur',
        where: 'id_faktur = ?',
        whereArgs: [idFaktur],
      );
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
    _assertUniqueDetailBarangIds(details.map((e) => e.idBarang), 'nota');
    _assertValidTransactionAmounts(
      docName: 'nota',
      total: nota.total,
      items: details.map((e) => (qty: e.banyaknya, jumlah: e.jumlah)),
      emptyQtyMessage: 'Banyaknya pembelian harus lebih dari 0.',
    );
    final stockDeltas = <int, int>{};
    for (final item in details) {
      stockDeltas[item.idBarang] = -item.banyaknya;
    }

    final db = await database;
    return db.transaction((txn) async {
      await _assertRowExists(
        txn,
        table: 'customer',
        idColumn: 'id_customer',
        id: nota.idCustomer,
        entityLabel: 'Customer',
      );
      await _assertRowExists(
        txn,
        table: 'petugas',
        idColumn: 'id_petugas',
        id: nota.idPetugas,
        entityLabel: 'Petugas',
      );

      final updatedIso = nota.updatedAt.toIso8601String();
      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: updatedIso,
        markBarangPending: false,
        useInsertNotaMessage: true,
      );

      final notaId = await txn.insert('nota', nota.toMap());
      for (final item in details) {
        await txn.insert(
          'detail_nota',
          item.copyWith(idNota: notaId).toMap(),
        );
      }
      return notaId;
    });
  }

  /// Memperbarui header & detail `nota` secara atomik dengan mengembalikan stok
  /// lama lalu memotong stok baru beserta penandaan sinkronisasi Cloud.
  Future<void> updateNotaTransaction(
    Nota updated,
    List<DetailNota> details,
  ) async {
    final idNota = updated.idNota;
    if (idNota == null) {
      throw ArgumentError('ID nota wajib diisi untuk pembaruan.');
    }
    if (details.isEmpty) {
      throw ArgumentError('Detail nota tidak boleh kosong.');
    }
    _assertUniqueDetailBarangIds(details.map((e) => e.idBarang), 'nota');
    _assertValidTransactionAmounts(
      docName: 'nota',
      total: updated.total,
      items: details.map((e) => (qty: e.banyaknya, jumlah: e.jumlah)),
      emptyQtyMessage: 'Banyaknya pembelian harus lebih dari 0.',
    );

    final db = await database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'nota',
        where: 'id_nota = ?',
        whereArgs: [idNota],
        limit: 1,
      );
      if (existingRows.isEmpty) {
        throw StateError('Nota tidak ditemukan atau sudah dihapus.');
      }
      final existingRemoteId =
          (existingRows.first['remote_id'] as String?) ?? updated.remoteId;

      await _assertRowExists(
        txn,
        table: 'customer',
        idColumn: 'id_customer',
        id: updated.idCustomer,
        entityLabel: 'Customer',
      );
      await _assertRowExists(
        txn,
        table: 'petugas',
        idColumn: 'id_petugas',
        id: updated.idPetugas,
        entityLabel: 'Petugas',
      );

      final oldDetailRows = await txn.query(
        'detail_nota',
        where: 'id_nota = ?',
        whereArgs: [idNota],
      );
      final stockDeltas = <int, int>{};
      for (final row in oldDetailRows) {
        final idBarang = (row['id_barang'] as num).toInt();
        final oldQty = (row['banyaknya'] as num).toInt();
        stockDeltas[idBarang] = (stockDeltas[idBarang] ?? 0) + oldQty;
      }
      for (final item in details) {
        stockDeltas[item.idBarang] =
            (stockDeltas[item.idBarang] ?? 0) - item.banyaknya;
      }

      final updatedIso = updated.updatedAt.toIso8601String();
      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: updatedIso,
        markBarangPending: true,
      );

      final normalized = updated.copyWith(
        idNota: idNota,
        remoteId: existingRemoteId,
        syncStatus: SyncStatus.pending,
      );
      await txn.update(
        'nota',
        normalized.toMap(),
        where: 'id_nota = ?',
        whereArgs: [idNota],
      );
      await txn.delete(
        'detail_nota',
        where: 'id_nota = ?',
        whereArgs: [idNota],
      );
      for (final item in details) {
        await txn.insert(
          'detail_nota',
          item.copyWith(idNota: idNota).toMap(),
        );
      }
    });
  }

  /// Menghapus `nota` beserta detailnya secara atomik dan mengembalikan stok
  /// barang yang sempat terjual.
  Future<void> deleteNotaTransaction(int idNota) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'nota',
        columns: ['remote_id'],
        where: 'id_nota = ?',
        whereArgs: [idNota],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Nota tidak ditemukan atau sudah dihapus.');
      }
      final remoteId = (rows.first['remote_id'] as String?) ?? '';
      final detailRows = await txn.query(
        'detail_nota',
        where: 'id_nota = ?',
        whereArgs: [idNota],
      );
      final stockDeltas = <int, int>{};
      for (final row in detailRows) {
        final idBarang = (row['id_barang'] as num).toInt();
        final qty = (row['banyaknya'] as num).toInt();
        stockDeltas[idBarang] = (stockDeltas[idBarang] ?? 0) + qty;
      }

      await _applyStockDeltas(
        txn,
        stockDeltas,
        updatedAtIso: DateTime.now().toIso8601String(),
        markBarangPending: true,
      );
      await _recordPendingDelete(txn, 'nota', remoteId);
      await txn.delete(
        'nota',
        where: 'id_nota = ?',
        whereArgs: [idNota],
      );
    });
  }

  /// Mengambil daftar `faktur` lengkap dengan nama supplier & petugas.
  Future<List<Faktur>> getAllFaktur() => _fetchFaktur();

  /// Mengambil satu `faktur` berdasarkan [idFaktur] atau null jika tidak ditemukan.
  Future<Faktur?> getFakturById(int idFaktur) async {
    final list = await _fetchFaktur(
      whereClause: 'WHERE f.id_faktur = ?',
      whereArgs: [idFaktur],
    );
    return list.isEmpty ? null : list.first;
  }

  /// Mengambil antrean `faktur` yang belum tersinkron (`PENDING`).
  Future<List<Faktur>> getPendingFaktur() =>
      _fetchFaktur(whereClause: "WHERE f.sync_status = 'PENDING'");

  Future<List<Faktur>> _fetchFaktur({
    String whereClause = '',
    List<Object?> whereArgs = const [],
  }) async {
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
    ''', whereArgs);
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

  /// Mengambil satu `nota` berdasarkan [idNota] atau null jika tidak ditemukan.
  Future<Nota?> getNotaById(int idNota) async {
    final list = await _fetchNota(
      whereClause: 'WHERE n.id_nota = ?',
      whereArgs: [idNota],
    );
    return list.isEmpty ? null : list.first;
  }

  /// Mengambil antrean `nota` yang belum tersinkron (`PENDING`).
  Future<List<Nota>> getPendingNota() =>
      _fetchNota(whereClause: "WHERE n.sync_status = 'PENDING'");

  Future<List<Nota>> _fetchNota({
    String whereClause = '',
    List<Object?> whereArgs = const [],
  }) async {
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
    ''', whereArgs);
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
    if (await hasPendingDelete('supplier', cloudSupplier.remoteId)) return;
    final existing = await getSupplierByRemoteId(cloudSupplier.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertSupplier(cloudSupplier.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudPetugas(Petugas cloudPetugas) async {
    if (await hasPendingDelete('petugas', cloudPetugas.remoteId)) return;
    final existing = await getPetugasByRemoteId(cloudPetugas.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertPetugas(cloudPetugas.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudCustomer(Customer cloudCustomer) async {
    if (await hasPendingDelete('customer', cloudCustomer.remoteId)) return;
    final existing = await getCustomerByRemoteId(cloudCustomer.remoteId);
    if (existing != null && existing.syncStatus == SyncStatus.pending) {
      return;
    }
    await upsertCustomer(cloudCustomer.copyWith(syncStatus: SyncStatus.synced));
  }

  Future<void> applyCloudBarang(Barang cloudBarang) async {
    if (await hasPendingDelete('barang', cloudBarang.remoteId)) return;
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

  String _resolveCloudUpdatedAt(Object? rawUpdatedAt) {
    if (rawUpdatedAt is String) {
      final trimmed = rawUpdatedAt.trim();
      if (DateTime.tryParse(trimmed) != null) {
        return trimmed;
      }
    }
    return _cloudFallbackUpdatedAt;
  }

  bool _shouldSkipCloudTransactionWrite({
    required List<Map<String, Object?>> existing,
    required String cloudUpdatedAt,
  }) {
    if (existing.isEmpty) return false;
    final status = existing.first['sync_status'] as String?;
    if (status == SyncStatus.pending.value) return true;
    final localUpdatedAt = existing.first['updated_at'] as String?;
    if (localUpdatedAt == cloudUpdatedAt) return true;
    if (localUpdatedAt != null) {
      final localDt = DateTime.tryParse(localUpdatedAt);
      final cloudDt = DateTime.tryParse(cloudUpdatedAt);
      if (localDt != null && cloudDt != null && !cloudDt.isAfter(localDt)) {
        return true;
      }
    }
    return false;
  }

  double? _resolveCloudTotal(Object? rawTotal, double fallbackSum) {
    if (rawTotal == null) return fallbackSum;
    if (rawTotal is! num) return null;
    final total = rawTotal.toDouble();
    if (!total.isFinite || total < 0) return null;
    return total;
  }

  Future<List<T>?> _resolveCloudTransactionDetails<T>({
    required Object? rawDetails,
    required String qtyKey,
    required T Function(
      int idBarang,
      String barangRemoteId,
      double jumlah,
      int qty,
    ) builder,
  }) async {
    if (rawDetails is! List || rawDetails.isEmpty) return null;
    final seenBarangIds = <int>{};
    final resolved = <T>[];
    for (final raw in rawDetails) {
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final barangRemoteId = map['barang_remote_id'];
      if (barangRemoteId is! String || barangRemoteId.trim().isEmpty) {
        return null;
      }
      final rawQty = map[qtyKey];
      final qty = rawQty is num && rawQty.isFinite ? rawQty.toInt() : 0;
      final rawJumlah = map['jumlah'];
      final jumlah = rawJumlah is num ? rawJumlah.toDouble() : -1.0;
      if (qty <= 0 ||
          qty > _maxTransactionQty ||
          !jumlah.isFinite ||
          jumlah < 0) {
        return null;
      }
      final barang = await getBarangByRemoteId(barangRemoteId);
      final idBarang = barang?.idBarang;
      if (idBarang == null || !seenBarangIds.add(idBarang)) {
        return null;
      }
      resolved.add(builder(idBarang, barangRemoteId, jumlah, qty));
    }
    return resolved;
  }

  /// Menyimpan atau memperbarui `faktur` dari Cloud Firestore secara aman
  /// (mengabaikan entri di `pending_deletes` atau `sync_status = PENDING`,
  /// tanpa memodifikasi `stok_barang` karena stok diambil dari koleksi `barang`).
  Future<bool> insertCloudFakturIfMissing({
    required String remoteId,
    required Map<String, dynamic> data,
  }) async {
    if (remoteId.trim().isEmpty) return false;
    if (await hasPendingDelete('faktur', remoteId)) return false;

    final db = await database;
    final existing = await db.query(
      'faktur',
      columns: ['id_faktur', 'sync_status', 'updated_at'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    final cloudUpdatedAt = _resolveCloudUpdatedAt(data['updated_at']);
    if (_shouldSkipCloudTransactionWrite(
      existing: existing,
      cloudUpdatedAt: cloudUpdatedAt,
    )) {
      return false;
    }

    final supplierRemoteId = data['supplier_remote_id'];
    final petugasRemoteId = data['petugas_remote_id'];
    if (supplierRemoteId is! String ||
        supplierRemoteId.trim().isEmpty ||
        petugasRemoteId is! String ||
        petugasRemoteId.trim().isEmpty) {
      return false;
    }

    final supplier = await getSupplierByRemoteId(supplierRemoteId);
    final petugas = await getPetugasByRemoteId(petugasRemoteId);
    if (supplier?.idSupplier == null || petugas?.idPetugas == null) {
      return false;
    }

    final resolvedDetails = await _resolveCloudTransactionDetails<DetailFaktur>(
      rawDetails: data['details'],
      qtyKey: 'quantity',
      builder: (idBarang, barangRemoteId, jumlah, qty) => DetailFaktur(
        idBarang: idBarang,
        jumlah: jumlah,
        quantity: qty,
        barangRemoteId: barangRemoteId,
      ),
    );
    if (resolvedDetails == null) return false;

    final resolvedTotal = _resolveCloudTotal(
      data['total'],
      Faktur.hitungTotal(resolvedDetails),
    );
    if (resolvedTotal == null) return false;

    final fakturValues = <String, Object?>{
      'no_faktur': (data['no_faktur'] as String?) ?? '',
      'tanggal_faktur': (data['tanggal_faktur'] as String?) ?? '',
      'total': resolvedTotal,
      'id_supplier': supplier!.idSupplier!,
      'id_petugas': petugas!.idPetugas!,
      'remote_id': remoteId,
      'supplier_remote_id': supplierRemoteId,
      'petugas_remote_id': petugasRemoteId,
      'sync_status': SyncStatus.synced.value,
      'updated_at': cloudUpdatedAt,
    };

    await db.transaction((txn) async {
      final int fakturId;
      if (existing.isEmpty) {
        fakturId = await txn.insert('faktur', fakturValues);
      } else {
        fakturId = (existing.first['id_faktur'] as num).toInt();
        await txn.update(
          'faktur',
          fakturValues,
          where: 'id_faktur = ?',
          whereArgs: [fakturId],
        );
        await txn.delete(
          'detail_faktur',
          where: 'id_faktur = ?',
          whereArgs: [fakturId],
        );
      }
      for (final item in resolvedDetails) {
        await txn.insert(
          'detail_faktur',
          item.copyWith(idFaktur: fakturId).toMap(),
        );
      }
    });
    return true;
  }

  /// Menyimpan atau memperbarui `nota` dari Cloud Firestore secara aman
  /// (mengabaikan entri di `pending_deletes` atau `sync_status = PENDING`,
  /// tanpa memodifikasi `stok_barang` karena stok diambil dari koleksi `barang`).
  Future<bool> insertCloudNotaIfMissing({
    required String remoteId,
    required Map<String, dynamic> data,
  }) async {
    if (remoteId.trim().isEmpty) return false;
    if (await hasPendingDelete('nota', remoteId)) return false;

    final db = await database;
    final existing = await db.query(
      'nota',
      columns: ['id_nota', 'sync_status', 'updated_at'],
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );
    final cloudUpdatedAt = _resolveCloudUpdatedAt(data['updated_at']);
    if (_shouldSkipCloudTransactionWrite(
      existing: existing,
      cloudUpdatedAt: cloudUpdatedAt,
    )) {
      return false;
    }

    final petugasRemoteId = data['petugas_remote_id'];
    final customerRemoteId = data['customer_remote_id'];
    if (petugasRemoteId is! String ||
        petugasRemoteId.trim().isEmpty ||
        customerRemoteId is! String ||
        customerRemoteId.trim().isEmpty) {
      return false;
    }

    final petugas = await getPetugasByRemoteId(petugasRemoteId);
    final customer = await getCustomerByRemoteId(customerRemoteId);
    if (petugas?.idPetugas == null || customer?.idCustomer == null) {
      return false;
    }

    final resolvedDetails = await _resolveCloudTransactionDetails<DetailNota>(
      rawDetails: data['details'],
      qtyKey: 'banyaknya',
      builder: (idBarang, barangRemoteId, jumlah, qty) => DetailNota(
        idBarang: idBarang,
        jumlah: jumlah,
        banyaknya: qty,
        barangRemoteId: barangRemoteId,
      ),
    );
    if (resolvedDetails == null) return false;

    final resolvedTotal = _resolveCloudTotal(
      data['total'],
      Nota.hitungTotal(resolvedDetails),
    );
    if (resolvedTotal == null) return false;

    final notaValues = <String, Object?>{
      'tanggal_nota': (data['tanggal_nota'] as String?) ?? '',
      'total': resolvedTotal,
      'id_petugas': petugas!.idPetugas!,
      'id_customer': customer!.idCustomer!,
      'remote_id': remoteId,
      'petugas_remote_id': petugasRemoteId,
      'customer_remote_id': customerRemoteId,
      'sync_status': SyncStatus.synced.value,
      'updated_at': cloudUpdatedAt,
    };

    await db.transaction((txn) async {
      final int notaId;
      if (existing.isEmpty) {
        notaId = await txn.insert('nota', notaValues);
      } else {
        notaId = (existing.first['id_nota'] as num).toInt();
        await txn.update(
          'nota',
          notaValues,
          where: 'id_nota = ?',
          whereArgs: [notaId],
        );
        await txn.delete(
          'detail_nota',
          where: 'id_nota = ?',
          whereArgs: [notaId],
        );
      }
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
