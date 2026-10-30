// lib/presentation/widgets/hazelnut/warehouse_dialogs.dart
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/hazelnut_models.dart';
import 'package:serenutos/presentation/controllers/hazelnut_controller.dart';
import 'package:serenutos/presentation/widgets/app_notification_host.dart';
import 'package:serenutos/providers/hazelnut_providers.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kGreenLight = POSColors.greenLight;
const _kRed = POSColors.red;
const _kRedLight = POSColors.redLight;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class WarehouseDialogs {
  WarehouseDialogs._();

  static final NumberFormat _numFormat = NumberFormat.decimalPattern('tr_TR');

  /// ── 1. Depo Düzenleme Diyaloğu ──────────────────────────────────────────
  static Future<void> showEditWarehouseDialog(
    BuildContext context,
    WidgetRef ref,
    WarehouseEntity warehouse,
  ) async {
    final nameController = TextEditingController(text: warehouse.name);
    final locationController = TextEditingController(text: warehouse.location ?? '');
    final capacityController = TextEditingController(
      text: warehouse.capacityKg > 0 ? warehouse.capacityKg.toStringAsFixed(0) : '',
    );
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kGreenLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: _kGreenDark, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Depo Bilgilerini Düzenle',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
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
                        'Mevcut Stok: ${_numFormat.format(warehouse.currentStockKg)} kg '
                        '• Ort. Randıman: ${warehouse.averageRendiment.toStringAsFixed(1)} R',
                        style: const TextStyle(fontSize: 12, color: _kTextSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Depo / Silo Adı *',
                          hintText: 'Örn: Silo 1, Çarşamba Depo',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Depo adı zorunludur.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Konum / Adres',
                          hintText: 'Örn: Sanayi Mah. Fındıkçılar Sitesi No: 4',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: capacityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Maksimum Kapasite (Kg)',
                          hintText: 'Boş bırakılırsa sınırsız kabul edilir',
                          border: OutlineInputBorder(),
                          suffixText: 'kg',
                          prefixIcon: Icon(Icons.storage_rounded, size: 20),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return null;
                          final cap = double.tryParse(val.trim().replaceAll(',', '.'));
                          if (cap == null || cap < 0) {
                            return 'Geçerli bir kapasite değeri giriniz.';
                          }
                          if (cap < warehouse.currentStockKg) {
                            return 'Kapasite mevcut stoktan (${_numFormat.format(warehouse.currentStockKg)} kg) küçük olamaz.';
                          }
                          return null;
                        },
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                ),
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Değişiklikleri Kaydet'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final name = nameController.text.trim();
                        final loc = locationController.text.trim();
                        final cap = double.tryParse(capacityController.text.trim().replaceAll(',', '.')) ?? 0.0;

                        setDialogState(() => saving = true);
                        try {
                          final updated = warehouse.copyWith(
                            name: name,
                            location: loc.isNotEmpty ? loc : null,
                            capacityKg: cap,
                            updatedAt: clock.now(),
                          );

                          await ref.read(hazelnutControllerProvider).saveWarehouse(updated);

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text('$name deposu başarıyla güncellendi.'),
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

  /// ── 2. Depolar Arası Transfer Diyaloğu ────────────────────────────────────
  static Future<void> showTransferDialog(
    BuildContext context,
    WidgetRef ref,
    WarehouseEntity sourceWarehouse,
  ) async {
    final allWarehouses = ref.read(warehousesProvider).valueOrNull ?? [];
    final targetWarehouses = allWarehouses.where((w) => w.id != sourceWarehouse.id && w.isActive).toList();

    if (targetWarehouses.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Transfer Yapılamaz'),
          content: const Text(
            'Transfer yapabilmek için sistemde en az bir başka aktif depo bulunmalıdır. '
            'Lütfen önce "Yeni Depo Ekle" butonunu kullanarak hedef bir depo oluşturun.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anladım'),
            ),
          ],
        ),
      );
      return;
    }

    if (sourceWarehouse.currentStockKg <= 0.001) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yetersiz Stok'),
          content: Text(
            '${sourceWarehouse.name} deposunda transfer edilecek stok bulunmamaktadır (Mevcut Stok: 0 kg).',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }

    String selectedTargetId = targetWarehouses.first.id;
    final qtyController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final targetWh = targetWarehouses.firstWhere((w) => w.id == selectedTargetId);

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.swap_horiz_rounded, color: Colors.blue, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Depolar Arası Transfer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: POSColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward_rounded, size: 16, color: _kRed),
                                const SizedBox(width: 6),
                                const Text('Kaynak Depo: ', style: TextStyle(fontSize: 12, color: _kTextSecondary)),
                                Expanded(
                                  child: Text(
                                    sourceWarehouse.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${_numFormat.format(sourceWarehouse.currentStockKg)} kg',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: _kGreenDark, fontSize: 13),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.arrow_downward_rounded, size: 16, color: _kGreenDark),
                                const SizedBox(width: 6),
                                const Text('Hedef Depo: ', style: TextStyle(fontSize: 12, color: _kTextSecondary)),
                                Expanded(
                                  child: Text(
                                    targetWh.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${_numFormat.format(targetWh.currentStockKg)} kg',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: _kTextSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedTargetId,
                        decoration: const InputDecoration(
                          labelText: 'Hedef Depo / Silo Seçin *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.warehouse_rounded, size: 20),
                        ),
                        items: targetWarehouses.map((w) {
                          return DropdownMenuItem<String>(
                            value: w.id,
                            child: Text(
                              '${w.name} (Stok: ${_numFormat.format(w.currentStockKg)} kg)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedTargetId = val);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Transfer Edilecek Miktar (Kg) *',
                          hintText: 'Örn: 5000',
                          border: const OutlineInputBorder(),
                          suffixText: 'kg',
                          prefixIcon: const Icon(Icons.scale_rounded, size: 20),
                          helperText: 'Maksimum transfer edilebilir: ${_numFormat.format(sourceWarehouse.currentStockKg)} kg',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Transfer miktarı giriniz.';
                          final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                          if (parsed == null || parsed <= 0) return 'Geçerli bir miktar giriniz.';
                          if (parsed > sourceWarehouse.currentStockKg) {
                            return 'Kaynak depodaki mevcut stoktan (${_numFormat.format(sourceWarehouse.currentStockKg)} kg) fazla olamaz.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: descController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama / Sevk Notu (İsteğe bağlı)',
                          hintText: 'Örn: Silo aktarımı, kurutma sonrası transfer',
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Transferi Gerçekleştir'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final qty = double.parse(qtyController.text.trim().replaceAll(',', '.'));
                        final desc = descController.text.trim();

                        setDialogState(() => saving = true);
                        try {
                          await ref.read(hazelnutControllerProvider).transferBetweenWarehouses(
                            sourceWarehouseId: sourceWarehouse.id,
                            targetWarehouseId: selectedTargetId,
                            quantityKg: qty,
                            description: desc.isNotEmpty ? desc : null,
                          );

                          if (ctx.mounted) Navigator.pop(ctx);
                          AppNotificationHost.show(
                            SnackBar(
                              content: Text(
                                '${_numFormat.format(qty)} kg fındık ${targetWh.name} deposuna başarıyla transfer edildi.',
                              ),
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

  /// ── 3. Mal Çıkışı Diyaloğu ────────────────────────────────────────────────
  static Future<void> showDispatchDialog(
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
            {'code': 'RETURN_OUT', 'label': 'İade / Diğer Çıkış'},
          ];

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _kRedLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, color: _kRed, size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Depodan Mal Çıkışı',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
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
                        '${warehouse.name} deposundan mal çıkışı yapılır.\nMevcut Stok: ${_numFormat.format(warehouse.currentStockKg)} kg',
                        style: const TextStyle(fontSize: 13, color: _kTextSecondary),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: movementType,
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
                          if (val == null || val.trim().isEmpty) return 'Miktar giriniz.';
                          final parsed = double.tryParse(val.trim().replaceAll(',', '.'));
                          if (parsed == null || parsed <= 0) return 'Geçerli bir miktar giriniz.';
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
                          await ref.read(hazelnutControllerProvider).dispatchFromWarehouse(
                            warehouseId: warehouse.id,
                            movementType: movementType,
                            quantityKg: qty,
                            description: desc.isNotEmpty ? desc : null,
                          );

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

  /// ── 4. Depo Silme / Arşive Alma Güvenlikli Diyaloğu ──────────────────────
  static Future<void> showDeleteWarehouseDialog(
    BuildContext context,
    WidgetRef ref,
    WarehouseEntity warehouse, {
    VoidCallback? onDeleted,
  }) async {
    if (warehouse.currentStockKg > 0.001) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: POSColors.amberDark, size: 26),
              SizedBox(width: 8),
              Text('Depo Silinemez'),
            ],
          ),
          content: Text(
            '${warehouse.name} deposunda halen ${_numFormat.format(warehouse.currentStockKg)} kg fındık bulunmaktadır.\n\n'
            'Depo silinmeden önce tüm stok sıfırlanmalıdır. Mal çıkışı yapabilir veya fındığı başka bir depoya transfer edebilirsiniz.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anladım'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kRedLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: _kRed, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Depoyu Sil / Arşive Al',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '${warehouse.name} deposunu silmek istediğinize emin misiniz?\n\n'
          'Depo pasife alınacak ve listelerden kaldırılacaktır. Geçmiş hareket kayıtları denetim ve muhasebe için korunacaktır.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kRed, foregroundColor: Colors.white),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Evet, Depoyu Sil'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(hazelnutControllerProvider).deleteWarehouse(warehouse.id);

      AppNotificationHost.show(
        SnackBar(
          content: Text('${warehouse.name} deposu başarıyla silindi.'),
          backgroundColor: _kGreenDark,
        ),
      );
      if (onDeleted != null) {
        onDeleted();
      }
    } catch (e) {
      AppNotificationHost.show(
        SnackBar(content: Text('Hata: $e'), backgroundColor: _kRed),
      );
    }
  }
}

