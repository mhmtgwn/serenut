// lib/presentation/pages/warehouse_details_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class WarehouseDetailsPage extends ConsumerWidget {
  final String warehouseId;
  const WarehouseDetailsPage({super.key, required this.warehouseId});

  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');
  static final DateFormat _dateFormat = DateFormat('dd.MM.yyyy HH:mm');

  Future<void> _showDispatchDialog(
    BuildContext context,
    WidgetRef ref,
    WarehouseEntity warehouse,
  ) async {
    final qtyController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var movementType = 'SALE_OUT'; // SALE_OUT, TRANSFER_OUT, RETURN_OUT
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final types = [
            {'code': 'SALE_OUT', 'label': 'Fabrika Satışı / Sevk'},
            {'code': 'TRANSFER_OUT', 'label': 'Başka Depoya Transfer'},
            {'code': 'RETURN_OUT', 'label': 'İade / Diğer Çıkış'},
          ];

          return AlertDialog(
            title: const Text('Depodan Mal Çıkışı'),
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
                        '${warehouse.name} deposundan fındık çıkışı yapılır. Mevcut Stok: ${_numFormat.format(warehouse.currentStockKg)} kg',
                        style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: movementType,
                        decoration: const InputDecoration(
                          labelText: 'Çıkış Nedeni / Türü',
                          border: OutlineInputBorder(),
                        ),
                        items: types.map((t) {
                          return DropdownMenuItem<String>(
                            value: t['code']!,
                            child: Text(t['label']!),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => movementType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Çıkış Miktarı (Kg)',
                          border: OutlineInputBorder(),
                          suffixText: 'kg',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Miktar giriniz.';
                          }
                          final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                          if (parsed == null || parsed <= 0) {
                            return 'Geçerli bir miktar giriniz.';
                          }
                          if (parsed > warehouse.currentStockKg) {
                            return 'Mevcut stoktan (${_numFormat.format(warehouse.currentStockKg)} kg) fazla olamaz.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama / Sevk No / İrsaliye',
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
                style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.arrow_upward_rounded, size: 18),
                label: const Text('Çıkışı Onayla'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final qty = double.parse(qtyController.text.trim().replaceAll(',', '.'));
                        final desc = descController.text.trim();

                        setDialogState(() => saving = true);
                        try {
                          final repo = ref.read(hazelnutRepositoryProvider);
                          await repo.dispatchFromWarehouse(
                            warehouseId: warehouse.id,
                            movementType: movementType,
                            quantityKg: qty,
                            description: desc.isNotEmpty ? desc : null,
                          );

                          ref.invalidate(warehouseDetailProvider(warehouse.id));
                          ref.invalidate(warehouseMovementsProvider(warehouse.id));
                          ref.invalidate(warehousesProvider);

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text('${_numFormat.format(qty)} kg fındık çıkışı başarıyla yapıldı.'),
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
    final whAsync = ref.watch(warehouseDetailProvider(warehouseId));
    final movementsAsync = ref.watch(warehouseMovementsProvider(warehouseId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          whAsync.valueOrNull?.name ?? 'Depo Detayı',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: whAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Hata: $err', style: const TextStyle(color: _kRed))),
        data: (wh) {
          if (wh == null) {
            return const Center(child: Text('Depo bulunamadı.'));
          }

          final occupancyRatio = wh.capacityKg > 0 ? (wh.currentStockKg / wh.capacityKg).clamp(0.0, 1.0) : 0.0;

          return Column(
            children: [
              // ── Depo Özet Kartı ──────────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kGreenLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.warehouse_rounded, color: _kGreenDark, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                wh.name,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kText),
                              ),
                              if (wh.location != null && wh.location!.isNotEmpty)
                                Text(
                                  wh.location!,
                                  style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                                ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                          label: const Text('Mal Çıkışı'),
                          onPressed: () => _showDispatchDialog(context, ref, wh),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat('Mevcut Stok', '${_numFormat.format(wh.currentStockKg)} kg', _kGreenDark),
                        _buildStat('Ortalama Randıman', '${wh.averageRendiment.toStringAsFixed(1)} R', _kText),
                        _buildStat('Kapasite', wh.capacityKg > 0 ? '${_numFormat.format(wh.capacityKg)} kg' : 'Sınırsız', _kTextSecondary),
                      ],
                    ),
                    if (wh.capacityKg > 0) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: occupancyRatio,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation(
                            occupancyRatio > 0.9 ? _kRed : (occupancyRatio > 0.7 ? POSColors.amber : _kGreen),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Doluluk Oranı: %${(occupancyRatio * 100).toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Depo Hareketleri Başlığı ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 18, color: _kGreenDark),
                    const SizedBox(width: 8),
                    const Text(
                      'Depo Hareketleri (Giriş / Çıkış Ekstresi)',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // ── Hareket Listesi ──────────────────────────────────────────
              Expanded(
                child: movementsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Hareketler yüklenemedi: $e')),
                  data: (movements) {
                    if (movements.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 10),
                            const Text('Bu depoda henüz bir hareket kaydedilmemiş.', style: TextStyle(color: _kTextSecondary)),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final m = movements[index];
                        final isIncoming = m.movementType.contains('IN');

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isIncoming ? _kGreenLight : _kRedLight,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: isIncoming ? _kGreenDark : _kRed,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _movementTypeLabel(m.movementType),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kText),
                                    ),
                                    if (m.description != null && m.description!.isNotEmpty)
                                      Text(
                                        m.description!,
                                        style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                                      ),
                                    Text(
                                      _dateFormat.format(m.createdAt),
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isIncoming ? '+' : '-'}${_numFormat.format(m.quantityKg)} kg',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: isIncoming ? _kGreenDark : _kRed,
                                    ),
                                  ),
                                  Text(
                                    '${m.rendiment.toStringAsFixed(1)} Randıman',
                                    style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                                  ),
                                  Text(
                                    'Bakiye: ${_numFormat.format(m.balanceKgAfter)} kg',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
      ],
    );
  }

  String _movementTypeLabel(String type) {
    switch (type) {
      case 'ESCROW_IN':
        return 'Müşteri Emanet Girişi';
      case 'PURCHASE_IN':
        return 'Doğrudan Alım Girişi';
      case 'TRANSFER_IN':
        return 'Depo Transfer Girişi';
      case 'SALE_OUT':
        return 'Fabrika Satış / Çıkış';
      case 'TRANSFER_OUT':
        return 'Depo Transfer Çıkışı';
      case 'RETURN_OUT':
        return 'İade / Diğer Çıkış';
      default:
        return type;
    }
  }
}

