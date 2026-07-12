// lib/presentation/pages/sale_details_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/customers_controller.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/config/utils.dart';

class SaleDetailsPage extends ConsumerWidget {
  final String saleId;

  const SaleDetailsPage({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleVal = ref.watch(saleDetailProvider(saleId));
    final customersVal = ref.watch(customersControllerProvider);
    // ── Ürün adı haritası (UUID → isim) ──
    final productsVal = ref.watch(productsControllerProvider);
    final productNameMap = productsVal.maybeWhen(
      data: (list) => {for (final p in list) p.id: p.name},
      orElse: () => <String, String>{},
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Satış Detayı #${saleId.toShortId}'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Color(0xFF16A34A)),
      ),
      body: saleVal.when(
        data: (sale) {
          if (sale == null) {
            return const Center(child: Text('Satış bulunamadı.'));
          }
          final customerName = customersVal.maybeWhen(
            data: (list) {
              try {
                return list.firstWhere((c) => c.id == sale.customerId).name;
              } catch (_) {
                return 'Bilinmeyen Müşteri';
              }
            },
            orElse: () => '...',
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSaleSummaryCard(sale, customerName),
                const SizedBox(height: 16),

                if (sale.items.isNotEmpty) ...[
                  const Text(
                    'Ürünler',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildItemsCard(sale.items, productNameMap),
                  const SizedBox(height: 16),
                ],

                _buildPaymentSummaryCard(sale),
                const SizedBox(height: 16),

                if (sale.status != 'cancelled')
                  _buildActionBar(context, ref, sale),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF16A34A)),
          ),
        ),
        error: (e, _) => Center(child: Text('Hata: $e')),
      ),
    );
  }

  Widget _buildSaleSummaryCard(SaleEntity sale, String customerName) {
    final statusColors = {
      'completed': [const Color(0xFFDCFCE7), const Color(0xFF16A34A)],
      'partial': [Colors.orange[50]!, Colors.orange[700]!],
      'pending': [const Color(0xFFFEF9C3), const Color(0xFFD97706)],
      'cancelled': [Colors.grey[100]!, Colors.grey[600]!],
    };
    final statusLabels = {
      'completed': 'Tamamlandı',
      'partial': 'Kısmi Ödeme',
      'pending': 'Bekliyor',
      'cancelled': 'İptal Edildi',
    };

    final colors = statusColors[sale.status] ?? [Colors.grey[100]!, Colors.grey[600]!];
    final label = statusLabels[sale.status] ?? sale.status;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Satış #${saleId.toShortId}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(DateFormat('dd MMMM yyyy, HH:mm', 'tr_TR').format(sale.createdAt),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors[0],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(label,
                      style: TextStyle(fontWeight: FontWeight.bold, color: colors[1], fontSize: 12)),
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow(Icons.person_outline, 'Müşteri', customerName),
            const SizedBox(height: 8),
            _infoRow(Icons.payment_outlined, 'Ödeme Yöntemi', _paymentLabel(sale.paymentMethod)),
            if (sale.createdBy != null && sale.createdBy!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow(Icons.badge_outlined, 'Kasiyer / İşlemi Yapan', sale.createdBy!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  String _paymentLabel(String method) {
    const labels = {
      'cash': 'Nakit', 'nakit': 'Nakit',
      'card': 'Kart', 'kart': 'Kart',
      'debt': 'Vadeli', 'vadeli': 'Vadeli',
      'transfer': 'Havale', 'havale': 'Havale',
    };
    return labels[method.toLowerCase()] ?? method;
  }

  Widget _buildItemsCard(
    List<Map<String, dynamic>> items,
    Map<String, String> productNameMap,
  ) {
    double total = 0;
    for (final item in items) {
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] ?? item['unitPrice']) as double? ?? 0.0;
      total += qty * price;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            final price = (item['unit_price'] ?? item['unitPrice']) as double? ?? 0.0;
            final productId = item['product_id']?.toString() ?? '';
            // UUID → gerçek ürün adına çevir
            final productName = productNameMap[productId] ?? item['product_name']?.toString() ?? productId;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            qty % 1 == 0 ? qty.toInt().toString() : qty.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${price.toStringAsFixed(2)} TL / adet',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(price * qty).toStringAsFixed(2)} TL',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < items.length - 1)
                  const Divider(height: 1, indent: 64),
              ],
            );
          }),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Toplam',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '${total.toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryCard(SaleEntity sale) {
    final remaining = sale.totalAmount - sale.paidAmount;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ödeme Özeti',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            _paymentRow('Toplam Tutar', sale.totalAmount, Colors.black87),
            const SizedBox(height: 8),
            _paymentRow('Ödenen', sale.paidAmount, Colors.green[700]!),
            if (remaining > 0) ...[
              const SizedBox(height: 8),
              _paymentRow('Kalan Borç', remaining, Colors.red[700]!,
                  bold: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(String label, double amount, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        Text(
          '${amount.toStringAsFixed(2)} TL',
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
            fontSize: bold ? 16 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context, WidgetRef ref, SaleEntity sale) {
    final remaining = sale.totalAmount - sale.paidAmount;
    return Column(
      children: [
        // Kısmi Ödeme — only if debt exists
        if (remaining > 0) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showPartialPaymentDialog(context, ref, sale, remaining),
              icon: const Icon(Icons.payments_outlined),
              label: Text('Kısmi Ödeme Yap (${remaining.toStringAsFixed(2)} TL borç)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // İade İşlemi — only if items exist
        if (sale.items.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showReturnDialog(context, ref, sale),
              icon: const Icon(Icons.undo),
              label: const Text('İade İşlemi'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange[800],
                side: BorderSide(color: Colors.orange[600]!),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Satış İptali
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _confirmCancel(context, ref, sale),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Satışı İptal Et'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[700],
              side: BorderSide(color: Colors.red[400]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmCancel(BuildContext context, WidgetRef ref, SaleEntity sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Satışı İptal Et'),
        content: Text(
          'Bu satışı iptal etmek istediğinize emin misiniz?\n\n'
          'Stok ve müşteri bakiyesi geri alınacaktır.\n'
          'Toplam: ${sale.totalAmount.toStringAsFixed(2)} TL',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(salesControllerProvider.notifier).cancelSale(sale.id);
              ref.invalidate(saleDetailProvider(sale.id));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Satış iptal edildi.'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
  }

  void _showPartialPaymentDialog(BuildContext context, WidgetRef ref, SaleEntity sale, double remaining) {
    showDialog(
      context: context,
      builder: (ctx) => _PartialPaymentDialog(sale: sale, remaining: remaining, parentContext: context),
    );
  }

  void _showReturnDialog(BuildContext context, WidgetRef ref, SaleEntity sale) {
    final productsVal = ref.read(productsControllerProvider);
    final productNameMap = productsVal.maybeWhen(
      data: (list) => {for (final p in list) p.id: p.name},
      orElse: () => <String, String>{},
    );

    // Build return items list from sale.items
    final returnItems = sale.items.map((item) {
      final qty = item['quantity'] as int? ?? 0;
      return _ReturnItem(
        productId: item['product_id']?.toString() ?? '',
        maxQty: qty,
        unitPrice: (item['unit_price'] ?? item['unitPrice']) as double? ?? 0.0,
        returnQty: 0,
      );
    }).toList();
    String refundMethod = 'balance';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final refundTotal = returnItems.fold<double>(
              0.0, (s, i) => s + (i.returnQty * i.unitPrice));
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.undo, color: Colors.orange),
                SizedBox(width: 8),
                Text('İade İşlemi'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...returnItems.map((ri) {
                      final name = productNameMap[ri.productId] ?? ri.productId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500))),
                          IconButton(
                            onPressed: ri.returnQty > 0
                                ? () => setDialog(() => ri.returnQty--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: const Color(0xFF16A34A),
                          ),
                          Text('${ri.returnQty} / ${ri.maxQty}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            onPressed: ri.returnQty < ri.maxQty
                                ? () => setDialog(() => ri.returnQty++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                            color: const Color(0xFF16A34A),
                          ),
                        ],
                      ),
                    );
                  }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('İade Tutarı:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('${refundTotal.toStringAsFixed(2)} TL',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[700])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: refundMethod,
                      decoration: InputDecoration(
                        labelText: 'İade Yöntemi',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'balance', child: Text('Müşteri Bakiyesine Ekle')),
                        DropdownMenuItem(value: 'cash', child: Text('Nakit İade')),
                      ],
                      onChanged: (v) => setDialog(() => refundMethod = v ?? 'balance'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
              ElevatedButton(
                onPressed: refundTotal > 0
                    ? () async {
                        Navigator.pop(ctx);
                        final items = returnItems
                            .where((ri) => ri.returnQty > 0)
                            .map((ri) => SaleItemInput(
                                  productId: ri.productId,
                                  quantity: ri.returnQty,
                                  unitPrice: ri.unitPrice,
                                ))
                            .toList();
                        await ref
                            .read(salesControllerProvider.notifier)
                            .returnItems(
                              saleId: sale.id,
                              itemsToReturn: items,
                              refundMethod: refundMethod,
                            );
                        ref.invalidate(saleDetailProvider(sale.id));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('İade tamamlandı. ${refundTotal.toStringAsFixed(2)} TL iade edildi.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('İadeyi Onayla'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReturnItem {
  final String productId;
  final int maxQty;
  final double unitPrice;
  int returnQty;

  _ReturnItem({
    required this.productId,
    required this.maxQty,
    required this.unitPrice,
    required this.returnQty,
  });
}

class _PartialPaymentDialog extends ConsumerStatefulWidget {
  final SaleEntity sale;
  final double remaining;
  final BuildContext parentContext;

  const _PartialPaymentDialog({
    required this.sale,
    required this.remaining,
    required this.parentContext,
  });

  @override
  ConsumerState<_PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends ConsumerState<_PartialPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController amtCtrl;
  String method = 'cash';

  @override
  void initState() {
    super.initState();
    amtCtrl = TextEditingController(text: widget.remaining.toStringAsFixed(2));
  }

  @override
  void dispose() {
    amtCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.payments, color: Color(0xFF16A34A)),
          SizedBox(width: 8),
          Text('Kısmi Ödeme'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kalan borç: ${widget.remaining.toStringAsFixed(2)} TL',
                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 12),
            TextFormField(
              controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Ödenecek Tutar (TL)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Tutar girin';
                final d = double.tryParse(v);
                if (d == null || d <= 0) return 'Geçerli tutar';
                if (d > widget.remaining) return 'Borçtan fazla olamaz';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: method,
              decoration: InputDecoration(
                labelText: 'Yöntem',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                DropdownMenuItem(value: 'card', child: Text('Kart')),
                DropdownMenuItem(value: 'transfer', child: Text('Havale')),
              ],
              onChanged: (v) => setState(() => method = v ?? 'cash'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        ElevatedButton(
          onPressed: () async {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final amount = double.parse(amtCtrl.text);
            Navigator.pop(context);
            await ref.read(salesControllerProvider.notifier)
                .recordPartialPayment(saleId: widget.sale.id, amount: amount, method: method);
            ref.invalidate(saleDetailProvider(widget.sale.id));
            if (widget.parentContext.mounted) {
              ScaffoldMessenger.of(widget.parentContext).showSnackBar(
                SnackBar(
                  content: Text('${amount.toStringAsFixed(2)} TL ödeme alındı.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
          ),
          child: const Text('Öde'),
        ),
      ],
    );
  }
}
