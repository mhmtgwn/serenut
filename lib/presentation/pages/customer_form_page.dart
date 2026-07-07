// lib/presentation/pages/customer_form_page.dart
// Serenut POS — Müşteri Ekleme / Düzenleme (Tam Ekran Form)
// UX Redesign v3: Full-screen, no dialog, mobile banking form style

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:uuid/uuid.dart';

const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kRed        = Color(0xFFDC2626);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class CustomerFormPage extends ConsumerStatefulWidget {
  final bool isEditing;
  final CustomerEntity? existingCustomer;

  const CustomerFormPage({
    super.key,
    required this.isEditing,
    this.existingCustomer,
  });

  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus    = FocusNode();
  final _phoneFocus   = FocusNode();
  final _emailFocus   = FocusNode();
  final _balanceFocus = FocusNode();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _balanceController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existingCustomer;
    _nameController    = TextEditingController(text: c?.name ?? '');
    _phoneController   = TextEditingController(text: c?.phone ?? '');
    _emailController   = TextEditingController(text: c?.email ?? '');
    _balanceController = TextEditingController(
        text: c == null ? '0' : c.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _balanceController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _balanceFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      final id = widget.isEditing
          ? widget.existingCustomer!.id
          : const Uuid().v4();

      final customer = CustomerEntity(
        id: id,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        balance: widget.isEditing
            ? widget.existingCustomer!.balance
            : (double.tryParse(
                    _balanceController.text.trim().replaceAll(',', '.')) ??
                0.0),
        createdAt:
            widget.isEditing ? widget.existingCustomer!.createdAt : DateTime.now(),
      );

      final notifier = ref.read(customersControllerProvider.notifier);
      if (widget.isEditing) {
        await notifier.updateCustomer(customer);
      } else {
        await notifier.addCustomer(customer);
      }
      ref.invalidate(dashboardProvider);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing
                  ? '${customer.name} güncellendi.'
                  : '${customer.name} eklendi.',
            ),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _kText),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.isEditing ? 'Müşteri Düzenle' : 'Yeni Müşteri',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: _kText, fontSize: 17),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(_kGreen),
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: Text(
                      widget.isEditing ? 'Kaydet' : 'Ekle',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Profil İkon ────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _kGreenLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: _kGreen.withValues(alpha: 0.3), width: 2),
                    ),
                    child: const Icon(Icons.person_rounded,
                        size: 36, color: _kGreenDark),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isEditing ? 'Müşteri bilgilerini düzenleyin' : 'Yeni müşteri hesabı oluşturun',
                    style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Temel Bilgiler ─────────────────────────────────────────────
            _buildSection(
              icon: Icons.badge_rounded,
              label: 'Temel Bilgiler',
              children: [
                _buildField(
                  controller: _nameController,
                  focusNode: _nameFocus,
                  label: 'Müşteri / Firma Adı *',
                  icon: Icons.person_rounded,
                  textCapitalization: TextCapitalization.words,
                  nextFocus: _phoneFocus,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ad zorunludur' : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _phoneController,
                  focusNode: _phoneFocus,
                  label: 'Telefon Numarası',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\+\-]'))],
                  nextFocus: _emailFocus,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  label: 'E-posta Adresi',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  nextFocus: widget.isEditing ? null : _balanceFocus,
                ),
              ],
            ),

            // ── Açılış Bakiyesi (sadece yeni müşteride) ──────────────────
            if (!widget.isEditing) ...[
              const SizedBox(height: 16),
              _buildSection(
                icon: Icons.account_balance_wallet_rounded,
                label: 'Başlangıç Bakiyesi',
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 16, color: Color(0xFFB45309)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Negatif değer borç (ör: -150), pozitif değer alacak anlamına gelir.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _balanceController,
                    focusNode: _balanceFocus,
                    label: 'Başlangıç Bakiyesi (₺)',
                    icon: Icons.account_balance_wallet_rounded,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\.\,\-]'))
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Bakiye giriniz';
                      if (double.tryParse(v.trim().replaceAll(',', '.')) == null) {
                        return 'Geçerli bir sayı giriniz';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),

            // ── Kaydet Butonu (büyük) ─────────────────────────────────────
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        widget.isEditing
                            ? Icons.save_rounded
                            : Icons.person_add_rounded),
                label: Text(
                  widget.isEditing ? 'Değişiklikleri Kaydet' : 'Müşteri Ekle',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String label,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 14, color: _kGreenDark),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kText),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    FocusNode? nextFocus,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      textInputAction:
          nextFocus != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        } else {
          focusNode.unfocus();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kRed),
        ),
        filled: true,
        fillColor: _kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
