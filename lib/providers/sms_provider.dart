// lib/providers/sms_provider.dart
// Serenut OS — SMS Service Riverpod Provider
// Created: 24 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/domain/notifications/sms_notification_handler.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/providers/event_providers.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:serenutos/infrastructure/services/sms_gateway_service.dart';
import 'package:serenutos/infrastructure/sync_v4/sms_cloud_outbox.dart';
import 'package:serenutos/infrastructure/sync_v4/whatsapp_notification_outbox.dart';

/// Builds SmsConfig from the current app Settings.
SmsConfig? _buildSmsConfig(Settings? settings) {
  if (settings == null) return null;
  if (!settings.smsEnabled) return null;

  return SmsConfig(
    provider: SmsProvider.sim,
    apiKey: '',
    username: '',
    sender:
        settings.businessPhone.isNotEmpty ? settings.businessPhone : 'SERENUT',
    simSubscriptionId: settings.smsSimSubscriptionId,
    monthlyLimit: settings.smsMonthlyLimit,
    sentThisMonth: settings.smsSentThisMonth,
    limitResetMonth: settings.smsLimitResetMonth,
  );
}

/// Provider for SmsService — rebuilds when settings change.
final smsServiceProvider = Provider<SmsService>((ref) {
  final settingsAsync = ref.watch(settingsNotifierProvider);
  final settings = settingsAsync.value;
  final config = _buildSmsConfig(settings);
  final apiClient = ref.watch(apiClientProvider);
  final cloudOutbox = SmsCloudOutbox(apiClient);

  // Delivery reports left by a previous offline session are retried whenever
  // the SMS service is reconstructed (login, settings refresh, app restart).
  cloudOutbox.flush();

  return SmsService(
    config: config,
    onSmsSent: () async {
      await ref.read(settingsNotifierProvider.notifier).incrementSmsCounter();
    },
    onSmsDispatched: (phone, message, status, errorMessage, messageId) async {
      await cloudOutbox.enqueue({
        'recipient': phone,
        'body': message,
        'status': status,
        'error_message': errorMessage,
        'channel': 'sms',
        'client_message_id': messageId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      final synced = await cloudOutbox.flush();
      if (synced == 0) {
        debugPrint('SMS teslim raporu çevrimdışı kuyruğa alındı: $messageId');
      }
    },
  );
});

/// Provider to expose pending SMS queue count.
final smsPendingCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(smsServiceProvider);
  return service.getPendingCount();
});

final smsGatewayServiceProvider = Provider<SmsGatewayService>((ref) {
  final service = SmsGatewayService(
    ref.watch(apiClientProvider),
    ref.watch(smsServiceProvider),
    ref.watch(deviceManagerProvider),
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

/// Provider for SmsLogRepository
final smsLogRepositoryProvider = Provider<SmsLogRepository>((ref) {
  return SmsLogRepository(DatabaseManager());
});

/// Provider for SmsNotificationHandler (eagerly listens to events)
final smsNotificationHandlerProvider =
    FutureProvider<SmsNotificationHandler>((ref) async {
  final eventPublisher = ref.watch(eventPublisherProvider);
  final customerRepo = await ref.watch(customerRepositoryProvider.future);
  final smsService = ref.watch(smsServiceProvider);
  final smsLogRepo = ref.watch(smsLogRepositoryProvider);
  final settings = ref.watch(settingsNotifierProvider).value;
  final whatsappOutbox =
      WhatsappNotificationOutbox(ref.watch(apiClientProvider));
  whatsappOutbox.flush();

  final handler = SmsNotificationHandler(
    eventPublisher: eventPublisher,
    customerRepository: customerRepo,
    smsService: smsService,
    smsLogRepository: smsLogRepo,
    onCloudNotification: ({
      required clientEventId,
      required eventType,
      required phone,
      required fallbackBody,
      required variables,
    }) async {
      final parameters = switch (eventType) {
        'sale_created' => [
            variables['customer'] ?? '',
            variables['id'] ?? '',
            variables['amount'] ?? '',
            variables['business'] ?? '',
          ],
        'debt_created' => [
            variables['customer'] ?? '',
            variables['id'] ?? '',
            variables['balance'] ?? '',
            variables['business'] ?? '',
          ],
        'collection_recorded' => [
            variables['customer'] ?? '',
            variables['amount'] ?? '',
            variables['debt'] ?? '',
            variables['business'] ?? '',
          ],
        'order_created' => [
            variables['customer'] ?? '',
            variables['id'] ?? '',
            variables['amount'] ?? '',
            variables['business'] ?? '',
          ],
        _ => [
            variables['customer'] ?? '',
            variables['id'] ?? '',
            variables['business'] ?? '',
          ],
      };
      await whatsappOutbox.enqueue({
        'client_event_id': clientEventId,
        'event_key': eventType,
        'recipient': phone,
        'parameters': parameters,
        'fallback_body': fallbackBody,
      });
      await whatsappOutbox.flush();
    },
  );

  if (settings != null) {
    handler.updateSettings(settings);
  }

  ref.onDispose(() {
    handler.dispose();
  });

  return handler;
});

/// Provider for list of SmsLogEntry from repository
final smsLogsProvider =
    FutureProvider.autoDispose<List<SmsLogEntry>>((ref) async {
  final repo = ref.watch(smsLogRepositoryProvider);
  return repo.getRecentLogs(limit: 100);
});
