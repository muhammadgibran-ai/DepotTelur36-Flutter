import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/screens/transaksi/riwayat_faktur_screen.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Layar standalone Pendev `08 Faktur Masuk` ketika dibuka di luar shell tab.
class FakturMasukScreen extends StatelessWidget {
  const FakturMasukScreen({
    super.key,
    required this.viewModel,
    this.onTransactionSaved,
  });

  final TransactionCrudViewModel viewModel;
  final Future<void> Function()? onTransactionSaved;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: FakturMasukView(
        viewModel: viewModel,
        embedded: false,
        onTransactionSaved: onTransactionSaved,
      ),
    );
  }
}

/// Konten interaktif Pendev `08 Faktur Masuk` untuk tab `Faktur` maupun layar penuh.
class FakturMasukView extends StatefulWidget {
  const FakturMasukView({
    super.key,
    required this.viewModel,
    this.embedded = true,
    this.onTransactionSaved,
    this.onOpenHistory,
  });

  final TransactionCrudViewModel viewModel;
  final bool embedded;
  final Future<void> Function()? onTransactionSaved;
  final VoidCallback? onOpenHistory;

  @override
  State<FakturMasukView> createState() => _FakturMasukViewState();
}

class _FakturMasukViewState extends State<FakturMasukView> {
  late final TextEditingController _noFakturController;
  final FocusNode _noFakturFocus = FocusNode();
  String? _dismissedMessage;

  @override
  void initState() {
    super.initState();
    _noFakturController = TextEditingController(
      text: widget.viewModel.noFakturInput,
    );
  }

  @override
  void dispose() {
    _noFakturFocus.dispose();
    _noFakturController.dispose();
    super.dispose();
  }

  void _syncNoFakturController(String vmNoFaktur) {
    if (!_noFakturFocus.hasFocus && _noFakturController.text != vmNoFaktur) {
      _noFakturController.value = TextEditingValue(
        text: vmNoFaktur,
        selection: TextSelection.collapsed(offset: vmNoFaktur.length),
      );
    }
  }

  Future<void> _pickSupplier() async {
    final vm = widget.viewModel;
    final selected = await showEntitySelectorSheet<Supplier>(
      context: context,
      title: 'Pilih Supplier Pemasok',
      items: vm.suppliers,
      labelOf: (s) => s.namaSupplier,
      subtitleOf: (s) => s.noTelpSupplier,
      selected: vm.selectedFakturSupplier,
      equals: (a, b) => a.idSupplier == b.idSupplier,
    );
    if (selected?.idSupplier != null && mounted) {
      _dismissedMessage = null;
      vm.selectFakturSupplier(selected!.idSupplier);
    }
  }

  Future<void> _pickDate() async {
    final vm = widget.viewModel;
    final picked = await pickTransactionDate(context, vm.selectedFakturDate);
    if (picked != null && mounted) {
      _dismissedMessage = null;
      vm.selectFakturDate(picked);
    }
  }

  Future<void> _openCatalogPicker() async {
    _dismissedMessage = null;
    await showCatalogItemPickerSheet(
      context: context,
      title: 'Tambah Barang ke Faktur',
      barangs: widget.viewModel.barangs,
      currentQtyFor: widget.viewModel.fakturQtyFor,
      enforceAvailableStock: false,
      onAddBarang: (b) => widget.viewModel.addOrIncrementFakturBarang(b),
    );
  }

  void _openHistory() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!();
      return;
    }
    Navigator.of(context).push<void>(
      buildAuthRoute<void>(RiwayatFakturScreen(viewModel: widget.viewModel)),
    );
  }

  Future<void> _handleSubmit() async {
    _dismissedMessage = null;
    final idFaktur = await widget.viewModel.submitFakturMasuk();
    if (!mounted) return;
    if (idFaktur != null) {
      await widget.onTransactionSaved?.call();
      if (!mounted) return;
      if (!widget.embedded) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Faktur stok masuk berhasil disimpan.'),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        _syncNoFakturController(vm.noFakturInput);

        final lines = vm.fakturCartLines;
        final activeError = vm.errorMessage;
        final activeSuccess = vm.successMessage;
        final bannerMessage =
            (activeError != null && activeError != _dismissedMessage)
                ? activeError
                : (activeSuccess != null && activeSuccess != _dismissedMessage)
                    ? activeSuccess
                    : null;
        final isErrorBanner = activeError != null && activeError == bannerMessage;
        final supplierName =
            vm.selectedFakturSupplier?.namaSupplier ?? 'Pilih Supplier';
        final dateText = TransactionCrudViewModel.formatDisplayDate(
          vm.selectedFakturDate,
        );

        return Column(
          children: [
            MasterAmberHeader(
              title: 'Faktur Barang Masuk',
              subtitle: 'Catat pembelian stok dari supplier',
              showBackButton: !widget.embedded,
              actionLabel: 'Riwayat',
              onAction: _openHistory,
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.ink,
                backgroundColor: AppColors.surface,
                onRefresh: () => vm.loadData(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    (widget.embedded && lines.isEmpty)
                        ? MediaQuery.paddingOf(context).bottom + 20
                        : 14,
                  ),
                  children: [
                    ShakeOnError(
                      pulse: vm.errorShakePulse,
                      child: AuthFeedbackBanner(
                        errorMessage: isErrorBanner ? bannerMessage : null,
                        infoMessage: isErrorBanner ? null : bannerMessage,
                        onDismiss: () {
                          setState(() => _dismissedMessage = bannerMessage);
                          vm.clearMessages();
                        },
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
                            key: const ValueKey('faktur_no_field'),
                            controller: _noFakturController,
                            focusNode: _noFakturFocus,
                            onChanged: (value) {
                              _dismissedMessage = null;
                              vm.setNoFakturInput(value);
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final stackVertical = constraints.maxWidth < 340;
                              if (stackVertical) {
                                return Column(
                                  children: [
                                    TransactionMetaSelectorTile(
                                      tileKey: const ValueKey(
                                        'faktur_supplier_selector',
                                      ),
                                      label: 'Supplier',
                                      valueText: supplierName,
                                      leadingIcon:
                                          Icons.local_shipping_outlined,
                                      trailingIcon:
                                          Icons.keyboard_arrow_down_rounded,
                                      onTap: _pickSupplier,
                                    ),
                                    const SizedBox(height: 10),
                                    TransactionMetaSelectorTile(
                                      tileKey: const ValueKey(
                                        'faktur_date_selector',
                                      ),
                                      label: 'Tanggal Masuk',
                                      valueText: dateText,
                                      leadingIcon: Icons.calendar_today_rounded,
                                      trailingIcon: Icons.edit_calendar_rounded,
                                      onTap: _pickDate,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(
                                    child: TransactionMetaSelectorTile(
                                      tileKey: const ValueKey(
                                        'faktur_supplier_selector',
                                      ),
                                      label: 'Supplier',
                                      valueText: supplierName,
                                      leadingIcon:
                                          Icons.local_shipping_outlined,
                                      trailingIcon:
                                          Icons.keyboard_arrow_down_rounded,
                                      onTap: _pickSupplier,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TransactionMetaSelectorTile(
                                      tileKey: const ValueKey(
                                        'faktur_date_selector',
                                      ),
                                      label: 'Tanggal Masuk',
                                      valueText: dateText,
                                      leadingIcon: Icons.calendar_today_rounded,
                                      trailingIcon: Icons.edit_calendar_rounded,
                                      onTap: _pickDate,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Detail Barang Masuk (${lines.length} Item)',
                      style: AppTypography.heading(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (lines.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 30,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Belum ada barang masuk yang dipilih',
                              textAlign: TextAlign.center,
                              style: AppTypography.heading(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tambahkan barang dari katalog untuk memperbarui stok gudang secara otomatis.',
                              textAlign: TextAlign.center,
                              style: AppTypography.body(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final line in lines) ...[
                        DetailLineItemCard(
                          itemKeyPrefix: 'faktur_item_${line.barang.idBarang}',
                          barang: line.barang,
                          qty: line.qty,
                          currentWarehouseStock: line.barang.stokBarang,
                          stockDeltaPreview: line.qty,
                          onIncrement: () =>
                              vm.addOrIncrementFakturBarang(line.barang),
                          onDecrement: () => vm.decrementFakturQty(line.barang),
                          onRemove: () =>
                              vm.removeFakturItem(line.barang.idBarang!),
                        ),
                        const SizedBox(height: 10),
                      ],
                    const SizedBox(height: 12),
                    Semantics(
                      button: true,
                      label: 'Tambah Barang dari Katalog',
                      child: TactilePressScale(
                        pressedScale: 0.97,
                        child: OutlinedButton.icon(
                          key: const ValueKey('faktur_add_catalog_button'),
                          onPressed: _openCatalogPicker,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.ink,
                            side: const BorderSide(
                              color: AppColors.yolk,
                              width: 1.5,
                            ),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            '+ Tambah Barang dari Katalog',
                            style: AppTypography.body(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              bottom: true,
              child: FloatingTransactionTotalBar(
                visible: lines.isNotEmpty,
                caption: 'Total Pembelian',
                itemCountBadge: vm.fakturItemCount,
                totalAmount: vm.fakturGrandTotal,
                buttonLabel: 'Simpan Faktur',
                isSubmitting: vm.isSubmitting,
                ctaKey: const ValueKey('faktur_submit_button'),
                onPressed: _handleSubmit,
              ),
            ),
          ],
        );
      },
    );
  }
}
