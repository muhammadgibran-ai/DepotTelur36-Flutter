import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';

/// Layar Pendev `19 Detail & Edit Faktur` untuk melihat, memperbarui, atau menghapus Faktur.
class DetailFakturScreen extends StatefulWidget {
  const DetailFakturScreen({
    super.key,
    required this.viewModel,
    required this.faktur,
  });

  final TransactionCrudViewModel viewModel;
  final Faktur faktur;

  @override
  State<DetailFakturScreen> createState() => _DetailFakturScreenState();
}

class _DetailFakturScreenState extends State<DetailFakturScreen> {
  late Faktur _faktur;
  late final TextEditingController _noFakturController;
  late String _tanggalFaktur;
  int? _supplierId;
  int? _petugasId;
  final Map<int, int> _draftQty = <int, int>{};
  final Map<int, int> _originalQty = <int, int>{};
  String? _localError;
  int _errorPulse = 0;

  @override
  void initState() {
    super.initState();
    _faktur = widget.faktur;
    _noFakturController = TextEditingController(text: _faktur.noFaktur);
    _tanggalFaktur = _faktur.tanggalFaktur;
    _supplierId = _faktur.idSupplier;
    _petugasId = _faktur.idPetugas;
    for (final detail in _faktur.details) {
      _draftQty[detail.idBarang] = detail.quantity;
      _originalQty[detail.idBarang] = detail.quantity;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        widget.viewModel.clearMessages();
        _refreshLatestFaktur();
      }
    });
  }

  @override
  void dispose() {
    _noFakturController.dispose();
    super.dispose();
  }

  Future<void> _refreshLatestFaktur() async {
    final id = _faktur.idFaktur;
    if (id == null) return;
    final fresh = await widget.viewModel.reloadFakturById(id);
    if (!mounted || fresh == null) return;
    setState(() {
      _faktur = fresh;
    });
  }

  Supplier? _resolveSupplier() {
    for (final s in widget.viewModel.suppliers) {
      if (s.idSupplier == _supplierId) return s;
    }
    return null;
  }

  Petugas? _resolvePetugas() {
    for (final p in widget.viewModel.petugasList) {
      if (p.idPetugas == _petugasId) return p;
    }
    return widget.viewModel.activePetugas;
  }

  Barang? _resolveBarang(int idBarang) {
    for (final b in widget.viewModel.barangs) {
      if (b.idBarang == idBarang) return b;
    }
    for (final d in _faktur.details) {
      if (d.idBarang == idBarang) {
        final unitPrice = d.quantity > 0 ? d.jumlah / d.quantity : 0.0;
        return Barang(
          idBarang: idBarang,
          namaBarang: d.namaBarang ?? 'Barang #$idBarang',
          stokBarang: 0,
          satuan: d.satuan ?? 'Unit',
          hargaSatuan: unitPrice,
          remoteId: d.barangRemoteId ?? 'local-$idBarang',
          syncStatus: SyncStatus.synced,
          updatedAt: _faktur.updatedAt,
        );
      }
    }
    return null;
  }

  List<CartLineDraft> _buildLines() {
    final lines = <CartLineDraft>[];
    for (final entry in _draftQty.entries) {
      if (entry.value <= 0) continue;
      final barang = _resolveBarang(entry.key);
      if (barang != null) {
        lines.add(CartLineDraft(barang: barang, qty: entry.value));
      }
    }
    return lines;
  }

  void _setError(String message) {
    setState(() {
      _localError = message;
      _errorPulse++;
    });
  }

  Future<void> _pickSupplier() async {
    final selected = await showEntitySelectorSheet<Supplier>(
      context: context,
      title: 'Pilih Supplier',
      items: widget.viewModel.suppliers,
      labelOf: (s) => s.namaSupplier,
      subtitleOf: (s) => s.noTelpSupplier,
      selected: _resolveSupplier(),
      equals: (a, b) => a.idSupplier == b.idSupplier,
    );
    if (selected?.idSupplier != null && mounted) {
      setState(() {
        _supplierId = selected!.idSupplier;
        _localError = null;
      });
    }
  }

  Future<void> _pickPetugas() async {
    final selected = await showEntitySelectorSheet<Petugas>(
      context: context,
      title: 'Pilih Petugas Penerima',
      items: widget.viewModel.petugasList,
      labelOf: (p) => p.namaPetugas,
      subtitleOf: (p) => p.role.label,
      selected: _resolvePetugas(),
      equals: (a, b) => a.idPetugas == b.idPetugas,
    );
    if (selected?.idPetugas != null && mounted) {
      setState(() {
        _petugasId = selected!.idPetugas;
        _localError = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await pickTransactionDate(context, _tanggalFaktur);
    if (picked != null && mounted) {
      setState(() {
        _tanggalFaktur = TransactionCrudViewModel.toIsoDateString(picked);
        _localError = null;
      });
    }
  }

  Future<void> _openCatalogPicker() async {
    await showCatalogItemPickerSheet(
      context: context,
      title: 'Tambah Barang ke Faktur',
      barangs: widget.viewModel.barangs,
      currentQtyFor: (b) => b.idBarang == null ? 0 : (_draftQty[b.idBarang!] ?? 0),
      enforceAvailableStock: false,
      onAddBarang: (b) {
        final id = b.idBarang;
        if (id == null) return;
        setState(() {
          _draftQty[id] = (_draftQty[id] ?? 0) + 1;
          _localError = null;
        });
      },
    );
  }

  Future<void> _saveChanges() async {
    final lines = _buildLines();
    if (lines.isEmpty) {
      _setError('Detail faktur wajib berisi minimal 1 barang.');
      return;
    }
    final supplier = _resolveSupplier();
    if (supplier == null || supplier.idSupplier == null) {
      _setError('Supplier wajib dipilih.');
      return;
    }
    final petugas = _resolvePetugas();
    if (petugas == null || petugas.idPetugas == null) {
      _setError('Petugas penerima tidak ditemukan.');
      return;
    }

    final ok = await widget.viewModel.updateFakturRecord(
      existing: _faktur,
      noFaktur: _noFakturController.text,
      tanggalFaktur: _tanggalFaktur,
      supplier: supplier,
      petugas: petugas,
      items: lines
          .map((e) => (barang: e.barang, quantity: e.qty))
          .toList(growable: false),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _localError =
            widget.viewModel.errorMessage ?? 'Gagal memperbarui faktur.';
        _errorPulse++;
      });
    }
  }

  Future<void> _deleteFaktur() async {
    final id = _faktur.idFaktur;
    if (id == null) {
      _setError('Faktur lokal tidak memiliki ID.');
      return;
    }
    final ok = await widget.viewModel.deleteFakturRecord(id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _localError =
            widget.viewModel.errorMessage ?? 'Gagal menghapus faktur.';
        _errorPulse++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final lines = _buildLines();
        final grandTotal = lines.fold(0.0, (sum, l) => sum + l.subtotal);
        final supplierName =
            _resolveSupplier()?.namaSupplier ??
            _faktur.namaSupplier ??
            'Pilih supplier';
        final petugasName =
            _resolvePetugas()?.namaPetugas ??
            _faktur.namaPetugas ??
            'Pilih petugas';

        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              MasterAmberHeader(
                title: 'Faktur ${_faktur.noFaktur}',
                subtitle: 'Edit rincian penerimaan stok atau hapus faktur',
                showBackButton: true,
                badgeLabel: _faktur.syncStatus == SyncStatus.pending
                    ? 'Pending Sync'
                    : 'Tersinkron Cloud',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  children: [
                    ShakeOnError(
                      pulse: _errorPulse,
                      child: AuthFeedbackBanner(
                        errorMessage: _localError,
                        onDismiss: () => setState(() => _localError = null),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No. Faktur Supplier',
                            style: AppTypography.body(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            key: const ValueKey('detail_faktur_no_field'),
                            controller: _noFakturController,
                            onChanged: (_) {
                              if (_localError != null) {
                                setState(() => _localError = null);
                              }
                            },
                            style: AppTypography.body(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Contoh: FKT-20260221-001',
                              filled: true,
                              fillColor: AppColors.surfaceWarm,
                              prefixIcon: const Icon(
                                Icons.receipt_long_outlined,
                                size: 19,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.borderSubtle,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.borderSubtle,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.ink,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_faktur_supplier'),
                            label: 'Supplier',
                            valueText: supplierName,
                            leadingIcon: Icons.local_shipping_outlined,
                            trailingIcon: Icons.keyboard_arrow_down_rounded,
                            onTap: _pickSupplier,
                          ),
                          const SizedBox(height: 12),
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_faktur_date'),
                            label: 'Tanggal Faktur',
                            valueText:
                                TransactionCrudViewModel.formatDisplayDate(
                                  _tanggalFaktur,
                                ),
                            leadingIcon: Icons.calendar_today_rounded,
                            trailingIcon: Icons.edit_calendar_rounded,
                            onTap: _pickDate,
                          ),
                          const SizedBox(height: 12),
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_faktur_petugas'),
                            label: 'Petugas Penerima',
                            valueText: petugasName,
                            leadingIcon: Icons.badge_outlined,
                            trailingIcon: Icons.keyboard_arrow_down_rounded,
                            onTap: _pickPetugas,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rincian Barang Faktur (${lines.length})',
                            style: AppTypography.heading(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('detail_faktur_add_item'),
                          onPressed: _openCatalogPicker,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: AppColors.ink,
                          ),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          label: Text(
                            'Tambah Barang',
                            style: AppTypography.body(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (lines.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Text(
                          'Belum ada item di faktur ini. Ketuk "Tambah Barang" untuk menambahkan item.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      for (final line in lines) ...[
                        Builder(
                          builder: (context) {
                            final id = line.barang.idBarang!;
                            final orig = _originalQty[id] ?? 0;
                            final deltaPreview = line.qty - orig;
                            return DetailLineItemCard(
                              itemKeyPrefix: 'detail_faktur_$id',
                              barang: line.barang,
                              qty: line.qty,
                              currentWarehouseStock: line.barang.stokBarang,
                              stockDeltaPreview: deltaPreview == 0
                                  ? null
                                  : deltaPreview,
                              onIncrement: () {
                                setState(() {
                                  _draftQty[id] = line.qty + 1;
                                  _localError = null;
                                });
                              },
                              onDecrement: () {
                                setState(() {
                                  if (line.qty <= 1) {
                                    _draftQty.remove(id);
                                  } else {
                                    _draftQty[id] = line.qty - 1;
                                  }
                                  _localError = null;
                                });
                              },
                              onRemove: () {
                                setState(() {
                                  _draftQty.remove(id);
                                  _localError = null;
                                });
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              TransactionBottomSummarySheet(
                totalLabel: 'Total Pembelian Faktur',
                totalAmount: grandTotal,
                deleteLabel: 'Hapus Faktur',
                deleteWarningText:
                    'Hapus Faktur ${_faktur.noFaktur}? Penambahan stok dari faktur ini akan ditarik kembali.',
                isSubmitting: vm.isSubmitting,
                saveKey: const ValueKey('detail_faktur_save_button'),
                deleteKey: const ValueKey('detail_faktur_delete_button'),
                onDeleteConfirmed: _deleteFaktur,
                onSaveChanges: _saveChanges,
              ),
            ],
          ),
        );
      },
    );
  }
}
