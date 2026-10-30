// lib/presentation/widgets/hazelnut/warehouses_tab_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/presentation/controllers/hazelnut_controller.dart';
import 'package:serenutos/presentation/pages/warehouse_details_page.dart';
import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/presentation/widgets/hazelnut/warehouse_dialogs.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class WarehousesTabView extends ConsumerWidget {
  const WarehousesTabView({super.key});

  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');

  Future<void> _showAddWarehouseDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final locationController = TextEditingController();
    final capacityController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Yeni Depo / Silo Ekle'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Depo Adı *',
                        hintText: 'Örn: Silo 2, Çarşamba Depo',
                        border: OutlineInputBorder(),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Depo adı zorunludur.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Konum / Adres',
                        hintText: 'Örn: Sanayi Mah. No: 12',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: capacityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Kapasite (Kg)',
                        hintText: 'Örn: 50000',
                        border: OutlineInputBorder(),
                        suffixText: 'kg',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton.icon(
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kaydet'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final name = nameController.text.trim();
                        final loc = locationController.text.trim();
                        final cap = double.tryParse(capacityController.text.trim().replaceAll(',', '.')) ?? 0.0;

                        setDialogState(() => saving = true);
                        try {
                          final now = DateTime.now();
                          final newWh = WarehouseEntity(
                            id: const Uuid().v4(),
                            name: name,
                            location: loc.isNotEmpty ? loc : null,
                            capacityKg: cap,
                            currentStockKg: 0.0,
                            averageRendiment: 50.0,
                            createdAt: now,
                            updatedAt: now,
                          );
                          await ref.read(hazelnutControllerProvider).saveWarehouse(newWh);

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text('$name deposu başarıyla eklendi.'),
                              backgroundColor: _kGreenDark,
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (ctx.mounted) {
                            AppNotificationHost.show(
                              SnackBar(content: Text('Hata: $e'), backgroundColor: POSColors.red),
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
    final warehousesAsync = ref.watch(warehousesProvider);

    return warehousesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Depolar yüklenemedi: $e', style: const TextStyle(color: POSColors.red))),
      data: (warehouses) {
        double totalStock = 0;
        double weightedRendimentSum = 0;
        for (final w in warehouses) {
          totalStock += w.currentStockKg;
          weightedRendimentSum += (w.currentStockKg * w.averageRendiment);
        }
        final overallAverageRendiment = totalStock > 0 ? (weightedRendimentSum / totalStock) : 50.0;

        return Column(
          children: [
            // ── Üst Genel Özet Kartı ──────────────────────────────────────
            Container(
              margin: const EdgeInsets.all(16),
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
                        _buildSummaryItem(
                          'Toplam Fiziksel Stok',
                          '${_numFormat.format(totalStock)} kg',
                          Icons.inventory_2_rounded,
                          _kGreenDark,
                        ),
                        _buildSummaryItem(
                          'Genel Ort. Randıman',
                          '${overallAverageRendiment.toStringAsFixed(1)} R',
                          Icons.analytics_rounded,
                          _kText,
                        ),
                        _buildSummaryItem(
                          'Aktif Depo Sayısı',
                          '${warehouses.length} Depo',
                          Icons.warehouse_rounded,
                          POSColors.amberDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Yeni Depo Ekle'),
                    onPressed: () => _showAddWarehouseDialog(context, ref),
                  ),
                ],
              ),
            ),

            // ── Depo Kartları Listesi ─────────────────────────────────────
            Expanded(
              child: warehouses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warehouse_rounded, size: 56, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text('Kayıtlı depo bulunamadı.', style: TextStyle(color: _kTextSecondary)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('İlk Depoyu Oluştur'),
                            onPressed: () => _showAddWarehouseDialog(context, ref),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 700;
                        if (isDesktop) {
                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 460,
                              mainAxisExtent: 180,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                            ),
                            itemCount: warehouses.length,
                            itemBuilder: (context, index) => _buildWarehouseCard(context, ref, warehouses[index]),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: warehouses.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _buildWarehouseCard(context, ref, warehouses[index]),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: _kTextSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _buildWarehouseCard(BuildContext context, WidgetRef ref, WarehouseEntity wh) {
    final occupancy = wh.capacityKg > 0 ? (wh.currentStockKg / wh.capacityKg).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _kGreenLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warehouse_rounded, color: _kGreenDark, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wh.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kText),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (wh.location != null && wh.location!.isNotEmpty)
                      Text(
                        wh.location!,
                        style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  side: const BorderSide(color: _kGreen),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: _kGreenDark),
                label: const Text('Depo Detayı', style: TextStyle(color: _kGreenDark, fontSize: 12)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WarehouseDetailsPage(warehouseId: wh.id),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: _kTextSecondary),
                tooltip: 'İşlemler',
                padding: EdgeInsets.zero,
                onSelected: (val) {
                  switch (val) {
                    case 'edit':
                      WarehouseDialogs.showEditWarehouseDialog(context, ref, wh);
                      break;
                    case 'transfer':
                      WarehouseDialogs.showTransferDialog(context, ref, wh);
                      break;
                    case 'dispatch':
                      WarehouseDialogs.showDispatchDialog(context, ref, wh);
                      break;
                    case 'delete':
                      WarehouseDialogs.showDeleteWarehouseDialog(context, ref, wh);
                      break;
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.edit_outlined, size: 18),
                      title: Text('Depoyu Düzenle'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'transfer',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.swap_horiz_rounded, size: 18, color: Colors.blue),
                      title: Text('Transfer Yap'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'dispatch',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.arrow_upward_rounded, size: 18, color: POSColors.red),
                      title: Text('Mal Çıkışı'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline_rounded, size: 18, color: POSColors.red),
                      title: Text('Depoyu Sil', style: TextStyle(color: POSColors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
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
                  const Text('Mevcut Stok', style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                  Text(
                    '${_numFormat.format(wh.currentStockKg)} kg',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kGreenDark),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Ort. Randıman', style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                  Text(
                    '${wh.averageRendiment.toStringAsFixed(1)} R',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kText),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Kapasite', style: TextStyle(fontSize: 11, color: _kTextSecondary)),
                  Text(
                    wh.capacityKg > 0 ? '${_numFormat.format(wh.capacityKg)} kg' : 'Sınırsız',
                    style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                  ),
                ],
              ),
            ],
          ),
          if (wh.capacityKg > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: occupancy,
                minHeight: 5,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(
                  occupancy > 0.9 ? POSColors.red : (occupancy > 0.7 ? POSColors.amber : _kGreen),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

