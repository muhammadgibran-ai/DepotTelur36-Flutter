import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/customer.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/screens/master/atur_harga_screen.dart';
import 'package:depot_telur_36/screens/master/barang_form_screen.dart';
import 'package:depot_telur_36/screens/master/petugas_form_screen.dart';
import 'package:depot_telur_36/screens/master/supplier_form_screen.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Layar terpadu tab `Master` (Owner) & `Stok` (Operator) untuk Pendev Screens `09`, `11`, `13`, `14`.
class MasterDataTabView extends StatefulWidget {
  const MasterDataTabView({
    super.key,
    required this.viewModel,
    this.onRefreshRequested,
  });

  final MasterCrudViewModel viewModel;
  final Future<void> Function()? onRefreshRequested;

  @override
  State<MasterDataTabView> createState() => _MasterDataTabViewState();
}

class _MasterDataTabViewState extends State<MasterDataTabView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  final TextEditingController _customerNameController = TextEditingController();
  final FocusNode _customerFocusNode = FocusNode();
  final GlobalKey _customerFormKey = GlobalKey();

  Customer? _editingCustomer;
  String? _customerFieldError;
  String? _successMessage;
  int _customerErrorPulse = 0;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.viewModel.searchQuery;
    _customerFocusNode.addListener(_onCustomerFocusChanged);
  }

  void _onCustomerFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MasterDataTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.searchQuery != _searchController.text) {
      _searchController.text = widget.viewModel.searchQuery;
    }
  }

  @override
  void dispose() {
    _customerFocusNode.removeListener(_onCustomerFocusChanged);
    _searchController.dispose();
    _listScrollController.dispose();
    _customerNameController.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pushScreen(Widget screen) async {
    await Navigator.of(
      context,
    ).push<bool>(buildAuthRoute<bool>(screen));
  }

  Future<void> _handleAddPressed() async {
    final vm = widget.viewModel;
    switch (vm.activeCategory) {
      case MasterCategory.barang:
        await _pushScreen(BarangFormScreen(viewModel: vm));
      case MasterCategory.supplier:
        await _pushScreen(SupplierFormScreen(viewModel: vm));
      case MasterCategory.pelanggan:
        _startCreateCustomer();
      case MasterCategory.petugas:
        if (!vm.isOwner) return;
        await _pushScreen(PetugasFormScreen(viewModel: vm));
    }
  }

  void _startCreateCustomer() {
    setState(() {
      _editingCustomer = null;
      _customerNameController.clear();
      _customerFieldError = null;
      _successMessage = null;
    });
    _scrollToCustomerForm();
  }

  void _startEditCustomer(Customer customer) {
    setState(() {
      _editingCustomer = customer;
      _customerNameController.text = customer.namaCustomer;
      _customerFieldError = null;
      _successMessage = null;
    });
    _scrollToCustomerForm();
  }

  void _scrollToCustomerForm() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _customerFormKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          alignment: 0.7,
        );
      }
      _customerFocusNode.requestFocus();
    });
  }

  void _cancelCustomerForm() {
    setState(() {
      _editingCustomer = null;
      _customerNameController.clear();
      _customerFieldError = null;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _saveCustomerForm() async {
    final raw = _customerNameController.text;
    if (raw.trim().length < 2) {
      setState(() {
        _customerFieldError = 'Nama pelanggan minimal 2 karakter.';
        _successMessage = null;
        _customerErrorPulse++;
      });
      return;
    }

    final isEdit = _editingCustomer != null;
    final ok = await widget.viewModel.saveCustomer(
      idCustomer: _editingCustomer?.idCustomer,
      existingRemoteId: _editingCustomer?.remoteId,
      namaCustomer: raw,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _customerErrorPulse++);
      return;
    }

    setState(() {
      _editingCustomer = null;
      _customerNameController.clear();
      _customerFieldError = null;
      _successMessage = isEdit
          ? 'Nama pelanggan berhasil diperbarui.'
          : 'Pelanggan baru berhasil ditambahkan.';
    });
  }

  Future<void> _confirmAndDeleteSupplier(Supplier supplier) async {
    final confirmed = await showMasterDeleteDialog(
      context: context,
      title: 'Konfirmasi Hapus Supplier?',
      message:
          'Mitra "${supplier.namaSupplier}" akan dihapus bila belum tercatat pada Faktur masuk.',
      confirmLabel: 'Ya, Hapus Supplier',
    );
    if (!confirmed || !mounted) return;
    final ok = await widget.viewModel.deleteSupplier(supplier);
    if (ok && mounted) {
      setState(() {
        _successMessage = 'Supplier "${supplier.namaSupplier}" berhasil dihapus.';
      });
    }
  }

  Future<void> _confirmAndDeleteCustomer(Customer customer) async {
    final confirmed = await showMasterDeleteDialog(
      context: context,
      title: 'Konfirmasi Hapus Pelanggan?',
      message:
          'Pelanggan "${customer.namaCustomer}" akan dihapus bila belum memiliki riwayat Nota kasir.',
      confirmLabel: 'Ya, Hapus Pelanggan',
    );
    if (!confirmed || !mounted) return;
    final ok = await widget.viewModel.deleteCustomer(customer);
    if (ok && mounted) {
      if (_editingCustomer?.idCustomer == customer.idCustomer) {
        _editingCustomer = null;
        _customerNameController.clear();
      }
      setState(() {
        _successMessage =
            'Pelanggan "${customer.namaCustomer}" berhasil dihapus.';
      });
    }
  }

  Future<void> _confirmAndDeletePetugas(Petugas petugas) async {
    final confirmed = await showMasterDeleteDialog(
      context: context,
      title: 'Konfirmasi Hapus Petugas?',
      message:
          'Akun "${petugas.namaPetugas}" akan dihapus bila bukan akun aktif/Owner terakhir dan belum memiliki transaksi.',
      confirmLabel: 'Ya, Hapus Petugas',
    );
    if (!confirmed || !mounted) return;
    final ok = await widget.viewModel.deletePetugas(petugas);
    if (ok && mounted) {
      setState(() {
        _successMessage = 'Akun "${petugas.namaPetugas}" berhasil dihapus.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final category = vm.activeCategory;
        final feedback = vm.accessDeniedMessage ?? vm.errorMessage;

        return Column(
          children: [
            MasterAmberHeader(
              title: category.headerTitle,
              subtitle: category.headerSubtitle,
              actionLabel: category.addButtonLabel,
              onAction: _handleAddPressed,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: MasterCategoryTabBar(
                categories: vm.categories,
                activeCategory: category,
                onSelected: (next) {
                  setState(() => _successMessage = null);
                  if (_listScrollController.hasClients) {
                    _listScrollController.jumpTo(0);
                  }
                  vm.selectCategory(next);
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.ink,
                backgroundColor: AppColors.surface,
                onRefresh: () async {
                  await vm.loadData();
                  await widget.onRefreshRequested?.call();
                },
                child: ListView(
                  controller: _listScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 112),
                  children: [
                    MasterSearchField(
                      controller: _searchController,
                      hintText: category.searchHint,
                      onChanged: vm.setSearchQuery,
                      onClear: () {
                        _searchController.clear();
                        vm.clearSearch();
                      },
                    ),
                    SoftAnimatedReveal(
                      visible: feedback != null,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: MasterFeedbackBanner(
                          message: feedback ?? '',
                          onDismiss: vm.clearMessages,
                        ),
                      ),
                    ),
                    SoftAnimatedReveal(
                      visible: _successMessage != null,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: MasterFeedbackBanner(
                          message: _successMessage ?? '',
                          isError: false,
                          onDismiss: () =>
                              setState(() => _successMessage = null),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : AppTokens.stateDuration,
                      switchInCurve: AppTokens.arrivalCurve,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            ?currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        if (MediaQuery.disableAnimationsOf(context)) {
                          return FadeTransition(opacity: animation, child: child);
                        }
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.02),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(category),
                        child: _buildCategoryContent(vm),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryContent(MasterCrudViewModel vm) {
    switch (vm.activeCategory) {
      case MasterCategory.barang:
        return _buildBarangSection(vm);
      case MasterCategory.supplier:
        return _buildSupplierSection(vm);
      case MasterCategory.pelanggan:
        return _buildCustomerSection(vm);
      case MasterCategory.petugas:
        return _buildPetugasSection(vm);
    }
  }

  Widget _buildBarangSection(MasterCrudViewModel vm) {
    final items = vm.filteredBarang;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              'Katalog Barang (${items.length})',
              style: AppTypography.heading(fontSize: 15),
            ),
            if (vm.isOwner)
              Semantics(
                button: true,
                label: 'Buka Atur Harga Jual',
                child: TactilePressScale(
                  pressedScale: 0.94,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Material(
                      color: AppColors.yolkSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const ValueKey('master_open_atur_harga_button'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _pushScreen(AturHargaScreen(viewModel: vm));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.sell_rounded,
                                size: 16,
                                color: AppColors.ink,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Atur Harga',
                                style: AppTypography.body(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const MasterEmptyStateCard(
            icon: Icons.inventory_2_outlined,
            title: 'Belum ada data barang',
            subtitle:
                'Ketuk tombol "+ Tambah" di kanan atas untuk menambahkan komoditas telur atau sembako.',
          )
        else
          MasterSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.borderSubtle,
                    ),
                  _buildBarangRow(vm, items[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBarangRow(MasterCrudViewModel vm, Barang item) {
    final lowStock = item.stokBarang <= kLowStockThreshold;
    final stockLabel = '${item.stokBarang} ${item.satuan}';
    final stockChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: lowStock ? AppColors.dangerBg : AppColors.yolkSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stockLabel,
        style: AppTypography.body(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: lowStock ? AppColors.danger : AppColors.ink,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BarangThumbnail(barang: item, size: 48, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.namaBarang,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lowStock
                          ? '${formatRupiah(item.hargaSatuan)} / ${item.satuan} · Stok Menipis'
                          : '${formatRupiah(item.hargaSatuan)} / ${item.satuan}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 12.5,
                        fontWeight: lowStock ? FontWeight.w600 : FontWeight.w500,
                        color: lowStock
                            ? AppColors.danger
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (compact) ...[const SizedBox(height: 6), stockChip],
                  ],
                ),
              ),
              if (!compact) ...[const SizedBox(width: 8), stockChip],
              const SizedBox(width: 2),
              MasterActionIconButton.edit(
                key: ValueKey('edit_barang_${item.remoteId}'),
                semanticLabel: 'Edit ${item.namaBarang}',
                onTap: () => _pushScreen(
                  BarangFormScreen(viewModel: vm, initialBarang: item),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSupplierSection(MasterCrudViewModel vm) {
    final items = vm.filteredSuppliers;
    if (items.isEmpty) {
      return const MasterEmptyStateCard(
        icon: Icons.local_shipping_outlined,
        title: 'Belum ada data supplier',
        subtitle:
            'Tambahkan mitra peternakan atau distributor dengan tombol "+ Supplier".',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildSupplierCard(vm, items[i]),
        ],
      ],
    );
  }

  Widget _buildSupplierCard(MasterCrudViewModel vm, Supplier supplier) {
    return MasterSectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MasterUiColors.neutralButtonBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  size: 22,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.namaSupplier,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.heading(fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supplier.noTelpSupplier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              MasterActionIconButton.edit(
                key: ValueKey('edit_supplier_${supplier.remoteId}'),
                semanticLabel: 'Edit supplier ${supplier.namaSupplier}',
                onTap: () => _pushScreen(
                  SupplierFormScreen(viewModel: vm, initialSupplier: supplier),
                ),
              ),
              MasterActionIconButton.delete(
                key: ValueKey('delete_supplier_${supplier.remoteId}'),
                semanticLabel: 'Hapus supplier ${supplier.namaSupplier}',
                onTap: () => _confirmAndDeleteSupplier(supplier),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppColors.borderSubtle),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  supplier.alamatSupplier,
                  style: AppTypography.body(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSection(MasterCrudViewModel vm) {
    final items = vm.filteredCustomers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          const MasterEmptyStateCard(
            icon: Icons.group_outlined,
            title: 'Belum ada pelanggan ditemukan',
            subtitle:
                'Tambahkan pelanggan toko pada kartu formulir cepat di bawah.',
          )
        else
          MasterSectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.borderSubtle,
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            color: MasterUiColors.neutralButtonBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            size: 20,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            items[i].namaCustomer,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.heading(fontSize: 14),
                          ),
                        ),
                        MasterActionIconButton.edit(
                          key: ValueKey('edit_customer_${items[i].remoteId}'),
                          semanticLabel: 'Ubah ${items[i].namaCustomer}',
                          onTap: () => _startEditCustomer(items[i]),
                        ),
                        MasterActionIconButton.delete(
                          key: ValueKey('delete_customer_${items[i].remoteId}'),
                          semanticLabel: 'Hapus ${items[i].namaCustomer}',
                          onTap: () => _confirmAndDeleteCustomer(items[i]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 14),
        ShakeOnError(
          pulse: _customerErrorPulse,
          child: AnimatedContainer(
            key: _customerFormKey,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppTokens.stateDuration,
            curve: AppTokens.arrivalCurve,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _editingCustomer != null
                    ? MasterUiColors.editBlue
                    : AppColors.borderSubtle,
                width: _editingCustomer != null ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : AppTokens.microDuration,
                        child: SizedBox(
                          key: ValueKey(_editingCustomer != null),
                          width: double.infinity,
                          child: Text(
                            _editingCustomer != null
                                ? 'Ubah Nama Pelanggan'
                                : 'Tambah Pelanggan Baru',
                            style: AppTypography.heading(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                    AnimatedBadgePop(
                      visible: _editingCustomer != null,
                      badgeKey: const ValueKey('customer_edit_badge'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: MasterUiColors.editBlueBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Mode Edit',
                          style: AppTypography.body(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MasterUiColors.editBlueText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Nama Pelanggan',
                  style: AppTypography.body(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  curve: AppTokens.arrivalCurve,
                  decoration: BoxDecoration(
                    color: _customerFocusNode.hasFocus
                        ? AppColors.surface
                        : AppColors.inputBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _customerFieldError != null
                          ? AppColors.danger
                          : _customerFocusNode.hasFocus
                          ? AppColors.ink
                          : AppColors.borderSubtle,
                      width:
                          (_customerFieldError != null ||
                              _customerFocusNode.hasFocus)
                          ? 1.4
                          : 1,
                    ),
                  ),
                  child: TextField(
                    key: const ValueKey('customer_quick_nama_field'),
                    controller: _customerNameController,
                    focusNode: _customerFocusNode,
                    onChanged: (_) {
                      if (_customerFieldError != null) {
                        setState(() => _customerFieldError = null);
                      }
                    },
                    style: AppTypography.body(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'cth: Warung Sembako Bu Dewi',
                      hintStyle: AppTypography.body(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
                SoftAnimatedReveal(
                  visible: _customerFieldError != null,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _customerFieldError ?? '',
                            style: AppTypography.body(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'Batal formulir pelanggan',
                      child: TactilePressScale(
                        enabled: !vm.isSaving,
                        pressedScale: 0.95,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            minWidth: 84,
                          ),
                          child: Material(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              key: const ValueKey('customer_quick_cancel_button'),
                              borderRadius: BorderRadius.circular(12),
                              onTap: vm.isSaving
                                  ? null
                                  : () {
                                      HapticFeedback.selectionClick();
                                      _cancelCustomerForm();
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Center(
                                  child: Text(
                                    'Batal',
                                    style: AppTypography.body(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        button: true,
                        label: 'Simpan Pelanggan',
                        child: TactilePressScale(
                          enabled: !vm.isSaving,
                          pressedScale: 0.96,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Material(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                key: const ValueKey('customer_quick_save_button'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: vm.isSaving
                                    ? null
                                    : () {
                                        HapticFeedback.lightImpact();
                                        _saveCustomerForm();
                                      },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration:
                                          MediaQuery.disableAnimationsOf(context)
                                          ? Duration.zero
                                          : AppTokens.microDuration,
                                      child: Text(
                                        vm.isSaving
                                            ? 'Menyimpan...'
                                            : _editingCustomer != null
                                            ? 'Simpan Perubahan'
                                            : 'Simpan Pelanggan',
                                        key: ValueKey(
                                          '${vm.isSaving}|${_editingCustomer != null}',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.body(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.surface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPetugasSection(MasterCrudViewModel vm) {
    if (!vm.isOwner) {
      return const MasterEmptyStateCard(
        icon: Icons.lock_outline_rounded,
        title: 'Akses Khusus Owner',
        subtitle:
            'Hanya Owner yang dapat melihat dan mengelola daftar akun petugas.',
      );
    }

    final items = vm.filteredPetugas;
    if (items.isEmpty) {
      return const MasterEmptyStateCard(
        icon: Icons.manage_accounts_outlined,
        title: 'Belum ada akun petugas ditemukan',
        subtitle:
            'Tambahkan akun kasir atau Owner baru melalui tombol "+ Petugas" di kanan atas.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildPetugasCard(vm, items[i]),
        ],
      ],
    );
  }

  Widget _buildPetugasCard(MasterCrudViewModel vm, Petugas petugas) {
    final isRoleOwner = petugas.role == UserRole.owner;
    final isCurrentSession = petugas.remoteId == vm.session.petugasRemoteId;

    return MasterSectionCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isRoleOwner ? AppColors.ink : AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isRoleOwner ? Icons.verified_user_rounded : Icons.badge_rounded,
              size: 22,
              color: isRoleOwner ? AppColors.yolk : AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  petugas.namaPetugas,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.heading(fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isRoleOwner
                            ? AppColors.ink
                            : AppColors.successBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        petugas.role.label,
                        style: AppTypography.body(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isRoleOwner
                              ? AppColors.yolk
                              : AppColors.success,
                        ),
                      ),
                    ),
                    if (isCurrentSession)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: MasterUiColors.editBlueBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Aktif',
                          style: AppTypography.body(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: MasterUiColors.editBlueText,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  petugas.email.isNotEmpty
                      ? petugas.email
                      : 'PIN Kasir terkonfigurasi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          MasterActionIconButton.edit(
            key: ValueKey('edit_petugas_${petugas.remoteId}'),
            semanticLabel: 'Edit akun ${petugas.namaPetugas}',
            onTap: () => _pushScreen(
              PetugasFormScreen(viewModel: vm, initialPetugas: petugas),
            ),
          ),
          MasterActionIconButton.delete(
            key: ValueKey('delete_petugas_${petugas.remoteId}'),
            semanticLabel: isCurrentSession
                ? 'Akun aktif tidak dapat dihapus'
                : 'Hapus akun ${petugas.namaPetugas}',
            onTap: isCurrentSession
                ? null
                : () => _confirmAndDeletePetugas(petugas),
          ),
        ],
      ),
    );
  }
}
