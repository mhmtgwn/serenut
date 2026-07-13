// lib/domain/events/event_publisher.dart
// PHASE 0 Day 3 - Event System Implementation
// Domain event publishing for notifications + audit trail
// Generated: 21 Jun 2026

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/events/domain_event.dart';

typedef EventListener<T extends DomainEvent> = void Function(T event);

/// Central event publisher for domain events
/// 
/// Responsibilities:
/// - Collect events from TransactionEngine
/// - Publish to listeners (SMS, webhooks, auth changes)
/// - Fire-and-forget (no blocking)
/// - Audit trail (all events logged)
/// 
/// Usage:
/// ```dart
/// final publisher = EventPublisher();
/// 
/// // Subscribe to events
/// publisher.subscribe<SaleCreatedEvent>((event) {
///   print('Sale created: ${event.saleId}');
///   // Send SMS, update balance, etc.
/// });
/// 
/// // Publish event
/// publisher.publish(SaleCreatedEvent(saleId: 123, ...));
/// ```
class EventPublisher {
  static final _instance = EventPublisher._();
  factory EventPublisher() => _instance;
  EventPublisher._();

  // Event listeners by type
  final Map<Type, List<Function>> _listeners = {};
  
  // Event history (audit trail)
  final List<DomainEvent> _eventHistory = [];
  final StreamController<DomainEvent> _eventStreamController = StreamController.broadcast();

  /// Subscribe to events of a specific type
  void subscribe<T extends DomainEvent>(EventListener<T> listener) {
    _listeners.putIfAbsent(T, () => []).add(listener);
  }

  /// Unsubscribe from events
  void unsubscribe<T extends DomainEvent>(EventListener<T> listener) {
    final listeners = _listeners[T];
    if (listeners != null) {
      listeners.remove(listener);
    }
  }

  /// Publish event to all listeners (fire-and-forget)
  void publish<T extends DomainEvent>(T event) {
    final deferred = Zone.current[#deferred_events] as List<DomainEvent>?;
    if (deferred != null) {
      deferred.add(event);
      // print('📥 Event deferred (inside transaction): ${event.runtimeType}');
      return;
    }

    // Add to history (audit trail) with max capacity 200
    _eventHistory.add(event);
    if (_eventHistory.length > 200) {
      _eventHistory.removeAt(0);
    }
    
    // Broadcast to stream
    _eventStreamController.add(event);
    
    // Call listeners (async, no blocking)
    Future.microtask(() {
      final listenersByT = _listeners[T];
      if (listenersByT != null) {
        for (final listener in listenersByT) {
          try {
            (listener)(event);
          } catch (e, stack) {
            debugPrint('Error in event listener for ${event.runtimeType}: $e\n$stack');
          }
        }
      }

      if (event.runtimeType != T) {
        final listenersByRuntimeType = _listeners[event.runtimeType];
        if (listenersByRuntimeType != null) {
          for (final listener in listenersByRuntimeType) {
            try {
              (listener)(event);
            } catch (e, stack) {
              debugPrint('Error in event listener for ${event.runtimeType}: $e\n$stack');
            }
          }
        }
      }
    });

    // Log to console (debug)
    // print('📢 Event published: ${event.runtimeType}');
  }

  /// Get event stream (for reactive UI)
  Stream<DomainEvent> get eventStream => _eventStreamController.stream;

  /// Get event history
  List<DomainEvent> getEventHistory() => List.unmodifiable(_eventHistory);

  /// Get events of specific type from history
  List<T> getEventsByType<T extends DomainEvent>() {
    return _eventHistory.whereType<T>().toList();
  }

  /// Clear event history (test purposes only)
  void clearHistory() {
    _eventHistory.clear();
  }

  /// Clear all listeners (test purposes only)
  void clearListeners() {
    _listeners.clear();
  }

  /// Dispose
  void dispose() {
    _eventStreamController.close();
    _listeners.clear();
    _eventHistory.clear();
  }
}

/// ════════════════════════════════════════════════════════════
/// Event Handler Services
/// ════════════════════════════════════════════════════════════

/// Handles SaleCreatedEvent
/// Updates customer balance, sends SMS
class SaleCreatedEventHandler {
  final EventPublisher _eventPublisher;

  SaleCreatedEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<SaleCreatedEvent>(_onSaleCreated);
  }

  Future<void> _onSaleCreated(SaleCreatedEvent event) async {
    // print('🛍️ Sale created: ${event.saleId}');
    // print('   Customer: ${event.customerId}');
    // print('   Amount: ${event.totalAmount} TL');
    // print('   Payment methods: ${event.paymentMethods}');

    // TODO: Send SMS to customer
    // TODO: Send notification to customers
    // TODO: Update inventory
  }
}

/// Handles OrderCreatedEvent
class OrderCreatedEventHandler {
  final EventPublisher _eventPublisher;

  OrderCreatedEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<OrderCreatedEvent>(_onOrderCreated);
  }

  Future<void> _onOrderCreated(OrderCreatedEvent event) async {
    // print('📦 Order created: ${event.orderId}');
    // print('   Customer: ${event.customerId}');
    // print('   Amount: ${event.totalAmount} TL');
    // print('   Expected delivery: ${event.expectedDeliveryDate}');

    // TODO: Send SMS to customer with tracking
    // TODO: Update manager dashboard
  }
}

/// Handles OrderDeliveredEvent
class OrderDeliveredEventHandler {
  final EventPublisher _eventPublisher;

  OrderDeliveredEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<OrderDeliveredEvent>(_onOrderDelivered);
  }

  Future<void> _onOrderDelivered(OrderDeliveredEvent event) async {
    // print('✅ Order delivered: ${event.orderId}');
    // print('   Stock changes: ${event.stockChanges?.length ?? 0} items');

    // TODO: Update inventory
    // TODO: Send SMS confirmation
    // TODO: Record financial transaction
  }
}

/// Handles PaymentRecordedEvent
class PaymentRecordedEventHandler {
  final EventPublisher _eventPublisher;

  PaymentRecordedEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<PaymentRecordedEvent>(_onPaymentRecorded);
  }

  Future<void> _onPaymentRecorded(PaymentRecordedEvent event) async {
    // print('💳 Payment recorded: ${event.paymentId}');
    // print('   Amount: ${event.paidAmount} TL');
    // print('   Method: ${event.paymentMethod}');

    // TODO: Update customer balance
    // TODO: Send SMS confirmation
    // TODO: Update reports
  }
}

/// Handles PaymentFailedEvent
class PaymentFailedEventHandler {
  final EventPublisher _eventPublisher;

  PaymentFailedEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<PaymentFailedEvent>(_onPaymentFailed);
  }

  Future<void> _onPaymentFailed(PaymentFailedEvent event) async {
    // print('❌ Payment failed: ${event.paymentId}');
    // print('   Reason: ${event.reason}');

    // TODO: Alert manager
    // TODO: Log incident
    // TODO: Notify customer
  }
}

/// Handles RefundIssuedEvent
class RefundIssuedEventHandler {
  final EventPublisher _eventPublisher;

  RefundIssuedEventHandler(this._eventPublisher) {
    _eventPublisher.subscribe<RefundIssuedEvent>(_onRefundIssued);
  }

  Future<void> _onRefundIssued(RefundIssuedEvent event) async {
    // print('🔄 Refund issued: ${event.refundId}');
    // print('   Amount: ${event.amount} TL');
    // print('   Reference: ${event.refundReason}');

    // TODO: Update customer balance
    // TODO: Cancel related orders
    // TODO: Send SMS confirmation
  }
}

/// ════════════════════════════════════════════════════════════
/// Initialize all event handlers
/// ════════════════════════════════════════════════════════════

void initializeEventHandlers(EventPublisher publisher) {
  SaleCreatedEventHandler(publisher);
  OrderCreatedEventHandler(publisher);
  OrderDeliveredEventHandler(publisher);
  PaymentRecordedEventHandler(publisher);
  PaymentFailedEventHandler(publisher);
  RefundIssuedEventHandler(publisher);
  
  // print('✅ Event handlers initialized');
}
