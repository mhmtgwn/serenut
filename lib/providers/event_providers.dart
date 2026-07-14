// lib/providers/event_providers.dart
// PHASE 0 Day 3 - Event System Riverpod Integration
// Providers for EventPublisher and event streams
// Generated: 21 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/events/domain_event.dart';

/// ════════════════════════════════════════════════════════════
/// EventPublisher Provider
/// ════════════════════════════════════════════════════════════
///
/// Provides singleton instance of EventPublisher
///
/// Usage:
/// ```dart
/// final publisher = ref.watch(eventPublisherProvider);
/// publisher.publish(SaleCreatedEvent(...));
/// ```

/// EventPublisher singleton provider
///
/// Initialized once and reused across the app
/// Safe for concurrent access
final eventPublisherProvider = Provider<EventPublisher>((ref) {
  final publisher = EventPublisher();
  // Handlers will be initialized elsewhere or lazily
  return publisher;
});

/// Event stream provider
///
/// Returns a stream of all domain events
/// Useful for reactive UI updates
///
/// Usage:
/// ```dart
/// final eventStream = ref.watch(eventStreamProvider);
/// eventStream.when(
///   data: (event) => Text('Event: ${event.runtimeType}'),
///   loading: () => CircularProgressIndicator(),
///   error: (err, st) => Text('Error: $err'),
/// );
/// ```
final eventStreamProvider = StreamProvider<DomainEvent>((ref) {
  final publisher = ref.watch(eventPublisherProvider);
  return publisher.eventStream;
});

/// Event history provider
///
/// Returns audit trail of all published events
/// Useful for debugging and analytics
///
/// Usage:
/// ```dart
/// final history = ref.watch(eventHistoryProvider);
/// for (final event in history) {
///   print('${event.runtimeType} published at ${event.timestamp}');
/// }
/// ```
final eventHistoryProvider = Provider<List<DomainEvent>>((ref) {
  final publisher = ref.watch(eventPublisherProvider);
  return publisher.getEventHistory();
});

/// Last event provider
///
/// Returns the most recently published event
/// Useful for UI notifications
///
/// Usage:
/// ```dart
/// final lastEventAsync = ref.watch(lastEventProvider);
/// lastEventAsync.whenData((event) {
///   if (event is SaleCreatedEvent) {
///     showNotification('Sale created: \$${event.totalAmount}');
///   }
/// });
/// ```
final lastEventProvider = FutureProvider<DomainEvent?>((ref) async {
  final history = ref.watch(eventHistoryProvider);
  return history.isEmpty ? null : history.last;
});

/// ════════════════════════════════════════════════════════════
/// Example Usage in Widgets
/// ════════════════════════════════════════════════════════════
///
/// Listen to events in real-time:
/// ```dart
/// class EventListener extends ConsumerStatefulWidget {
///   @override
///   ConsumerState<EventListener> createState() => _EventListenerState();
/// }
///
/// class _EventListenerState extends ConsumerState<EventListener> {
///   @override
///   void initState() {
///     super.initState();
///     // Subscribe to specific event
///     final publisher = ref.read(eventPublisherProvider);
///     publisher.subscribe<SaleCreatedEvent>((event) {
///       ScaffoldMessenger.of(context).showSnackBar(
///         SnackBar(text: 'Sale created!'),
///       );
///     });
///   }
///
///   @override
///   Widget build(BuildContext context) {
///     final eventStream = ref.watch(eventStreamProvider);
///     return eventStream.when(
///       data: (event) => Text('Event: ${event.runtimeType}'),
///       loading: () => CircularProgressIndicator(),
///       error: (err, st) => Text('Error: $err'),
///     );
///   }
/// }
/// ```
///
/// Publish events from services:
/// ```dart
/// class SalesService {
///   final EventPublisher _publisher;
///
///   SalesService(this._publisher);
///
///   Future<void> createSale(Sale sale) async {
///     // Create sale in database
///     await _repo.create(sale);
///
///     // Publish event
///     _publisher.publish(SaleCreatedEvent(
///       saleId: sale.id,
///       customerId: sale.customerId,
///       totalAmount: sale.totalAmount,
///       timestamp: DateTime.now(),
///     ));
///   }
/// }
/// ```
///
/// ════════════════════════════════════════════════════════════
