// lib/domain/services/audit_service.dart
import 'package:serenutos/domain/models/audit_event.dart';
import 'package:serenutos/domain/repositories/audit_repository.dart';
import 'package:uuid/uuid.dart';

class AuditService {
  final IAuditRepository _repository;
  final String? _currentUserId;
  final String? _currentUserName;
  final String? _deviceId;

  AuditService({
    required IAuditRepository repository,
    String? currentUserId,
    String? currentUserName,
    String? deviceId,
  })  : _repository = repository,
        _currentUserId = currentUserId,
        _currentUserName = currentUserName,
        _deviceId = deviceId;

  Future<void> logEvent({
    required String eventType,
    required String entityType,
    String? entityId,
    String? oldValue,
    String? newValue,
    String? notes,
  }) async {
    final event = AuditEvent(
      id: const Uuid().v4(),
      eventType: eventType,
      entityType: entityType,
      entityId: entityId,
      userId: _currentUserId,
      userName: _currentUserName,
      oldValue: oldValue,
      newValue: newValue,
      timestamp: DateTime.now(),
      deviceId: _deviceId,
      notes: notes,
    );
    await _repository.logEvent(event);
  }

  // Wrappers
  Future<void> logPriceChange(String productId, String productName, double oldPrice, double newPrice) async {
    await logEvent(
      eventType: 'price_changed',
      entityType: 'product',
      entityId: productId,
      oldValue: '₺${oldPrice.toStringAsFixed(2)}',
      newValue: '₺${newPrice.toStringAsFixed(2)}',
      notes: 'Ürün Fiyatı Değiştirildi: $productName',
    );
  }

  Future<void> logCustomerUpdate(String customerId, String customerName, String changeDetails) async {
    await logEvent(
      eventType: 'customer_updated',
      entityType: 'customer',
      entityId: customerId,
      notes: 'Müşteri Güncellendi: $customerName ($changeDetails)',
    );
  }

  Future<void> logPayment(String customerId, String customerName, double amount, String type) async {
    await logEvent(
      eventType: 'payment_recorded',
      entityType: 'payment',
      entityId: customerId,
      newValue: '₺${amount.toStringAsFixed(2)}',
      notes: 'Tahsilat/Ödeme Yapıldı: $customerName ($type)',
    );
  }

  Future<void> logDelete(String entityType, String entityId, String entityName) async {
    await logEvent(
      eventType: 'entity_deleted',
      entityType: entityType,
      entityId: entityId,
      notes: 'Varlık Silindi ($entityType): $entityName',
    );
  }

  Future<void> logSystemAction(String action, String details) async {
    await logEvent(
      eventType: 'system_action',
      entityType: 'system',
      notes: 'Sistem İşlemi ($action): $details',
    );
  }
}
