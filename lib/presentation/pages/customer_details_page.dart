// lib/presentation/pages/customer_details_page.dart
// Serenut OS — Müşteri Detay Sayfası (Bankacılık Stili)
// UX Redesign v3: Hero gradient card, bank-statement transaction list,
// full-screen collection push (no dialog). Uses existing providers — zero backend changes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/presentation/widgets/auth/rbac_guard.dart';
import 'package:serenutos/presentation/widgets/export_bottom_sheet.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/presentation/widgets/common/country_code_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/domain/models/installment_models.dart';
import 'package:serenutos/domain/utils/safe_money.dart';
import 'package:serenutos/presentation/controllers/installment_controller.dart';
import 'package:serenutos/providers/printing_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kAmber = POSColors.amber;
const _kAmberLight = POSColors.amberLight;
const _kAmberDark = POSColors.amberDark;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class CustomerDetailsPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailsPage({super.key, required this.customerId});

  Future<void> _showManualDebtDialog(
      BuildContext context, WidgetRef ref, CustomerEntity customer) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final downPaymentController = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();
    var isInstallment = false;
    var installmentCount = 3;
    var firstDueDate = DateTime.now().add(const Duration(days: 30));
    var downPaymentMethod = 'cash';
    var printReceipt = true;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalAmt = double.tryParse(
                  amountController.text.trim().replaceAll(',', '.')) ??
              0.0;
          final downAmt = double.tryParse(
                  downPaymentController.text.trim().replaceAll(',', '.')) ??
              0.0;
          final financedAmt =
              (totalAmt - downAmt).clamp(0.0, double.infinity);
          final basePerInst = installmentCount > 0
              ? (financedAmt / installmentCount).floorToDouble()
              : 0.0;
          final lastInstAmt = installmentCount > 0
              ? (financedAmt - (basePerInst * (installmentCount - 1)))
              : 0.0;

          return AlertDialog(
            title: Text(
                isInstallment ? 'Taksitli Borç Planı Ekle' : 'Elle Borç Ekle'),
            content: SizedBox(
              width: 440,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer.name} için cari hesaba borç kaydı oluşturulur.',
                        style: const TextStyle(
                            fontSize: 13, color: _kTextSecondary),
                      ),
                      const SizedBox(height: 12),

                      // Seçim Segmenti: Tek Seferlik vs Taksitli
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => setDialogState(
                                    () => isInstallment = false),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: !isInstallment
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: !isInstallment
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Tek Seferlik Borç',
                                    style: TextStyle(
                                      fontWeight: !isInstallment
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: !isInstallment
                                          ? _kGreenDark
                                          : _kTextSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => setDialogState(
                                    () => isInstallment = true),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isInstallment
                                        ? Colors.white
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: isInstallment
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calendar_month_rounded,
                                          size: 16,
                                          color: isInstallment
                                              ? _kAmberDark
                                              : _kTextSecondary),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Taksitli Borç Planı',
                                        style: TextStyle(
                                          fontWeight: isInstallment
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isInstallment
                                              ? _kAmberDark
                                              : _kTextSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tutar
                      TextFormField(
                        controller: amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: isInstallment
                              ? 'Toplam Tutar (₺)'
                              : 'Borç Tutarı (₺)',
                          prefixIcon: const Icon(
                              Icons.account_balance_wallet_rounded),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                        validator: (value) {
                          final amount = double.tryParse((value ?? '')
                              .trim()
                              .replaceAll(',', '.'));
                          return amount == null || amount <= 0
                              ? 'Sıfırdan büyük bir tutar girin'
                              : null;
                        },
                      ),
                      const SizedBox(height: 12),

                      if (isInstallment) ...[
                        // Taksit Sayısı
                        DropdownButtonFormField<int>(
                          value: installmentCount,
                          decoration: const InputDecoration(
                            labelText: 'Taksit Sayısı',
                            prefixIcon:
                                Icon(Icons.format_list_numbered_rounded),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 2, child: Text('2 Taksit')),
                            DropdownMenuItem(
                                value: 3, child: Text('3 Taksit')),
                            DropdownMenuItem(
                                value: 4, child: Text('4 Taksit')),
                            DropdownMenuItem(
                                value: 5, child: Text('5 Taksit')),
                            DropdownMenuItem(
                                value: 6, child: Text('6 Taksit')),
                            DropdownMenuItem(
                                value: 9, child: Text('9 Taksit')),
                            DropdownMenuItem(
                                value: 12, child: Text('12 Taksit')),
                            DropdownMenuItem(
                                value: 18, child: Text('18 Taksit')),
                            DropdownMenuItem(
                                value: 24, child: Text('24 Taksit')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setDialogState(() => installmentCount = v);
                            }
                          },
                        ),
                        const SizedBox(height: 12),

                        // Peşinat
                        TextFormField(
                          controller: downPaymentController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Alınan Peşinat (₺, Opsiyonel)',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          onChanged: (_) => setDialogState(() {}),
                          validator: (value) {
                            final down = double.tryParse((value ?? '')
                                    .trim()
                                    .replaceAll(',', '.')) ??
                                0.0;
                            final tot = double.tryParse(amountController
                                    .text
                                    .trim()
                                    .replaceAll(',', '.')) ??
                                0.0;
                            if (down < 0) return 'Peşinat negatif olamaz';
                            if (tot > 0 && down >= tot) {
                              return 'Peşinat toplam tutardan az olmalıdır';
                            }
                            return null;
                          },
                        ),
                        if (downAmt > 0) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: downPaymentMethod,
                            decoration: const InputDecoration(
                              labelText: 'Peşinat Ödeme Yöntemi',
                              prefixIcon: Icon(Icons.payment_rounded),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'cash', child: Text('Nakit (Kasa)')),
                              DropdownMenuItem(
                                  value: 'credit_card',
                                  child: Text('Kredi Kartı / POS')),
                              DropdownMenuItem(
                                  value: 'bank_transfer',
                                  child: Text('Havale / EFT')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => downPaymentMethod = v);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 12),

                        // İlk Vade Tarihi
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: firstDueDate,
                              firstDate: DateTime.now()
                                  .subtract(const Duration(days: 30)),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365 * 3)),
                            );
                            if (picked != null) {
                              setDialogState(() => firstDueDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'İlk Taksit Vade Tarihi',
                              prefixIcon: Icon(Icons.event_rounded),
                              suffixIcon:
                                  Icon(Icons.calendar_today_rounded, size: 18),
                            ),
                            child: Text(
                              DateFormat('dd MMMM yyyy', 'tr_TR')
                                  .format(firstDueDate),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Canlı Hesaplama Özeti Kartı
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kAmberLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _kAmber.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.calculate_rounded,
                                      size: 16, color: _kAmberDark),
                                  SizedBox(width: 6),
                                  Text(
                                    'Ödeme Özeti',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _kAmberDark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                downAmt > 0
                                    ? 'Peşinat: ₺${downAmt.toStringAsFixed(2)} • Kalan: ₺${financedAmt.toStringAsFixed(2)}'
                                    : 'Kalan Tutar: ₺${financedAmt.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 12, color: _kText),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (basePerInst - lastInstAmt).abs() < 0.01
                                    ? 'Aylık Taksit: $installmentCount x ₺${basePerInst.toStringAsFixed(2)}'
                                    : 'Aylık Taksit: ${installmentCount - 1} x ₺${basePerInst.toStringAsFixed(2)} • Son: ₺${lastInstAmt.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _kGreenDark),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'İlk Ödeme: ${DateFormat('dd.MM.yyyy').format(firstDueDate)} (Her ayın ${firstDueDate.day}. günü)',
                                style: const TextStyle(
                                    fontSize: 11, color: _kTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Açıklama
                      TextField(
                        controller: noteController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Açıklama',
                          hintText: isInstallment
                              ? 'Örn. Çeyiz Paketi / Mobilya'
                              : 'Örn. Önceki dönem devri',
                        ),
                      ),
                      if (isInstallment) ...[
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Ödeme Planını Fişe Yazdır',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              '58/80mm termal sözleşme & döküm çıktısı (müşteri & yetkili imza alanı)',
                              style: TextStyle(
                                  fontSize: 11, color: _kTextSecondary)),
                          value: printReceipt,
                          activeColor: _kGreen,
                          onChanged: (val) =>
                              setDialogState(() => printReceipt = val),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setDialogState(() => saving = true);
                        try {
                          final amt = double.parse(amountController.text
                              .trim()
                              .replaceAll(',', '.'));
                          final note = noteController.text.trim();

                          if (isInstallment) {
                            final down = double.tryParse(downPaymentController
                                    .text
                                    .trim()
                                    .replaceAll(',', '.')) ??
                                0.0;
                            final plan = await ref
                                .read(installmentsControllerProvider.notifier)
                                .createPlan(
                                  customerId: customer.id,
                                  totalAmount: amt,
                                  downPayment: down,
                                  downPaymentMethod: downPaymentMethod,
                                  installmentCount: installmentCount,
                                  firstDueDate: firstDueDate,
                                  description: note,
                                );

                            if (printReceipt) {
                              try {
                                final planInsts = await ref
                                    .read(installmentRepositoryProvider)
                                    .getInstallmentsForPlan(plan.id);
                                final settings =
                                    await ref.read(settingsProvider.future);
                                await ref
                                    .read(printingApplicationServiceProvider)
                                    .queueInstallmentPlanReceipt(
                                      customer: customer,
                                      plan: plan,
                                      installments: planInsts,
                                      settings: settings,
                                    );
                              } catch (printErr) {
                                debugPrint(
                                    'Taksit planı fiş yazdırma hatası: $printErr');
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (context.mounted) {
                              AppNotificationHost.show(
                                const SnackBar(
                                  content: Text(
                                      'Taksitli borç planı başarıyla oluşturuldu.'),
                                  backgroundColor: _kGreen,
                                ),
                              );
                            }
                          } else {
                            await ref
                                .read(customersControllerProvider.notifier)
                                .recordManualDebt(
                                  customerId: customer.id,
                                  amount: amt,
                                  notes: note,
                                );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (context.mounted) {
                              AppNotificationHost.show(
                                const SnackBar(
                                  content: Text('Borç hareketi eklendi.'),
                                  backgroundColor: _kGreen,
                                ),
                              );
                            }
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() => saving = false);
                            AppNotificationHost.show(
                              SnackBar(content: Text('Hata oluştu: $error')),
                            );
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isInstallment ? 'Planı Başlat' : 'Borcu Ekle'),
              ),
            ],
          );
        },
      ),
    );
    amountController.dispose();
    noteController.dispose();
    downPaymentController.dispose();
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));
    final transactionsVal = ref.watch(customerTransactionsProvider(customerId));
    final balanceVal = ref.watch(customerBalanceDetailsProvider(customerId));
    final plansVal = ref.watch(customerInstallmentPlansProvider(customerId));
    final installmentsVal = ref.watch(customerInstallmentsProvider(customerId));

    return customerAsync.when(
      skipLoadingOnReload: true,
      loading: () => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: _kGreenDark),
          title: const Text('Müşteri Detayı',
              style: TextStyle(color: _kText, fontWeight: FontWeight.bold)),
        ),
        body: const Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_kGreen))),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: _kGreenDark),
          title: const Text('Müşteri Detayı',
              style: TextStyle(color: _kText, fontWeight: FontWeight.bold)),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hata: $err', style: const TextStyle(color: _kRed)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () =>
                    ref.invalidate(customerDetailProvider(customerId)),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              iconTheme: const IconThemeData(color: _kGreenDark),
              title: const Text('Müşteri Detayı',
                  style: TextStyle(color: _kText, fontWeight: FontWeight.bold)),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_off_rounded,
                      size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('Müşteri bulunamadı.',
                      style: TextStyle(fontSize: 16, color: _kTextSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/customers'),
                    child: const Text('Geri Dön'),
                  ),
                ],
              ),
            ),
          );
        }

        final isClear = customer.balance.abs() < 0.01;
        final isDebt = customer.balance < -0.009;

        return Scaffold(
          backgroundColor: _kSurface,
          body: CustomScrollView(
            slivers: [
              // ── Hero AppBar + Gradient Card ─────────────────────────────────────
              SliverAppBar(
                expandedHeight: customer.address != null &&
                        customer.address!.trim().isNotEmpty
                    ? 225
                    : 200,
                pinned: true,
                backgroundColor: isDebt
                    ? _kRed
                    : (isClear ? const Color(0xFF334155) : _kGreen),
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                    tooltip: 'Düzenle',
                    onPressed: () => context.push(
                        '/customers/edit/${customer.id}',
                        extra: customer),
                  ),
                  if (customer.id.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white),
                      tooltip: 'Sil',
                      onPressed: () => _confirmDelete(context, ref, customer),
                    ),
                  // ── WhatsApp Bakiye Bildirimi ──
                  if (customer.phone.trim().isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_rounded,
                          color: Colors.white),
                      tooltip: 'WhatsApp ile Bakiye Gönder',
                      onPressed: () => _sendWhatsAppBalance(context, customer),
                    ),
                  // ── Phase 4: PDF / Excel / SMS Export Button ──
                  IconButton(
                    icon: const Icon(Icons.upload_rounded, color: Colors.white),
                    tooltip: 'Dışa Aktar',
                    onPressed: () {
                      final txs = transactionsVal.maybeWhen(
                        data: (list) => list,
                        orElse: () => <FinancialTransactionEntity>[],
                      );
                      ExportBottomSheet.show(
                        context,
                        customer: customer,
                        transactions: txs,
                      );
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDebt
                            ? [const Color(0xFFDC2626), const Color(0xFFB91C1C)]
                            : isClear
                                ? [
                                    const Color(0xFF334155),
                                    const Color(0xFF1E293B)
                                  ]
                                : [
                                    const Color(0xFF16A34A),
                                    const Color(0xFF15803D)
                                  ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 32),
                          // Avatar
                          CircleAvatar(
                            radius: 34,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 28),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            customer.name.toTurkishUpperCase,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            customer.phone.isNotEmpty
                                ? formatPhoneForDisplay(customer.phone)
                                : 'Kayıt: ${DateFormat('dd.MM.yyyy').format(customer.createdAt)}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13),
                          ),
                          if (customer.address != null &&
                              customer.address!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      size: 14,
                                      color:
                                          Colors.white.withValues(alpha: 0.85)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      customer.address!,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                          fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bakiye Özet Satırı ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: balanceVal.when(
                    skipLoadingOnReload: true,
                    loading: () => const SizedBox(
                        height: 80,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2))),
                    error: (e, _) => Text('Bakiye yüklenemedi: $e',
                        style: const TextStyle(color: _kRed)),
                    data: (details) => _buildBalanceRow(customer, details),
                  ),
                ),
              ),

              // ── Tahsilat Butonu ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                context.push('/customers/$customerId/collect'),
                            icon:
                                const Icon(Icons.price_check_rounded, size: 20),
                            label: const Text('Tahsilat Yap'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _showManualDebtDialog(context, ref, customer),
                            icon: const Icon(Icons.add_card_rounded, size: 20),
                            label: const Text('Borç Ekle'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Taksit Planları Bölümü (Varsa) ──
              _buildInstallmentPlansSliver(
                  context, ref, customer, plansVal, installmentsVal),

              // ── Banka Ekstresi: İşlem Geçmişi ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: _kGreenLight,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.receipt_long_rounded,
                            size: 14, color: _kGreenDark),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Hareket Geçmişi',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: _kText),
                      ),
                    ],
                  ),
                ),
              ),

              transactionsVal.when(
                skipLoadingOnReload: true,
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                      child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(_kGreen)),
                  )),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Hareketler yüklenemedi: $e',
                        style: const TextStyle(color: _kRed)),
                  ),
                ),
                data: (txns) {
                  if (txns.isEmpty) {
                    return SliverToBoxAdapter(child: _buildEmptyState());
                  }
                  // Group by month
                  final grouped = _groupByMonth(txns);
                  final months = grouped.keys.toList();

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) {
                        final month = months[idx];
                        final items = grouped[month]!;
                        return _buildMonthGroup(month, items);
                      },
                      childCount: months.length,
                    ),
                  );
                },
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        );
      },
    );
  }

  // ── Bakiye Özet Satırı ────────────────────────────────────────────────────

  Widget _buildBalanceRow(
      CustomerEntity customer, Map<String, double> details) {
    final isClear = customer.balance.abs() < 0.01;
    final isDebt = customer.balance < -0.009;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Net Bakiye',
            value: '₺${customer.balance.abs().toStringAsFixed(2)}',
            sub: isClear ? 'Bakiye Yok' : (isDebt ? 'Borçlu' : 'Alacaklı'),
            bg: isClear
                ? const Color(0xFFF1F5F9)
                : (isDebt ? _kRedLight : _kGreenLight),
            fg: isClear ? _kTextSecondary : (isDebt ? _kRed : _kGreenDark),
            icon: isClear
                ? Icons.check_circle_outline_rounded
                : (isDebt
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Toplam İşlem',
            value: '₺${(details['totalDebt'] ?? 0).toStringAsFixed(2)}',
            sub: 'Alışveriş & Borç',
            bg: _kAmberLight,
            fg: _kAmber,
            icon: Icons.shopping_bag_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Toplam Ödeme',
            value: '₺${(details['totalPaid'] ?? 0).toStringAsFixed(2)}',
            sub: 'Tahsilat & Peşin',
            bg: _kGreenLight,
            fg: _kGreenDark,
            icon: Icons.check_circle_rounded,
          ),
        ),
      ],
    );
  }

  // ── Taksit Planları Bölümü ──────────────────────────────────────────────────

  Widget _buildInstallmentPlansSliver(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
    AsyncValue<List<CustomerInstallmentPlanEntity>> plansVal,
    AsyncValue<List<CustomerInstallmentEntity>> installmentsVal,
  ) {
    return plansVal.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (plans) {
        if (plans.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final allInstallments = installmentsVal.valueOrNull ?? [];

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_month_rounded,
                        size: 16, color: _kAmberDark),
                    SizedBox(width: 8),
                    Text(
                      'Taksit Planları & Vadeler',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: _kText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...plans.map((plan) {
                  final planInsts = allInstallments
                      .where((i) => i.planId == plan.id)
                      .toList();
                  final paidInsts =
                      planInsts.where((i) => i.isPaid).length;
                  final totalInsts = plan.installmentCount;
                  final paidSum = planInsts.fold<double>(
                      0.0, (acc, i) => acc + i.paidAmount);
                  final remainingSum = planInsts.fold<double>(
                      0.0, (acc, i) => acc + i.remainingAmount);
                  final progress = plan.financedAmount > 0
                      ? (paidSum / plan.financedAmount).clamp(0.0, 1.0)
                      : 1.0;
                  final isCompleted = plan.status == 'completed' ||
                      (totalInsts > 0 && paidInsts == totalInsts);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCompleted
                            ? _kBorder
                            : _kAmberDark.withValues(alpha: 0.35),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plan Başlığı
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.grey[50]
                                : _kAmberLight.withValues(alpha: 0.35),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(13)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCompleted
                                    ? Icons.task_alt_rounded
                                    : Icons.receipt_long_rounded,
                                size: 18,
                                color: isCompleted ? _kGreenDark : _kAmberDark,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  plan.description.isNotEmpty
                                      ? plan.description
                                      : 'Taksitli Borç Planı',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _kText,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCompleted
                                      ? _kGreenLight
                                      : (plan.status == 'cancelled'
                                          ? Colors.grey[200]
                                          : _kAmberLight),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isCompleted
                                      ? 'Tamamlandı'
                                      : (plan.status == 'cancelled'
                                          ? 'İptal Edildi'
                                          : '$paidInsts/$totalInsts Taksit'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isCompleted
                                        ? _kGreenDark
                                        : (plan.status == 'cancelled'
                                            ? Colors.grey[700]
                                            : _kAmberDark),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.print_outlined,
                                    size: 18, color: _kTextSecondary),
                                tooltip: 'Ödeme Planını Fişe Yazdır',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 28),
                                onPressed: () => _printInstallmentPlan(
                                  context,
                                  ref,
                                  customer,
                                  plan,
                                  planInsts,
                                ),
                              ),
                              if (plan.status == 'active')
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded,
                                      size: 18, color: _kTextSecondary),
                                  padding: EdgeInsets.zero,
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'cancel',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cancel_outlined,
                                              size: 16, color: _kRed),
                                          SizedBox(width: 8),
                                          Text('Planı İptal Et',
                                              style: TextStyle(color: _kRed)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (val) {
                                    if (val == 'cancel') {
                                      _confirmCancelPlan(
                                          context, ref, plan, customer);
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),

                        // İlerleme ve Özet
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Toplam: ₺${plan.totalAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: _kTextSecondary,
                                    ),
                                  ),
                                  if (plan.downPayment > 0)
                                    Text(
                                      'Peşinat: ₺${plan.downPayment.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _kGreenDark,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  Text(
                                    'Kalan: ₺${remainingSum.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: remainingSum > 0
                                          ? _kRed
                                          : _kGreenDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation(
                                      isCompleted ? _kGreen : _kAmberDark),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(height: 1, indent: 14, endIndent: 14),

                        // Taksit Satırları
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          itemCount: planInsts.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, idx) {
                            final inst = planInsts[idx];
                            return _buildInstallmentItemRow(
                                context, ref, customer, inst);
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstallmentItemRow(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
    CustomerInstallmentEntity inst,
  ) {
    final isPaid = inst.isPaid;
    final isPartiallyPaid = !isPaid && inst.paidAmount > 0.009;
    final isOverdue = inst.isOverdue;
    final isDueToday = inst.isDueToday;

    Color badgeBg;
    Color badgeFg;
    String badgeText;
    IconData? badgeIcon;

    if (isPaid) {
      badgeBg = _kGreenLight;
      badgeFg = _kGreenDark;
      badgeText = 'Ödendi';
      badgeIcon = Icons.check_circle_outline_rounded;
    } else if (isPartiallyPaid) {
      badgeBg = _kAmberLight;
      badgeFg = _kAmberDark;
      badgeText = 'Kısmi Ödendi';
      badgeIcon = Icons.timelapse_rounded;
    } else if (isOverdue) {
      badgeBg = _kRedLight;
      badgeFg = _kRed;
      badgeText = 'Gecikti';
      badgeIcon = Icons.warning_amber_rounded;
    } else if (isDueToday) {
      badgeBg = _kAmberLight;
      badgeFg = _kAmberDark;
      badgeText = 'Vadesi Bugün';
      badgeIcon = Icons.today_rounded;
    } else {
      badgeBg = const Color(0xFFF1F5F9);
      badgeFg = _kTextSecondary;
      badgeText = 'Bekliyor';
      badgeIcon = Icons.hourglass_top_rounded;
    }

    final dateStr = inst.parsedDueDate != null
        ? DateFormat('dd.MM.yyyy').format(inst.parsedDueDate!)
        : inst.dueDate;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Taksit No Çemberi
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isPaid
                  ? _kGreenLight
                  : (isPartiallyPaid
                      ? _kAmberLight
                      : (isOverdue ? _kRedLight : const Color(0xFFF1F5F9))),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${inst.installmentNo}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isPaid
                    ? _kGreenDark
                    : (isPartiallyPaid
                        ? _kAmberDark
                        : (isOverdue ? _kRed : _kText)),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Vade ve Bilgi
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$dateStr Vadeli',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isOverdue ? FontWeight.bold : FontWeight.w600,
                        color: isOverdue ? _kRed : _kText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 10, color: badgeFg),
                          const SizedBox(width: 3),
                          Text(
                            badgeText,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeFg),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isPaid && inst.paidAmount > 0)
                  Text(
                    'Ödenen: ₺${inst.paidAmount.toStringAsFixed(2)} • Kalan: ₺${inst.remainingAmount.toStringAsFixed(2)}',
                    style:
                        const TextStyle(fontSize: 11, color: _kTextSecondary),
                  ),
              ],
            ),
          ),

          // Tutar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isPartiallyPaid) ...[
                Text(
                  '₺${inst.remainingAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isOverdue ? _kRed : _kAmberDark,
                  ),
                ),
                Text(
                  'Top: ₺${inst.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _kTextSecondary,
                  ),
                ),
              ] else ...[
                Text(
                  '₺${inst.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isPaid
                        ? _kTextSecondary
                        : (isOverdue ? _kRed : _kText),
                    decoration: isPaid ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 8),

          // İşlem Butonları (Ödenmediyse)
          if (!isPaid) ...[
            // WhatsApp Hatırlat Butonu
            if (customer.phone.trim().isNotEmpty)
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 18, color: Color(0xFF25D366)),
                tooltip: 'WhatsApp ile Hatırlat',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () =>
                    _sendWhatsAppInstallmentReminder(context, customer, inst),
              ),

            // Tahsil Et Butonu
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGreenDark,
                side: const BorderSide(color: _kGreen),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () =>
                  _showPayInstallmentDialog(context, ref, customer, inst),
              child: const Text('Tahsil Et',
                  style:
                      TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPayInstallmentDialog(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
    CustomerInstallmentEntity inst,
  ) async {
    final amountController = TextEditingController(
      text: inst.remainingAmount.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    var method = 'cash';
    var printReceipt = true;
    var saving = false;
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${inst.installmentNo}. Taksit Tahsilatı'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Müşteri: ${customer.name}\nVade: ${DateFormat('dd.MM.yyyy').format(inst.parsedDueDate ?? DateTime.now())}\nKalan Taksit: ₺${inst.remainingAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13, color: _kTextSecondary),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tahsil Edilen Tutar (₺)',
                      prefixIcon: Icon(Icons.price_check_rounded),
                    ),
                    validator: (v) {
                      final val = double.tryParse(
                          (v ?? '').trim().replaceAll(',', '.'));
                      if (val == null || val <= 0) {
                        return 'Geçerli bir tutar girin';
                      }
                      if (val > (inst.remainingAmount + 0.01)) {
                        return 'Kalan tutardan fazla girilemez';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: const InputDecoration(
                      labelText: 'Ödeme Yöntemi',
                      prefixIcon: Icon(Icons.payment_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'cash', child: Text('Nakit (Kasa)')),
                      DropdownMenuItem(
                          value: 'credit_card',
                          child: Text('Kredi Kartı / POS')),
                      DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('Havale / EFT')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => method = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Not (Opsiyonel)',
                      hintText: 'Örn. Elden nakit teslim alındı',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tahsilat Makbuzu Yazdır',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('58/80mm termal tahsilat fişi çıktısı',
                        style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                    value: printReceipt,
                    activeColor: _kGreen,
                    onChanged: (val) =>
                        setDialogState(() => printReceipt = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final amt = double.parse(amountController.text
                            .trim()
                            .replaceAll(',', '.'));
                        await ref
                            .read(installmentsControllerProvider.notifier)
                            .payInstallment(
                              customerId: customer.id,
                              installmentId: inst.id,
                              amount: amt,
                              paymentMethod: method,
                              note: noteController.text.trim(),
                            );

                        if (printReceipt) {
                          try {
                            final settings =
                                await ref.read(settingsProvider.future);
                            final updatedPlanInsts = await ref
                                .read(installmentRepositoryProvider)
                                .getInstallmentsForPlan(inst.planId);
                            final updatedCurrentInst = updatedPlanInsts
                                .firstWhere((i) => i.id == inst.id,
                                    orElse: () => inst);
                            final remainingInsts = updatedPlanInsts
                                .where((i) => !i.isPaid && SafeMoney.isPositive(i.remainingAmount))
                                .toList();
                            await ref
                                .read(printingApplicationServiceProvider)
                                .queueInstallmentPaymentReceipt(
                                  customer: customer,
                                  installment: updatedCurrentInst,
                                  paidAmount: amt,
                                  paymentMethod: method,
                                  settings: settings,
                                  remainingCount: remainingInsts.length,
                                  remainingDebt: remainingInsts.fold<double>(
                                      0.0, (acc, i) => SafeMoney.add(acc, i.remainingAmount)),
                                  nextDueDate: remainingInsts.isNotEmpty
                                      ? remainingInsts.first.dueDate
                                      : null,
                                );
                          } catch (printErr) {
                            debugPrint(
                                'Taksit tahsilatı fiş yazdırma hatası: $printErr');
                          }
                        }

                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (context.mounted) {
                          AppNotificationHost.show(
                            const SnackBar(
                              content: Text(
                                  'Taksit tahsilatı başarıyla kaydedildi.'),
                              backgroundColor: _kGreen,
                            ),
                          );
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDialogState(() => saving = false);
                          AppNotificationHost.show(
                            SnackBar(content: Text('Tahsilat hatası: $err')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Tahsil Et'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
  }

  Future<void> _printInstallmentPlan(
    BuildContext context,
    WidgetRef ref,
    CustomerEntity customer,
    CustomerInstallmentPlanEntity plan,
    List<CustomerInstallmentEntity> planInsts,
  ) async {
    try {
      final settings = await ref.read(settingsProvider.future);
      await ref.read(printingApplicationServiceProvider).queueInstallmentPlanReceipt(
            customer: customer,
            plan: plan,
            installments: planInsts,
            settings: settings,
          );
      if (context.mounted) {
        AppNotificationHost.show(
          const SnackBar(
            content: Text('Taksit ödeme planı fişi yazıcıya gönderildi.'),
            backgroundColor: _kGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppNotificationHost.show(
          SnackBar(content: Text('Yazdırma hatası: $e')),
        );
      }
    }
  }

  Future<void> _sendWhatsAppInstallmentReminder(
    BuildContext context,
    CustomerEntity customer,
    CustomerInstallmentEntity inst,
  ) async {
    final phone = customer.phone.trim();
    if (phone.isEmpty) {
      AppNotificationHost.show(
        const SnackBar(
          content: Text('Müşterinin kayıtlı telefon numarası bulunmuyor.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dueDateFormatted = inst.parsedDueDate != null
        ? DateFormat('dd.MM.yyyy').format(inst.parsedDueDate!)
        : inst.dueDate;
    final amountFormatted = '₺${inst.remainingAmount.toStringAsFixed(2)}';

    final message = '''📅 *Taksit Ödeme Hatırlatması*

Sayın *${customer.name}*,
Mağazamızdaki taksitli alışverişinize ait vade hatırlatmasıdır:

▫️ *Taksit No:* ${inst.installmentNo}. Taksit
▫️ *Vade Tarihi:* $dueDateFormatted
▫️ *Ödenecek Tutar:* *$amountFormatted*

Ödemenizi mağazamızdan veya banka hesaplarımıza gerçekleştirebilirsiniz.
Hayırlı günler dileriz.

ℹ️ _Bildirimlerin tarafınıza sorunsuz ulaşabilmesi için lütfen numaramızı rehberinize kaydediniz._''';

    final normalized = normalizeForWhatsApp(phone);
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$normalized?text=$encoded');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          AppNotificationHost.show(
            const SnackBar(
              content: Text('WhatsApp başlatılamadı.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppNotificationHost.show(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: _kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmCancelPlan(
    BuildContext context,
    WidgetRef ref,
    CustomerInstallmentPlanEntity plan,
    CustomerEntity customer,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Taksit Planını İptal Et'),
        content: Text(
          '"${plan.description.isNotEmpty ? plan.description : 'Taksit Planı'}" iptal edilecek.\n\nNot: Bu işlem plandaki bekleyen taksitleri iptal eder. Onaylıyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Planı İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref
            .read(installmentsControllerProvider.notifier)
            .cancelPlan(planId: plan.id, customerId: customer.id);
        if (context.mounted) {
          AppNotificationHost.show(
            const SnackBar(
              content: Text('Taksit planı iptal edildi.'),
              backgroundColor: _kGreen,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          AppNotificationHost.show(
            SnackBar(
                content: Text('İptal hatası: $e'), backgroundColor: _kRed),
          );
        }
      }
    }
  }


  // ── Aylara Göre Gruplama ──────────────────────────────────────────────────

  Map<String, List<FinancialTransactionEntity>> _groupByMonth(
      List<FinancialTransactionEntity> txns) {
    final sorted = List.of(txns)..sort((a, b) => b.date.compareTo(a.date));
    final map = <String, List<FinancialTransactionEntity>>{};
    for (final txn in sorted) {
      final key = DateFormat('MMMM yyyy', 'tr_TR').format(txn.date);
      map.putIfAbsent(key, () => []).add(txn);
    }
    return map;
  }

  Widget _buildMonthGroup(
      String month, List<FinancialTransactionEntity> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              month.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _kTextSecondary,
                  letterSpacing: 0.8),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _TransactionRow(txn: items[i]),
                  if (i < items.length - 1)
                    const Divider(height: 1, indent: 56, endIndent: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 52, color: _kBorder),
          SizedBox(height: 12),
          Text(
            'Henüz hareket yok',
            style: TextStyle(
                color: _kTextSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
          SizedBox(height: 4),
          Text(
            'İlk satış veya tahsilat yapıldığında burada görünür.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, CustomerEntity customer) {
    if (customer.balance.abs() > 0.01) {
      AppNotificationHost.show(
        SnackBar(
          content: Text(
            customer.balance < 0
                ? 'Bu müşterinin borcu bulunmaktadır (${customer.balance.abs().toStringAsFixed(2)} ₺). Bakiyesi sıfırlanmadan müşteri silinemez.'
                : 'Bu müşterinin alacağı bulunmaktadır (${customer.balance.toStringAsFixed(2)} ₺). Bakiyesi sıfırlanmadan müşteri silinemez.',
          ),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    requireAdminAccess(context, title: 'Müşteri Silme Yetkisi',
        onGranted: (approvedByUserId, approvedByUserName) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Müşteriyi Sil'),
            content: Text(
                '"${customer.name}" müşterisini sistemden silmek istediğinize emin misiniz?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await ref
                      .read(customersControllerProvider.notifier)
                      .deleteCustomer(
                        customer.id,
                        approvedByUserId: approvedByUserId,
                        approvedByUserName: approvedByUserName,
                      );
                  final state = ref.read(customersControllerProvider);
                  if (state.hasError) {
                    if (context.mounted) {
                      final errorMsg = state.error != null
                          ? state.error
                              .toString()
                              .replaceFirst('Bad state: ', '')
                          : 'Müşteri silinemedi: Bu müşteriye ait satış veya işlem kayıtları bulunmaktadır.';
                      AppNotificationHost.show(
                        SnackBar(
                          content: Text(errorMsg),
                          backgroundColor: _kRed,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } else {
                    ref.invalidate(dashboardProvider);
                    if (context.mounted) {
                      context.pop();
                    }
                  }
                },
                child: const Text('Sil'),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _sendWhatsAppBalance(
      BuildContext context, CustomerEntity customer) async {
    final phone = customer.phone.trim();
    if (phone.isEmpty) {
      AppNotificationHost.show(
        const SnackBar(
          content: Text('Müşterinin kayıtlı telefon numarası bulunmuyor.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isDebt = customer.balance < 0;
    final isClear = customer.balance == 0;
    final absBalance = customer.balance.abs();
    final statusText =
        isDebt ? 'Borçlu' : (isClear ? 'Bakiyesi Yok' : 'Alacaklı');

    final message = '''📋 *Cari Hesap Bilgilendirmesi*

Sayın *${customer.name}*,
Güncel hesap durumunuz:

▫️ *Durum:* $statusText
▫️ *Güncel Tutar:* *₺${absBalance.toStringAsFixed(2)}*

Detaylı bilgi ve mutabakat için bizimle iletişime geçebilirsiniz.

ℹ️ _Bildirimlerin tarafınıza sorunsuz ulaşabilmesi için lütfen numaramızı rehberinize kaydediniz._''';

    final normalized = normalizeForWhatsApp(phone);
    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$normalized?text=$encoded');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          AppNotificationHost.show(
            const SnackBar(
              content: Text('WhatsApp başlatılamadı.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppNotificationHost.show(
          SnackBar(
            content: Text('Hata: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Yardımcı Veri Sınıfları ────────────────────────────────────────────────────

class _TxnStyle {
  final IconData icon;
  final String label;
  final Color bgColor;
  final Color fgColor;
  const _TxnStyle({
    required this.icon,
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color bg;
  final Color fg;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.bg,
    required this.fg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(height: 6),
          Text(
            value,
            style:
                TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: fg),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: fg, fontWeight: FontWeight.w600)),
          Text(sub,
              style: TextStyle(fontSize: 9, color: fg.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _TransactionRow extends ConsumerWidget {
  final FinancialTransactionEntity txn;
  const _TransactionRow({required this.txn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _TxnStyle style = _txnStyle(txn);
    final isCashSale = txn.type == 'sale' && txn.debtAmount <= 0.009;
    final isCancellation = txn.type == 'cancellation';
    final isRefundToBalance = txn.type == 'refund' && txn.paidAmount <= 0.009;
    final isCashRefund = txn.type == 'refund' && txn.paidAmount > 0.009;
    final isCredit = txn.type == 'collection' ||
        txn.type == 'payment' ||
        isCancellation ||
        isRefundToBalance;
    final itemsVal = ref.watch(transactionItemsProvider(txn));

    final String sign;
    final Color amountColor;
    final String displayAmount;

    if (isCancellation) {
      sign = '+';
      amountColor = _kGreenDark;
      displayAmount =
          (txn.debtAmount > 0 ? txn.debtAmount : txn.amount).toStringAsFixed(2);
    } else if (isRefundToBalance) {
      sign = '+';
      amountColor = _kGreenDark;
      displayAmount = txn.amount.toStringAsFixed(2);
    } else if (isCashRefund) {
      sign = '';
      amountColor = _kAmber;
      displayAmount = txn.amount.toStringAsFixed(2);
    } else if (isCashSale) {
      sign = '';
      amountColor = _kText;
      displayAmount = txn.amount.toStringAsFixed(2);
    } else if (isCredit) {
      sign = '+';
      amountColor = _kGreenDark;
      displayAmount = txn.amount.toStringAsFixed(2);
    } else {
      sign = '-';
      amountColor = _kRed;
      displayAmount = txn.amount.toStringAsFixed(2);
    }

    String? subText;
    Color subTextColor = _kTextSecondary;
    if (isCashSale) {
      subText = 'Peşin Ödendi';
      subTextColor = _kGreenDark;
    } else if (isCancellation) {
      subText = 'Borç İptal Edildi';
      subTextColor = _kGreenDark;
    } else if (isRefundToBalance) {
      subText = 'Bakiyeye İade';
      subTextColor = _kGreenDark;
    } else if (isCashRefund) {
      subText = 'Nakit İade';
      subTextColor = _kAmber;
    } else if (txn.debtAmount > 0) {
      subText = 'Kalan Borç: ₺${txn.debtAmount.toStringAsFixed(2)}';
      subTextColor = _kRed.withValues(alpha: 0.8);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: style.bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(style.icon, size: 17, color: style.fgColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _kText),
                    ),
                    Text(
                      DateFormat('dd.MM.yyyy HH:mm').format(txn.date),
                      style:
                          const TextStyle(fontSize: 11, color: _kTextSecondary),
                    ),
                    if (txn.metadata?['notes']?.toString().trim().isNotEmpty ==
                            true ||
                        txn.metadata?['note']?.toString().trim().isNotEmpty ==
                            true) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Not: ${(txn.metadata?['notes'] ?? txn.metadata?['note'])?.toString().trim()}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign₺$displayAmount',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: amountColor),
                  ),
                  if (subText != null)
                    Text(
                      subText,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: subTextColor),
                    ),
                ],
              ),
            ],
          ),
          itemsVal.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 8, left: 48),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 12,
                            color: _kTextSecondary.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        const Text(
                          'Detaylar:',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...items.map((item) {
                      final name =
                          (item['name'] ?? item['product_name'] ?? 'Ürün')
                              .toString();
                      final qty = item['quantity'];
                      final price =
                          (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final qtyStr = _formatQuantity(qty);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '• $name',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kText,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '$qtyStr adet x ₺${price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _kTextSecondary,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 8, left: 48),
              child: SizedBox(
                height: 12,
                width: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(_kGreen),
                ),
              ),
            ),
            error: (e, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _formatQuantity(dynamic qty) {
    if (qty == null) return '0';
    if (qty is num) {
      if (qty % 1 == 0) {
        return qty.toInt().toString();
      }
      return qty.toStringAsFixed(2);
    }
    return qty.toString();
  }

  _TxnStyle _txnStyle(FinancialTransactionEntity txn) {
    switch (txn.type) {
      case 'sale':
        final isPesin = txn.debtAmount <= 0.009;
        return _TxnStyle(
            icon: Icons.shopping_cart_rounded,
            label: isPesin ? 'Peşin Satış' : 'Vadeli Satış',
            bgColor: isPesin ? const Color(0xFFF1F5F9) : _kRedLight,
            fgColor: isPesin ? _kText : _kRed);
      case 'manual_debt':
        return const _TxnStyle(
            icon: Icons.add_card_rounded,
            label: 'Elle Eklenen Borç',
            bgColor: _kRedLight,
            fgColor: _kRed);
      case 'collection':
      case 'payment':
        return const _TxnStyle(
            icon: Icons.price_check_rounded,
            label: 'Tahsilat',
            bgColor: _kGreenLight,
            fgColor: _kGreenDark);
      case 'refund':
        return const _TxnStyle(
            icon: Icons.undo_rounded,
            label: 'İade',
            bgColor: _kAmberLight,
            fgColor: _kAmber);
      case 'cancellation':
        return const _TxnStyle(
            icon: Icons.cancel_rounded,
            label: 'Satış İptali',
            bgColor: Color(0xFFF1F5F9),
            fgColor: _kTextSecondary);
      default:
        return _TxnStyle(
            icon: Icons.receipt_rounded,
            label: txn.type,
            bgColor: Colors.grey[100]!,
            fgColor: _kTextSecondary);
    }
  }
}
