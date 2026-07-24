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

  return SmsService(
    config: config,
    onSmsSent: () async {
      await ref.read(settingsNotifierProvider.notifier).incrementSmsCounter();
    },
    onSmsDispatched: (phone, message, status, errorMessage, messageId) async {
      try {
        await apiClient.send(
          'POST',
          '/api/v1/notifications/sync-local',
          body: {
            'recipient': phone,
            'body': message,
            'status': status,
            'error_message': errorMessage,
            'channel': 'sms',
            'client_message_id': messageId,
            'created_at': DateTime.now().toIso8601String(),
          },
        );
      } catch (e) {
        // Silently catch sync errors to prevent blocking the UI/operation
        debugPrint('❌ SMS Sync failed (usually offline): $e');
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

  final handler = SmsNotificationHandler(
    eventPublisher: eventPublisher,
    customerRepository: customerRepo,
    smsService: smsService,
    smsLogRepository: smsLogRepo,
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
