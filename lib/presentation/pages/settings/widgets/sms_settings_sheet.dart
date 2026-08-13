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
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/presentation/pages/settings/sms_history_page.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart'; // FullScreenSettingsPage
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sms_message_analyzer.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart'; // POSColors & AppSpacing

class SmsSettingsSheet extends ConsumerStatefulWidget {
  final Settings settings;
  final bool operationsOnly;

  const SmsSettingsSheet({
    required this.settings,
    this.operationsOnly = false,
    super.key,
  });

  @override
  ConsumerState<SmsSettingsSheet> createState() => _SmsSettingsSheetState();
}

class _SmsSettingsSheetState extends ConsumerState<SmsSettingsSheet>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late List<Map<String, dynamic>> listTemplates;
  late final TextEditingController minAmountCtrl;
  late final TextEditingController ageDaysCtrl;
  late final TextEditingController limitCtrl;
  late bool smsEnabled;
  late String selectedProvider;
  late bool autoDebtReminderEnabled;
  bool isSendingBulk = false;
  bool whatsappStatusLoading = true;
  bool whatsappConnected = false;
  String? whatsappPhone;
  final Map<String, Map<String, String>> whatsappTemplates = {};

  // SIM SMS Specific States
  List<Map<String, dynamic>> simCards = [];
  bool hasPermissions = false;
  bool checkingPermissions = true;
  int? selectedSubscriptionId;
  List<SmsLogEntry> interruptedLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    listTemplates = _parseFlexibleSmsTemplates(widget.settings.smsTemplate);
    smsEnabled = widget.settings.smsEnabled;
    selectedProvider = 'sim';
    autoDebtReminderEnabled = widget.settings.smsAutoDebtReminderEnabled;
    minAmountCtrl = TextEditingController(
      text: widget.settings.smsAutoDebtReminderMinAmount.toStringAsFixed(0),
    );
    ageDaysCtrl = TextEditingController(
      text: widget.settings.smsAutoDebtReminderDays.toString(),
    );
    limitCtrl = TextEditingController(
      text: widget.settings.smsMonthlyLimit != null
          ? widget.settings.smsMonthlyLimit.toString()
          : '',
    );
    selectedSubscriptionId = widget.settings.smsSimSubscriptionId;

    // Check permissions and load SIMs asynchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissionsAndLoadSims();
      _loadInterruptedLogs();
      _loadWhatsAppStatus();
    });
  }

  Future<void> _loadWhatsAppStatus() async {
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait([
        api.get('/api/v1/whatsapp/connection'),
        api.get('/api/v1/whatsapp/templates'),
      ]);
      final body = Map<String, dynamic>.from(results[0].json as Map);
      final connection = body['connection'] is Map
          ? Map<String, dynamic>.from(body['connection'] as Map)
          : <String, dynamic>{};
      final templates =
          results[1].json is List ? results[1].json as List : const <dynamic>[];
      if (!mounted) return;
      setState(() {
        whatsappConnected = connection['status'] == 'active';
        whatsappPhone = connection['display_phone_number']?.toString();
        whatsappTemplates
          ..clear()
          ..addEntries(
            templates.whereType<Map>().map((item) {
              final row = Map<String, dynamic>.from(item);
              return MapEntry(
                row['event_key']?.toString() ?? '',
                {
                  'status': row['status']?.toString() ?? 'pending',
                  'name': row['meta_template_name']?.toString() ?? '',
                },
              );
            }),
          );
        whatsappStatusLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => whatsappStatusLoading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    minAmountCtrl.dispose();
    ageDaysCtrl.dispose();
    limitCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionsAndLoadSims();
    }
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
    if (mounted) setState(() => checkingPermissions = true);
    final smsService = ref.read(smsServiceProvider);
    final granted = await smsService.hasSimPermissions();
    if (mounted) {
      setState(() {
        hasPermissions = granted;
        checkingPermissions = false;
      });
    }
    if (granted) {
      try {
        final List<dynamic>? result = await const MethodChannel(
          'serenut/sms_sender',
        ).invokeListMethod('getSmsSimCards');
        if (result != null && mounted) {
          setState(() {
            simCards =
                result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            // If previously selected subscription ID is no longer valid, fallback
            if (selectedSubscriptionId != null &&
                !simCards.any(
                  (sim) => sim['subscriptionId'] == selectedSubscriptionId,
                )) {
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
    setState(() => checkingPermissions = true);
    final smsService = ref.read(smsServiceProvider);
    await smsService.requestSimPermissions();
    await _checkPermissionsAndLoadSims();
  }

  List<Map<String, dynamic>> _parseFlexibleSmsTemplates(String? templateStr) {
    final List<Map<String, dynamic>> defaultTemplates = [
      {
        'id': 'sale',
        'name': 'Satış Onayı',
        'template':
            'Merhaba {customer}, {id} numaralı satış işleminiz tamamlandı. Toplam: {amount}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'debt',
        'name': 'Vadeli Bakiye Kaydı',
        'template':
            'Merhaba {customer}, {id} numaralı işlem sonrası vadeli tutarınız {debt}, güncel bakiyeniz {balance}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'collection',
        'name': 'Ödeme Alındı',
        'template':
            'Merhaba {customer}, {amount} tutarındaki ödemeniz alındı. Kalan bakiyeniz {debt}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order',
        'name': 'Sipariş Alındı',
        'template':
            'Merhaba {customer}, {id} numaralı siparişiniz alındı. Toplam: {amount}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_preparing',
        'name': 'Sipariş Hazırlanıyor',
        'template':
            'Merhaba {customer}, {id} numaralı siparişiniz hazırlanıyor. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_ready',
        'name': 'Sipariş Hazır',
        'template':
            'Merhaba {customer}, {id} numaralı siparişiniz hazır. Teslim alabilirsiniz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_delivered',
        'name': 'Sipariş Teslim Edildi',
        'template':
            'Merhaba {customer}, {id} numaralı siparişiniz teslim edildi. Bizi tercih ettiğiniz için teşekkür ederiz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_cancelled',
        'name': 'Sipariş İptal Edildi',
        'template':
            'Merhaba {customer}, {id} numaralı siparişiniz iptal edildi. Ayrıntılı bilgi için işletmemizle iletişime geçebilirsiniz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'balance_reminder',
        'name': 'Bakiye Hatırlatması',
        'template':
            'Merhaba {customer}, hesabınızdaki güncel vadeli bakiye {balance}. Ödeme bilgisi için işletmemizle iletişime geçebilirsiniz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
    ];

    if (templateStr == null || templateStr.trim().isEmpty) {
      return defaultTemplates;
    }

    try {
      final decoded = jsonDecode(templateStr);
      if (decoded is List) {
        final list =
            decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Eski sürümlerde ayrı bir indirim olayı yayınlanmadığı halde bu
        // şablon gösteriliyordu. Hiç tetiklenemeyen ayarı arayüzden kaldır.
        list.removeWhere((item) =>
            item['id'] == 'discount' || item['id'] == 'discount_applied');
        for (final item in list) {
          item['sms_enabled'] ??= item['enabled'] == true;
          item['whatsapp_enabled'] ??= false;
          item['enabled'] = item['sms_enabled'] == true;
        }
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

  String _balanceReminderMessage(String customerName, double amount) {
    final configured = listTemplates.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item?['id'] == 'balance_reminder',
          orElse: () => null,
        );
    final amountText =
        '${amount.toStringAsFixed(2).replaceAll('.', ',')} ${widget.settings.currency}';
    var message = configured?['template']?.toString() ??
        'Merhaba {customer}, hesabınızdaki güncel vadeli bakiye {balance}. Ödeme bilgisi için işletmemizle iletişime geçebilirsiniz. {business}';
    return message
        .replaceAll('{customer}', customerName)
        .replaceAll('{balance}', amountText)
        .replaceAll('{debt}', amountText)
        .replaceAll('{business}', widget.settings.businessName);
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
        if (!context.mounted) return;
        pendingIds = activeLogs
            .map((log) => log.id.replaceFirst('bulk_debt_', ''))
            .toList();
        final resumeConfirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Yarım Kalan Bakiye İletişimi'),
            content: Text(
              'Sistemde tamamlanmamış bir bakiye hatırlatma gönderimi bulundu (${pendingIds.length} müşteri bekliyor). Devam etmek ister misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Yeniden Başlat',
                  style: TextStyle(color: POSColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Devam Et',
                  style: TextStyle(
                    color: POSColors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

        if (resumeConfirm == null) return;
        if (resumeConfirm == true) {
          isResume = true;
          final allCampaignLogs = await logRepo.getRecentLogs(limit: 1000);
          sentCount = allCampaignLogs
              .where(
                (e) =>
                    e.eventType == 'bulk_debt_reminder' &&
                    e.status == SmsLogStatus.sent,
              )
              .length;
          failedCount = allCampaignLogs
              .where(
                (e) =>
                    e.eventType == 'bulk_debt_reminder' &&
                    e.status == SmsLogStatus.failed,
              )
              .length;
          totalCount = allCampaignLogs
              .where((e) => e.eventType == 'bulk_debt_reminder')
              .length;
        } else {
          await logRepo.cancelActiveCampaignLogs();
          pendingIds = [];
        }
      }

      List<dynamic> activeDebtors = [];
      if (isResume) {
        activeDebtors =
            customers.where((c) => pendingIds.contains(c.id)).toList();
      } else {
        final allDebtors = customers
            .where((c) => c.balance < 0 && c.phone.trim().isNotEmpty)
            .toList();
        if (allDebtors.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Borçlu ve telefon numarası tanımlı müşteri bulunamadı.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        if (!context.mounted) return;
        final selectedDebtors = await _selectBulkDebtors(context, allDebtors);
        if (selectedDebtors == null || selectedDebtors.isEmpty) return;
        activeDebtors = selectedDebtors;
        totalCount = activeDebtors.length;
        pendingIds = activeDebtors.map((c) => c.id.toString()).toList();

        // Mark any previous campaign logs cancelled to be clean
        await logRepo.cancelActiveCampaignLogs();

        // Insert all pending logs into SQLite (this creates the campaign state machine in SQLite)
        for (final customer in activeDebtors) {
          final debtAmount = customer.balance.abs();
          final message = _balanceReminderMessage(customer.name, debtAmount);
          await logRepo.insertLog(
            SmsLogEntry(
              id: 'bulk_debt_${customer.id}',
              phone: customer.phone,
              eventType: 'bulk_debt_reminder',
              message: message,
              createdAt: DateTime.now(),
              status: SmsLogStatus.pending,
            ),
          );
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
                    // A local SIM is a single-channel gateway. Serial delivery
                    // prevents platform-channel races and false failures.
                    const int batchSize = 1;
                    while (pendingIds.isNotEmpty && !isBulkCancelled) {
                      final currentBatchIds = pendingIds.sublist(
                        0,
                        pendingIds.length > batchSize
                            ? batchSize
                            : pendingIds.length,
                      );
                      final currentBatchDebtors = activeDebtors
                          .where((c) => currentBatchIds.contains(c.id))
                          .toList();

                      // Set status to sending in database for current batch
                      for (final debtor in currentBatchDebtors) {
                        await logRepo.updateStatus(
                          'bulk_debt_${debtor.id}',
                          SmsLogStatus.sending,
                        );
                      }

                      await Future.wait(
                        currentBatchDebtors.map((customer) async {
                          if (isBulkCancelled) return;
                          try {
                            final debtAmount = customer.balance.abs();
                            final message = _balanceReminderMessage(
                              customer.name,
                              debtAmount,
                            );

                            final success = await smsService.sendSms(
                              customer.phone,
                              message,
                            );
                            if (success) {
                              sentCount++;
                              await logRepo
                                  .updateStatus(
                                    'bulk_debt_${customer.id}',
                                    SmsLogStatus.sent,
                                    sentAt: DateTime.now(),
                                  )
                                  .onError((_, __) {});
                            } else {
                              failedCount++;
                              await logRepo
                                  .updateStatus(
                                    'bulk_debt_${customer.id}',
                                    SmsLogStatus.failed,
                                    errorMessage: 'Send failed',
                                  )
                                  .onError((_, __) {});
                            }
                          } catch (_) {
                            failedCount++;
                            await logRepo
                                .updateStatus(
                                  'bulk_debt_${customer.id}',
                                  SmsLogStatus.failed,
                                  errorMessage: 'Exception',
                                )
                                .onError((_, __) {});
                          }
                        }),
                      );

                      if (isBulkCancelled) {
                        // Mark all remaining pending and sending logs as cancelled
                        await logRepo.cancelActiveCampaignLogs();
                        break;
                      }

                      pendingIds.removeWhere(
                        (id) => currentBatchIds.contains(id),
                      );

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
                          content: Text(
                            isBulkCancelled
                                ? 'Bakiye hatırlatma gönderimi iptal edildi. Gönderilen: $sentCount ✅ Başarısız: $failedCount ❌'
                                : 'Gönderildi: $sentCount ✅  Başarısız: $failedCount ❌',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  });
                }

                final totalProcessed = sentCount + failedCount;
                final progress =
                    totalCount > 0 ? totalProcessed / totalCount : 0.0;

                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: const Text('Bakiye Hatırlatmaları Gönderiliyor'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          POSColors.green,
                        ),
                        backgroundColor: POSColors.border,
                      ),
                      const SizedBox(height: 16),
                      Text('İlerleme: $totalProcessed / $totalCount'),
                      Text(
                        'Başarılı: $sentCount ✅ | Başarısız: $failedCount ❌',
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        isBulkCancelled = true;
                        setDialogState(() {});
                      },
                      child: Text(
                        isBulkCancelled ? 'İptal Ediliyor...' : 'İptal Et',
                        style: const TextStyle(color: POSColors.red),
                      ),
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
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: POSColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<List<CustomerEntity>?> _selectBulkDebtors(
    BuildContext context,
    List<CustomerEntity> debtors,
  ) {
    final selected = debtors.map((customer) => customer.id).toSet();
    var query = '';
    var minimumDebt = autoDebtReminderEnabled
        ? (double.tryParse(minAmountCtrl.text) ?? 0.0)
        : 0.0;
    return showDialog<List<CustomerEntity>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = debtors.where((customer) {
            final normalized = query.toLowerCase().trim();
            final matchesQuery = normalized.isEmpty ||
                customer.name.toLowerCase().contains(normalized) ||
                customer.phone.contains(normalized);
            return matchesQuery && customer.balance.abs() >= minimumDebt;
          }).toList(growable: false);
          final selectedCustomers = debtors
              .where((customer) => selected.contains(customer.id))
              .toList(growable: false);
          final longestMessage = selectedCustomers.isEmpty
              ? ''
              : selectedCustomers
                  .map(
                    (customer) => _balanceReminderMessage(
                      customer.name,
                      customer.balance.abs(),
                    ),
                  )
                  .reduce((a, b) => a.length >= b.length ? a : b);
          final analysis = const SmsMessageAnalyzer().analyze(
            longestMessage,
          );
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('SMS Alıcılarını Seç'),
            content: SizedBox(
              width: 520,
              height: 430,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: POSColors.amberLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sms_rounded,
                          color: POSColors.amberDark,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${selected.length} / ${debtors.length} müşteri • En uzun mesaj: ${analysis.characters} karakter, ${analysis.segments} SMS',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setDialogState(() {
                            if (selected.length == debtors.length) {
                              selected.clear();
                            } else {
                              selected.addAll(visible.map((e) => e.id));
                            }
                          }),
                          child: Text(
                            selected.length == debtors.length
                                ? 'Temizle'
                                : 'Tümünü seç',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'Müşteri veya telefon ara',
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [0.0, 100.0, 500.0, 1000.0]
                        .map(
                          (amount) => ChoiceChip(
                            label: Text(
                              amount == 0
                                  ? 'Tüm borçlar'
                                  : '${amount.toStringAsFixed(0)} ₺ üzeri',
                            ),
                            selected: minimumDebt == amount,
                            onSelected: (_) => setDialogState(
                              () => minimumDebt = amount,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final customer = visible[index];
                        return CheckboxListTile(
                          value: selected.contains(customer.id),
                          activeColor: POSColors.green,
                          title: Text(customer.name),
                          subtitle: Text(
                            '${customer.phone} • ${customer.balance.abs().toStringAsFixed(2).replaceAll('.', ',')} ₺',
                          ),
                          onChanged: (checked) => setDialogState(() {
                            checked == true
                                ? selected.add(customer.id)
                                : selected.remove(customer.id);
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Vazgeç'),
              ),
              FilledButton.icon(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          debtors
                              .where(
                                (customer) => selected.contains(customer.id),
                              )
                              .toList(),
                        ),
                icon: const Icon(Icons.send_rounded),
                label: Text('${selected.length} kişiye gönder'),
              ),
            ],
          );
        },
      ),
    );
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
      final targets =
          customers.where((c) => c.phone.trim().isNotEmpty).toList();

      if (targets.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Telefon numarası tanımlı müşteri bulunamadı.'),
              behavior: SnackBarBehavior.floating,
            ),
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$sentCount tanıtım ve duyuru mesajı gönderim sırasına alındı.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: POSColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _retryFailedDebtMessages(BuildContext context) async {
    final logRepository = ref.read(smsLogRepositoryProvider);
    final failed = await logRepository.getFailedCampaignLogs();
    if (failed.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yeniden gönderilecek başarısız SMS bulunmuyor.'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Başarısız SMS’leri Yeniden Gönder'),
        content: Text(
          '${failed.length} mesaj sırayla yeniden gönderilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yeniden gönder'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    var sent = 0;
    for (final entry in failed) {
      await logRepository.incrementRetry(entry.id);
      await logRepository.updateStatus(entry.id, SmsLogStatus.sending);
      final success = await ref
          .read(smsServiceProvider)
          .sendSms(entry.phone, entry.message);
      await logRepository.updateStatus(
        entry.id,
        success ? SmsLogStatus.sent : SmsLogStatus.failed,
        sentAt: success ? DateTime.now() : null,
        errorMessage: success ? null : 'Retry failed',
      );
      if (success) sent++;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$sent / ${failed.length} SMS başarıyla gönderildi.'),
        ),
      );
    }
  }

  void _showEditTemplateDialog(
    Map<String, dynamic>? existingTpl,
    ValueChanged<Map<String, dynamic>> onSave,
  ) {
    showDialog(
      context: context,
      builder: (ctx) =>
          _EditTemplateDialog(existingTpl: existingTpl, onSave: onSave),
    );
  }

  String _canonicalEventId(String id) =>
      const {
        'sale': 'sale_created',
        'debt': 'debt_created',
        'collection': 'collection_recorded',
        'order': 'order_created',
      }[id] ??
      id;

  Widget _buildWhatsAppConnectionCard() {
    final color = whatsappStatusLoading
        ? POSColors.textSecondary
        : whatsappConnected
            ? POSColors.green
            : POSColors.amber;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WhatsApp Business',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  whatsappStatusLoading
                      ? 'Bağlantı durumu kontrol ediliyor…'
                      : whatsappConnected
                          ? '${whatsappPhone ?? 'İşletme numarası'} bağlı. Aşağıdaki olaylar için WhatsApp’ı ayrı ayrı açabilirsiniz.'
                          : 'Bağlantı kurulmadı. Firma sahibi müşteri portalındaki Bildirim Kanalları bölümünden hesabını bağlamalıdır.',
                  style: const TextStyle(
                    color: POSColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!whatsappStatusLoading)
            Icon(
              whatsappConnected
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: color,
            ),
        ],
      ),
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
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? POSColors.green.withValues(alpha: 0.15)
                    : POSColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: !isSupported
                    ? POSColors.textDisabled
                    : (isSelected ? POSColors.green : POSColors.textSecondary),
                size: 24,
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
                      color: !isSupported
                          ? POSColors.textDisabled
                          : POSColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected && isSupported)
              const Icon(
                Icons.check_circle_rounded,
                color: POSColors.green,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsCenter() {
    return FullScreenSettingsPage(
      title: 'Müşteri İletişimi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: POSColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: POSColors.border),
            ),
            child: const Text(
              'Bakiye hatırlatmalarını ve tanıtım mesajlarını kontrollü alıcı seçimiyle gönderin; sonuçları gönderim geçmişinden takip edin.',
              style: TextStyle(color: POSColors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: isSendingBulk
                ? null
                : () async {
                    setState(() => isSendingBulk = true);
                    await _sendBulkDebtReminder(context);
                    if (mounted) setState(() => isSendingBulk = false);
                  },
            icon: const Icon(Icons.people_alt_rounded),
            label: const Text('Bakiye hatırlatması gönder'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: isSendingBulk
                ? null
                : () async {
                    setState(() => isSendingBulk = true);
                    await _sendBulkAnnouncement(context);
                    if (mounted) setState(() => isSendingBulk = false);
                  },
            icon: const Icon(Icons.campaign_rounded),
            label: const Text('Tanıtım ve duyuru mesajı oluştur'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed:
                isSendingBulk ? null : () => _retryFailedDebtMessages(context),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Başarısız bakiye mesajlarını yeniden gönder'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SmsHistoryPage()),
            ),
            icon: const Icon(Icons.history_rounded),
            label: const Text('SMS gönderim geçmişi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.operationsOnly) {
      return _buildOperationsCenter();
    }
    final limit =
        int.tryParse(limitCtrl.text) ?? widget.settings.smsMonthlyLimit;
    final sent = widget.settings.smsSentThisMonth;
    final isLimitExceeded = limit != null && sent >= limit;
    final double percent =
        limit != null && limit > 0 ? (sent / limit).clamp(0.0, 1.0) : 0.0;

    return FullScreenSettingsPage(
      title: 'SMS ve WhatsApp Bildirimleri',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // limit uyarı banner'ı
              if (smsEnabled &&
                  selectedProvider == 'sim' &&
                  isLimitExceeded) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: POSColors.redLight,
                    border: Border.all(
                      color: POSColors.red.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: POSColors.red,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SMS Gönderim Limiti Aşıldı!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: POSColors.red,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bu ayki limitiniz ($limit SMS) dolmuştur. Yeni ay başında sayaç otomatik olarak sıfırlanacaktır.',
                              style: const TextStyle(
                                color: POSColors.red,
                                fontSize: 12,
                              ),
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
                    border: Border.all(
                      color: POSColors.amber.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: POSColors.amber,
                        size: 24,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${interruptedLogs.length} Adet SMS\'in Durumu Belirsiz Kaldı',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: POSColors.amberDark,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Uygulama beklenmedik şekilde kapandı. Bu SMS\'lerin gönderilip gönderilmediği belirsizdir. Tekrar göndermek istiyor musunuz?',
                              style: TextStyle(
                                color: POSColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: isSendingBulk
                                      ? null
                                      : _resendInterruptedLogs,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: POSColors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Tekrar Gönder',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: isSendingBulk
                                      ? null
                                      : _discardInterruptedLogs,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: POSColors.red,
                                    side: const BorderSide(
                                      color: POSColors.red,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Yoksay',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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

              _buildWhatsAppConnectionCard(),
              _buildSwitchRow(
                title: 'SMS Bildirimlerini Etkinleştir',
                subtitle: 'Android ana cihazın SIM kartından SMS gönderimi',
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
                  'Yerel SIM Gönderimi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: POSColors.text,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                _buildProviderCard(
                  providerId: 'sim',
                  title: 'Cihazın SIM Kartı (Yerel)',
                  subtitle:
                      'Android cihazınızdaki hattı kullanarak SMS gönderir.',
                  icon: Icons.sim_card_rounded,
                  isSupported: !kIsWeb &&
                      Theme.of(context).platform == TargetPlatform.android,
                ),
                const SizedBox(height: AppSpacing.md),

                // Grup 2: Dinamik Sağlayıcı Alanları
                if (selectedProvider == 'sim') ...[
                  // İzin Durumu
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: hasPermissions
                          ? POSColors.greenLight
                          : POSColors.amberLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (checkingPermissions)
                          const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            hasPermissions
                                ? Icons.check_circle_outline_rounded
                                : Icons.warning_amber_rounded,
                            color: hasPermissions
                                ? POSColors.greenDark
                                : POSColors.amberDark,
                            size: 24,
                          ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            checkingPermissions
                                ? 'İzin durumu kontrol ediliyor…'
                                : hasPermissions
                                    ? 'SMS İzinleri Tanımlı (Gönderime Hazır)'
                                    : 'SMS gönderebilmek için SMS ve Telefon izinleri gereklidir.',
                            style: TextStyle(
                              color: hasPermissions
                                  ? POSColors.greenDark
                                  : POSColors.amberDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (!hasPermissions && !checkingPermissions)
                          TextButton(
                            onPressed: _requestPermissions,
                            child: const Text(
                              'İzin Ver',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: POSColors.amberDark,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // SIM Seçici Dropdown
                  if (hasPermissions && simCards.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      value: selectedSubscriptionId,
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                        color: POSColors.text,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Gönderici SIM Kart',
                        prefixIcon: const Icon(
                          Icons.sim_card_outlined,
                          size: 18,
                          color: POSColors.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: POSColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: POSColors.border),
                        ),
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
                              const Text(
                                'Bu Ayki SMS Kullanımı',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: POSColors.text,
                                ),
                              ),
                              Text(
                                '$sent / $limit SMS',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isLimitExceeded
                                      ? POSColors.red
                                      : POSColors.greenDark,
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
                                    : (percent >= 0.8
                                        ? POSColors.amber
                                        : POSColors.green),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],

                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sim_card_rounded, size: 18),
                    label: const Text('DEBUG: SIM Kartları Listele'),
                    onPressed: _checkPermissionsAndLoadSims,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: AppSpacing.lg),

              // Bakiye iletişimi
              const Text(
                'Müşteri Bakiye İletişimi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: POSColors.text,
                ),
              ),
              const Divider(color: POSColors.border),
              _buildSwitchRow(
                title: 'Bakiye Hatırlatma Tercihlerini Kullan',
                subtitle:
                    'Manuel hatırlatma listesinde belirlediğiniz eşikleri uygular',
                icon: Icons.notifications_active_rounded,
                color: POSColors.blue,
                value: autoDebtReminderEnabled,
                onChanged: (val) {
                  setState(() => autoDebtReminderEnabled = val);
                },
              ),
              if (autoDebtReminderEnabled) ...[
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: minAmountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Önerilecek Minimum Bakiye (TL)',
                    helperText:
                        'Hatırlatma ekranı bu tutarın altındaki müşterileri başlangıçta filtreler.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              if (widget.operationsOnly) ...[
                // Müşteri iletişimi
                const Text(
                  'Müşteri İletişimi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: POSColors.text,
                  ),
                ),
                const Divider(color: POSColors.border),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: isSendingBulk
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF8B5CF6),
                                ),
                              )
                            : const Icon(
                                Icons.people_alt_rounded,
                                size: 16,
                                color: Color(0xFF8B5CF6),
                              ),
                        label: const Text(
                          'Bakiye Hatırlatması',
                          style: TextStyle(color: POSColors.text, fontSize: 12),
                        ),
                        onPressed: !isSendingBulk
                            ? () async {
                                setState(() => isSendingBulk = true);
                                await _sendBulkDebtReminder(context);
                                if (mounted) {
                                  setState(() => isSendingBulk = false);
                                }
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: POSColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: isSendingBulk
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: POSColors.green,
                                ),
                              )
                            : const Icon(
                                Icons.campaign_rounded,
                                size: 16,
                                color: POSColors.green,
                              ),
                        label: const Text(
                          'Tanıtım Mesajı',
                          style: TextStyle(color: POSColors.text, fontSize: 12),
                        ),
                        onPressed: !isSendingBulk
                            ? () async {
                                setState(() => isSendingBulk = true);
                                await _sendBulkAnnouncement(context);
                                if (mounted) {
                                  setState(() => isSendingBulk = false);
                                }
                              }
                            : null,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: POSColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Flexible Templates Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Otomatik Bildirim Şablonları',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: POSColors.text,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 18,
                      color: POSColors.green,
                    ),
                    label: const Text(
                      'Şablon Ekle',
                      style: TextStyle(
                        color: POSColors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () => _showEditTemplateDialog(null, (newTpl) {
                      setState(() {
                        listTemplates.add(newTpl);
                      });
                    }),
                  ),
                ],
              ),
              const Divider(color: POSColors.border),
              const Text(
                'SMS metnini burada düzenleyebilirsiniz. WhatsApp, Meta tarafından onaylanan ve olayla eşleştirilen kurumsal şablonu kullanır.',
                style: TextStyle(
                  color: POSColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),

              // Templates list view
              if (listTemplates.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Tanımlı şablon bulunamadı. Lütfen yeni şablon ekleyin.',
                    style: TextStyle(
                      color: POSColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (int i = 0; i < listTemplates.length; i++) ...[
                      Builder(
                        builder: (context) {
                          final tpl = listTemplates[i];
                          final smsTemplateEnabled =
                              tpl['sms_enabled'] ?? tpl['enabled'] == true;
                          final whatsappTemplateEnabled =
                              tpl['whatsapp_enabled'] == true;
                          final eventId = _canonicalEventId(
                            tpl['id']?.toString() ?? '',
                          );
                          final whatsappSupported = const {
                            'sale_created',
                            'debt_created',
                            'collection_recorded',
                            'order_created',
                            'order_preparing',
                            'order_ready',
                            'order_delivered',
                            'order_cancelled',
                          }.contains(eventId);
                          final whatsappTemplate = whatsappTemplates[eventId];
                          final whatsappStatus = whatsappTemplate?['status'];
                          final whatsappTemplateName =
                              whatsappTemplate?['name'];
                          final isEnabled =
                              smsTemplateEnabled || whatsappTemplateEnabled;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isEnabled
                                  ? POSColors.surface
                                  : Colors.grey[50]!,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isEnabled
                                    ? POSColors.border
                                    : Colors.grey[200]!,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      tpl['name'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: isEnabled
                                            ? POSColors.text
                                            : POSColors.textDisabled,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Mesaj metnini düzenle',
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 18,
                                        color: POSColors.blue,
                                      ),
                                      onPressed: () {
                                        _showEditTemplateDialog(tpl, (
                                          updatedTpl,
                                        ) {
                                          setState(() {
                                            updatedTpl['sms_enabled'] =
                                                smsTemplateEnabled;
                                            updatedTpl['whatsapp_enabled'] =
                                                whatsappTemplateEnabled;
                                            updatedTpl['enabled'] =
                                                smsTemplateEnabled;
                                            listTemplates[i] = updatedTpl;
                                          });
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tpl['template'] ?? '',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isEnabled
                                        ? POSColors.textSecondary
                                        : POSColors.textDisabled,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Switch.adaptive(
                                          value: smsTemplateEnabled,
                                          activeColor: POSColors.green,
                                          onChanged: smsEnabled
                                              ? (val) => setState(() {
                                                    tpl['sms_enabled'] = val;
                                                    tpl['enabled'] = val;
                                                  })
                                              : null,
                                        ),
                                        const Text(
                                          'SMS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Switch.adaptive(
                                          value: whatsappTemplateEnabled,
                                          activeColor: const Color(0xFF16A34A),
                                          onChanged: whatsappConnected &&
                                                  whatsappSupported
                                              ? (val) => setState(
                                                    () =>
                                                        tpl['whatsapp_enabled'] =
                                                            val,
                                                  )
                                              : null,
                                        ),
                                        Text(
                                          !whatsappSupported
                                              ? 'WhatsApp • uygun değil'
                                              : whatsappStatus == null
                                                  ? 'WhatsApp • şablon bekliyor'
                                                  : 'WhatsApp • $whatsappTemplateName • $whatsappStatus',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: whatsappConnected &&
                                                    whatsappSupported
                                                ? POSColors.text
                                                : POSColors.textDisabled,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isEnabled
                                            ? POSColors.blue.withValues(
                                                alpha: 0.08,
                                              )
                                            : Colors.grey[100]!,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tpl['id'] ?? '',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isEnabled
                                              ? POSColors.blue
                                              : POSColors.textDisabled,
                                        ),
                                      ),
                                    ),
                                    if (tpl['id'] != 'sale' &&
                                        tpl['id'] != 'discount' &&
                                        tpl['id'] != 'debt' &&
                                        tpl['id'] != 'collection' &&
                                        tpl['id'] != 'order')
                                      TextButton.icon(
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 14,
                                          color: POSColors.red,
                                        ),
                                        label: const Text(
                                          'Sil',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: POSColors.red,
                                          ),
                                        ),
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
                        },
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 24),
              _buildModalSaveButton(
                onTap: () async {
                  if (_formKey.currentState!.validate()) {
                    final templateJson = jsonEncode(listTemplates);

                    // Save SMS Settings including new SIM and limits fields
                    final updated = widget.settings.copyWith(
                      smsEnabled: smsEnabled,
                      smsProvider: 'sim',
                      smsApiKey: null,
                      smsTemplate: templateJson,
                      smsSimSubscriptionId: selectedSubscriptionId,
                      smsMonthlyLimit: limitCtrl.text.trim().isEmpty
                          ? null
                          : int.tryParse(limitCtrl.text.trim()),
                    );
                    final minAmt = double.tryParse(minAmountCtrl.text) ?? 100.0;
                    final ageDays = int.tryParse(ageDaysCtrl.text) ?? 15;
                    final updatedWithReminder = updated.copyWith(
                      smsAutoDebtReminderEnabled: autoDebtReminderEnabled,
                      smsAutoDebtReminderMinAmount: minAmt,
                      smsAutoDebtReminderDays: ageDays,
                    );
                    try {
                      await ref
                          .read(settingsNotifierProvider.notifier)
                          .updateSettings(updatedWithReminder);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Hata: $e'),
                            backgroundColor: POSColors.red,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: POSColors.text,
              ),
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
      style: TextStyle(
        color: enabled ? POSColors.text : POSColors.textSecondary,
        fontSize: 14,
      ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Kaydet',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _EditTemplateDialog extends StatefulWidget {
  final Map<String, dynamic>? existingTpl;
  final ValueChanged<Map<String, dynamic>> onSave;

  const _EditTemplateDialog({required this.existingTpl, required this.onSave});

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
    templateCtrl = TextEditingController(
      text: widget.existingTpl?['template'] ?? '',
    );

    selectedEvent = widget.existingTpl?['id'] ?? 'sale_created';
    if (selectedEvent == 'sale') selectedEvent = 'sale_created';
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

  Widget _buildVariableChip(
    TextEditingController controller,
    String token,
    String label,
  ) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, color: POSColors.green),
      ),
      backgroundColor: POSColors.green.withValues(alpha: 0.08),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onPressed: () {
        final text = controller.text;
        final selection = controller.selection;
        if (selection.start >= 0) {
          final newText = text.replaceRange(
            selection.start,
            selection.end,
            token,
          );
          controller.text = newText;
          controller.selection = TextSelection.collapsed(
            offset: selection.start + token.length,
          );
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
      'debt_created',
      'collection_recorded',
      'order_created',
      'order_preparing',
      'order_ready',
      'order_delivered',
      'order_cancelled',
      'balance_reminder',
    ];
    if (!validEvents.contains(selectedEvent)) {
      selectedEvent = 'sale_created';
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isNew ? 'Yeni Şablon Ekle' : 'Şablonu Düzenle',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Şablon adı gerekli' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedEvent,
                style: const TextStyle(fontSize: 14, color: Colors.black),
                decoration: InputDecoration(
                  labelText: 'Tetikleyici Durum (Olay)',
                  prefixIcon: const Icon(Icons.flash_on_rounded, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'sale_created',
                    child: Text('Satış Tamamlandığında'),
                  ),
                  DropdownMenuItem(
                    value: 'debt_created',
                    child: Text('Borç Eklendiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'collection_recorded',
                    child: Text('Tahsilat Yapıldığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_created',
                    child: Text('Sipariş Alındığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_preparing',
                    child: Text('Sipariş Hazırlanmaya Başladığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_ready',
                    child: Text('Sipariş Hazırlandığında'),
                  ),
                  DropdownMenuItem(
                    value: 'order_delivered',
                    child: Text('Sipariş Teslim Edildiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'order_cancelled',
                    child: Text('Sipariş İptal Edildiğinde'),
                  ),
                  DropdownMenuItem(
                    value: 'balance_reminder',
                    child: Text('Bakiye Hatırlatması Gönderildiğinde'),
                  ),
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Şablon içeriği gerekli' : null,
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kullanılabilir Değişkenler:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: POSColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildVariableChip(templateCtrl, '{customer}', 'Müşteri'),
                  _buildVariableChip(templateCtrl, '{amount}', 'Tutar'),
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
          child: const Text(
            'İptal',
            style: TextStyle(color: POSColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final result = {
                'id': selectedEvent,
                'name': nameCtrl.text.trim(),
                'template': templateCtrl.text.trim(),
                'enabled': widget.existingTpl?['sms_enabled'] ??
                    widget.existingTpl?['enabled'] ??
                    true,
                'sms_enabled': widget.existingTpl?['sms_enabled'] ??
                    widget.existingTpl?['enabled'] ??
                    true,
                'whatsapp_enabled':
                    widget.existingTpl?['whatsapp_enabled'] ?? false,
              };
              widget.onSave(result);
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: POSColors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
  State<_BulkAnnouncementDialog> createState() =>
      _BulkAnnouncementDialogState();
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
      title: const Text('Tanıtım ve Duyuru Mesajı'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: msgCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Tanıtım veya Duyuru Mesajı',
            hintText:
                'İletişim izni bulunan müşterilere gönderilecek metni yazın...',
            border: OutlineInputBorder(),
          ),
          validator: (val) =>
              val == null || val.trim().isEmpty ? 'Boş bırakılamaz' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Vazgeç',
            style: TextStyle(color: POSColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, msgCtrl.text.trim());
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: POSColors.text,
            foregroundColor: Colors.white,
          ),
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}
