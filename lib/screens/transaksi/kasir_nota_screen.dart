import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/screens/transaksi/riwayat_nota_screen.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';

/// Layar standalone Pendev `07 Kasir Nota` ketika dibuka di luar shell tab.
class KasirNotaScreen extends StatelessWidget {
  const KasirNotaScreen({
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
      body: KasirNotaView(
        viewModel: viewModel,
        embedded: false,
        onTransactionSaved: onTransactionSaved,
      ),
    );
  }
}

/// Konten interaktif Pendev `07 Kasir Nota` untuk tab `Kasir` maupun layar penuh.
class KasirNotaView extends StatefulWidget {
  const KasirNotaView({
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
  State<KasirNotaView> createState() => _KasirNotaViewState();
}

class _KasirNotaViewState extends State<KasirNotaView> {
  final TextEditingController _searchController = TextEditingController();
  String? _dismissedMessage;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.viewModel.kasirSearchQuery;
  }

  @override
  void didUpdateWidget(covariant KasirNotaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.kasirSearchQuery != _searchController.text) {
      _searchController.text = widget.viewModel.kasirSearchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final vm = widget.viewModel;
    final selected = await showEntitySelectorSheet<Customer>(
      context: context,
      title: 'Pilih Pelanggan Kasir',
      items: vm.customers,
      labelOf: (c) => c.namaCustomer,
      selected: vm.selectedNotaCustomer,
      equals: (a, b) => a.idCustomer == b.idCustomer,
    );
    if (selected?.idCustomer != null && mounted) {
      _dismissedMessage = null;
      vm.selectNotaCustomer(selected!.idCustomer);
    }
  }

  Future<void> _pickDate() async {
    final vm = widget.viewModel;
    final picked = await pickTransactionDate(context, vm.selectedNotaDate);
    if (picked != null && mounted) {
      _dismissedMessage = null;
      vm.selectNotaDate(picked);
    }
  }

  void _openHistory() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    if (widget.onOpenHistory != null) {
      widget.onOpenHistory!();
      return;
    }
    Navigator.of(context).push<void>(
      buildAuthRoute<void>(RiwayatNotaScreen(viewModel: widget.viewModel)),
    );
  }

  Future<void> _handleSubmit() async {
    _dismissedMessage = null;
    final idNota = await widget.viewModel.submitKasirNota();
    if (!mounted) return;
    if (idNota != null) {
      await widget.onTransactionSaved?.call();
      if (!mounted) return;
      if (!widget.embedded) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Nota #$idNota berhasil disimpan.')),
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
        final items = vm.filteredKasirBarangs;
        final activeError = vm.errorMessage;
        final activeSuccess = vm.successMessage;
        final bannerMessage = (activeError != null && activeError != _dismissedMessage)
            ? activeError
            : (activeSuccess != null && activeSuccess != _dismissedMessage)
                ? activeSuccess
                : null;
        final isErrorBanner = activeError != null && activeError == bannerMessage;
        final customerName = vm.selectedNotaCustomer?.namaCustomer ?? 'Pilih Pelanggan';
        final dateText = TransactionCrudViewModel.formatDisplayDate(
          vm.selectedNotaDate,
          short: true,
        );

        return Column(
          children: [
            MasterAmberHeader(
              title: 'Kasir Nota Keluar',
              subtitle: 'Catat penjualan ke pelanggan',
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
                    (widget.embedded && vm.kasirItemCount == 0)
                        ? MediaQuery.paddingOf(context).bottom + 20
                        : 14,
                  ),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: TransactionContextPill(
                            pillKey: const ValueKey('kasir_customer_pill'),
                            icon: Icons.person_outline_rounded,
                            label: customerName,
                            isEmphasized: vm.selectedNotaCustomer != null,
                            onTap: _pickCustomer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: TransactionContextPill(
                            pillKey: const ValueKey('kasir_date_pill'),
                            icon: Icons.calendar_today_rounded,
                            label: dateText,
                            onTap: _pickDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    MasterSearchField(
                      controller: _searchController,
                      hintText: 'Cari telur atau sembako...',
                      onChanged: vm.setKasirSearchQuery,
                      onClear: () {
                        _searchController.clear();
                        vm.setKasirSearchQuery('');
                      },
                    ),
                    const SizedBox(height: 12),
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
                    if (vm.isLoading && vm.barangs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.ink,
                          ),
                        ),
                      )
                    else if (items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.search_off_rounded,
                              size: 32,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Barang tidak ditemukan',
                              style: AppTypography.heading(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Coba kata kunci lain atau periksa daftar barang di tab Stok.',
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
                      for (final barang in items) ...[
                        KasirCatalogItemCard(
                          barang: barang,
                          qty: vm.kasirQtyFor(barang),
                          onIncrement: () {
                            _dismissedMessage = null;
                            vm.incrementKasirQty(barang);
                          },
                          onDecrement: () {
                            _dismissedMessage = null;
                            vm.decrementKasirQty(barang);
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              bottom: true,
              child: FloatingTransactionTotalBar(
                visible: vm.kasirItemCount > 0,
                caption: 'Total (${vm.kasirTotalUnits} Unit)',
                itemCountBadge: vm.kasirItemCount,
                totalAmount: vm.kasirGrandTotal,
                buttonLabel: 'Simpan Nota',
                isSubmitting: vm.isSubmitting,
                ctaKey: const ValueKey('kasir_submit_nota_button'),
                onPressed: _handleSubmit,
              ),
            ),
          ],
        );
      },
    );
  }
}
