// lib/providers/sms_provider.dart
// Serenut POS — SMS Service Riverpod Provider
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
import 'package:serenutos/domain/models/sms_log_entry.dart';

/// Builds SmsConfig from the current app Settings.
SmsConfig? _buildSmsConfig(Settings? settings) {
  if (settings == null) return null;
  if (!settings.smsEnabled) return null;

  final provider = settings.smsProvider?.toLowerCase();
  SmsProvider smsProvider;
  switch (provider) {
    case 'twilio':
      smsProvider = SmsProvider.twilio;
    case 'netgsm':
      smsProvider = SmsProvider.netgsm;
    default:
      smsProvider = SmsProvider.none;
  }

  if (smsProvider == SmsProvider.none) return null;
  if (settings.smsApiKey == null || settings.smsApiKey!.isEmpty) return null;

  return SmsConfig(
    provider:  smsProvider,
    apiKey:    settings.smsApiKey!,
    username:  settings.smsApiKey!.split(':').first,  // Netgsm: apiKey IS the key; Twilio: accountSid:authToken
    sender:    settings.businessPhone.isNotEmpty ? settings.businessPhone : 'SERENUT',
    apiSecret: smsProvider == SmsProvider.twilio
        ? (settings.smsApiKey!.contains(':')
            ? settings.smsApiKey!.split(':').last
            : null)
        : null,
  );
}

/// Provider for SmsService — rebuilds when settings change.
final smsServiceProvider = Provider<SmsService>((ref) {
  final settingsAsync = ref.watch(settingsNotifierProvider);
  final settings = settingsAsync.value;
  final config   = _buildSmsConfig(settings);
  return SmsService(config: config);
});

/// Provider to expose pending SMS queue count.
final smsPendingCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(smsServiceProvider);
  return service.getPendingCount();
});

/// Provider for SmsLogRepository
final smsLogRepositoryProvider = Provider<SmsLogRepository>((ref) {
  return SmsLogRepository(DatabaseManager());
});

/// Provider for SmsNotificationHandler (eagerly listens to events)
final smsNotificationHandlerProvider = FutureProvider<SmsNotificationHandler>((ref) async {
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
final smsLogsProvider = FutureProvider.autoDispose<List<SmsLogEntry>>((ref) async {
  final repo = ref.watch(smsLogRepositoryProvider);
  return repo.getRecentLogs(limit: 100);
});
