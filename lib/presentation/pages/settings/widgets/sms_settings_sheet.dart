// lib/presentation/pages/settings/widgets/sms_settings_sheet.dart
// Redesigned SMS Settings Sheet with Premium UI/UX & theme tokens (Sprint 10)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sms_provider.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart'; // FullScreenSettingsPage
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart'; // POSColors & AppSpacing

class SmsSettingsSheet extends ConsumerStatefulWidget {
  final Settings settings;

  const SmsSettingsSheet({required this.settings, super.key});

  @override
  ConsumerState<SmsSettingsSheet> createState() => _SmsSettingsSheetState();
}

class _SmsSettingsSheetState extends ConsumerState<SmsSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late List<Map<String, dynamic>> listTemplates;
  late final TextEditingController apiKeyCtrl;
  late final TextEditingController minAmountCtrl;
  late final TextEditingController ageDaysCtrl;
  late final TextEditingController limitCtrl;
  late bool smsEnabled;
  late String selectedProvider;
  late bool autoDebtReminderEnabled;
  bool isSendingBulk = false;

  // SIM SMS Specific States
  List<Map<String, dynamic>> simCards = [];
  bool hasPermissions = false;
  int? selectedSubscriptionId;
  List<SmsLogEntry> interruptedLogs = [];

  @override
  void initState() {
    super.initState();
    listTemplates = _parseFlexibleSmsTemplates(widget.settings.smsTemplate);
    apiKeyCtrl = TextEditingController(text: widget.settings.smsApiKey ?? '');
    smsEnabled = widget.settings.smsEnabled;
    selectedProvider = widget.settings.smsProvider ?? 'sim';
    autoDebtReminderEnabled = widget.settings.smsAutoDebtReminderEnabled;
    minAmountCtrl = TextEditingController(text: widget.settings.smsAutoDebtReminderMinAmount.toStringAsFixed(0));
    ageDaysCtrl = TextEditingController(text: widget.settings.smsAutoDebtReminderDays.toString());
    limitCtrl = TextEditingController(
      text: widget.settings.smsMonthlyLimit != null ? widget.settings.smsMonthlyLimit.toString() : '',
    );
    selectedSubscriptionId = widget.settings.smsSimSubscriptionId;
    
    // Check permissions and load SIMs asynchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndLoadSims();
      _loadInterruptedLogs();
    });
  }

  @override
  void dispose() {
    apiKeyCtrl.dispose();
    minAmountCtrl.dispose();
    ageDaysCtrl.dispose();
    limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInterruptedLogs() async {
    final logRepo = ref.read(smsLogRepositoryProvider);
    await logRepo.resetStuckJobs();
    final logs = await logRepo.getUnknownLogs();
    if (mounted) {
      setState(() {
        interruptedLogs = logs;
      });
    }
  }

  Future<void> _resendInterruptedLogs() async {
    if (interruptedLogs.isEmpty) return;
    
    setState(() {
      isSendingBulk = true;
    });
    
    final smsService = ref.read(smsServiceProvider);
    final logRepo = ref.read(smsLogRepositoryProvider);
    
    int sentCount = 0;
    int failedCount = 0;
    
    final logsToResend = List<SmsLogEntry>.from(interruptedLogs);
    
    for (final log in logsToResend) {
      await logRepo.updateStatus(log.id, SmsLogStatus.sending);
      
      final success = await smsService.sendSms(log.phone, log.message);
      if (success) {
        sentCount++;
        await logRepo.updateStatus(
          log.id,
          SmsLogStatus.sent,
          sentAt: DateTime.now(),
        ).onError((_, __) {});
      } else {
        failedCount++;
        await logRepo.updateStatus(
          log.id,
          SmsLogStatus.failed,
          errorMessage: 'Resend failed',
        ).onError((_, __) {});
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gönderildi: $sentCount ✅ | Başarısız: $failedCount ❌'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    await _loadInterruptedLogs();
    
    if (mounted) {
      setState(() {
        isSendingBulk = false;
      });
    }
  }

  Future<void> _discardInterruptedLogs() async {
    final logRepo = ref.read(smsLogRepositoryProvider);
    for (final log in interruptedLogs) {
      await logRepo.updateStatus(log.id, SmsLogStatus.cancelled);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belirsiz durumdaki SMS kayıtları iptal edildi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    await _loadInterruptedLogs();
  }

  Future<void> _checkPermissionsAndLoadSims() async {
    final smsService = ref.read(smsServiceProvider);
    final granted = await smsService.hasSimPermissions();
    if (mounted) {
      setState(() {
        hasPermissions = granted;
      });
    }
    if (granted) {
      try {
        final List<dynamic>? result = await const MethodChannel('serenut/sms_sender')
            .invokeListMethod('getSmsSimCards');
        if (result != null && mounted) {
          setState(() {
            simCards = result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            // If previously selected subscription ID is no longer valid, fallback
            if (selectedSubscriptionId != null && 
                !simCards.any((sim) => sim['subscriptionId'] == selectedSubscriptionId)) {
              selectedSubscriptionId = simCards.isNotEmpty 
                  ? simCards.first['subscriptionId'] as int? 
                  : null;
            } else if (selectedSubscriptionId == null && simCards.isNotEmpty) {
              selectedSubscriptionId = simCards.first['subscriptionId'] as int?;
            }
          });
        }
      } catch (e) {
        debugPrint('SIM kartlar yüklenemedi: $e');
      }
    }
  }

  Future<void> _requestPermissions() async {
    final smsService = ref.read(smsServiceProvider);
    final granted = await smsService.requestSimPermissions();
    if (mounted) {
      setState(() {
        hasPermissions = granted;
      });
    }
    if (granted) {
      _checkPermissionsAndLoadSims();
    }
  }

  List<Map<String, dynamic>> _parseFlexibleSmsTemplates(String? templateStr) {
    final List<Map<String, dynamic>> defaultTemplates = [
      {
        'id': 'sale',
        'name': 'Satış Tamamlandı',
        'template': 'Sn. {customer}, {amount} TL tutarındaki alışverişiniz tamamlanmıştır. Fiş No: {id}',
        'enabled': true,
      },
      {
        'id': 'discount',
        'name': 'İndirim Uygulandı',
        'template': 'Sn. {customer}, alışverişinizde {discount} TL indirim uygulandı! Yeni tutar: {amount} TL.',
        'enabled': true,
      },
      {
        'id': 'debt',
        'name': 'Borç/Veresiye Kaydı',
        'template': 'Sn. {customer}, hesabınıza {amount} TL borç eklendi. Güncel borcunuz: {debt} TL.',
        'enabled': true,
      },
      {
        'id': 'collection',
        'name': 'Alacak / Tahsilat Alındı',
        'template': 'Sn. {customer}, {amount} TL tutarındaki ödemeniz alınmıştır. Kalan borcunuz: {debt} TL.',
        'enabled': true,
      },
      {
        'id': 'order',
        'name': 'Sipariş Alındı',
        'template': 'Sn. {customer}, {id} numaralı siparişiniz alınmıştır. Tutar: {amount} TL.',
        'enabled': true,
      },
      {
        'id': 'order_preparing',
        'name': 'Sipariş Hazırlanıyor',
        'template': 'Sn. {customer}, {id} numaralı siparişiniz hazırlanmaya başlandı.',
        'enabled': true,
      },
      {
        'id': 'order_ready',
        'name': 'Sipariş Hazır',
        'template': 'Sn. {customer}, {id} numaralı siparişiniz hazırlanmıştır. Teslim alabilirsiniz.',
        'enabled': true,
      },
      {
        'id': 'order_delivered',
        'name': 'Sipariş Teslim Edildi',
        'template': 'Sn. {customer}, {id} numaralı siparişiniz teslim edilmiştir. Bizi tercih ettiğiniz için teşekkür ederiz.',
        'enabled': true,
      },
      {
        'id': 'order_cancelled',
        'name': 'Sipariş İptal Edildi',
        'template': 'Sn. {customer}, {id} numaralı siparişiniz iptal edilmiştir.',
        'enabled': true,
      },
    ];

    if (templateStr == null || templateStr.trim().isEmpty) {
      return defaultTemplates;
    }

    try {
      final decoded = jsonDecode(templateStr);
      if (decoded is List) {
        final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        for (final def in defaultTemplates) {
          if (!list.any((t) => t['id'] == def['id'])) {
            list.add(def);
          }
        }
        return list;
      }
    } catch (_) {}
    return defaultTemplates;
  }

  Future<void> _sendBulkDebtReminder(BuildContext context) async {
    try {
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customers = await customerRepo.findAll();
      final logRepo = ref.read(smsLogRepositoryProvider);
      final smsService = ref.read(smsServiceProvider);

      final activeLogs = await logRepo.getActiveCampaignLogs();
      List<String> pendingIds = [];
      
      int sentCount = 0;
      int failedCount = 0;
      int totalCount = 0;
      bool isResume = false;

      if (activeLogs.isNotEmpty) {
        pendingIds = activeLogs.map((log) => log.id.replaceFirst('bulk_debt_', '')).toList();
        final resumeConfirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Yarım Kalan Toplu SMS'),
            content: Text('Sistemde yarım kalmış bir toplu SMS gönderimi bulundu (${pendingIds.length} müşteri bekliyor). Devam etmek ister misiniz?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Yeniden Başlat', style: TextStyle(color: POSColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Devam Et', style: TextStyle(color: POSColors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (resumeConfirm == null) return;
        if (resumeConfirm == true) {
          isResume = true;
          final allCampaignLogs = await logRepo.getRecentLogs(limit: 1000);
          sentCount = allCampaignLogs.where((e) => e.eventType == 'bulk_debt_reminder' && e.status == SmsLogStatus.sent).length;
          failedCount = allCampaignLogs.where((e) => e.eventType == 'bulk_debt_reminder' && e.status == SmsLogStatus.failed).length;
          totalCount = allCampaignLogs.where((e) => e.eventType == 'bulk_debt_reminder').length;
        } else {
          await logRepo.cancelActiveCampaignLogs();
          pendingIds = [];
        }
      }

      List<dynamic> activeDebtors = [];
      if (isResume) {
        activeDebtors = customers.where((c) => pendingIds.contains(c.id)).toList();
      } else {
        final allDebtors = customers.where((c) => c.balance < 0 && c.phone.trim().isNotEmpty).toList();
        if (allDebtors.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Borçlu ve telefon numarası tanımlı müşteri bulunamadı.'), behavior: SnackBarBehavior.floating),
            );
          }
          return;
        }

        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Toplu Borç Hatırlatma'),
            content: Text('${allDebtors.length} adet borçlu müşteriye SMS hatırlatma mesajı gönderilecektir. Devam edilsin mi?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç', style: TextStyle(color: POSColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Devam Et', style: TextStyle(color: POSColors.green, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (confirm != true) return;
        activeDebtors = allDebtors;
        totalCount = activeDebtors.length;
        pendingIds = activeDebtors.map((c) => c.id.toString()).toList();
        
        // Mark any previous campaign logs cancelled to be clean
        await logRepo.cancelActiveCampaignLogs();
        
        // Insert all pending logs into SQLite (this creates the campaign state machine in SQLite)
        for (final customer in activeDebtors) {
          final debtAmount = customer.balance.abs();
          final message = 'Sn. ${customer.name}, veresiye hesabınızda ${debtAmount.toStringAsFixed(2).replaceAll('.', ',')} ₺ borç bulunmaktadır. Ödemenizi rica ederiz.';
          await logRepo.insertLog(SmsLogEntry(
            id: 'bulk_debt_${customer.id}',
            phone: customer.phone,
            eventType: 'bulk_debt_reminder',
            message: message,
            createdAt: DateTime.now(),
            status: SmsLogStatus.pending,
          ));
        }
      }

      bool isBulkCancelled = false;

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) {
            return StatefulBuilder(
              builder: (ctx, setDialogState) {
                if (!isSendingBulk) {
                  isSendingBulk = true;
                  Future(() async {
                    const int batchSize = 5;
                    while (pendingIds.isNotEmpty && !isBulkCancelled) {
                      final currentBatchIds = pendingIds.sublist(0, pendingIds.length > batchSize ? batchSize : pendingIds.length);
                      final currentBatchDebtors = activeDebtors.where((c) => currentBatchIds.contains(c.id)).toList();

                      // Set status to sending in database for current batch
                      for (final debtor in currentBatchDebtors) {
                        await logRepo.updateStatus('bulk_debt_${debtor.id}', SmsLogStatus.sending);
                      }

                      await Future.wait(currentBatchDebtors.map((customer) async {
                        if (isBulkCancelled) return;
                        try {
                          final debtAmount = customer.balance.abs();
                          final message = 'Sn. ${customer.name}, veresiye hesabınızda ${debtAmount.toStringAsFixed(2).replaceAll('.', ',')} ₺ borç bulunmaktadır. Ödemenizi rica ederiz.';

                          final success = await smsService.sendSms(customer.phone, message);
                          if (success) {
                            sentCount++;
                            await logRepo.updateStatus(
                              'bulk_debt_${customer.id}',
                              SmsLogStatus.sent,
                              sentAt: DateTime.now(),
                            ).onError((_, __) {});
                          } else {
                            failedCount++;
                            await logRepo.updateStatus(
                              'bulk_debt_${customer.id}',
                              SmsLogStatus.failed,
                              errorMessage: 'Send failed',
                            ).onError((_, __) {});
                          }
                        } catch (_) {
                          failedCount++;
                          await logRepo.updateStatus(
                            'bulk_debt_${customer.id}',
                            SmsLogStatus.failed,
                            errorMessage: 'Exception',
                          ).onError((_, __) {});
                        }
                      }));

                      if (isBulkCancelled) {
                        // Mark all remaining pending and sending logs as cancelled
                        await logRepo.cancelActiveCampaignLogs();
                        break;
                      }

                      pendingIds.removeWhere((id) => currentBatchIds.contains(id));

                      if (dialogCtx.mounted) {
                        setDialogState(() {});
                      }

                      await Future.delayed(const Duration(seconds: 1));
                    }

                    isSendingBulk = false;

                    if (dialogCtx.mounted) {
                      Navigator.pop(dialogCtx);
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(isBulkCancelled 
                            ? 'Toplu SMS gönderimi iptal edildi. Gönderilen: $sentCount ✅ Başarısız: $failedCount ❌'
                            : 'Gönderildi: $sentCount ✅  Başarısız: $failedCount ❌'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  });
                }

                final totalProcessed = sentCount + failedCount;
                final progress = totalCount > 0 ? totalProcessed / totalCount : 0.0;

                return AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Toplu SMS Gönderiliyor'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(POSColors.green),
                        backgroundColor: POSColors.border,
                      ),
                      const SizedBox(height: 16),
                      Text('İlerleme: $totalProcessed / $totalCount'),
                      Text('Başarılı: $sentCount ✅ | Başarısız: $failedCount ❌'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        isBulkCancelled = true;
                        setDialogState(() {});
                      },
                      child: Text(isBulkCancelled ? 'İptal Ediliyor...' : 'İptal Et', style: const TextStyle(color: POSColors.red)),
                    ),
                  ],
                );
              },
            );
          },
        );
      }
    } catch (e) {
      isSendingBulk = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: POSColors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _sendBulkAnnouncement(BuildContext context) async {
    final confirmText = await showDialog<String>(
      context: context,
      builder: (ctx) => const _BulkAnnouncementDialog(),
    );

    if (confirmText == null || confirmText.isEmpty) return;

    try {
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customers = await customerRepo.findAll();
      final targets = customers.where((c) => c.phone.trim().isNotEmpty).toList();

      if (targets.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Telefon numarası tanımlı müşteri bulunamadı.'), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }

      final smsService = ref.read(smsServiceProvider);
      final logRepo = ref.read(smsLogRepositoryProvider);

      int sentCount = 0;
      for (final customer in targets) {
        final message = confirmText.replaceAll('{customer}', customer.name);

        await Future.delayed(const Duration(milliseconds: 300));

        final logId = const Uuid().v4();
        await logRepo.insertLog(SmsLogEntry(
          id: logId,
          phone: customer.phone,
          eventType: 'bulk_announcement',
          message: message,
          createdAt: DateTime.now(),
        ));

        smsService.sendSms(customer.phone, message).then((success) {
          logRepo.updateStatus(
            logId,
            success ? SmsLogStatus.sent : SmsLogStatus.failed,
            sentAt: success ? DateTime.now() : null,
            errorMessage: success ? null : 'Send failed',
          ).ignore();
        }).onError((e, _) {
          logRepo.updateStatus(
            logId,
            SmsLogStatus.failed,
            errorMessage: e.toString(),
          ).ignore();
        });
        sentCount++;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$sentCount adet duyuru mesajı gönderim sırasına alındı.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: POSColors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showEditTemplateDialog(Map<String, dynamic>? existingTpl, ValueChanged<Map<String, dynamic>> onSave) {
    showDialog(
      context: context,
      builder: (ctx) => _EditTemplateDialog(existingTpl: existingTpl, onSave: onSave),
    );
  }

  Widget _buildProviderCard({
    required String providerId,
    required String title,
    required String subtitle,
    required IconData icon,
    bool isSupported = true,
  }) {
    final isSelected = selectedProvider == providerId;
    return GestureDetector(
      onTap: isSupported && smsEnabled
          ? () {
              setState(() {
                selectedProvider = providerId;
              });
              if (providerId == 'sim') {
                _requestPermissions();
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: !isSupported 
              ? const Color(0xFFF1F5F9).withValues(alpha: 0.5)
              : (isSelected ? POSColors.greenLight : POSColors.card),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !isSupported
                ? Colors.transparent
                : (isSelected ? POSColors.green : POSColors.border),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: POSColors.shadowColor,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected ? POSColors.green.withValues(alpha: 0.15) : POSColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon, 
                color: !isSupported 
                    ? POSColors.textDisabled 
                    : (isSelected ? POSColors.green : POSColors.textSecondary), 
                size: 24
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: !isSupported 
                          ? POSColors.textDisabled 
                          : (isSelected ? POSColors.greenDark : POSColors.text),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: !isSupported ? POSColors.textDisabled : POSColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected && isSupported)
              const Icon(Icons.check_circle_rounded, color: POSColors.green, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final limit = int.tryParse(limitCtrl.text) ?? widget.settings.smsMonthlyLimit;
    final sent = widget.settings.smsSentThisMonth;
    final isLimitExceeded = limit != null && sent >= limit;
    final double percent = limit != null && limit > 0 ? (sent / limit).clamp(0.0, 1.0) : 0.0;

    return FullScreenSettingsPage(
      title: 'SMS Servis Ayarları',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // limit uyarı banner'ı
              if (smsEnabled && selectedProvider == 'sim' && isLimitExceeded) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: POSColors.redLight,
                    border: Border.all(color: POSColors.red.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: POSColors.red, size: 24),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SMS Gönderim Limiti Aşıldı!',
                              style: TextStyle(fontWeight: FontWeight.bold, color: POSColors.red, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bu ayki limitiniz ($limit SMS) dolmuştur. Yeni ay başında sayaç otomatik olarak sıfırlanacaktır.',
                              style: const TextStyle(color: POSColors.red, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Interrupted / Stuck SMS warning banner
              if (smsEnabled && interruptedLogs.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: POSColors.amberLight,
                    border: Border.all(color: POSColors.amber.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: POSColors.amber, size: 24),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${interruptedLogs.length} Adet SMS\'in Durumu Belirsiz Kaldı',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: POSColors.amberDark, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Uygulama beklenmedik şekilde kapandı. Bu SMS\'lerin gönderilip gönderilmediği belirsizdir. Tekrar göndermek istiyor musunuz?',
                              style: TextStyle(color: POSColors.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: isSendingBulk ? null : _resendInterruptedLogs,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: POSColors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Tekrar Gönder', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: isSendingBulk ? null : _discardInterruptedLogs,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: POSColors.red,
                                    side: const BorderSide(color: POSColors.red),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Yoksay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              _buildSwitchRow(
                title: 'SMS Bildirimlerini Etkinleştir',
                subtitle: 'İşlem sonrası otomatik mesaj gönderimi',
                icon: Icons.message_rounded,
                color: POSColors.orange,
                value: smsEnabled,
                onChanged: (val) {
                  setState(() => smsEnabled = val);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              if (smsEnabled) ...[
                const Text(
                  'SMS Servis Sağlayıcı',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: POSColors.text),
                ),
                const SizedBox(height: AppSpacing.sm),
                
                // Sağlayıcı Kartları
                _buildProviderCard(
                  providerId: 'sim',
                  title: 'Cihazın SIM Kartı (Yerel)',
                  subtitle: 'Android cihazınızdaki hattı kullanarak SMS gönderir.',
                  icon: Icons.sim_card_rounded,
                  isSupported: !kIsWeb && Theme.of(context).platform == TargetPlatform.android,
                ),
                _buildProviderCard(
                  providerId: 'netgsm',
                  title: 'NetGSM',
                  subtitle: 'NetGSM API entegrasyonu üzerinden gönderim.',
                  icon: Icons.cloud_done_rounded,
                ),
                _buildProviderCard(
                  providerId: 'twilio',
                  title: 'Twilio',
                  subtitle: 'Uluslararası Twilio Gateway API üzerinden gönderim.',
                  icon: Icons.api_rounded,
                ),
                const SizedBox(height: AppSpacing.md),

                // Grup 2: Dinamik Sağlayıcı Alanları
                if (selectedProvider == 'sim') ...[
                  // İzin Durumu
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: hasPermissions ? POSColors.greenLight : POSColors.amberLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasPermissions ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                          color: hasPermissions ? POSColors.greenDark : POSColors.amberDark,
                          size: 24,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            hasPermissions 
                                ? 'SMS İzinleri Tanımlı (Gönderime Hazır)' 
                                : 'SMS gönderebilmek için SMS ve Telefon izinleri gereklidir.',
                            style: TextStyle(
                              color: hasPermissions ? POSColors.greenDark : POSColors.amberDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (!hasPermissions)
                          TextButton(
                            onPressed: _requestPermissions,
                            child: const Text('İzin Ver', style: TextStyle(fontWeight: FontWeight.bold, color: POSColors.amberDark)),
                          ),
                      ],
                    ),
                  ),

                  // SIM Seçici Dropdown
                  if (hasPermissions && simCards.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      value: selectedSubscriptionId,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: POSColors.text, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Gönderici SIM Kart',
                        prefixIcon: const Icon(Icons.sim_card_outlined, size: 18, color: POSColors.textSecondary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: POSColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: POSColors.border)),
                        filled: true,
                        fillColor: POSColors.surface,
                      ),
                      items: simCards.map((sim) {
                        final slot = (sim['simSlotIndex'] as int? ?? 0) + 1;
                        final op = sim['displayName'] ?? 'Bilinmeyen Operatör';
                        return DropdownMenuItem<int>(
                          value: sim['subscriptionId'] as int?,
                          child: Text('SIM $slot - $op'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedSubscriptionId = val;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // SMS Limit Girişi
                  _buildFormTextField(
                    controller: limitCtrl,
                    label: 'Aylık SMS Gönderim Limiti (Boş = Limitsiz)',
                    icon: Icons.speed_rounded,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Limit Durum Çubuğu
                  if (limit != null && limit > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: POSColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: POSColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bu Ayki SMS Kullanımı', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: POSColors.text)),
                              Text(
                                '$sent / $limit SMS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 13, 
                                  color: isLimitExceeded ? POSColors.red : POSColors.greenDark
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percent,
                              minHeight: 8,
                              backgroundColor: POSColors.surface,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isLimitExceeded 
                                    ? POSColors.red 
                                    : (percent >= 0.8 ? POSColors.amber : POSColors.green)
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ] else ...[
                  // API Şifre alanı (Twilio/Netgsm)
                  _buildFormTextField(
                    controller: apiKeyCtrl,
                    label: 'API Anahtarı / Şifre',
                    icon: Icons.key_rounded,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // SMS History Log Trigger Button
                ElevatedButton.icon(
                  icon: const Icon(Icons.history_toggle_off_rounded, size: 18),
                  label: const Text('SMS Gönderim Geçmişini Görüntüle'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SmsHistoryPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: POSColors.text,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sim_card_rounded, size: 18),
                    label: const Text('DEBUG: SIM Kartları Listele'),
                    onPressed: _checkPermissionsAndLoadSims,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),

                // Tetikleyiciler & Otomatik Kurallar
                const Text(
                  'Tetikleyiciler & Kurallar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: POSColors.text),
                ),
                const Divider(color: POSColors.border),
                _buildSwitchRow(
                  title: 'Otomatik Borç Hatırlatıcısı Gönder',
                  subtitle: 'Belirli koşullara göre müşteriye otomatik hatırlatma gönderimi',
                  icon: Icons.notifications_active_rounded,
                  color: POSColors.blue,
                  value: autoDebtReminderEnabled,
                  onChanged: (val) {
                    setState(() => autoDebtReminderEnabled = val);
                  },
                ),
                if (autoDebtReminderEnabled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: minAmountCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Min Borç Tutarı (TL)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: ageDaysCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Hatırlatma Yaşı (Gün)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),

                // Toplu SMS İşlemleri
                const Text(
                  'Toplu SMS İşlemleri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: POSColors.text),
                ),
                const Divider(color: POSColors.border),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: isSendingBulk 
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)))
                            : const Icon(Icons.people_alt_rounded, size: 16, color: Color(0xFF8B5CF6)),
                        label: const Text('Borçlulara SMS', style: TextStyle(color: POSColors.text, fontSize: 12)),
                        onPressed: !isSendingBulk ? () async {
                          setState(() => isSendingBulk = true);
                          await _sendBulkDebtReminder(context);
                          if (mounted) setState(() => isSendingBulk = false);
                        } : null,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: POSColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: isSendingBulk 
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: POSColors.green))
                            : const Icon(Icons.campaign_rounded, size: 16, color: POSColors.green),
                        label: const Text('Toplu Duyuru SMS', style: TextStyle(color: POSColors.text, fontSize: 12)),
                        onPressed: !isSendingBulk ? () async {
                          setState(() => isSendingBulk = true);
                          await _sendBulkAnnouncement(context);
                          if (mounted) setState(() => isSendingBulk = false);
                        } : null,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: POSColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                
                // Flexible Templates Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Esnek SMS Şablonları',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: POSColors.text),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: POSColors.green),
                      label: const Text('Şablon Ekle', style: TextStyle(color: POSColors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => _showEditTemplateDialog(null, (newTpl) {
                        setState(() {
                          listTemplates.add(newTpl);
                        });
                      }),
                    ),
                  ],
                ),
                const Divider(color: POSColors.border),
                
                // Templates list view
                if (listTemplates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Tanımlı şablon bulunamadı. Lütfen yeni şablon ekleyin.', style: TextStyle(color: POSColors.textSecondary, fontSize: 13)),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < listTemplates.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final tpl = listTemplates[i];
                            final isEnabled = tpl['enabled'] == true;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isEnabled ? POSColors.surface : Colors.grey[50]!,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isEnabled ? POSColors.border : Colors.grey[200]!),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        tpl['name'] ?? '',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isEnabled ? POSColors.text : POSColors.textDisabled,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Switch.adaptive(
                                            value: isEnabled,
                                            activeColor: POSColors.green,
                                            onChanged: (val) {
                                              setState(() {
                                                listTemplates[i]['enabled'] = val;
                                              });
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.edit_rounded, size: 18, color: isEnabled ? POSColors.blue : POSColors.textDisabled),
                                            onPressed: isEnabled ? () {
                                              _showEditTemplateDialog(tpl, (updatedTpl) {
                                                setState(() {
                                                  listTemplates[i] = updatedTpl;
                                                });
                                              });
                                            } : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tpl['template'] ?? '',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isEnabled ? POSColors.textSecondary : POSColors.textDisabled,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isEnabled ? POSColors.blue.withValues(alpha: 0.08) : Colors.grey[100]!,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tpl['id'] ?? '',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isEnabled ? POSColors.blue : POSColors.textDisabled,
                                          ),
                                        ),
                                      ),
                                      if (tpl['id'] != 'sale' &&
                                          tpl['id'] != 'discount' &&
                                          tpl['id'] != 'debt' &&
                                          tpl['id'] != 'collection' &&
                                          tpl['id'] != 'order')
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete_outline_rounded, size: 14, color: POSColors.red),
                                          label: const Text('Sil', style: TextStyle(fontSize: 12, color: POSColors.red)),
                                          onPressed: () {
                                            setState(() {
                                              listTemplates.removeAt(i);
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }
                        ),
                      ]
                    ],
                  ),
              ],
              
              const SizedBox(height: 24),
              _buildModalSaveButton(onTap: () async {
                if (_formKey.currentState!.validate()) {
                  final templateJson = jsonEncode(listTemplates);
                  
                  // Save SMS Settings including new SIM and limits fields
                  final updated = widget.settings.copyWith(
                    smsEnabled: smsEnabled,
                    smsProvider: selectedProvider,
                    smsApiKey: apiKeyCtrl.text.trim().isEmpty ? null : apiKeyCtrl.text.trim(),
                    smsTemplate: templateJson,
                    smsSimSubscriptionId: selectedSubscriptionId,
                    smsMonthlyLimit: limitCtrl.text.trim().isEmpty ? null : int.tryParse(limitCtrl.text.trim()),
                  );
                  final minAmt = double.tryParse(minAmountCtrl.text) ?? 100.0;
                  final ageDays = int.tryParse(ageDaysCtrl.text) ?? 15;
                  final updatedWithReminder = updated.copyWith(
                    smsAutoDebtReminderEnabled: autoDebtReminderEnabled,
                    smsAutoDebtReminderMinAmount: minAmt,
                    smsAutoDebtReminderDays: ageDays,
                  );
                  try {
                    await ref.read(settingsNotifierProvider.notifier).updateSettings(updatedWithReminder);
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Hata: $e'), backgroundColor: POSColors.red),
                      );
                    }
                  }
                }
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _iOSIconBadge(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: POSColors.text),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: POSColors.green,
          ),
        ],
      ),
    );
  }

  Widget _iOSIconBadge({required IconData icon, required Color color}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: POSColors.textSecondary, size: 18),
    );
  }

  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      onChanged: onChanged,
      style: TextStyle(color: enabled ? POSColors.text : POSColors.textSecondary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20, color: POSColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: POSColors.green, width: 1.5),
        ),
        filled: true,
        fillColor: enabled ? POSColors.surface : const Color(0xFFEFEFEF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildModalSaveButton({required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: POSColors.green,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: const Text(
          'Kaydet',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

class _EditTemplateDialog extends StatefulWidget {
  final Map<String, dynamic>? existingTpl;
  final ValueChanged<Map<String, dynamic>> onSave;

  const _EditTemplateDialog({
    required this.existingTpl,
    required this.onSave,
  });

  @override
  State<_EditTemplateDialog> createState() => _EditTemplateDialogState();
}

class _EditTemplateDialogState extends State<_EditTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameCtrl;
  late final TextEditingController templateCtrl;
  late String selectedEvent;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.existingTpl?['name'] ?? '');
    templateCtrl = TextEditingController(text: widget.existingTpl?['template'] ?? '');
    
    selectedEvent = widget.existingTpl?['id'] ?? 'sale_created';
    if (selectedEvent == 'sale') selectedEvent = 'sale_created';
    if (selectedEvent == 'discount') selectedEvent = 'discount_applied';
    if (selectedEvent == 'debt') selectedEvent = 'debt_created';
    if (selectedEvent == 'collection') selectedEvent = 'collection_recorded';
    if (selectedEvent == 'order') selectedEvent = 'order_created';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    templateCtrl.dispose();
    super.dispose();
  }

  Widget _buildVariableChip(TextEditingController controller, String token, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: POSColors.green)),
      backgroundColor: POSColors.green.withValues(alpha: 0.08),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        final text = controller.text;
        final selection = controller.selection;
        if (selection.start >= 0) {
          final newText = text.replaceRange(selection.start, selection.end, token);
          controller.text = newText;
          controller.selection = TextSelection.collapsed(offset: selection.start + token.length);
        } else {
          controller.text = text + token;
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existingTpl == null;
    const validEvents = [
      'sale_created',
      'discount_applied',
      'debt_created',
      'collection_recorded',
      'order_created',
      'order_preparing',
      'order_ready',
      'order_delivered',
      'order_cancelled',
    ];
    if (!validEvents.contains(selectedEvent)) {
      selectedEvent = 'sale_created';
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isNew ? 'Yeni Şablon Ekle' : 'Şablonu Düzenle', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Şablon Adı',
                  prefixIcon: const Icon(Icons.title_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) => v!.trim().isEmpty ? 'Şablon adı gerekli' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedEvent,
                style: const TextStyle(fontSize: 14, color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'Tetikleyici Durum (Olay)',
                  prefixIcon: const Icon(Icons.flash_on_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'sale_created', child: Text('Satış Tamamlandığında')),
                  DropdownMenuItem(value: 'discount_applied', child: Text('İndirim Yapıldığında')),
                  DropdownMenuItem(value: 'debt_created', child: Text('Borç Eklendiğinde')),
                  DropdownMenuItem(value: 'collection_recorded', child: Text('Tahsilat Yapıldığında')),
                  DropdownMenuItem(value: 'order_created', child: Text('Sipariş Alındığında')),
                  DropdownMenuItem(value: 'order_preparing', child: Text('Sipariş Hazırlanmaya Başladığında')),
                  DropdownMenuItem(value: 'order_ready', child: Text('Sipariş Hazırlandığında')),
                  DropdownMenuItem(value: 'order_delivered', child: Text('Sipariş Teslim Edildiğinde')),
                  DropdownMenuItem(value: 'order_cancelled', child: Text('Sipariş İptal Edildiğinde')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      selectedEvent = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: templateCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Mesaj Şablonu',
                  hintText: 'örn: Sn. {customer}, {amount} TL ödemeniz alındı.',
                  prefixIcon: const Icon(Icons.text_snippet_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) => v!.trim().isEmpty ? 'Şablon içeriği gerekli' : null,
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Kullanılabilir Değişkenler:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: POSColors.textSecondary)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildVariableChip(templateCtrl, '{customer}', 'Müşteri'),
                  _buildVariableChip(templateCtrl, '{amount}', 'Tutar'),
                  _buildVariableChip(templateCtrl, '{discount}', 'İndirim'),
                  _buildVariableChip(templateCtrl, '{debt}', 'Borç/Bakiye'),
                  _buildVariableChip(templateCtrl, '{id}', 'Fiş/İşlem No'),
                  _buildVariableChip(templateCtrl, '{business}', 'İşletme Adı'),
                  _buildVariableChip(templateCtrl, '{date}', 'İşlem Tarihi'),
                  _buildVariableChip(templateCtrl, '{items}', 'Ürünler'),
                  _buildVariableChip(templateCtrl, '{phone}', 'Telefon'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: POSColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = {
                'id': selectedEvent,
                'name': nameCtrl.text.trim(),
                'template': templateCtrl.text.trim(),
                'enabled': widget.existingTpl?['enabled'] ?? true,
              };
              widget.onSave(result);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: POSColors.green,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _BulkAnnouncementDialog extends StatefulWidget {
  const _BulkAnnouncementDialog();

  @override
  State<_BulkAnnouncementDialog> createState() => _BulkAnnouncementDialogState();
}

class _BulkAnnouncementDialogState extends State<_BulkAnnouncementDialog> {
  final _formKey = GlobalKey<FormState>();
  final msgCtrl = TextEditingController();

  @override
  void dispose() {
    msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Toplu Mesaj Gönder'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: msgCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Duyuru Mesajı',
            hintText: 'Tüm müşterilere gönderilecek mesajı yazın...',
            border: OutlineInputBorder(),
          ),
          validator: (val) => val == null || val.trim().isEmpty ? 'Boş bırakılamaz' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç', style: TextStyle(color: POSColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, msgCtrl.text.trim());
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: POSColors.text, foregroundColor: Colors.white),
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}
