import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/models/transaksi.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';

/// Layar Pendev `17 Detail & Edit Nota` untuk melihat, mengubah, atau menghapus Nota.
class DetailNotaScreen extends StatefulWidget {
  const DetailNotaScreen({
    super.key,
    required this.viewModel,
    required this.nota,
  });

  final TransactionCrudViewModel viewModel;
  final Nota nota;

  @override
  State<DetailNotaScreen> createState() => _DetailNotaScreenState();
}

class _DetailNotaScreenState extends State<DetailNotaScreen> {
  late Nota _nota;
  late String _tanggalNota;
  int? _customerId;
  int? _petugasId;
  final Map<int, int> _draftQty = <int, int>{};
  final Map<int, int> _originalQty = <int, int>{};
  String? _localError;
  int _errorPulse = 0;

  @override
  void initState() {
    super.initState();
    _nota = widget.nota;
    _tanggalNota = _nota.tanggalNota;
    _customerId = _nota.idCustomer;
    _petugasId = _nota.idPetugas;
    for (final detail in _nota.details) {
      _draftQty[detail.idBarang] = detail.banyaknya;
      _originalQty[detail.idBarang] = detail.banyaknya;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        widget.viewModel.clearMessages();
        _refreshLatestNota();
      }
    });
  }

  Future<void> _refreshLatestNota() async {
    final id = _nota.idNota;
    if (id == null) return;
    final fresh = await widget.viewModel.reloadNotaById(id);
    if (!mounted || fresh == null) return;
    setState(() {
      _nota = fresh;
    });
  }

  Customer? _resolveCustomer() {
    for (final c in widget.viewModel.customers) {
      if (c.idCustomer == _customerId) return c;
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
    for (final d in _nota.details) {
      if (d.idBarang == idBarang) {
        final unitPrice = d.banyaknya > 0 ? d.jumlah / d.banyaknya : 0.0;
        return Barang(
          idBarang: idBarang,
          namaBarang: d.namaBarang ?? 'Barang #$idBarang',
          stokBarang: 0,
          satuan: d.satuan ?? 'Unit',
          hargaSatuan: unitPrice,
          remoteId: d.barangRemoteId ?? 'local-$idBarang',
          syncStatus: SyncStatus.synced,
          updatedAt: _nota.updatedAt,
        );
      }
    }
    return null;
  }

  int _maxAllowedQtyFor(Barang barang) {
    final id = barang.idBarang;
    if (id == null) return barang.stokBarang;
    return barang.stokBarang + (_originalQty[id] ?? 0);
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

  Future<void> _pickCustomer() async {
    final selected = await showEntitySelectorSheet<Customer>(
      context: context,
      title: 'Pilih Pelanggan',
      items: widget.viewModel.customers,
      labelOf: (c) => c.namaCustomer,
      selected: _resolveCustomer(),
      equals: (a, b) => a.idCustomer == b.idCustomer,
    );
    if (selected?.idCustomer != null && mounted) {
      setState(() {
        _customerId = selected!.idCustomer;
        _localError = null;
      });
    }
  }

  Future<void> _pickPetugas() async {
    final selected = await showEntitySelectorSheet<Petugas>(
      context: context,
      title: 'Pilih Petugas Kasir',
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
    final picked = await pickTransactionDate(context, _tanggalNota);
    if (picked != null && mounted) {
      setState(() {
        _tanggalNota = TransactionCrudViewModel.toIsoDateString(picked);
        _localError = null;
      });
    }
  }

  Future<void> _openCatalogPicker() async {
    await showCatalogItemPickerSheet(
      context: context,
      title: 'Tambah Barang ke Nota',
      barangs: widget.viewModel.barangs,
      currentQtyFor: (b) => b.idBarang == null ? 0 : (_draftQty[b.idBarang!] ?? 0),
      enforceAvailableStock: false,
      onAddBarang: (b) {
        final id = b.idBarang;
        if (id == null) return;
        final current = _draftQty[id] ?? 0;
        final maxAllowed = _maxAllowedQtyFor(b);
        if (current + 1 > maxAllowed) {
          _setError(
            'Stok "${b.namaBarang}" maksimal $maxAllowed ${b.satuan} untuk perubahan nota ini.',
          );
          return;
        }
        setState(() {
          _draftQty[id] = current + 1;
          _localError = null;
        });
      },
    );
  }

  Future<void> _saveChanges() async {
    final lines = _buildLines();
    if (lines.isEmpty) {
      _setError('Detail nota wajib berisi minimal 1 barang.');
      return;
    }
    final customer = _resolveCustomer();
    if (customer == null || customer.idCustomer == null) {
      _setError('Pelanggan wajib dipilih.');
      return;
    }
    final petugas = _resolvePetugas();
    if (petugas == null || petugas.idPetugas == null) {
      _setError('Petugas kasir tidak ditemukan.');
      return;
    }

    final ok = await widget.viewModel.updateNotaRecord(
      existing: _nota,
      tanggalNota: _tanggalNota,
      customer: customer,
      petugas: petugas,
      items: lines
          .map((e) => (barang: e.barang, banyaknya: e.qty))
          .toList(growable: false),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _localError =
            widget.viewModel.errorMessage ?? 'Gagal memperbarui nota.';
        _errorPulse++;
      });
    }
  }

  Future<void> _deleteNota() async {
    final id = _nota.idNota;
    if (id == null) {
      _setError('Nota lokal tidak memiliki ID.');
      return;
    }
    final ok = await widget.viewModel.deleteNotaRecord(id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _localError =
            widget.viewModel.errorMessage ?? 'Gagal menghapus nota.';
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
        final customerName =
            _resolveCustomer()?.namaCustomer ??
            _nota.namaCustomer ??
            'Pilih pelanggan';
        final petugasName =
            _resolvePetugas()?.namaPetugas ??
            _nota.namaPetugas ??
            'Pilih petugas';

        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              MasterAmberHeader(
                title: 'Detail Nota #${_nota.idNota ?? '-'}',
                subtitle: 'Ubah rincian pembelian atau batalkan nota',
                showBackButton: true,
                badgeLabel: _nota.syncStatus == SyncStatus.pending
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
                        children: [
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_nota_customer'),
                            label: 'Pelanggan',
                            valueText: customerName,
                            leadingIcon: Icons.person_outline_rounded,
                            trailingIcon: Icons.keyboard_arrow_down_rounded,
                            onTap: _pickCustomer,
                          ),
                          const SizedBox(height: 12),
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_nota_date'),
                            label: 'Tanggal Nota',
                            valueText:
                                TransactionCrudViewModel.formatDisplayDate(
                                  _tanggalNota,
                                ),
                            leadingIcon: Icons.calendar_today_rounded,
                            trailingIcon: Icons.edit_calendar_rounded,
                            onTap: _pickDate,
                          ),
                          const SizedBox(height: 12),
                          TransactionMetaSelectorTile(
                            tileKey: const ValueKey('detail_nota_petugas'),
                            label: 'Petugas Kasir',
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
                            'Rincian Barang Nota (${lines.length})',
                            style: AppTypography.heading(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('detail_nota_add_item'),
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
                          'Belum ada item di nota ini. Ketuk "Tambah Barang" untuk menambahkan item.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      for (final line in lines) ...[
                        DetailLineItemCard(
                          itemKeyPrefix: 'detail_nota_${line.barang.idBarang}',
                          barang: line.barang,
                          qty: line.qty,
                          currentWarehouseStock: _maxAllowedQtyFor(line.barang),
                          maxQty: _maxAllowedQtyFor(line.barang),
                          onIncrement: () {
                            final id = line.barang.idBarang!;
                            final maxAllowed = _maxAllowedQtyFor(line.barang);
                            if (line.qty + 1 > maxAllowed) {
                              _setError(
                                'Stok "${line.barang.namaBarang}" maksimal $maxAllowed ${line.barang.satuan}.',
                              );
                              return;
                            }
                            setState(() {
                              _draftQty[id] = line.qty + 1;
                              _localError = null;
                            });
                          },
                          onDecrement: () {
                            final id = line.barang.idBarang!;
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
                            final id = line.barang.idBarang!;
                            setState(() {
                              _draftQty.remove(id);
                              _localError = null;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              TransactionBottomSummarySheet(
                totalLabel: 'Total Pembayaran Nota',
                totalAmount: grandTotal,
                deleteLabel: 'Hapus Nota',
                deleteWarningText:
                    'Hapus Nota #${_nota.idNota ?? '-'}? Semua stok barang pada nota ini akan dikembalikan ke gudang.',
                isSubmitting: vm.isSubmitting,
                saveKey: const ValueKey('detail_nota_save_button'),
                deleteKey: const ValueKey('detail_nota_delete_button'),
                onDeleteConfirmed: _deleteNota,
                onSaveChanges: _saveChanges,
              ),
            ],
          ),
        );
      },
    );
  }
}
