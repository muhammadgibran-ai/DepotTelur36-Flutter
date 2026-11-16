import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/dashboard_models.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Halaman batch update harga satuan khusus Owner sesuai Pendev Screen `21 Atur Harga Jual`.
class AturHargaScreen extends StatefulWidget {
  const AturHargaScreen({super.key, required this.viewModel});

  final MasterCrudViewModel viewModel;

  @override
  State<AturHargaScreen> createState() => _AturHargaScreenState();
}

class _AturHargaScreenState extends State<AturHargaScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<int, TextEditingController> _priceControllers = {};
  final Set<int> _dirtyIds = {};

  String? _localError;
  String? _successMessage;
  int _batchErrorPulse = 0;

  @override
  void initState() {
    super.initState();
    widget.viewModel.clearSearch();
    widget.viewModel.clearMessages();
    widget.viewModel.setPriceFilter(PriceFilterCategory.semua);
    _syncControllers(widget.viewModel.allBarang);
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncControllers(List<Barang> items) {
    final activeIds = <int>{};
    for (final item in items) {
      final id = item.idBarang;
      if (id == null) continue;
      activeIds.add(id);
      final baseText = item.hargaSatuan.round().toString();
      final existing = _priceControllers[id];
      if (existing == null) {
        _priceControllers[id] = TextEditingController(text: baseText);
      } else if (!_dirtyIds.contains(id) && existing.text != baseText) {
        existing.text = baseText;
      }
    }
    final staleIds = _priceControllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final staleId in staleIds) {
      _priceControllers.remove(staleId)?.dispose();
      _dirtyIds.remove(staleId);
    }
  }

  bool _isModified(Barang item) {
    final id = item.idBarang;
    if (id == null || !_dirtyIds.contains(id)) return false;
    final text = _priceControllers[id]?.text.trim() ?? '';
    final parsed = int.tryParse(text);
    return parsed == null || parsed != item.hargaSatuan.round();
  }

  Map<int, double> _collectChanges(List<Barang> allItems) {
    final changes = <int, double>{};
    for (final item in allItems) {
      final id = item.idBarang;
      if (id == null || !_isModified(item)) continue;
      final parsed = double.tryParse(_priceControllers[id]?.text.trim() ?? '');
      if (parsed != null) {
        changes[id] = parsed;
      }
    }
    return changes;
  }

  void _handlePriceChanged(Barang item, String raw) {
    final id = item.idBarang;
    if (id == null) return;
    final parsed = int.tryParse(raw.trim());
    setState(() {
      _localError = null;
      _successMessage = null;
      if (parsed != null && parsed == item.hargaSatuan.round()) {
        _dirtyIds.remove(id);
      } else {
        _dirtyIds.add(id);
      }
    });
  }

  void _resetAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _localError = null;
      _successMessage = null;
      _dirtyIds.clear();
      for (final item in widget.viewModel.allBarang) {
        final id = item.idBarang;
        if (id == null) continue;
        _priceControllers[id]?.text = item.hargaSatuan.round().toString();
      }
    });
  }

  Future<void> _saveBatch() async {
    final allItems = widget.viewModel.allBarang;
    final modifiedItems = allItems.where(_isModified).toList();
    if (modifiedItems.isEmpty) {
      setState(() {
        _localError = 'Ubah minimal satu harga barang terlebih dahulu.';
        _successMessage = null;
        _batchErrorPulse++;
      });
      return;
    }

    final changes = <int, double>{};
    for (final item in modifiedItems) {
      final id = item.idBarang!;
      final raw = _priceControllers[id]?.text.trim() ?? '';
      final parsed = double.tryParse(raw);
      if (raw.isEmpty || parsed == null || !parsed.isFinite || parsed <= 0) {
        setState(() {
          _localError =
              'Harga baru untuk "${item.namaBarang}" harus lebih dari Rp 0.';
          _successMessage = null;
          _batchErrorPulse++;
        });
        return;
      }
      changes[id] = parsed;
    }

    setState(() {
      _localError = null;
      _successMessage = null;
    });

    final ok = await widget.viewModel.saveHargaBatch(changes);
    if (!mounted) return;
    if (!ok) {
      setState(() => _batchErrorPulse++);
      return;
    }

    setState(() {
      _dirtyIds.clear();
      _syncControllers(widget.viewModel.allBarang);
      _successMessage =
          '${changes.length} harga jual barang berhasil diperbarui.';
    });
  }

  Widget _buildFilterRow(MasterCrudViewModel vm) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < PriceFilterCategory.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _PriceFilterPill(
              filter: PriceFilterCategory.values[i],
              isActive: vm.priceFilter == PriceFilterCategory.values[i],
              onTap: () => vm.setPriceFilter(PriceFilterCategory.values[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceRow(Barang item) {
    final id = item.idBarang;
    final controller = id != null ? _priceControllers[id] : null;
    final modified = _isModified(item);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.namaBarang,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.heading(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppTokens.stateDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: SizedBox(
                    key: ValueKey(modified),
                    width: double.infinity,
                    child: Text(
                      modified
                          ? 'Stok ${item.stokBarang} · Sebelum ${formatRupiah(item.hargaSatuan)}'
                          : 'Stok ${item.stokBarang} ${item.satuan}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        fontSize: 12,
                        fontWeight:
                            modified ? FontWeight.w600 : FontWeight.w500,
                        color: modified
                            ? MasterUiColors.editBlueText
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 96,
              maxWidth: 126,
              minHeight: 48,
            ),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppTokens.stateDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: modified ? MasterUiColors.editBlueBg : AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: modified
                      ? MasterUiColors.editBlue
                      : AppColors.borderSubtle,
                  width: modified ? 1.4 : 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Text(
                    'Rp',
                    style: AppTypography.body(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: modified
                          ? MasterUiColors.editBlueText
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: TextField(
                        key: ValueKey('atur_harga_input_${item.remoteId}'),
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        textAlignVertical: TextAlignVertical.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (val) => _handlePriceChanged(item, val),
                        style: AppTypography.body(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: modified
                              ? MasterUiColors.editBlueText
                              : AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        _syncControllers(vm.allBarang);

        if (!vm.isOwner) {
          return Scaffold(
            backgroundColor: AppColors.surfaceWarm,
            body: Column(
              children: [
                const MasterAmberHeader(
                  showBackButton: true,
                  title: 'Akses Dibatasi',
                  subtitle: 'Halaman Atur Harga Jual khusus Owner',
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: MasterEmptyStateCard(
                        icon: Icons.lock_outline_rounded,
                        title: 'Khusus Owner DepotTelur36',
                        subtitle:
                            'Hanya akun Owner yang dapat mengubah daftar harga jual barang.',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final visibleItems = vm.filteredBarangForPrice;
        final modifiedChanges = _collectChanges(vm.allBarang);
        final hasDirty = _dirtyIds.isNotEmpty;
        final activeError = _localError ?? vm.errorMessage;

        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              const MasterAmberHeader(
                showBackButton: true,
                title: 'Atur Harga Jual',
                subtitle: 'Perbarui harga satuan untuk transaksi kasir',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    MasterSearchField(
                      controller: _searchController,
                      hintText: 'Cari komoditas untuk ubah harga...',
                      onChanged: vm.setSearchQuery,
                      onClear: () {
                        _searchController.clear();
                        vm.clearSearch();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildFilterRow(vm),
                    SoftAnimatedReveal(
                      visible: activeError != null,
                      child: activeError != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: MasterFeedbackBanner(
                                key: ValueKey(activeError),
                                message: activeError,
                                onDismiss: () {
                                  setState(() => _localError = null);
                                  vm.clearMessages();
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    SoftAnimatedReveal(
                      visible: _successMessage != null,
                      child: _successMessage != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: MasterFeedbackBanner(
                                key: ValueKey(_successMessage!),
                                message: _successMessage!,
                                isError: false,
                                onDismiss: () =>
                                    setState(() => _successMessage = null),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 12),
                    if (visibleItems.isEmpty)
                      const MasterEmptyStateCard(
                        icon: Icons.sell_outlined,
                        title: 'Tidak ada komoditas ditemukan',
                        subtitle:
                            'Coba ubah kata kunci pencarian atau pilih filter komoditas lain.',
                      )
                    else
                      MasterSectionCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < visibleItems.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: AppColors.borderSubtle,
                                ),
                              _buildPriceRow(visibleItems[i]),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    top: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      enabled: hasDirty && !vm.isSaving,
                      label: 'Reset perubahan harga',
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          minWidth: 88,
                        ),
                        child: TactilePressScale(
                          enabled: hasDirty && !vm.isSaving,
                          child: Material(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: const ValueKey('atur_harga_reset_button'),
                              borderRadius: BorderRadius.circular(14),
                              onTap:
                                  (hasDirty && !vm.isSaving) ? _resetAll : null,
                              child: AnimatedOpacity(
                                opacity: hasDirty ? 1 : 0.45,
                                duration: MediaQuery.disableAnimationsOf(
                                  context,
                                )
                                    ? Duration.zero
                                    : AppTokens.microDuration,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Reset',
                                      style: AppTypography.body(
                                        fontSize: 13.5,
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
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ShakeOnError(
                        pulse: _batchErrorPulse,
                        child: Semantics(
                          button: true,
                          label: 'Simpan Harga Baru',
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: TactilePressScale(
                              enabled: !vm.isSaving,
                              child: Material(
                                color: AppColors.ink,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  key: const ValueKey('atur_harga_save_button'),
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: vm.isSaving ? null : _saveBatch,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        RotatingSyncIcon(
                                          isSpinning: vm.isSaving,
                                          icon: vm.isSaving
                                              ? Icons.sync_rounded
                                              : Icons.check_rounded,
                                          size: 18,
                                          color: AppColors.yolk,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration:
                                                MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                                    ? Duration.zero
                                                    : AppTokens.microDuration,
                                            switchInCurve: Curves.easeOutCubic,
                                            switchOutCurve: Curves.easeInCubic,
                                            child: Text(
                                              vm.isSaving
                                                  ? 'Menyimpan...'
                                                  : modifiedChanges.isEmpty
                                                  ? 'Simpan Harga Baru'
                                                  : 'Simpan Harga Baru (${modifiedChanges.length})',
                                              key: ValueKey(
                                                '${vm.isSaving}_${modifiedChanges.length}',
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
                                      ],
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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PriceFilterPill extends StatelessWidget {
  const _PriceFilterPill({
    required this.filter,
    required this.isActive,
    required this.onTap,
  });

  final PriceFilterCategory filter;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: isActive,
      label: 'Filter ${filter.label}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: TactilePressScale(
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppTokens.stateDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isActive ? AppColors.ink : AppColors.inputBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? AppColors.ink : AppColors.borderSubtle,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                key: ValueKey('price_filter_${filter.name}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (!isActive) {
                    HapticFeedback.selectionClick();
                  }
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Center(
                    child: Text(
                      filter.label,
                      style: AppTypography.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isActive
                            ? AppColors.surface
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
