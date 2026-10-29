// lib/presentation/widgets/hazelnut/customer_escrow_tab_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/domain/services/hazelnut_calculator.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kAmberLight = POSColors.amberLight;
const _kAmberDark = POSColors.amberDark;
const _kRed = POSColors.red;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class CustomerEscrowTabView extends ConsumerWidget {
  final CustomerEntity customer;
  const CustomerEscrowTabView({super.key, required this.customer});

  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');
  static final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  // ── 1. Emanet Fındık Girişi Dialog ──────────────────────────────────────────
  Future<void> _showAddEscrowDialog(BuildContext context, WidgetRef ref) async {
    final grossController = TextEditingController();
    final sackCountController = TextEditingController(text: '0');
    final tarePerSackController = TextEditingController(text: '1.0');
    final rendimentController = TextEditingController(text: '50.0');
    final receiptController = TextEditingController();
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final repo = ref.read(hazelnutRepositoryProvider);
    var warehouses = await repo.getWarehouses();
    if (warehouses.isEmpty) {
      final defaultWh = WarehouseEntity(
        id: 'wh-main',
        name: 'Ana Depo (Silo 1)',
        location: 'Merkez',
        capacityKg: 50000.0,
        currentStockKg: 0.0,
        averageRendiment: 50.0,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repo.saveWarehouse(defaultWh);
      ref.invalidate(warehousesProvider);
      warehouses = [defaultWh];
    }

    String selectedWarehouseId = warehouses.first.id;
    var saving = false;

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final gross = double.tryParse(grossController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final sacks = int.tryParse(sackCountController.text.trim()) ?? 0;
          final tarePerSack = double.tryParse(tarePerSackController.text.trim().replaceAll(',', '.')) ?? 1.0;
          final calculatedNet = HazelnutCalculator.calculateNetKg(
            grossKg: gross,
            sackCount: sacks,
            tarePerSack: tarePerSack,
          );

          return AlertDialog(
            title: const Text('Yeni Emanet Fındık Girişi'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer.name} adına emanet fındık kabulü.',
                        style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedWarehouseId,
                              decoration: const InputDecoration(
                                labelText: 'Giriş Yapılacak Depo / Silo *',
                                border: OutlineInputBorder(),
                              ),
                              items: warehouses.map((w) {
                                return DropdownMenuItem<String>(
                                  value: w.id,
                                  child: Text('${w.name} (Stok: ${_numFormat.format(w.currentStockKg)} kg)'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => selectedWarehouseId = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: 'Hızlı Yeni Depo Ekle',
                            child: InkWell(
                              onTap: () async {
                                final whNameCtrl = TextEditingController();
                                final created = await showDialog<WarehouseEntity>(
                                  context: ctx,
                                  builder: (subCtx) => AlertDialog(
                                    title: const Text('Hızlı Depo / Silo Tanımla'),
                                    content: TextField(
                                      controller: whNameCtrl,
                                      autofocus: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Depo Adı *',
                                        hintText: 'Örn: Depo 2, Silo B',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(subCtx),
                                        child: const Text('Vazgeç'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          final name = whNameCtrl.text.trim();
                                          if (name.isEmpty) return;
                                          final now = DateTime.now();
                                          final newWh = WarehouseEntity(
                                            id: const Uuid().v4(),
                                            name: name,
                                            capacityKg: 50000.0,
                                            currentStockKg: 0.0,
                                            averageRendiment: 50.0,
                                            createdAt: now,
                                            updatedAt: now,
                                          );
                                          await repo.saveWarehouse(newWh);
                                          ref.invalidate(warehousesProvider);
                                          if (subCtx.mounted) Navigator.pop(subCtx, newWh);
                                        },
                                        child: const Text('Ekle'),
                                      ),
                                    ],
                                  ),
                                );
                                if (created != null) {
                                  final freshWhs = await repo.getWarehouses();
                                  setDialogState(() {
                                    warehouses = freshWhs;
                                    selectedWarehouseId = created.id;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                height: 52,
                                width: 52,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.add_business_rounded, color: _kGreenDark),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: grossController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Brüt Kilo (Kg) *',
                                border: OutlineInputBorder(),
                                suffixText: 'kg',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Brüt kilo zorunludur.';
                                final n = double.tryParse(val.trim().replaceAll(',', '.'));
                                if (n == null || n <= 0) return 'Geçerli kilo giriniz.';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: sackCountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Çuval Adedi',
                                border: OutlineInputBorder(),
                                suffixText: 'adet',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: tarePerSackController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Çuval Başı Dara (Kg)',
                                border: OutlineInputBorder(),
                                suffixText: 'kg',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: rendimentController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Randıman (R) *',
                                border: OutlineInputBorder(),
                                hintText: 'Örn: 52.4',
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Randıman zorunludur.';
                                final r = double.tryParse(val.trim().replaceAll(',', '.'));
                                if (r == null || r < 30 || r > 65) return 'Geçerli randıman (30-65) giriniz.';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Hesaplanan Net Kilo:', style: TextStyle(fontWeight: FontWeight.w600, color: _kGreenDark)),
                            Text(
                              '${_numFormat.format(calculatedNet)} kg',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kGreenDark),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: receiptController,
                        decoration: const InputDecoration(
                          labelText: 'Kantar Fiş No (Opsiyonel)',
                          border: OutlineInputBorder(),
                          hintText: 'Boş bırakılırsa otomatik üretilir',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Parti Notu / Açıklama',
                          border: OutlineInputBorder(),
                          hintText: 'Örn: 2026 Çakıldak fındığı',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kGreen, foregroundColor: Colors.white),
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Emanet Girişini Kaydet'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final grossVal = double.parse(grossController.text.trim().replaceAll(',', '.'));
                        final sacksVal = int.tryParse(sackCountController.text.trim()) ?? 0;
                        final tareVal = double.tryParse(tarePerSackController.text.trim().replaceAll(',', '.')) ?? 1.0;
                        final rendimentVal = double.parse(rendimentController.text.trim().replaceAll(',', '.'));
                        final receiptVal = receiptController.text.trim();
                        final notesVal = notesController.text.trim();

                        setDialogState(() => saving = true);
                        try {
                          final repo = ref.read(hazelnutRepositoryProvider);
                          final escrow = await repo.addEscrowBatch(
                            customerId: customer.id,
                            warehouseId: selectedWarehouseId,
                            receiptNo: receiptVal.isNotEmpty ? receiptVal : null,
                            grossKg: grossVal,
                            sackCount: sacksVal,
                            tarePerSack: tareVal,
                            rendiment: rendimentVal,
                            notes: notesVal.isNotEmpty ? notesVal : null,
                          );

                          ref.invalidate(customerEscrowsProvider(customer.id));
                          ref.invalidate(warehousesProvider);
                          ref.invalidate(warehouseDetailProvider(selectedWarehouseId));
                          ref.invalidate(warehouseMovementsProvider(selectedWarehouseId));

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text('${escrow.receiptNo} fişiyle ${_numFormat.format(escrow.netKg)} kg emanet fındık kaydedildi.'),
                              backgroundColor: _kGreenDark,
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (ctx.mounted) {
                            AppNotificationHost.show(
                              SnackBar(content: Text('Hata: $e'), backgroundColor: _kRed),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 2. Fiyat Kesme Dialog ──────────────────────────────────────────────────
  Future<void> _showPriceCutDialog(
    BuildContext context,
    WidgetRef ref,
    CustomerHazelnutEscrowEntity escrow,
  ) async {
    final cutKgController = TextEditingController(text: escrow.remainingKg.toStringAsFixed(1));
    final basePriceController = TextEditingController(text: '130.0');
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Settlement type: CASH_PAID, OFFSET_DEBT, ACCOUNT_CREDIT
    String settlementType = customer.balance < -0.01 ? 'OFFSET_DEBT' : 'ACCOUNT_CREDIT';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cutKg = double.tryParse(cutKgController.text.trim().replaceAll(',', '.')) ?? 0.0;
          final base50 = double.tryParse(basePriceController.text.trim().replaceAll(',', '.')) ?? 0.0;

          final effectiveUnitPrice = HazelnutCalculator.calculateEffectiveUnitPrice(
            basePrice50: base50,
            rendiment: escrow.rendiment,
          );
          final totalAmount = HazelnutCalculator.calculateTotalAmount(
            cutKg: cutKg,
            effectiveUnitPrice: effectiveUnitPrice,
          );

          return AlertDialog(
            title: const Text('Fiyat Kesimi (Emanet Bozdurma)'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bilgi Başlığı
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fiş No: ${escrow.receiptNo ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('Depo: ${escrow.warehouseName ?? 'Ana Depo'}', style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Kalan Emanet: ${_numFormat.format(escrow.remainingKg)} kg', style: const TextStyle(fontWeight: FontWeight.bold, color: _kGreenDark)),
                                Text('Randıman: ${escrow.rendiment.toStringAsFixed(1)} R', style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Kesim Girdileri
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: cutKgController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Kesilecek Kilo (Kg) *',
                                border: OutlineInputBorder(),
                                suffixText: 'kg',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Miktar giriniz.';
                                final k = double.tryParse(val.trim().replaceAll(',', '.'));
                                if (k == null || k <= 0) return 'Geçerli kilo giriniz.';
                                if (k > escrow.remainingKg + 0.001) {
                                  return 'Kalan emanetten (${_numFormat.format(escrow.remainingKg)} kg) fazla olamaz.';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: basePriceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: '50 Randıman Baz Fiyat (TL) *',
                                border: OutlineInputBorder(),
                                suffixText: '₺/kg',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Fiyat giriniz.';
                                final p = double.tryParse(val.trim().replaceAll(',', '.'));
                                if (p == null || p <= 0) return 'Geçerli fiyat giriniz.';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Hesaplanan Fiyat ve Tutar Özeti
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _kGreenLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${escrow.rendiment.toStringAsFixed(1)} R Efektif Birim Fiyat:', style: const TextStyle(fontSize: 12, color: _kGreenDark)),
                                Text('${effectiveUnitPrice.toStringAsFixed(2)} ₺/kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kGreenDark)),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Toplam Kesim Tutarı:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _kText)),
                                Text(
                                  _currencyFormat.format(totalAmount),
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: _kGreenDark),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Mahsup / Ödeme Seçenekleri
                      const Text(
                        'Ödeme / Mahsup Türü:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
                      ),
                      const SizedBox(height: 6),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: 'OFFSET_DEBT',
                        groupValue: settlementType,
                        title: const Text('Müşterinin Eski Borcuna Mahsup Et (Borçtan Düş)'),
                        subtitle: Text(
                          customer.balance < -0.01 ? 'Mevcut Borç: ${_currencyFormat.format(customer.balance.abs())}' : 'Müşterinin borcu bulunmuyor',
                          style: TextStyle(fontSize: 11, color: customer.balance < -0.01 ? _kRed : _kTextSecondary),
                        ),
                        onChanged: (val) => setDialogState(() => settlementType = val!),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: 'CASH_PAID',
                        groupValue: settlementType,
                        title: const Text('Kasadan Nakit Olarak Hemen Öde'),
                        subtitle: const Text('Kasadan nakit çıkışı yapılır, cari bakiye değişmez', style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                        onChanged: (val) => setDialogState(() => settlementType = val!),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: 'ACCOUNT_CREDIT',
                        groupValue: settlementType,
                        title: const Text('Cari Hesabına Alacak Olarak Yaz'),
                        subtitle: const Text('Müşterinin bakiyesine alacak işlenir, sonraki alışverişlerinde kullanır', style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                        onChanged: (val) => setDialogState(() => settlementType = val!),
                      ),
                      const SizedBox(height: 8),

                      TextFormField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Fiyat Kesim Notu (Opsiyonel)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _kGreenDark, foregroundColor: Colors.white),
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Fiyat Kesimini Onayla'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final cutKgVal = double.parse(cutKgController.text.trim().replaceAll(',', '.'));
                        final base50Val = double.parse(basePriceController.text.trim().replaceAll(',', '.'));
                        final notesVal = notesController.text.trim();

                        setDialogState(() => saving = true);
                        try {
                          final repo = ref.read(hazelnutRepositoryProvider);
                          final cutResult = await repo.cutEscrowPrice(
                            escrowId: escrow.id,
                            cutKg: cutKgVal,
                            basePrice50: base50Val,
                            settlementType: settlementType,
                            customerName: customer.name,
                            notes: notesVal.isNotEmpty ? notesVal : null,
                          );

                          // Invalidate all related providers so customer ledger and escrows refresh
                          ref.invalidate(customerEscrowsProvider(customer.id));
                          ref.invalidate(customerDetailProvider(customer.id));
                          ref.invalidate(customerTransactionsProvider(customer.id));
                          ref.invalidate(customerBalanceDetailsProvider(customer.id));

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text('${_numFormat.format(cutResult.cutKg)} kg fındık için ${_currencyFormat.format(cutResult.totalAmount)} tutarında fiyat kesildi.'),
                              backgroundColor: _kGreenDark,
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (ctx.mounted) {
                            AppNotificationHost.show(
                              SnackBar(content: Text('Hata: $e'), backgroundColor: _kRed),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final escrowsAsync = ref.watch(customerEscrowsProvider(customer.id));

    return escrowsAsync.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
      error: (e, _) => Center(child: Text('Emanet bilgileri yüklenemedi: $e', style: const TextStyle(color: _kRed))),
      data: (escrows) {
        double totalRemainingKg = 0;
        double weightedRendimentSum = 0;
        int activeCount = 0;

        for (final e in escrows) {
          if (e.remainingKg > 0.01) {
            totalRemainingKg += e.remainingKg;
            weightedRendimentSum += (e.remainingKg * e.rendiment);
            activeCount++;
          }
        }
        final avgRendiment = totalRemainingKg > 0 ? (weightedRendimentSum / totalRemainingKg) : 50.0;

        return Column(
          children: [
            // ── Üst Emanet Özet Kartı ──────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat('Kalan Emanet Fındık', '${_numFormat.format(totalRemainingKg)} kg', _kGreenDark),
                        _buildStat('Ortalama Randıman', '${avgRendiment.toStringAsFixed(1)} R', _kText),
                        _buildStat('Aktif Parti Sayısı', '$activeCount Parti', _kAmberDark),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Emanet Girişi'),
                    onPressed: () => _showAddEscrowDialog(context, ref),
                  ),
                ],
              ),
            ),

            // ── Parti Kartları Listesi ─────────────────────────────────────
            if (escrows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text('Bu müşteriye ait emanet fındık kaydı bulunmuyor.', style: TextStyle(color: _kTextSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('İlk Emanet Fındığı Kabul Et'),
                        onPressed: () => _showAddEscrowDialog(context, ref),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: escrows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final e = escrows[index];
                  final isClosed = e.remainingKg <= 0.01;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isClosed ? const Color(0xFFF8FAFC) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isClosed ? Colors.grey[200] : (e.remainingKg < e.netKg ? _kAmberLight : _kGreenLight),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isClosed ? 'KAPANDI' : (e.remainingKg < e.netKg ? 'KISMİ KESİLDİ' : 'AKTİF'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isClosed ? Colors.grey[700] : (e.remainingKg < e.netKg ? POSColors.amberDark : _kGreenDark),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              e.receiptNo ?? 'Parti #${e.id.substring(0, 8)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
                            ),
                            const Spacer(),
                            Text(
                              _dateFormat.format(e.createdAt),
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Depo: ${e.warehouseName ?? 'Ana Depo'}', style: const TextStyle(fontSize: 12, color: _kTextSecondary)),
                                Text('Brüt: ${_numFormat.format(e.grossKg)} kg (${e.sackCount} Çuval, Dara: ${_numFormat.format(e.tareKg)} kg)',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Kalan: ${_numFormat.format(e.remainingKg)} / ${_numFormat.format(e.netKg)} kg',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isClosed ? Colors.grey : _kGreenDark,
                                  ),
                                ),
                                Text(
                                  '${e.rendiment.toStringAsFixed(1)} Randıman',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kText),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (e.notes != null && e.notes!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Not: ${e.notes!}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: _kTextSecondary)),
                        ],
                        if (!isClosed) ...[
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kGreenDark,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.price_check_rounded, size: 16),
                                label: const Text('Fiyat Kes'),
                                onPressed: () => _showPriceCutDialog(context, ref, e),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
      ],
    );
  }
}
