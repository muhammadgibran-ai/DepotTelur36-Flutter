import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/barang.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/barang_thumbnail.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Halaman tambah/ubah data barang sesuai Pendev Screen `10 Form Barang (CRUD)`.
class BarangFormScreen extends StatefulWidget {
  const BarangFormScreen({
    super.key,
    required this.viewModel,
    this.initialBarang,
  });

  final MasterCrudViewModel viewModel;
  final Barang? initialBarang;

  @override
  State<BarangFormScreen> createState() => _BarangFormScreenState();
}

class _BarangFormScreenState extends State<BarangFormScreen> {
  static const List<String> _unitPresets = ['Kg', 'Tray', 'Butir', 'Sak', 'Pouch'];

  late final TextEditingController _namaController;
  late final TextEditingController _stokController;
  late final TextEditingController _satuanController;
  late final TextEditingController _hargaController;
  final GlobalKey _deleteCardKey = GlobalKey();

  String? _selectedPresetAsset;
  bool _presetWasCleared = false;
  bool _showPhotoPicker = false;
  bool _showDeleteConfirm = false;
  int _validationErrorPulse = 0;

  String? _namaError;
  String? _stokError;
  String? _satuanError;
  String? _hargaError;

  bool get _isEdit => widget.initialBarang != null;

  @override
  void initState() {
    super.initState();
    final barang = widget.initialBarang;
    _namaController = TextEditingController(text: barang?.namaBarang ?? '');
    _stokController = TextEditingController(
      text: barang != null ? barang.stokBarang.toString() : '',
    );
    _satuanController = TextEditingController(text: barang?.satuan ?? 'Kg');
    _hargaController = TextEditingController(
      text: barang != null ? barang.hargaSatuan.round().toString() : '',
    );
    if (barang != null) {
      _selectedPresetAsset =
          BarangPhotoPresets.customAssetsListenable.value[barang.remoteId];
    }
    widget.viewModel.clearMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      }
    });
  }

  @override
  void dispose() {
    _namaController.dispose();
    _stokController.dispose();
    _satuanController.dispose();
    _hargaController.dispose();
    super.dispose();
  }

  void _selectUnit(String unit) {
    HapticFeedback.selectionClick();
    setState(() {
      _satuanController.text = unit;
      _satuanError = null;
    });
  }

  Future<void> _submit() async {
    final namaRaw = _namaController.text;
    final stokRaw = _stokController.text.trim();
    final satuanRaw = _satuanController.text;
    final hargaRaw = _hargaController.text.trim();

    final parsedStok = int.tryParse(stokRaw);
    final parsedHarga = double.tryParse(hargaRaw);

    String? namaErr;
    String? stokErr;
    String? satuanErr;
    String? hargaErr;

    if (namaRaw.trim().length < 2) {
      namaErr = 'Nama barang minimal 2 karakter.';
    }
    if (stokRaw.isEmpty || parsedStok == null || parsedStok < 0) {
      stokErr = 'Stok harus berupa angka >= 0.';
    }
    if (satuanRaw.trim().isEmpty) {
      satuanErr = 'Satuan wajib diisi.';
    }
    if (hargaRaw.isEmpty ||
        parsedHarga == null ||
        !parsedHarga.isFinite ||
        parsedHarga <= 0) {
      hargaErr = 'Harga satuan harus > Rp 0.';
    }

    if (namaErr != null ||
        stokErr != null ||
        satuanErr != null ||
        hargaErr != null) {
      setState(() {
        _namaError = namaErr;
        _stokError = stokErr;
        _satuanError = satuanErr;
        _hargaError = hargaErr;
        _validationErrorPulse++;
      });
      return;
    }

    setState(() {
      _namaError = null;
      _stokError = null;
      _satuanError = null;
      _hargaError = null;
    });

    final targetRemoteId =
        widget.initialBarang?.remoteId ?? const Uuid().v4();
    final ok = await widget.viewModel.saveBarang(
      idBarang: widget.initialBarang?.idBarang,
      existingRemoteId: targetRemoteId,
      namaBarang: namaRaw,
      stokBarang: parsedStok!,
      satuan: satuanRaw,
      hargaSatuan: parsedHarga!,
    );

    if (!mounted) return;
    if (!ok) {
      setState(() => _validationErrorPulse++);
      return;
    }

    if (_selectedPresetAsset != null) {
      BarangPhotoPresets.setAssetForRemoteId(
        targetRemoteId,
        _selectedPresetAsset,
      );
    } else if (_presetWasCleared) {
      BarangPhotoPresets.setAssetForRemoteId(targetRemoteId, null);
    }

    Navigator.of(context).pop(true);
  }

  void _scrollToDeleteCard() {
    if (!mounted || !_showDeleteConfirm) return;
    final ctx = _deleteCardKey.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(
        ctx,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        alignment: 0.9,
      );
    }
  }

  void _promptDelete() {
    setState(() => _showDeleteConfirm = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDeleteCard());
  }

  Future<void> _confirmDelete() async {
    final target = widget.initialBarang;
    if (target == null) return;
    final ok = await widget.viewModel.deleteBarang(target);
    if (!mounted) return;
    if (ok) {
      BarangPhotoPresets.setAssetForRemoteId(target.remoteId, null);
      Navigator.of(context).pop(true);
    } else {
      setState(() => _showDeleteConfirm = false);
    }
  }

  Widget _buildPhotoCard() {
    final previewBarang = Barang(
      idBarang: widget.initialBarang?.idBarang,
      namaBarang: _namaController.text.trim().isEmpty
          ? (widget.initialBarang?.namaBarang ?? 'Barang Baru')
          : _namaController.text.trim(),
      stokBarang: int.tryParse(_stokController.text.trim()) ?? 0,
      satuan: _satuanController.text.trim().isEmpty
          ? 'Kg'
          : _satuanController.text.trim(),
      hargaSatuan: double.tryParse(_hargaController.text.trim()) ?? 0,
      remoteId: widget.initialBarang?.remoteId ?? '__preview_barang__',
      syncStatus: SyncStatus.pending,
      updatedAt: DateTime.now(),
    );

    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final previewWidget = _selectedPresetAsset != null
        ? Container(
            key: ValueKey('preset_${_selectedPresetAsset!}'),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              _selectedPresetAsset!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) =>
                  BarangThumbnail(barang: previewBarang, size: 64, radius: 14),
            ),
          )
        : KeyedSubtree(
            key: const ValueKey('preset_auto'),
            child: BarangThumbnail(barang: previewBarang, size: 64, radius: 14),
          );

    return MasterSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: disableMotion ? Duration.zero : AppTokens.stateDuration,
                switchInCurve: AppTokens.arrivalCurve,
                transitionBuilder: (child, anim) {
                  if (disableMotion) {
                    return FadeTransition(opacity: anim, child: child);
                  }
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.9, end: 1.0).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: previewWidget,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Foto Barang',
                      style: AppTypography.heading(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pilih preset foto produk agar kasir mudah mengenali barang',
                      style: AppTypography.body(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Ganti Foto Barang',
                child: TactilePressScale(
                  pressedScale: 0.94,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Material(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: const ValueKey('barang_toggle_photo_picker'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showPhotoPicker = !_showPhotoPicker);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: disableMotion
                                  ? Duration.zero
                                  : AppTokens.microDuration,
                              child: Text(
                                _showPhotoPicker ? 'Tutup' : 'Ganti Foto',
                                key: ValueKey(_showPhotoPicker),
                                style: AppTypography.body(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
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
          SoftAnimatedReveal(
            visible: _showPhotoPicker,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPresetChip(
                    label: 'Otomatis',
                    isSelected: _selectedPresetAsset == null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedPresetAsset = null;
                        _presetWasCleared = true;
                      });
                    },
                  ),
                  for (final option in BarangPhotoPresets.options)
                    _buildPresetChip(
                      label: option.label,
                      isSelected: _selectedPresetAsset == option.assetPath,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedPresetAsset = option.assetPath;
                          _presetWasCleared = false;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Preset foto $label',
      child: TactilePressScale(
        pressedScale: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: AnimatedContainer(
            duration: disableMotion ? Duration.zero : AppTokens.microDuration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.ink : AppColors.inputBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: AppTypography.body(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isSelected
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final currentUnit = _satuanController.text.trim().toLowerCase();

        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              MasterAmberHeader(
                showBackButton: true,
                title: _isEdit ? 'Edit Data Barang' : 'Tambah Barang Baru',
                subtitle: 'Perbarui informasi barang, stok awal, dan harga',
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SoftAnimatedReveal(
                        visible: vm.errorMessage != null,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: MasterFeedbackBanner(
                            message: vm.errorMessage ?? '',
                            onDismiss: vm.clearMessages,
                          ),
                        ),
                      ),
                      _buildPhotoCard(),
                      const SizedBox(height: 12),
                      ShakeOnError(
                        pulse: _validationErrorPulse,
                        child: MasterSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MasterInputField(
                              fieldKey: const ValueKey('barang_nama_field'),
                              label: 'Nama Barang',
                              controller: _namaController,
                              hintText: 'cth: Telur Ayam Kampung',
                              errorText: _namaError,
                              onChanged: (_) => setState(() => _namaError = null),
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stokField = MasterInputField(
                                  fieldKey: const ValueKey('barang_stok_field'),
                                  label: 'Stok Gudang',
                                  controller: _stokController,
                                  hintText: '0',
                                  errorText: _stokError,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (_) =>
                                      setState(() => _stokError = null),
                                );
                                final satuanField = MasterInputField(
                                  fieldKey: const ValueKey(
                                    'barang_satuan_field',
                                  ),
                                  label: 'Satuan',
                                  controller: _satuanController,
                                  hintText: 'Kg / Tray',
                                  errorText: _satuanError,
                                  onChanged: (_) =>
                                      setState(() => _satuanError = null),
                                );

                                if (constraints.maxWidth < 300) {
                                  return Column(
                                    children: [
                                      stokField,
                                      const SizedBox(height: 14),
                                      satuanField,
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: stokField),
                                    const SizedBox(width: 12),
                                    Expanded(child: satuanField),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Pilih Cepat Satuan',
                              style: AppTypography.body(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _unitPresets.map((unit) {
                                final isSelected =
                                    currentUnit == unit.toLowerCase();
                                final disableMotion =
                                    MediaQuery.disableAnimationsOf(context);
                                return Semantics(
                                  button: true,
                                  selected: isSelected,
                                  label: 'Satuan $unit',
                                  child: TactilePressScale(
                                    pressedScale: 0.94,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 48,
                                      ),
                                      child: AnimatedContainer(
                                        duration: disableMotion
                                            ? Duration.zero
                                            : AppTokens.microDuration,
                                        curve: Curves.easeOutCubic,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.ink
                                              : AppColors.inputBg,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: InkWell(
                                            key: ValueKey('unit_chip_$unit'),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onTap: () => _selectUnit(unit),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 12,
                                              ),
                                              child: Center(
                                                widthFactor: 1,
                                                child: Text(
                                                  unit,
                                                  style: AppTypography.body(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: isSelected
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
                              }).toList(),
                            ),
                            const SizedBox(height: 14),
                            MasterInputField(
                              fieldKey: const ValueKey('barang_harga_field'),
                              label: 'Harga Satuan (Rp)',
                              controller: _hargaController,
                              hintText: '28500',
                              prefixText: 'Rp',
                              errorText: _hargaError,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) =>
                                  setState(() => _hargaError = null),
                            ),
                          ],
                        ),
                      ),
                      ),
                      SoftAnimatedReveal(
                        visible: _isEdit && _showDeleteConfirm,
                        alignment: Alignment.topCenter,
                        slideOffset: const Offset(0, 0.04),
                        onRevealed: _scrollToDeleteCard,
                        child: _isEdit
                            ? Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  key: _deleteCardKey,
                                  child: DeleteConfirmCard(
                                    title: 'Konfirmasi Hapus Barang?',
                                    message:
                                        'Barang "${widget.initialBarang!.namaBarang}" akan dihapus permanen bila belum tercatat di Faktur atau Nota.',
                                    confirmLabel: 'Ya, Hapus Barang',
                                    isBusy: vm.isSaving,
                                    onCancel: () => setState(
                                      () => _showDeleteConfirm = false,
                                    ),
                                    onConfirm: _confirmDelete,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              CrudActionFooter(
                saveLabel: _isEdit ? 'Simpan Perubahan' : 'Simpan Barang',
                isSaving: vm.isSaving,
                showDelete: _isEdit,
                onDelete: _promptDelete,
                onSave: _submit,
              ),
            ],
          ),
        );
      },
    );
  }
}
