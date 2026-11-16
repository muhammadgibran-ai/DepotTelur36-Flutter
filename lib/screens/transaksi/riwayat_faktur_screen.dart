import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/screens/transaksi/detail_faktur_screen.dart';
import 'package:depot_telur_36/screens/transaksi/faktur_masuk_screen.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';

/// Layar standalone Pendev `18 Riwayat Faktur Masuk` untuk melihat & audit Faktur.
class RiwayatFakturScreen extends StatefulWidget {
  const RiwayatFakturScreen({
    super.key,
    required this.viewModel,
    this.onCreateFaktur,
    this.onTransactionChanged,
  });

  final TransactionCrudViewModel viewModel;
  final VoidCallback? onCreateFaktur;
  final Future<void> Function()? onTransactionChanged;

  @override
  State<RiwayatFakturScreen> createState() => _RiwayatFakturScreenState();
}

class _RiwayatFakturScreenState extends State<RiwayatFakturScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _dismissedMessage;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.viewModel.fakturHistoryQuery;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreateFaktur() async {
    if (widget.onCreateFaktur != null) {
      widget.onCreateFaktur!();
      return;
    }
    await Navigator.of(context).push<void>(
      buildAuthRoute<void>(
        FakturMasukScreen(
          viewModel: widget.viewModel,
          onTransactionSaved: widget.onTransactionChanged,
        ),
      ),
    );
  }

  Future<void> _openDetail(int index) async {
    final faktur = widget.viewModel.filteredFakturs[index];
    final changed = await Navigator.of(context).push<bool>(
      buildAuthRoute<bool>(
        DetailFakturScreen(viewModel: widget.viewModel, faktur: faktur),
      ),
    );
    if (changed == true && mounted) {
      _dismissedMessage = null;
      await widget.onTransactionChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final vm = widget.viewModel;
          final fakturs = vm.filteredFakturs;
          final activeSuccess = vm.successMessage;
          final bannerMsg =
              (activeSuccess != null && activeSuccess != _dismissedMessage)
                  ? activeSuccess
                  : null;

          final supplierOptions = <({String? value, String label})>[
            (value: null, label: 'Semua'),
            for (final s in vm.suppliers)
              (value: s.remoteId, label: s.namaSupplier),
          ];

          return Column(
            children: [
              MasterAmberHeader(
                title: 'Riwayat Faktur Masuk',
                subtitle: 'Daftar penerimaan stok barang dari supplier',
                showBackButton: true,
                actionLabel: '+ Faktur',
                onAction: _openCreateFaktur,
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.ink,
                  backgroundColor: AppColors.surface,
                  onRefresh: () => vm.loadData(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                    children: [
                      MasterSearchField(
                        controller: _searchController,
                        hintText: 'Cari no. faktur atau nama supplier...',
                        onChanged: vm.setFakturHistoryQuery,
                        onClear: () {
                          _searchController.clear();
                          vm.setFakturHistoryQuery('');
                        },
                      ),
                      const SizedBox(height: 10),
                      TransactionFilterChipBar<String?>(
                        options: supplierOptions,
                        selectedValue: vm.fakturSupplierFilterRemoteId,
                        onSelected: vm.setFakturSupplierFilter,
                      ),
                      const SizedBox(height: 12),
                      AuthFeedbackBanner(
                        infoMessage: bannerMsg,
                        onDismiss: () {
                          setState(() => _dismissedMessage = bannerMsg);
                          vm.clearMessages();
                        },
                      ),
                      if (vm.isLoading && vm.fakturs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.ink,
                            ),
                          ),
                        )
                      else if (fakturs.isEmpty)
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
                                Icons.inventory_rounded,
                                size: 34,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Belum ada riwayat faktur',
                                style: AppTypography.heading(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Faktur pembelian stok masuk dari supplier akan tampil di sini.',
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
                        for (var i = 0; i < fakturs.length; i++) ...[
                          Builder(
                            builder: (context) {
                              final faktur = fakturs[i];
                              final supplier =
                                  (faktur.namaSupplier ?? '').trim().isNotEmpty
                                      ? faktur.namaSupplier!
                                      : 'Supplier';
                              final petugas =
                                  (faktur.namaPetugas ?? '').trim().isNotEmpty
                                      ? faktur.namaPetugas!
                                      : 'Petugas';
                              return TransactionHistoryCard(
                                cardKey: ValueKey(
                                  'faktur_card_${faktur.idFaktur}',
                                ),
                                title: '${faktur.noFaktur} · $supplier',
                                metaText:
                                    '${TransactionCrudViewModel.formatDisplayDate(faktur.tanggalFaktur)} · Penerima: $petugas',
                                itemsSummary: buildTransactionItemsSummary(
                                  faktur.details
                                      .map(
                                        (d) => (
                                          nama: d.namaBarang,
                                          qty: d.quantity,
                                          satuan: d.satuan,
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                                totalAmount: faktur.total,
                                syncStatus: faktur.syncStatus,
                                onTap: () => _openDetail(i),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
