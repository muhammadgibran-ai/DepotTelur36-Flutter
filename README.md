# 🥚 DepotTelur36 — Mobile POS & Inventory Management

Aplikasi **Point of Sales (POS) & Inventory Management Mobile** berbasis **Offline-First & Cloud Realtime Sync** untuk UMKM **DepotTelur36**.

---

## 👥 Tim Pengembang

| Role | Nama |
| :--- | :--- |
| **Project Manager (PM)** | **Rafli Abid Ghalid** |
| **Business Analyst (BA)** | **Mahier Mohammad Hinandar** |
| **Risk Manager (RM)** | **Muhammad Rakha Fadhlany** |
| **System Analyst 1 (SA-1)** | **Fakhri Shafwan Malik** |
| **System Analyst 2 (SA-2)** | **Muhammad Gibran Ramadhan** |

---

## 🏗️ Arsitektur & Tech Stack

- **Mobile Framework**: Flutter (Dart)
- **Software Architecture**: MVVM (*Model – View – ViewModel*) + *Repository Pattern*
- **Local Offline Database**: SQLite (`sqflite`) — 8 Tabel Relasional (`supplier`, `petugas`, `customer`, `barang`, `faktur`, `detail_faktur`, `nota`, `detail_nota`)
- **Cloud Realtime Database**: Firebase Cloud Firestore (`depottelur36-570a9`)
- **Sinkronisasi**: *Offline-First Auto-Sync* (Petugas tetap dapat menginput Faktur Supplier & Nota Penjualan saat offline, dan otomatis tersinkronisasi ke Cloud & HP Owner saat terhubung ke internet)
