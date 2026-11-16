import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/supplier.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Halaman tambah/ubah data supplier sesuai Pendev Screen `12 Form Supplier (CRUD)`.
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({
    super.key,
    required this.viewModel,
    this.initialSupplier,
  });

  final MasterCrudViewModel viewModel;
  final Supplier? initialSupplier;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  static final RegExp _phoneCleanRegex = RegExp(r'[\s\-\(\)\+]');
  static final RegExp _digitsRegex = RegExp(r'^\d{8,15}$');

  late final TextEditingController _namaController;
  late final TextEditingController _telpController;
  late final TextEditingController _alamatController;
  final GlobalKey _deleteCardKey = GlobalKey();

  String? _namaError;
  String? _telpError;
  String? _alamatError;
  bool _showDeleteConfirm = false;
  int _validationErrorPulse = 0;

  bool get _isEdit => widget.initialSupplier != null;

  @override
  void initState() {
    super.initState();
    final supplier = widget.initialSupplier;
    _namaController = TextEditingController(text: supplier?.namaSupplier ?? '');
    _telpController = TextEditingController(
      text: supplier?.noTelpSupplier ?? '',
    );
    _alamatController = TextEditingController(
      text: supplier?.alamatSupplier ?? '',
    );
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
    _telpController.dispose();
    _alamatController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final namaRaw = _namaController.text;
    final telpRaw = _telpController.text.trim();
    final alamatRaw = _alamatController.text.trim();

    String? namaErr;
    String? telpErr;
    String? alamatErr;

    if (namaRaw.trim().length < 2) {
      namaErr = 'Nama supplier minimal 2 karakter.';
    }
    final telpDigits = telpRaw.replaceAll(_phoneCleanRegex, '');
    if (telpRaw.isEmpty) {
      telpErr = 'Nomor telepon wajib diisi.';
    } else if (!_digitsRegex.hasMatch(telpDigits)) {
      telpErr = 'Nomor telepon harus 8-15 digit angka.';
    }
    if (alamatRaw.length < 5) {
      alamatErr = 'Alamat lengkap minimal 5 karakter.';
    }

    if (namaErr != null || telpErr != null || alamatErr != null) {
      setState(() {
        _namaError = namaErr;
        _telpError = telpErr;
        _alamatError = alamatErr;
        _validationErrorPulse++;
      });
      return;
    }

    setState(() {
      _namaError = null;
      _telpError = null;
      _alamatError = null;
    });

    final ok = await widget.viewModel.saveSupplier(
      idSupplier: widget.initialSupplier?.idSupplier,
      existingRemoteId: widget.initialSupplier?.remoteId,
      namaSupplier: namaRaw,
      alamatSupplier: alamatRaw,
      noTelpSupplier: telpRaw,
    );

    if (!mounted) return;
    if (!ok) {
      setState(() => _validationErrorPulse++);
      return;
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
    final target = widget.initialSupplier;
    if (target == null) return;
    final ok = await widget.viewModel.deleteSupplier(target);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _showDeleteConfirm = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              MasterAmberHeader(
                showBackButton: true,
                title: _isEdit ? 'Edit Data Supplier' : 'Tambah Supplier Baru',
                subtitle: 'Perbarui kontak dan alamat mitra pemasok telur',
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
                      ShakeOnError(
                        pulse: _validationErrorPulse,
                        child: MasterSectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MasterInputField(
                                fieldKey: const ValueKey('supplier_nama_field'),
                                label: 'Nama Supplier',
                                controller: _namaController,
                                hintText: 'cth: Peternakan Maju Jaya',
                                errorText: _namaError,
                                onChanged: (_) =>
                                    setState(() => _namaError = null),
                              ),
                              const SizedBox(height: 14),
                              MasterInputField(
                                fieldKey: const ValueKey('supplier_telp_field'),
                                label: 'No. Telepon / WhatsApp',
                                controller: _telpController,
                                hintText: 'cth: 0812-3456-7890',
                                errorText: _telpError,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9\+\-\s\(\)]'),
                                  ),
                                ],
                                onChanged: (_) =>
                                    setState(() => _telpError = null),
                              ),
                              const SizedBox(height: 14),
                              MasterInputField(
                                fieldKey: const ValueKey('supplier_alamat_field'),
                                label: 'Alamat Lengkap',
                                controller: _alamatController,
                                hintText: 'cth: Jl. Raya Bogor KM 24, Jakarta Timur',
                                errorText: _alamatError,
                                maxLines: 3,
                                onChanged: (_) =>
                                    setState(() => _alamatError = null),
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
                                    title: 'Konfirmasi Hapus Supplier?',
                                    message:
                                        'Supplier "${widget.initialSupplier!.namaSupplier}" tidak dapat dihapus jika sudah memiliki riwayat Faktur masuk.',
                                    confirmLabel: 'Ya, Hapus Supplier',
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
                saveLabel: _isEdit ? 'Simpan Perubahan' : 'Simpan Supplier',
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
