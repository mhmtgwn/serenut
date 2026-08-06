import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_outbox.dart';

class SqliteRefundMutationStore implements IRefundMutationStore {
  SqliteRefundMutationStore(this._gateway);
  final DbGateway _gateway;
  static const _uuid = Uuid();

  @override
  Future<String> create({
    required String saleId,
    required List<RefundLineRequest> items,
    required String refundMethod,
    required String reason,
    String? externalReference,
  }) {
    if (items.isEmpty) throw ArgumentError('İade kalemi zorunludur.');
    if (!{'cash', 'balance', 'card', 'mixed'}.contains(refundMethod)) {
      throw ArgumentError('Geçersiz iade yöntemi.');
    }
    if (reason.trim().length < 3) throw ArgumentError('İade gerekçesi zorunludur.');
    if ({'card', 'mixed'}.contains(refundMethod) && (externalReference?.trim().isEmpty ?? true)) {
      throw ArgumentError('Kart iadesi işlem referansı zorunludur.');
    }
    return _gateway.transaction(() async {
      final sales = await _gateway.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (sales.isEmpty) throw StateError('Satış bulunamadı.');
      final sale = sales.first;
      final state = (sale['fsm_state'] ?? sale['status']).toString();
      if (state != 'completed' && state != 'partially_refunded') throw StateError('Satış iade edilemez.');
      final refundId = _uuid.v4();
      var amount = 0.0;
      final payloadItems = <Map<String, Object?>>[];
      final normalized = <Map<String, Object?>>[];
      for (final requested in items) {
        final rows = await _gateway.rawQuery('''
          SELECT si.*,COALESCE((SELECT SUM(ri.quantity) FROM refund_items ri
            WHERE ri.sale_item_id=si.id),0) AS refunded_quantity
          FROM sale_items si WHERE si.id=? AND si.sale_id=?''', [requested.saleItemId, saleId]);
        if (rows.isEmpty || requested.quantity <= 0) throw StateError('Geçersiz iade kalemi.');
        final row = rows.first;
        final sold = (row['quantity'] as num).toDouble();
        final returned = (row['refunded_quantity'] as num).toDouble();
        if (requested.quantity > sold - returned) throw StateError('Satılandan fazla ürün iade edilemez.');
        final unit = (row['subtotal'] as num).toDouble() / sold;
        final subtotal = double.parse((unit * requested.quantity).toStringAsFixed(2));
        amount += subtotal;
        payloadItems.add({'sale_item_id': requested.saleItemId, 'quantity': requested.quantity});
        normalized.add({
          'sale_item_id': requested.saleItemId,
          'product_id': row['product_id'], 'quantity': requested.quantity,
          'unit_refund_amount': unit, 'subtotal': subtotal,
        });
      }
      amount = double.parse(amount.toStringAsFixed(2));
      final previous = (sale['refunded_amount'] as num?)?.toDouble() ?? 0;
      final total = (sale['total_amount'] as num).toDouble();
      if (amount <= 0 || previous + amount > total + 0.01) throw StateError('İade satış toplamını aşamaz.');
      final newRefunded = double.parse((previous + amount).toStringAsFixed(2));
      final newState = newRefunded >= total - 0.01 ? 'refunded' : 'partially_refunded';
      final now = DateTime.now().toUtc().toIso8601String();
      await _gateway.insert('refunds', {
        'id': refundId, 'sale_id': saleId, 'amount': amount, 'refund_method': refundMethod,
        'external_reference': externalReference?.trim(), 'reason': reason.trim(),
        'status': 'completed', 'created_at': now,
      });
      for (final row in normalized) {
        await _gateway.insert('refund_items', {
          'id': _uuid.v4(), 'refund_id': refundId, ...row,
        });
        final changed = await _gateway.rawUpdate(
          'UPDATE products SET quantity=quantity+?,updated_at=? WHERE id=?',
          [row['quantity'], now, row['product_id']],
        );
        if (changed != 1) throw StateError('İade ürünü bulunamadı.');
      }
      await _gateway.update('sales', {
        'refunded_amount': newRefunded, 'fsm_state': newState, 'updated_at': now,
      }, where: 'id = ?', whereArgs: [saleId]);
      final customerId = sale['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty) {
        await _gateway.insert('financial_transactions', {
          'id': 'refund-$refundId', 'type': 'refund', 'customer_id': customerId,
          'amount': amount, 'paid_amount': refundMethod == 'balance' ? 0.0 : amount,
          'debt_amount': 0.0, 'reference_id': refundId, 'description': reason.trim(),
          'payment_method': refundMethod, 'created_at': now, 'is_synced': 1,
        });
      }
      await SyncOutboxV4.enqueue(_gateway,
        entityType: 'refund', entityId: refundId, operation: 'UPSERT', payload: {
          'sale_id': saleId, 'refund_method': refundMethod, 'external_reference': externalReference,
          'reason': reason.trim(), 'items': payloadItems,
        });
      return refundId;
    });
  }
}
