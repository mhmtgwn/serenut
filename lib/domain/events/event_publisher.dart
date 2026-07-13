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
