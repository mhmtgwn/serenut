import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/notifications/template_resolver.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/infrastructure/repositories/sms_log_repository.dart';
import 'package:serenutos/infrastructure/sync_v4/whatsapp_notification_outbox.dart';
import 'package:uuid/uuid.dart';

/// Sonuç raporu modeli
class DebtReminderResult {
  final int eligibleCount;
  final int sentSmsCount;
  final int sentWhatsappCount;
  final int failedCount;
  final int skippedRecentCount;
  final List<String> errorMessages;

  const DebtReminderResult({
    this.eligibleCount = 0,
    this.sentSmsCount = 0,
    this.sentWhatsappCount = 0,
    this.failedCount = 0,
    this.skippedRecentCount = 0,
    this.errorMessages = const [],
  });
}

/// Hem SMS hem WhatsApp kanalları üzerinden otomatik ve manuel
/// bakiye/borç hatırlatmalarını yöneten merkezi servis.
class DebtReminderService {
  final ICustomerRepository _customerRepository;
  final SmsLogRepository _smsLogRepository;
  final SmsService _smsService;
  final WhatsappNotificationOutbox _whatsappOutbox;
  final TemplateResolver _templateResolver;

  DebtReminderService({
    required ICustomerRepository customerRepository,
    required SmsLogRepository smsLogRepository,
    required SmsService smsService,
    required WhatsappNotificationOutbox whatsappOutbox,
    TemplateResolver templateResolver = const TemplateResolver(),
  })  : _customerRepository = customerRepository,
        _smsLogRepository = smsLogRepository,
        _smsService = smsService,
        _whatsappOutbox = whatsappOutbox,
        _templateResolver = templateResolver;

  /// Borçlu müşterileri filtreler:
  /// - Bakiyesi negatif olanlar (borçlu)
  /// - Borcu >= settings.smsAutoDebtReminderMinAmount olanlar
  /// - Telefon numarası tanımlı olanlar
  /// - Son [repeatDays] gün içinde hatırlatma almamış olanlar (opsiyonel filtre)
  Future<List<CustomerEntity>> getEligibleDebtors({
    required Settings settings,
    bool checkRepeatInterval = true,
  }) async {
    final allCustomers = await _customerRepository.findAll();
    final minAmount = settings.smsAutoDebtReminderMinAmount;
    final repeatDays = settings.autoDebtReminderRepeatDays;

    final candidates = allCustomers.where((c) {
      final phone = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.isEmpty) return false;
      if (c.balance >= -0.01) return false;
      if (c.balance.abs() < minAmount) return false;
      return true;
    }).toList();

    if (!checkRepeatInterval || repeatDays <= 0) {
      return candidates;
    }

    final now = DateTime.now();
    final filtered = <CustomerEntity>[];
    for (final customer in candidates) {
      final lastDate = await _smsLogRepository.getLastReminderDate(customer.phone);
      if (lastDate != null) {
        final diffDays = now.difference(lastDate).inDays;
        if (diffDays < repeatDays) {
          continue; // Henüz tekrar süresi dolmamış
        }
      }
      filtered.add(customer);
    }
    return filtered;
  }

  /// Tek bir müşteriye belirtilen veya ayarlardaki kanallar üzerinden hatırlatma gönderir.
  Future<({bool smsSuccess, bool waSuccess})> sendReminderToCustomer({
    required CustomerEntity customer,
    required Settings settings,
    String? channelOverride, // 'sms', 'whatsapp', 'both'
  }) async {
    final channel = channelOverride ?? settings.autoDebtReminderChannel;
    final shouldSendSms = channel == 'sms' || channel == 'both';
    final shouldSendWa = channel == 'whatsapp' || channel == 'both';

    final vars = SmsTemplateVars.forBalanceReminder(
      customerName: customer.name,
      balance: customer.balance.abs(),
      businessName: settings.businessName,
      currency: settings.currency,
    );

    var smsOk = false;
    var waOk = false;

    // 1. WhatsApp Kanalı
    if (shouldSendWa) {
      try {
        final waText = _templateResolver.resolveWhatsApp(
          eventType: kSmsEventBalanceReminder,
          settings: settings,
          vars: vars,
        );

        if (waText != null && waText.trim().isNotEmpty) {
          final clientId = const Uuid().v4();
          await _whatsappOutbox.enqueue({
            'client_event_id': clientId,
            'event_key': kSmsEventBalanceReminder,
            'recipient': customer.phone,
            'parameters': [
              customer.name,
              vars['balance'] ?? '',
              settings.businessName,
            ],
            'fallback_body': waText,
          });
          await _whatsappOutbox.flush();

          // Log kaydı ekle (tekrar hatırlatma takip mekanizması için)
          await _smsLogRepository.insertLog(
            SmsLogEntry(
              id: 'wa_${const Uuid().v4()}',
              phone: customer.phone,
              eventType: kSmsEventBalanceReminder,
              message: waText,
              createdAt: DateTime.now(),
              sentAt: DateTime.now(),
              status: SmsLogStatus.sent,
            ),
          );
          waOk = true;
        }
      } catch (e) {
        debugPrint('⚠️ DebtReminderService WhatsApp gönderim hatası: $e');
      }
    }

    // 2. SMS Kanalı
    if (shouldSendSms) {
      try {
        final smsText = _templateResolver.resolveSms(
          eventType: kSmsEventBalanceReminder,
          settings: settings,
          vars: vars,
        );

        if (smsText != null && smsText.trim().isNotEmpty) {
          final logId = const Uuid().v4();
          await _smsLogRepository.insertLog(
            SmsLogEntry(
              id: logId,
              phone: customer.phone,
              eventType: kSmsEventBalanceReminder,
              message: smsText,
              createdAt: DateTime.now(),
              status: SmsLogStatus.pending,
            ),
          );

          final sent = await _smsService.sendSms(customer.phone, smsText);
          await _smsLogRepository.updateStatus(
            logId,
            sent ? SmsLogStatus.sent : SmsLogStatus.failed,
            sentAt: sent ? DateTime.now() : null,
            errorMessage: sent ? null : 'SMS iletim hatası',
          );
          smsOk = sent;
        }
      } catch (e) {
        debugPrint('⚠️ DebtReminderService SMS gönderim hatası: $e');
      }
    }

    return (smsSuccess: smsOk, waSuccess: waOk);
  }

  /// Toplu veya seçili müşterilere hatırlatma gönderimi
  Future<DebtReminderResult> sendBulkReminders({
    required List<CustomerEntity> customers,
    required Settings settings,
    String? channelOverride,
    void Function(int current, int total)? onProgress,
  }) async {
    var sentSms = 0;
    var sentWa = 0;
    var failed = 0;
    final errors = <String>[];

    for (var i = 0; i < customers.length; i++) {
      final customer = customers[i];
      try {
        final res = await sendReminderToCustomer(
          customer: customer,
          settings: settings,
          channelOverride: channelOverride,
        );
        if (res.smsSuccess) sentSms++;
        if (res.waSuccess) sentWa++;
        if (!res.smsSuccess && !res.waSuccess) failed++;
      } catch (e) {
        failed++;
        errors.add('${customer.name}: $e');
      }
      onProgress?.call(i + 1, customers.length);
    }

    return DebtReminderResult(
      eligibleCount: customers.length,
      sentSmsCount: sentSms,
      sentWhatsappCount: sentWa,
      failedCount: failed,
      errorMessages: errors,
    );
  }

  /// Otomatik arka plan / başlangıç kontrolü
  /// Günde en fazla 1 kez çalışır ve ayarlar açıksa borçlulara gönderir.
  Future<DebtReminderResult?> runAutoDebtReminderCheck({
    required Settings settings,
    required Future<void> Function(Settings updated) onSettingsUpdate,
  }) async {
    if (!settings.smsAutoDebtReminderEnabled) return null;

    final now = DateTime.now();
    final lastRun = settings.autoDebtReminderLastRun;
    if (lastRun != null) {
      // Bugün zaten çalışmışsa tekrar çalışma (aynı takvim günü veya 20 saat içi)
      final sameDay = lastRun.year == now.year &&
          lastRun.month == now.month &&
          lastRun.day == now.day;
      if (sameDay) return null;
    }

    final eligibleDebtors = await getEligibleDebtors(
      settings: settings,
      checkRepeatInterval: true,
    );

    if (eligibleDebtors.isEmpty) {
      await onSettingsUpdate(settings.copyWith(autoDebtReminderLastRun: now));
      return const DebtReminderResult();
    }

    final result = await sendBulkReminders(
      customers: eligibleDebtors,
      settings: settings,
    );

    await onSettingsUpdate(settings.copyWith(autoDebtReminderLastRun: now));
    return result;
  }
}
