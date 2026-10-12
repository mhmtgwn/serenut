// lib/presentation/controllers/sms_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/services/debt_reminder_service.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/sms_provider.dart';

final smsControllerProvider = Provider<SmsController>((ref) {
  return SmsController(ref);
});

class SmsController {
  final Ref _ref;

  SmsController(this._ref);

  Future<List<SmsLogEntry>> loadInterruptedLogs() async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    await logRepo.resetStuckJobs();
    return logRepo.getUnknownLogs();
  }

  Future<({int sentCount, int failedCount})> resendInterruptedLogs(
    List<SmsLogEntry> logs,
  ) async {
    if (logs.isEmpty) return (sentCount: 0, failedCount: 0);

    final smsService = _ref.read(smsServiceProvider);
    final logRepo = _ref.read(smsLogRepositoryProvider);

    int sentCount = 0;
    int failedCount = 0;

    for (final log in logs) {
      await logRepo.updateStatus(log.id, SmsLogStatus.sending);
      final success = await smsService.sendSms(log.phone, log.message);
      if (success) {
        sentCount++;
        await logRepo
            .updateStatus(log.id, SmsLogStatus.sent, sentAt: DateTime.now())
            .onError((_, __) {});
      } else {
        failedCount++;
        await logRepo
            .updateStatus(
              log.id,
              SmsLogStatus.failed,
              errorMessage: 'Resend failed',
            )
            .onError((_, __) {});
      }
    }

    return (sentCount: sentCount, failedCount: failedCount);
  }

  Future<void> discardInterruptedLogs(List<SmsLogEntry> logs) async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    for (final log in logs) {
      await logRepo.updateStatus(log.id, SmsLogStatus.cancelled);
    }
  }

  Future<bool> hasSimPermissions() async {
    final smsService = _ref.read(smsServiceProvider);
    return smsService.hasSimPermissions();
  }

  Future<void> requestSimPermissions() async {
    final smsService = _ref.read(smsServiceProvider);
    await smsService.requestSimPermissions();
  }

  Future<List<CustomerEntity>> getAllCustomers() async {
    final customerRepo = await _ref.read(customerRepositoryProvider.future);
    return customerRepo.findAll();
  }

  Future<List<SmsLogEntry>> getActiveDebtCampaignLogs() async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    return logRepo.getActiveCampaignLogs();
  }

  Future<List<SmsLogEntry>> getRecentLogs({int limit = 100}) async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    return logRepo.getRecentLogs(limit: limit);
  }

  Future<void> cancelActiveCampaignLogs() async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    await logRepo.cancelActiveCampaignLogs();
  }

  Future<void> insertLog(SmsLogEntry entry) async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    await logRepo.insertLog(entry);
  }

  Future<void> updateLogStatus(
    String logId,
    SmsLogStatus status, {
    String? errorMessage,
    DateTime? sentAt,
  }) async {
    final logRepo = _ref.read(smsLogRepositoryProvider);
    await logRepo.updateStatus(
      logId,
      status,
      errorMessage: errorMessage,
      sentAt: sentAt,
    );
  }

  Future<DebtReminderService> getDebtReminderService() async {
    return _ref.read(debtReminderServiceProvider.future);
  }

  Future<int> sendBulkAnnouncement({
    required List<CustomerEntity> targets,
    required String confirmText,
  }) async {
    final smsService = _ref.read(smsServiceProvider);
    final logRepo = _ref.read(smsLogRepositoryProvider);

    int sentCount = 0;
    for (final customer in targets) {
      final message = confirmText.replaceAll('{customer}', customer.name);

      await Future.delayed(const Duration(milliseconds: 300));

      final logId = const Uuid().v4();
      await logRepo.insertLog(
        SmsLogEntry(
          id: logId,
          phone: customer.phone,
          eventType: 'bulk_announcement',
          message: message,
          createdAt: DateTime.now(),
        ),
      );

      smsService.sendSms(customer.phone, message).then((success) {
        logRepo
            .updateStatus(
              logId,
              success ? SmsLogStatus.sent : SmsLogStatus.failed,
              sentAt: success ? DateTime.now() : null,
              errorMessage: success ? null : 'Send failed',
            )
            .ignore();
      }).onError((e, _) {
        logRepo
            .updateStatus(
              logId,
              SmsLogStatus.failed,
              errorMessage: e.toString(),
            )
            .ignore();
      });
      sentCount++;
    }

    return sentCount;
  }

  Future<List<SmsLogEntry>> getFailedDebtCampaignLogs() async {
    final logRepository = _ref.read(smsLogRepositoryProvider);
    return logRepository.getFailedCampaignLogs();
  }

  Future<int> retryFailedDebtLogs(List<SmsLogEntry> failedLogs) async {
    final logRepository = _ref.read(smsLogRepositoryProvider);
    final smsService = _ref.read(smsServiceProvider);

    var sent = 0;
    for (final entry in failedLogs) {
      await logRepository.incrementRetry(entry.id);
      await logRepository.updateStatus(entry.id, SmsLogStatus.sending);
      final success = await smsService.sendSms(entry.phone, entry.message);
      await logRepository.updateStatus(
        entry.id,
        success ? SmsLogStatus.sent : SmsLogStatus.failed,
        sentAt: success ? DateTime.now() : null,
        errorMessage: success ? null : 'Retry failed',
      );
      if (success) sent++;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return sent;
  }
}
