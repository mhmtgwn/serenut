// lib/presentation/pages/collection_page.dart
// Serenut POS — Müşteri Tahsilat Sayfası (Tam Ekran)
// UX Redesign v3: Full-screen, no dialog, live balance preview

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';

const _kGreen      = Color(0xFF16A34A);
const _kGreenDark  = Color(0xFF15803D);
const _kGreenLight = Color(0xFFDCFCE7);
const _kBlue       = Color(0xFF2563EB);
const _kBlueLight  = Color(0xFFDBEAFE);
const _kRed        = Color(0xFFDC2626);
const _kRedLight   = Color(0xFFFEE2E2);
const _kSurface    = Color(0xFFF8FAFC);
const _kText       = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder     = Color(0xFFE2E8F0);

class CollectionPage extends ConsumerStatefulWidget {
  final String customerId;

  const CollectionPage({super.key, required this.customerId});

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController   = TextEditingController();
  String _selectedMethod  = 'cash'; // 'cash' | 'card'
  bool _isSaving          = false;

  bool _printReceipt = true;
  bool _isPrintReceiptInitialized = false;

  CustomerEntity? _customer;

  double get _enteredAmount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0.0;

  double get _balanceAfter {
    if (_customer == null) return 0;
    // balance < 0 means debt; collecting reduces the debt
    return _customer!.balance + _enteredAmount;
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(collectionCustomersControllerProvider);

    return customersAsync.when(
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen),
          ),
        ),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Tahsilat')),
        body: Center(child: Text('Hata: $err')),
      ),
      data: (customers) {
        _customer = customers.where((c) => c.id == widget.customerId).firstOrNull;
        if (_customer == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => context.pop()),
              title: const Text('Tahsilat'),
            ),
            body: const Center(child: Text('Müşteri bulunamadı.')),
          );
        }

        final settingsAsync = ref.watch(settingsNotifierProvider);
        final settings = settingsAsync.value;
        if (settings != null && !_isPrintReceiptInitialized) {
          _printReceipt = settings.printReceipt;
          _isPrintReceiptInitialized = true;
        }

        return _buildScaffold(_customer!);
      },
    );
  }

  Widget _buildScaffold(CustomerEntity customer) {
    final debt = customer.balance < 0 ? customer.balance.abs() : 0.0;
    final isDebt = customer.balance < 0;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tahsilat Yap',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: _kText, fontSize: 16),
            ),
            Text(
              customer.name,
              style: const TextStyle(color: _kTextSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ── Müşteri Özet Kartı ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDebt
                      ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                      : [const Color(0xFF16A34A), const Color(0xFF15803D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(
                      customer.name.isNotEmpty
                          ? customer.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                        if (customer.phone.isNotEmpty)
                          Text(
                            customer.phone,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isDebt ? 'Toplam Borç' : 'Alacak',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '₺${customer.balance.abs().toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Tahsilat Tutarı ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.payments_rounded, size: 16, color: _kGreenDark),
                      SizedBox(width: 8),
                      Text('Tahsil Edilen Tutar',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _kText)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]'))
                    ],
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _kGreenDark),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w300,
                          color: _kBorder),
                      prefixText: '₺ ',
                      prefixStyle: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _kGreenDark),
                      filled: true,
                      fillColor: _kGreenLight.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: _kGreen.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kGreen, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Tutar giriniz';
                      final d = double.tryParse(v.trim().replaceAll(',', '.'));
                      if (d == null || d <= 0) {
                        return 'Geçerli bir pozitif tutar giriniz';
                      }
                      return null;
                    },
                  ),
                  // Tüm borcu al
                  if (isDebt && debt > 0) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() {
                        _amountController.text = debt.toStringAsFixed(2);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Tamamını Al: ₺${debt.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: _kGreenDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Bakiye Önizleme ────────────────────────────────────────────
            if (_enteredAmount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _balanceAfter >= 0 ? _kGreenLight : _kRedLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _balanceAfter >= 0
                        ? _kGreen.withValues(alpha: 0.3)
                        : _kRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _balanceAfter >= 0
                          ? Icons.check_circle_rounded
                          : Icons.info_rounded,
                      size: 18,
                      color: _balanceAfter >= 0 ? _kGreenDark : _kRed,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tahsilat Sonrası Bakiye',
                          style: TextStyle(
                              fontSize: 11,
                              color: _balanceAfter >= 0 ? _kGreenDark : _kRed,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '₺${_balanceAfter.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _balanceAfter >= 0 ? _kGreenDark : _kRed),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // ── Ödeme Yöntemi ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.credit_card_rounded, size: 16, color: _kTextSecondary),
                      SizedBox(width: 8),
                      Text('Tahsilat Yöntemi',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _kText)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MethodToggle(
                        label: 'Nakit',
                        icon: Icons.payments_rounded,
                        selected: _selectedMethod == 'cash',
                        color: _kGreen,
                        lightColor: _kGreenLight,
                        onTap: () => setState(() => _selectedMethod = 'cash'),
                      ),
                      const SizedBox(width: 10),
                      _MethodToggle(
                        label: 'Kart',
                        icon: Icons.credit_card_rounded,
                        selected: _selectedMethod == 'card',
                        color: _kBlue,
                        lightColor: _kBlueLight,
                        onTap: () => setState(() => _selectedMethod = 'card'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Açıklama ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notes_rounded, size: 16, color: _kTextSecondary),
                      SizedBox(width: 8),
                      Text('Açıklama (Opsiyonel)',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: _kText)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'İşlem açıklaması...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kGreen, width: 2)),
                      filled: true,
                      fillColor: _kSurface,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Yazıcı Ayarları ve Fiş Seçeneği ────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _printReceipt ? Icons.print_rounded : Icons.print_disabled_rounded,
                        size: 16,
                        color: _printReceipt ? _kGreenDark : _kTextSecondary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Yazıcı Ayarları',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: _kText),
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        value: _printReceipt,
                        activeColor: _kGreen,
                        onChanged: (val) => setState(() => _printReceipt = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Info about the active printer configuration
                  Builder(
                    builder: (context) {
                      final settingsAsync = ref.watch(settingsNotifierProvider);
                      final settings = settingsAsync.value;
                      if (settings == null) return const SizedBox.shrink();
                      
                      final hasIp = settings.printerIp != null && settings.printerIp!.isNotEmpty;
                      final hasName = settings.printerName != null && settings.printerName!.isNotEmpty;
                      
                      if (!hasIp && !hasName) {
                        return GestureDetector(
                          onTap: () {
                            context.push('/settings');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kRedLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _kRed.withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 16, color: _kRed),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Aktif yazıcı bulunamadı! Ayarlamak için dokunun.',
                                    style: TextStyle(color: _kRed, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 16, color: _kRed),
                              ],
                            ),
                          ),
                        );
                      }
                      
                      String printerInfo = '';
                      if (hasIp) {
                        printerInfo = 'Ağ Yazıcısı: ${settings.printerIp}';
                      } else if (hasName) {
                        printerInfo = 'Yazıcı: ${settings.printerName}';
                      }
                      
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _kGreenLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kGreen.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 16, color: _kGreenDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                printerInfo,
                                style: const TextStyle(color: _kGreenDark, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Kaydet Butonu ─────────────────────────────────────────────
            SizedBox(
              height: 58,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.price_check_rounded, size: 22),
                label: const Text(
                  'Tahsilatı Kaydet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(collectionCustomersControllerProvider.notifier).recordCollection(
            customerId: widget.customerId,
            amount: _enteredAmount,
            method: _selectedMethod,
            notes: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );

      // Get the settings and the updated customer (which now has updated balance)
      final settings = ref.read(settingsNotifierProvider).value;
      final updatedCustomers = ref.read(collectionCustomersControllerProvider).value;
      final updatedCustomer = updatedCustomers
          ?.where((c) => c.id == widget.customerId)
          .firstOrNull;
      
      final currentCustomer = _customer;
      final customerToPrint = updatedCustomer ??
          (currentCustomer != null
              ? CustomerEntity(
                  id: currentCustomer.id,
                  name: currentCustomer.name,
                  email: currentCustomer.email,
                  phone: currentCustomer.phone,
                  balance: currentCustomer.balance + _enteredAmount,
                  createdAt: currentCustomer.createdAt,
                )
              : null);

      if (_printReceipt && settings != null && customerToPrint != null) {
        ref.read(printerServiceProvider).enqueue(
              'Tahsilat Fişi (${customerToPrint.name})',
              () => ref.read(printerServiceProvider).printCollectionReceipt(
                    customerToPrint,
                    _enteredAmount,
                    _selectedMethod,
                    _noteController.text.trim().isEmpty
                        ? null
                        : _noteController.text.trim(),
                    settings,
                  ),
            );
      }

      ref.invalidate(dashboardProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tahsilat başarıyla kaydedildi.'),
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
}

// ── Ödeme Yöntemi Toggle ──────────────────────────────────────────────────────

class _MethodToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final Color lightColor;
  final VoidCallback onTap;

  const _MethodToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.lightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? color : _kSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : _kBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: selected ? Colors.white : color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
