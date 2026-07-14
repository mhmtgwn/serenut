// lib/domain/notifications/sms_notification_handler.dart
// Serenut POS — SMS Notification Handler (Event Subscriber)
//
// Responsibilities:
//   - Subscribe to domain events (SaleCreatedEvent, CollectionRecordedEvent)
//   - Look up customer data from repository (NOT from UI)
//   - Resolve SMS template via TemplateResolver
//   - Send SMS via SmsService
//   - Log result via SmsLogRepository
//
// Design:
//   - SalesService / PaymentService know NOTHING about SMS
//   - UI layer knows NOTHING about SMS
//   - All side-effects live here
//
// Created: 01 Jul 2026

import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/events/domain_event.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';

class SmsNotificationHandler {
  final EventPublisher _eventPublisher;
  final ICustomerRepository _customerRepository;
  final SmsService _smsService;
  final SmsLogRepository _smsLogRepository;
  final TemplateResolver _templateResolver;

  // Listeners kept for unsubscribe on dispose
  late final void Function(SaleCreatedEvent) _saleListener;
  late final void Function(CollectionRecordedEvent) _collectionListener;
  late final void Function(OrderCreatedEvent) _orderCreatedListener;
  late final void Function(OrderDeliveredEvent) _orderDeliveredListener;
  late final void Function(OrderPreparingEvent) _orderPreparingListener;
  late final void Function(OrderReadyEvent) _orderReadyListener;
  late final void Function(OrderCancelledEvent) _orderCancelledListener;

  SmsNotificationHandler({
    required EventPublisher eventPublisher,
    required ICustomerRepository customerRepository,
    required SmsService smsService,
    required SmsLogRepository smsLogRepository,
    TemplateResolver? templateResolver,
  })  : _eventPublisher = eventPublisher,
        _customerRepository = customerRepository,
        _smsService = smsService,
        _smsLogRepository = smsLogRepository,
        _templateResolver = templateResolver ?? const TemplateResolver() {
    _saleListener = _onSaleCreated;
    _collectionListener = _onCollectionRecorded;
    _orderCreatedListener = _onOrderCreated;
    _orderDeliveredListener = _onOrderDelivered;
    _orderPreparingListener = _onOrderPreparing;
    _orderReadyListener = _onOrderReady;
    _orderCancelledListener = _onOrderCancelled;

    _eventPublisher.subscribe<SaleCreatedEvent>(_saleListener);
    _eventPublisher.subscribe<CollectionRecordedEvent>(_collectionListener);
    _eventPublisher.subscribe<OrderCreatedEvent>(_orderCreatedListener);
    _eventPublisher.subscribe<OrderDeliveredEvent>(_orderDeliveredListener);
    _eventPublisher.subscribe<OrderPreparingEvent>(_orderPreparingListener);
    _eventPublisher.subscribe<OrderReadyEvent>(_orderReadyListener);
    _eventPublisher.subscribe<OrderCancelledEvent>(_orderCancelledListener);
  }

  // ── Event Handlers ──────────────────────────────────────────────────────────

  void _onSaleCreated(SaleCreatedEvent event) {
    if (event.customerIdStr.isEmpty) return;
    // Fire-and-forget: async work happens outside the event dispatch cycle
    _handleSaleCreated(event).ignore();
  }

  void _onCollectionRecorded(CollectionRecordedEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleCollectionRecorded(event).ignore();
  }

  void _onOrderCreated(OrderCreatedEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleOrderCreated(event).ignore();
  }

  void _onOrderDelivered(OrderDeliveredEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleOrderDelivered(event).ignore();
  }

  void _onOrderPreparing(OrderPreparingEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleOrderPreparing(event).ignore();
  }

  void _onOrderReady(OrderReadyEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleOrderReady(event).ignore();
  }

  void _onOrderCancelled(OrderCancelledEvent event) {
    if (event.customerIdStr.isEmpty) return;
    _handleOrderCancelled(event).ignore();
  }

  // ── Async Handlers ─────────────────────────────────────────────────────────

  Future<void> _handleSaleCreated(SaleCreatedEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      final currency = settings.currency;
      final business = settings.businessName;

      // ── 'sale_created' template ──
      _sendIfEnabled(
        eventType: kSmsEventSaleCreated,
        settings: settings,
        phone: customer.phone,
        vars: SmsTemplateVars.forSale(
          customerName: customer.name,
          totalAmount: event.totalAmount,
          paidAmount: event.paidAmount,
          saleId:
              event.saleIdStr.isNotEmpty ? event.saleIdStr : '${event.saleId}',
          businessName: business,
          currency: currency,
        ),
      );

      // ── 'debt_created' template — only for debt/karma sales ──
      if (event.hasDebt) {
        _sendIfEnabled(
          eventType: kSmsEventDebtCreated,
          settings: settings,
          phone: customer.phone,
          vars: SmsTemplateVars.forDebt(
            customerName: customer.name,
            totalAmount: event.totalAmount,
            paidAmount: event.paidAmount,
            saleId: event.saleIdStr.isNotEmpty
                ? event.saleIdStr
                : '${event.saleId}',
            businessName: business,
            currentBalance: customer.balance,
            currency: currency,
          ),
        );
      }
    } catch (e) {
      // SMS handler errors must NEVER bubble up to crash the app
      _log('⚠️ SmsNotificationHandler._handleSaleCreated error: $e');
    }
  }

  Future<void> _handleCollectionRecorded(CollectionRecordedEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventCollectionRecorded,
        settings: settings,
        phone: customer.phone,
        vars: SmsTemplateVars.forCollection(
          customerName: customer.name,
          collectedAmount: event.amount,
          remainingDebt: event.remainingDebt,
          transactionId: event.collectionIdStr,
          businessName: settings.businessName,
          currency: settings.currency,
        ),
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleCollectionRecorded error: $e');
    }
  }

  Future<void> _handleOrderCreated(OrderCreatedEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventOrderCreated,
        settings: settings,
        phone: customer.phone,
        vars: SmsTemplateVars.forOrder(
          customerName: customer.name,
          totalAmount: event.totalAmount,
          orderId: event.orderIdStr.isNotEmpty
              ? event.orderIdStr
              : '${event.orderId}',
          businessName: settings.businessName,
          currency: settings.currency,
        ),
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleOrderCreated error: $e');
    }
  }

  Future<void> _handleOrderDelivered(OrderDeliveredEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventOrderDelivered,
        settings: settings,
        phone: customer.phone,
        vars: {
          'customer': customer.name,
          'id': event.orderIdStr.isNotEmpty
              ? event.orderIdStr
              : '${event.orderId}',
          'business': settings.businessName,
          'date': _todayStr(),
        },
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleOrderDelivered error: $e');
    }
  }

  Future<void> _handleOrderPreparing(OrderPreparingEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventOrderPreparing,
        settings: settings,
        phone: customer.phone,
        vars: {
          'customer': customer.name,
          'id': event.orderIdStr.isNotEmpty
              ? event.orderIdStr
              : '${event.orderId}',
          'business': settings.businessName,
          'date': _todayStr(),
        },
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleOrderPreparing error: $e');
    }
  }

  Future<void> _handleOrderReady(OrderReadyEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventOrderReady,
        settings: settings,
        phone: customer.phone,
        vars: {
          'customer': customer.name,
          'id': event.orderIdStr.isNotEmpty
              ? event.orderIdStr
              : '${event.orderId}',
          'business': settings.businessName,
          'date': _todayStr(),
        },
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleOrderReady error: $e');
    }
  }

  Future<void> _handleOrderCancelled(OrderCancelledEvent event) async {
    try {
      final settings = await _getCurrentSettings();
      if (settings == null) return;

      final customer = await _customerRepository.findById(event.customerIdStr);
      if (customer == null || customer.phone.isEmpty) return;

      _sendIfEnabled(
        eventType: kSmsEventOrderCancelled,
        settings: settings,
        phone: customer.phone,
        vars: {
          'customer': customer.name,
          'id': event.orderIdStr.isNotEmpty
              ? event.orderIdStr
              : '${event.orderId}',
          'business': settings.businessName,
          'date': _todayStr(),
        },
      );
    } catch (e) {
      _log('⚠️ SmsNotificationHandler._handleOrderCancelled error: $e');
    }
  }

  static String _todayStr() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
  }

  // ── Send + Log ─────────────────────────────────────────────────────────────

  void _sendIfEnabled({
    required String eventType,
    required Settings settings,
    required String phone,
    required Map<String, String> vars,
  }) {
    final message = _templateResolver.resolve(
      eventType: eventType,
      settings: settings,
      vars: vars,
    );
    if (message == null || message.trim().isEmpty) return;

    _sendAndLog(phone: phone, eventType: eventType, message: message);
  }

  void _sendAndLog({
    required String phone,
    required String eventType,
    required String message,
  }) {
    final logId = const Uuid().v4();
    final entry = SmsLogEntry(
      id: logId,
      phone: phone,
      eventType: eventType,
      message: message,
      createdAt: DateTime.now(),
    );

    // Insert log entry (pending)
    _smsLogRepository.insertLog(entry).ignore();

    // Send SMS
    _smsService.sendSms(phone, message).then((success) {
      // Update log status
      _smsLogRepository
          .updateStatus(
            logId,
            success ? SmsLogStatus.sent : SmsLogStatus.failed,
            sentAt: success ? DateTime.now() : null,
            errorMessage: success ? null : 'Send failed',
          )
          .ignore();
    }).onError((e, _) {
      _smsLogRepository
          .updateStatus(
            logId,
            SmsLogStatus.failed,
            errorMessage: e.toString(),
          )
          .ignore();
    });
  }

  // ── Settings Access ────────────────────────────────────────────────────────
  // Settings are passed at handler initialization. For live updates,
  // the provider layer recreates this handler when settings change.
  Settings? _cachedSettings;

  void updateSettings(Settings? settings) {
    _cachedSettings = settings;
  }

  Future<Settings?> _getCurrentSettings() async {
    return _cachedSettings;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  void dispose() {
    _eventPublisher.unsubscribe<SaleCreatedEvent>(_saleListener);
    _eventPublisher.unsubscribe<CollectionRecordedEvent>(_collectionListener);
    _eventPublisher.unsubscribe<OrderCreatedEvent>(_orderCreatedListener);
    _eventPublisher.unsubscribe<OrderDeliveredEvent>(_orderDeliveredListener);
    _eventPublisher.unsubscribe<OrderPreparingEvent>(_orderPreparingListener);
    _eventPublisher.unsubscribe<OrderReadyEvent>(_orderReadyListener);
    _eventPublisher.unsubscribe<OrderCancelledEvent>(_orderCancelledListener);
  }

  void _log(String msg) {
    // ignore: avoid_print
    // print(msg);
  }
}
