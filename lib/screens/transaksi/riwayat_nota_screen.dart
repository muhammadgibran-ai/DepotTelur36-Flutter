import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/screens/transaksi/detail_nota_screen.dart';
import 'package:depot_telur_36/screens/transaksi/kasir_nota_screen.dart';
import 'package:depot_telur_36/viewmodels/transaction_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/transaction_widgets.dart';

/// Layar standalone Pendev `16 Riwayat Nota (Kasir)` untuk melihat & mencari semua Nota.
class RiwayatNotaScreen extends StatelessWidget {
  const RiwayatNotaScreen({
    super.key,
    required this.viewModel,
    this.onCreateNota,
    this.onTransactionChanged,
  });

  final TransactionCrudViewModel viewModel;
  final VoidCallback? onCreateNota;
  final Future<void> Function()? onTransactionChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceWarm,
      body: RiwayatNotaView(
        viewModel: viewModel,
        embedded: false,
        onCreateNota: onCreateNota,
        onTransactionChanged: onTransactionChanged,
      ),
    );
  }
}

/// Konten Pendev `16 Riwayat Nota (Kasir)` untuk tab `Nota` Owner maupun layar penuh.
class RiwayatNotaView extends StatefulWidget {
  const RiwayatNotaView({
    super.key,
    required this.viewModel,
    this.embedded = true,
    this.onCreateNota,
    this.onTransactionChanged,
  });

  final TransactionCrudViewModel viewModel;
  final bool embedded;
  final VoidCallback? onCreateNota;
  final Future<void> Function()? onTransactionChanged;

  @override
  State<RiwayatNotaView> createState() => _RiwayatNotaViewState();
}

class _RiwayatNotaViewState extends State<RiwayatNotaView> {
  final TextEditingController _searchController = TextEditingController();
  String? _dismissedMessage;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.viewModel.notaHistoryQuery;
  }

  @override
  void didUpdateWidget(covariant RiwayatNotaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.notaHistoryQuery != _searchController.text) {
      _searchController.text = widget.viewModel.notaHistoryQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreateNota() async {
    if (widget.onCreateNota != null) {
      widget.onCreateNota!();
      return;
    }
    await Navigator.of(context).push<void>(
      buildAuthRoute<void>(
        KasirNotaScreen(
          viewModel: widget.viewModel,
          onTransactionSaved: widget.onTransactionChanged,
        ),
      ),
    );
  }

  Future<void> _openDetail(int index) async {
    final nota = widget.viewModel.filteredNotas[index];
    final changed = await Navigator.of(context).push<bool>(
      buildAuthRoute<bool>(
        DetailNotaScreen(viewModel: widget.viewModel, nota: nota),
      ),
    );
    if (changed == true && mounted) {
      _dismissedMessage = null;
      await widget.onTransactionChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final notas = vm.filteredNotas;
        final activeSuccess = vm.successMessage;
        final bannerMsg =
            (activeSuccess != null && activeSuccess != _dismissedMessage)
                ? activeSuccess
                : null;

        return Column(
          children: [
            MasterAmberHeader(
              title: 'Riwayat Nota',
              subtitle: 'Pantau dan kelola transaksi penjualan kasir',
              showBackButton: !widget.embedded,
              badgeLabel: widget.embedded ? 'Khusus Owner · Audit Nota' : null,
              actionLabel: '+ Nota',
              onAction: _openCreateNota,
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
                    MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  children: [
                    MasterSearchField(
                      controller: _searchController,
                      hintText: 'Cari pelanggan, no nota, atau tanggal...',
                      onChanged: vm.setNotaHistoryQuery,
                      onClear: () {
                        _searchController.clear();
                        vm.setNotaHistoryQuery('');
                      },
                    ),
                    const SizedBox(height: 10),
                    TransactionFilterChipBar<NotaHistoryDateFilter>(
                      options: [
                        for (final f in NotaHistoryDateFilter.values)
                          (value: f, label: f.label),
                      ],
                      selectedValue: vm.notaDateFilter,
                      onSelected: vm.setNotaDateFilter,
                    ),
                    const SizedBox(height: 12),
                    AuthFeedbackBanner(
                      infoMessage: bannerMsg,
                      onDismiss: () {
                        setState(() => _dismissedMessage = bannerMsg);
                        vm.clearMessages();
                      },
                    ),
                    if (vm.isLoading && vm.notas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.ink,
                          ),
                        ),
                      )
                    else if (notas.isEmpty)
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
                              Icons.receipt_long_rounded,
                              size: 34,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Belum ada riwayat nota',
                              style: AppTypography.heading(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Transaksi kasir yang tercatat akan tampil di daftar ini secara langsung.',
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
                      for (var i = 0; i < notas.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final nota = notas[i];
                            final customer =
                                (nota.namaCustomer ?? '').trim().isNotEmpty
                                    ? nota.namaCustomer!
                                    : 'Pelanggan';
                            final petugas =
                                (nota.namaPetugas ?? '').trim().isNotEmpty
                                    ? nota.namaPetugas!
                                    : 'Kasir';
                            return TransactionHistoryCard(
                              cardKey: ValueKey('nota_card_${nota.idNota}'),
                              title:
                                  'Nota #${nota.idNota ?? '-'} · $customer',
                              metaText:
                                  '${TransactionCrudViewModel.formatDisplayDate(nota.tanggalNota)} · Kasir: $petugas',
                              itemsSummary: buildTransactionItemsSummary(
                                nota.details
                                    .map(
                                      (d) => (
                                        nama: d.namaBarang,
                                        qty: d.banyaknya,
                                        satuan: d.satuan,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                              totalAmount: nota.total,
                              syncStatus: nota.syncStatus,
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
    );
  }
}
