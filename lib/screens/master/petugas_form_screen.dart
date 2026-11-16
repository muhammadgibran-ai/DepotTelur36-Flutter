import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';
import 'package:depot_telur_36/models/petugas.dart';
import 'package:depot_telur_36/models/sync_status.dart';
import 'package:depot_telur_36/repositories/auth_repository.dart';
import 'package:depot_telur_36/viewmodels/master_crud_view_model.dart';
import 'package:depot_telur_36/widgets/auth_interactive_widgets.dart';
import 'package:depot_telur_36/widgets/master_crud_widgets.dart';
import 'package:depot_telur_36/widgets/ux_motion_widgets.dart';

/// Halaman tambah/ubah akun petugas & hak akses RBAC sesuai Pendev Screen `15`.
class PetugasFormScreen extends StatefulWidget {
  const PetugasFormScreen({
    super.key,
    required this.viewModel,
    this.initialPetugas,
  });

  final MasterCrudViewModel viewModel;
  final Petugas? initialPetugas;

  @override
  State<PetugasFormScreen> createState() => _PetugasFormScreenState();
}

class _PetugasFormScreenState extends State<PetugasFormScreen> {
  static final RegExp _pinRegex = RegExp(r'^\d{4}$');

  late final TextEditingController _namaController;
  late final TextEditingController _emailController;
  late final TextEditingController _pinController;
  final GlobalKey _deleteCardKey = GlobalKey();

  late UserRole _selectedRole;
  bool _pinVisible = false;
  bool _showDeleteConfirm = false;
  int _validationErrorPulse = 0;

  String? _namaError;
  String? _emailError;
  String? _pinError;

  bool get _isEdit => widget.initialPetugas != null;

  @override
  void initState() {
    super.initState();
    final petugas = widget.initialPetugas;
    _namaController = TextEditingController(text: petugas?.namaPetugas ?? '');
    _emailController = TextEditingController(text: petugas?.email ?? '');
    _pinController = TextEditingController(text: petugas?.pin ?? '');
    _selectedRole = petugas?.role ?? UserRole.petugas;
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
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final namaRaw = _namaController.text;
    final emailRaw = _emailController.text.trim();
    final pinRaw = _pinController.text.trim();

    String? namaErr;
    String? emailErr;
    String? pinErr;

    if (namaRaw.trim().length < 2) {
      namaErr = 'Nama petugas minimal 2 karakter.';
    }
    final requireEmail = !_isEdit || (widget.initialPetugas?.email.isNotEmpty ?? false);
    if (requireEmail && emailRaw.isEmpty) {
      emailErr = 'Email akun masuk wajib diisi.';
    } else if (emailRaw.isNotEmpty && !AuthRepository.isValidEmail(emailRaw)) {
      emailErr = 'Format email tidak valid.';
    }
    if (!_pinRegex.hasMatch(pinRaw)) {
      pinErr = 'PIN kasir harus tepat 4 digit angka.';
    }

    if (namaErr != null || emailErr != null || pinErr != null) {
      setState(() {
        _namaError = namaErr;
        _emailError = emailErr;
        _pinError = pinErr;
        _validationErrorPulse++;
      });
      return;
    }

    setState(() {
      _namaError = null;
      _emailError = null;
      _pinError = null;
    });

    final ok = await widget.viewModel.savePetugas(
      idPetugas: widget.initialPetugas?.idPetugas,
      existingRemoteId: widget.initialPetugas?.remoteId,
      namaPetugas: namaRaw,
      role: _selectedRole,
      pin: pinRaw,
      email: emailRaw,
      accountId: widget.initialPetugas?.accountId ?? '',
      requireEmail: requireEmail,
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
    final target = widget.initialPetugas;
    if (target == null) return;
    final ok = await widget.viewModel.deletePetugas(target);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _showDeleteConfirm = false);
    }
  }

  Widget _buildRoleOption(UserRole role, String label) {
    final isSelected = _selectedRole == role;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: 'Peran $label',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: TactilePressScale(
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : AppTokens.stateDuration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.ink : AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.ink
                      : AppColors.borderSubtle,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('petugas_role_${role.value}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    if (!isSelected) {
                      HapticFeedback.selectionClick();
                    }
                    setState(() => _selectedRole = role);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          role == UserRole.owner
                              ? Icons.verified_user_rounded
                              : Icons.badge_rounded,
                          size: 17,
                          color:
                              isSelected ? AppColors.yolk : AppColors.textPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: AppTypography.body(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? AppColors.surface
                                : AppColors.textPrimary,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;

        if (!vm.isOwner) {
          return Scaffold(
            backgroundColor: AppColors.surfaceWarm,
            body: Column(
              children: [
                const MasterAmberHeader(
                  showBackButton: true,
                  title: 'Akses Dibatasi',
                  subtitle: 'Halaman pengelolaan petugas hanya untuk Owner',
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: MasterEmptyStateCard(
                        icon: Icons.lock_outline_rounded,
                        title: 'Khusus Owner DepotTelur36',
                        subtitle:
                            'Akun Operator/Petugas tidak memiliki izin untuk menambah, mengubah, atau menghapus akun pengguna.',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.surfaceWarm,
          body: Column(
            children: [
              MasterAmberHeader(
                showBackButton: true,
                badgeLabel: 'RBAC OWNER ONLY',
                title: _isEdit ? 'Edit Akun Petugas' : 'Tambah Petugas Baru',
                subtitle:
                    'Atur identitas kasir, PIN, dan hak akses Owner/Petugas',
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SoftAnimatedReveal(
                        visible: vm.errorMessage != null,
                        child: vm.errorMessage != null
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: MasterFeedbackBanner(
                                  key: ValueKey(vm.errorMessage!),
                                  message: vm.errorMessage!,
                                  onDismiss: vm.clearMessages,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      ShakeOnError(
                        pulse: _validationErrorPulse,
                        child: MasterSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MasterInputField(
                              fieldKey: const ValueKey('petugas_nama_field'),
                              label: 'Nama Petugas',
                              controller: _namaController,
                              hintText: 'cth: Budi Santoso',
                              errorText: _namaError,
                              onChanged: (_) =>
                                  setState(() => _namaError = null),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Peran Petugas',
                              style: AppTypography.body(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _buildRoleOption(UserRole.petugas, 'Petugas'),
                                const SizedBox(width: 10),
                                _buildRoleOption(UserRole.owner, 'Owner'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : AppTokens.stateDuration,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: SizedBox(
                                key: ValueKey(_selectedRole),
                                width: double.infinity,
                                child: Text(
                                  _selectedRole == UserRole.owner
                                      ? 'Owner dapat mengakses laporan omzet, atur harga jual, dan kelola akun.'
                                      : 'Petugas fokus pada transaksi kasir, faktur masuk, dan daftar master operasional.',
                                  style: AppTypography.body(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            MasterInputField(
                              fieldKey: const ValueKey('petugas_email_field'),
                              label: 'Email Akun Masuk (Firebase)',
                              controller: _emailController,
                              hintText: 'petugas@depottelur36.com',
                              errorText: _emailError,
                              keyboardType: TextInputType.emailAddress,
                              onChanged: (_) =>
                                  setState(() => _emailError = null),
                            ),
                            const SizedBox(height: 14),
                            MasterInputField(
                              fieldKey: const ValueKey('petugas_pin_field'),
                              label: 'PIN Kasir (4 Digit)',
                              controller: _pinController,
                              hintText: '1234',
                              errorText: _pinError,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              obscureText: !_pinVisible,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) =>
                                  setState(() => _pinError = null),
                              suffix: IconButton(
                                key: const ValueKey(
                                  'petugas_pin_visibility_toggle',
                                ),
                                tooltip: _pinVisible
                                    ? 'Sembunyikan PIN'
                                    : 'Tampilkan PIN',
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setState(() => _pinVisible = !_pinVisible);
                                },
                                icon: AnimatedSwitcher(
                                  duration: MediaQuery.disableAnimationsOf(
                                    context,
                                  )
                                      ? Duration.zero
                                      : AppTokens.microDuration,
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(
                                    scale: animation,
                                    child: FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    ),
                                  ),
                                  child: Icon(
                                    _pinVisible
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    key: ValueKey(_pinVisible),
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
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
                                    title: 'Konfirmasi Hapus Petugas?',
                                    message:
                                        'Akun "${widget.initialPetugas!.namaPetugas}" akan dicabut dari perangkat dan cloud apabila belum memiliki transaksi Faktur/Nota.',
                                    confirmLabel: 'Ya, Hapus Petugas',
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
                saveLabel: _isEdit ? 'Simpan Perubahan' : 'Simpan Petugas',
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
