/// Event = Sistem genelinde her değişiklik bir event üretir
/// Domain events: SaleCreated, OrderCreated, PaymentAdded, StockChanged, SmsTriggered, etc.
library;

enum EventType {
  saleCreated,
  saleCompleted,
  saleCancelled,
  orderCreated,
  orderPreparing,
  orderReady,
  orderDelivered,
  orderCancelled,
  paymentAdded,
  paymentReversed,
  stockChanged,
  customerCreated,
  customerUpdated,
  smsTriggered,
  collectionRecorded, // tahsilat/ödeme kaydı
  debtCreated, // borçlu satış
}

abstract class DomainEvent {
  final EventType type;
  final DateTime occurredAt;
  final int? aggregateId; // saleId, orderId, customerId, etc.
  final String? aggregateType; // "Sale", "Order", "Customer", etc.
  final Map<String, dynamic>? metadata;

  DomainEvent({
    required this.type,
    DateTime? occurredAt,
    this.aggregateId,
    this.aggregateType,
    this.metadata,
  }) : occurredAt = occurredAt ?? DateTime.now();

  @override
  String toString() => '$type at ${occurredAt.toIso8601String()}';
}

class SaleCreatedEvent extends DomainEvent {
  // Legacy int fields (kept for backward compat)
  final int saleId;
  final int customerId;
  final double totalAmount;
  final List<String>? paymentMethods; // [cash, card, debt]

  // String UUID fields — used by SmsNotificationHandler
  final String saleIdStr; // actual UUID e.g. 'sale-xxx'
  final String customerIdStr; // actual UUID e.g. 'cust-yyy'
  final double paidAmount; // used to detect debt (totalAmount - paidAmount > 0)
  final String paymentMethod; // 'cash' | 'card' | 'debt' | 'karma'

  SaleCreatedEvent({
    required this.saleId,
    required this.customerId,
    required this.totalAmount,
    this.paymentMethods,
    // String IDs (default to empty for backward compat)
    this.saleIdStr = '',
    this.customerIdStr = '',
    this.paidAmount = 0,
    this.paymentMethod = 'cash',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.saleCreated,
          aggregateId: saleId,
          aggregateType: 'Sale',
        );

  /// True if the sale has any unpaid debt.
  bool get hasDebt => (totalAmount - paidAmount) > 0.001;
}

class OrderCreatedEvent extends DomainEvent {
  final int orderId;
  final int customerId;
  final double totalAmount;
  final DateTime expectedDeliveryDate;

  // String UUID fields
  final String orderIdStr;
  final String customerIdStr;

  OrderCreatedEvent({
    required this.orderId,
    required this.customerId,
    required this.totalAmount,
    required this.expectedDeliveryDate,
    this.orderIdStr = '',
    this.customerIdStr = '',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.orderCreated,
          aggregateId: orderId,
          aggregateType: 'Order',
        );
}

class PaymentAddedEvent extends DomainEvent {
  final int paymentId;
  final int? referenceId; // saleId or orderId
  final int customerId;
  final double paidAmount;
  final String paymentMethod; // cash, card, transfer, check

  PaymentAddedEvent({
    required this.paymentId,
    this.referenceId,
    required this.customerId,
    required this.paidAmount,
    required this.paymentMethod,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.paymentAdded,
          aggregateId: paymentId,
          aggregateType: 'Payment',
        );
}

// Aliases for compatibility with event_publisher.dart
class PaymentRecordedEvent extends PaymentAddedEvent {
  PaymentRecordedEvent({
    required super.paymentId,
    required super.customerId,
    required double amount,
    super.occurredAt,
    super.metadata,
  }) : super(
          paidAmount: amount,
          paymentMethod: 'recorded',
        );
}

class PaymentFailedEvent extends DomainEvent {
  final int paymentId;
  final int customerId;
  final String reason;

  PaymentFailedEvent({
    required this.paymentId,
    required this.customerId,
    required this.reason,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.paymentReversed,
          aggregateId: paymentId,
          aggregateType: 'Payment',
        );
}

class RefundIssuedEvent extends DomainEvent {
  final int refundId;
  final int customerId;
  final double amount;
  final String refundReason;

  RefundIssuedEvent({
    required this.refundId,
    required this.customerId,
    required this.amount,
    required this.refundReason,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.paymentReversed,
          aggregateId: refundId,
          aggregateType: 'Refund',
        );
}

class OrderDeliveredEvent extends DomainEvent {
  final int orderId;
  final int customerId;
  final List<int>? stockChanges; // product IDs that were decreased

  // String UUID fields
  final String orderIdStr;
  final String customerIdStr;

  OrderDeliveredEvent({
    required this.orderId,
    required this.customerId,
    this.stockChanges,
    this.orderIdStr = '',
    this.customerIdStr = '',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.orderDelivered,
          aggregateId: orderId,
          aggregateType: 'Order',
        );
}

class StockChangedEvent extends DomainEvent {
  final int productId;
  final int quantityChange; // + for increase, - for decrease
  final String reason; // 'sale', 'order_delivery', 'adjustment', 'receipt'

  StockChangedEvent({
    required this.productId,
    required this.quantityChange,
    required this.reason,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.stockChanged,
          aggregateId: productId,
          aggregateType: 'Product',
        );
}

class SmsTriggeredEvent extends DomainEvent {
  final String phoneNumber;
  final String message;
  final String
      trigger; // 'order_created', 'order_ready', 'order_delivered', 'payment_reminder'

  SmsTriggeredEvent({
    required this.phoneNumber,
    required this.message,
    required this.trigger,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.smsTriggered,
          aggregateType: 'Sms',
        );
}

/// Tahsilat / genel ödeme alındığında yayınlanır.
/// SmsNotificationHandler tarafından dinlenir.
class CollectionRecordedEvent extends DomainEvent {
  /// Veritabanı için string UUID
  final String collectionIdStr;
  final String customerIdStr;
  final double amount;
  final double
      remainingDebt; // tahsilat sonrası kalan borç (0 ise tamamen kapanmış)

  CollectionRecordedEvent({
    required this.collectionIdStr,
    required this.customerIdStr,
    required this.amount,
    required this.remainingDebt,
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.collectionRecorded,
          aggregateType: 'Collection',
        );
}

class OrderPreparingEvent extends DomainEvent {
  final int orderId;
  final int customerId;
  final String orderIdStr;
  final String customerIdStr;

  OrderPreparingEvent({
    required this.orderId,
    required this.customerId,
    this.orderIdStr = '',
    this.customerIdStr = '',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.orderPreparing,
          aggregateId: orderId,
          aggregateType: 'Order',
        );
}

class OrderReadyEvent extends DomainEvent {
  final int orderId;
  final int customerId;
  final String orderIdStr;
  final String customerIdStr;

  OrderReadyEvent({
    required this.orderId,
    required this.customerId,
    this.orderIdStr = '',
    this.customerIdStr = '',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.orderReady,
          aggregateId: orderId,
          aggregateType: 'Order',
        );
}

class OrderCancelledEvent extends DomainEvent {
  final int orderId;
  final int customerId;
  final String orderIdStr;
  final String customerIdStr;

  OrderCancelledEvent({
    required this.orderId,
    required this.customerId,
    this.orderIdStr = '',
    this.customerIdStr = '',
    super.occurredAt,
    super.metadata,
  }) : super(
          type: EventType.orderCancelled,
          aggregateId: orderId,
          aggregateType: 'Order',
        );
}
