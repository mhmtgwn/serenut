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
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart'; // FullScreenSettingsPage
import 'package:serenutos/domain/models/sms_log_entry.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sms_message_analyzer.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/theme.dart'; // POSColors & AppSpacing
import 'package:serenutos/presentation/pages/settings/widgets/sms_sub_widgets.dart';


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
  String selectedChannel = 'sms';
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
              return MapEntry(row['event_key']?.toString() ?? '', {
                'status': row['status']?.toString() ?? 'pending',
                'name': row['meta_template_name']?.toString() ?? '',
              });
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
          content: Text('GÃ¶nderildi: $sentCount âœ… | BaÅŸarÄ±sÄ±z: $failedCount âŒ'),
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
          content: Text('Belirsiz durumdaki SMS kayÄ±tlarÄ± iptal edildi.'),
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
        debugPrint('SIM kartlar yÃ¼klenemedi: $e');
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
        'name': 'SatÄ±ÅŸ OnayÄ±',
        'template':
            'Merhaba {customer}, {id} numaralÄ± satÄ±ÅŸ iÅŸleminiz tamamlandÄ±. Toplam: {amount}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'debt',
        'name': 'Vadeli Bakiye KaydÄ±',
        'template':
            'Merhaba {customer}, {id} numaralÄ± iÅŸlem sonrasÄ± vadeli tutarÄ±nÄ±z {debt}, gÃ¼ncel bakiyeniz {balance}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'collection',
        'name': 'Ã–deme AlÄ±ndÄ±',
        'template':
            'Merhaba {customer}, {amount} tutarÄ±ndaki Ã¶demeniz alÄ±ndÄ±. Kalan bakiyeniz {debt}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order',
        'name': 'SipariÅŸ AlÄ±ndÄ±',
        'template':
            'Merhaba {customer}, {id} numaralÄ± sipariÅŸiniz alÄ±ndÄ±. Toplam: {amount}. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_preparing',
        'name': 'SipariÅŸ HazÄ±rlanÄ±yor',
        'template':
            'Merhaba {customer}, {id} numaralÄ± sipariÅŸiniz hazÄ±rlanÄ±yor. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_ready',
        'name': 'SipariÅŸ HazÄ±r',
        'template':
            'Merhaba {customer}, {id} numaralÄ± sipariÅŸiniz hazÄ±r. Teslim alabilirsiniz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_delivered',
        'name': 'SipariÅŸ Teslim Edildi',
        'template':
            'Merhaba {customer}, {id} numaralÄ± sipariÅŸiniz teslim edildi. Bizi tercih ettiÄŸiniz iÃ§in teÅŸekkÃ¼r ederiz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'order_cancelled',
        'name': 'SipariÅŸ Ä°ptal Edildi',
        'template':
            'Merhaba {customer}, {id} numaralÄ± sipariÅŸiniz iptal edildi. AyrÄ±ntÄ±lÄ± bilgi iÃ§in iÅŸletmemizle iletiÅŸime geÃ§ebilirsiniz. {business}',
        'enabled': true,
        'sms_enabled': true,
        'whatsapp_enabled': false,
      },
      {
        'id': 'balance_reminder',
        'name': 'Bakiye HatÄ±rlatmasÄ±',
        'template':
            'Merhaba {customer}, hesabÄ±nÄ±zdaki gÃ¼ncel vadeli bakiye {balance}. Ã–deme bilgisi iÃ§in iÅŸletmemizle iletiÅŸime geÃ§ebilirsiniz. {business}',
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
        // Eski sÃ¼rÃ¼mlerde ayrÄ± bir indirim olayÄ± yayÄ±nlanmadÄ±ÄŸÄ± halde bu
        // ÅŸablon gÃ¶steriliyordu. HiÃ§ tetiklenemeyen ayarÄ± arayÃ¼zden kaldÄ±r.
        list.removeWhere(
          (item) =>
              item['id'] == 'discount' || item['id'] == 'discount_applied',
        );
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
        'Merhaba {customer}, hesabÄ±nÄ±zdaki gÃ¼ncel vadeli bakiye {balance}. Ã–deme bilgisi iÃ§in iÅŸletmemizle iletiÅŸime geÃ§ebilirsiniz. {business}';
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
            title: const Text('YarÄ±m Kalan Bakiye Ä°letiÅŸimi'),
            content: Text(
              'Sistemde tamamlanmamÄ±ÅŸ bir bakiye hatÄ±rlatma gÃ¶nderimi bulundu (${pendingIds.length} mÃ¼ÅŸteri bekliyor). Devam etmek ister misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Yeniden BaÅŸlat',
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
                  'BorÃ§lu ve telefon numarasÄ± tanÄ±mlÄ± mÃ¼ÅŸteri bulunamadÄ±.',
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
                                ? 'Bakiye hatÄ±rlatma gÃ¶nderimi iptal edildi. GÃ¶nderilen: $sentCount âœ… BaÅŸarÄ±sÄ±z: $failedCount âŒ'
                                : 'GÃ¶nderildi: $sentCount âœ…  BaÅŸarÄ±sÄ±z: $failedCount âŒ',
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
                  title: const Text('Bakiye HatÄ±rlatmalarÄ± GÃ¶nderiliyor'),
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
                      Text('Ä°lerleme: $totalProcessed / $totalCount'),
                      Text(
                        'BaÅŸarÄ±lÄ±: $sentCount âœ… | BaÅŸarÄ±sÄ±z: $failedCount âŒ',
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
                        isBulkCancelled ? 'Ä°ptal Ediliyor...' : 'Ä°ptal Et',
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
            title: const Text('SMS AlÄ±cÄ±larÄ±nÄ± SeÃ§'),
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
                            '${selected.length} / ${debtors.length} mÃ¼ÅŸteri â€¢ En uzun mesaj: ${analysis.characters} karakter, ${analysis.segments} SMS',
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
                                : 'TÃ¼mÃ¼nÃ¼ seÃ§',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      labelText: 'MÃ¼ÅŸteri veya telefon ara',
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
                                  ? 'TÃ¼m borÃ§lar'
                                  : '${amount.toStringAsFixed(0)} â‚º Ã¼zeri',
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
                            '${customer.phone} â€¢ ${customer.balance.abs().toStringAsFixed(2).replaceAll('.', ',')} â‚º',
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
                child: const Text('VazgeÃ§'),
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
                label: Text('${selected.length} kiÅŸiye gÃ¶nder'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendBulkAnnouncement(BuildContext context) async {
    try {
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customers = await customerRepo.findAll();
      final targets =
          customers.where((c) => c.phone.trim().isNotEmpty).toList();

      if (targets.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Telefon numarasÄ± tanÄ±mlÄ± mÃ¼ÅŸteri bulunamadÄ±.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;
      final confirmText = await showDialog<String>(
        context: context,
        builder: (ctx) =>
            SmsBulkAnnouncementDialog(recipientCount: targets.length),
      );

      if (confirmText == null || confirmText.isEmpty) return;

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
              '$sentCount tanÄ±tÄ±m ve duyuru mesajÄ± gÃ¶nderim sÄ±rasÄ±na alÄ±ndÄ±.',
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
            content: Text('Yeniden gÃ¶nderilecek baÅŸarÄ±sÄ±z SMS bulunmuyor.'),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('BaÅŸarÄ±sÄ±z SMSâ€™leri Yeniden GÃ¶nder'),
        content: Text(
          '${failed.length} mesaj sÄ±rayla yeniden gÃ¶nderilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('VazgeÃ§'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yeniden gÃ¶nder'),
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
          content: Text('$sent / ${failed.length} SMS baÅŸarÄ±yla gÃ¶nderildi.'),
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
          SmsEditTemplateDialog(existingTpl: existingTpl, onSave: onSave),
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

  String _triggerLabel(String eventId) =>
      const {
        'sale_created': 'SatÄ±ÅŸ tamamlandÄ±ÄŸÄ±nda',
        'debt_created': 'Vadeli iÅŸlem oluÅŸturulduÄŸunda',
        'collection_recorded': 'Tahsilat kaydedildiÄŸinde',
        'order_created': 'SipariÅŸ alÄ±ndÄ±ÄŸÄ±nda',
        'order_preparing': 'SipariÅŸ hazÄ±rlanmaya baÅŸladÄ±ÄŸÄ±nda',
        'order_ready': 'SipariÅŸ hazÄ±r olduÄŸunda',
        'order_delivered': 'SipariÅŸ teslim edildiÄŸinde',
        'order_cancelled': 'SipariÅŸ iptal edildiÄŸinde',
        'balance_reminder': 'Bakiye hatÄ±rlatmasÄ± gÃ¶nderildiÄŸinde',
      }[eventId] ??
      'Ä°ÅŸlem gerÃ§ekleÅŸtiÄŸinde';

  String _whatsappStatusLabel(String status) => switch (status.toLowerCase()) {
        'approved' || 'active' => 'Meta onaylÄ±',
        'pending' || 'in_review' => 'Meta incelemesinde',
        'rejected' => 'Meta tarafÄ±ndan reddedildi',
        'paused' || 'disabled' => 'Meta tarafÄ±ndan durduruldu',
        _ => 'Åablon durumu: $status',
      };

  Widget _buildChannelSelector() {
    final whatsappColor =
        whatsappConnected ? const Color(0xFF16A34A) : POSColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildChannelTab(
              id: 'sms',
              icon: Icons.sms_rounded,
              title: 'SMS',
              subtitle: smsEnabled ? 'Etkin' : 'KapalÄ±',
              color: POSColors.blue,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildChannelTab(
              id: 'whatsapp',
              icon: Icons.chat_rounded,
              title: 'WhatsApp',
              subtitle: whatsappStatusLoading
                  ? 'Kontrol ediliyor'
                  : whatsappConnected
                      ? 'BaÄŸlÄ±'
                      : 'BaÄŸlantÄ± gerekli',
              color: whatsappColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTab({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final selected = selectedChannel == id;
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => selectedChannel = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: color.withValues(alpha: 0.35))
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x120F172A),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                      ? 'BaÄŸlantÄ± durumu kontrol ediliyorâ€¦'
                      : whatsappConnected
                          ? '${whatsappPhone ?? 'Ä°ÅŸletme numarasÄ±'} baÄŸlÄ±. AÅŸaÄŸÄ±daki olaylar iÃ§in WhatsAppâ€™Ä± ayrÄ± ayrÄ± aÃ§abilirsiniz.'
                          : 'BaÄŸlantÄ± kurulmadÄ±. Firma sahibi mÃ¼ÅŸteri portalÄ±ndaki Bildirim KanallarÄ± bÃ¶lÃ¼mÃ¼nden hesabÄ±nÄ± baÄŸlamalÄ±dÄ±r.',
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
      title: 'Mesaj GÃ¶nder',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF12352B), Color(0xFF1D5949)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MÃ¼ÅŸterilerinize ulaÅŸÄ±n',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'GÃ¶nderim tÃ¼rÃ¼nÃ¼ seÃ§in; alÄ±cÄ±larÄ± ve mesajÄ± onayladÄ±ktan sonra gÃ¶nderin.',
                  style: TextStyle(color: Color(0xFFD5E7E1), height: 1.4),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SmsChannelStatusChip(
                      icon: Icons.sms_rounded,
                      label: smsEnabled ? 'SMS hazÄ±r' : 'SMS kapalÄ±',
                      ready: smsEnabled,
                    ),
                    SmsChannelStatusChip(
                      icon: Icons.chat_rounded,
                      label: whatsappStatusLoading
                          ? 'WhatsApp kontrol ediliyor'
                          : whatsappConnected
                              ? 'WhatsApp baÄŸlÄ±'
                              : 'WhatsApp baÄŸlantÄ±sÄ± gerekli',
                      ready: whatsappConnected,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SmsOperationsSectionLabel('YENÄ° GÃ–NDERÄ°M'),
          const SizedBox(height: 10),
          SmsMessageActionCard(
            icon: Icons.campaign_rounded,
            color: const Color(0xFF7C3AED),
            title: 'TanÄ±tÄ±m mesajÄ±',
            description:
                'Kampanya, yeni Ã¼rÃ¼n, Ã§alÄ±ÅŸma saati veya Ã¶zel gÃ¼n mesajÄ± gÃ¶nderin.',
            actionLabel: 'TanÄ±tÄ±m oluÅŸtur',
            enabled: !isSendingBulk && smsEnabled,
            onTap: () async {
              setState(() => isSendingBulk = true);
              await _sendBulkAnnouncement(context);
              if (mounted) setState(() => isSendingBulk = false);
            },
          ),
          const SizedBox(height: 12),
          SmsMessageActionCard(
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFD97706),
            title: 'Bakiye hatÄ±rlatmasÄ±',
            description:
                'Bakiyesi bulunan mÃ¼ÅŸterileri seÃ§in ve kiÅŸiselleÅŸtirilmiÅŸ hatÄ±rlatma gÃ¶nderin.',
            actionLabel: 'MÃ¼ÅŸterileri seÃ§',
            enabled: !isSendingBulk && smsEnabled,
            onTap: () async {
              setState(() => isSendingBulk = true);
              await _sendBulkDebtReminder(context);
              if (mounted) setState(() => isSendingBulk = false);
            },
          ),
          const SizedBox(height: 22),
          const SmsOperationsSectionLabel('GÃ–NDERÄ°M YÃ–NETÄ°MÄ°'),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: POSColors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  enabled: !isSendingBulk,
                  leading: const Icon(
                    Icons.replay_rounded,
                    color: POSColors.textSecondary,
                  ),
                  title: const Text(
                    'BaÅŸarÄ±sÄ±z hatÄ±rlatmalarÄ± yeniden dene',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: isSendingBulk
                      ? null
                      : () => _retryFailedDebtMessages(context),
                ),
              ],
            ),
          ),
          if (!smsEnabled) ...[
            const SizedBox(height: 14),
            const SmsMessageInfoBanner(
              icon: Icons.info_outline_rounded,
              text:
                  'GÃ¶nderim yapabilmek iÃ§in Bildirim AyarlarÄ± bÃ¶lÃ¼mÃ¼nden SMS kanalÄ±nÄ± etkinleÅŸtirin.',
            ),
          ],
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
      title: 'MÃ¼ÅŸteri Bildirimleri',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // limit uyarÄ± banner'Ä±
              if (selectedChannel == 'sms' &&
                  smsEnabled &&
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
                              'SMS GÃ¶nderim Limiti AÅŸÄ±ldÄ±!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: POSColors.red,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bu ayki limitiniz ($limit SMS) dolmuÅŸtur. Yeni ay baÅŸÄ±nda sayaÃ§ otomatik olarak sÄ±fÄ±rlanacaktÄ±r.',
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
              if (selectedChannel == 'sms' &&
                  smsEnabled &&
                  interruptedLogs.isNotEmpty) ...[
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
                              '${interruptedLogs.length} Adet SMS\'in Durumu Belirsiz KaldÄ±',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: POSColors.amberDark,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Uygulama beklenmedik ÅŸekilde kapandÄ±. Bu SMS\'lerin gÃ¶nderilip gÃ¶nderilmediÄŸi belirsizdir. Tekrar gÃ¶ndermek istiyor musunuz?',
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
                                    'Tekrar GÃ¶nder',
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

              _buildChannelSelector(),
              const SizedBox(height: AppSpacing.md),
              if (selectedChannel == 'whatsapp') _buildWhatsAppConnectionCard(),
              if (selectedChannel == 'sms') ...[
                _buildSwitchRow(
                  title: 'SMS Bildirimlerini EtkinleÅŸtir',
                  subtitle: 'Android ana cihazÄ±n SIM kartÄ±ndan SMS gÃ¶nderimi',
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
                    'Yerel SIM GÃ¶nderimi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: POSColors.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  _buildProviderCard(
                    providerId: 'sim',
                    title: 'CihazÄ±n SIM KartÄ± (Yerel)',
                    subtitle:
                        'Android cihazÄ±nÄ±zdaki hattÄ± kullanarak SMS gÃ¶nderir.',
                    icon: Icons.sim_card_rounded,
                    isSupported: !kIsWeb &&
                        Theme.of(context).platform == TargetPlatform.android,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Grup 2: Dinamik SaÄŸlayÄ±cÄ± AlanlarÄ±
                  if (selectedProvider == 'sim') ...[
                    // Ä°zin Durumu
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
                                  ? 'Ä°zin durumu kontrol ediliyorâ€¦'
                                  : hasPermissions
                                      ? 'SMS Ä°zinleri TanÄ±mlÄ± (GÃ¶nderime HazÄ±r)'
                                      : 'SMS gÃ¶nderebilmek iÃ§in SMS ve Telefon izinleri gereklidir.',
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
                                'Ä°zin Ver',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: POSColors.amberDark,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // SIM SeÃ§ici Dropdown
                    if (hasPermissions && simCards.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: selectedSubscriptionId,
                        dropdownColor: Colors.white,
                        style: const TextStyle(
                          color: POSColors.text,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'GÃ¶nderici SIM Kart',
                          prefixIcon: const Icon(
                            Icons.sim_card_outlined,
                            size: 18,
                            color: POSColors.textSecondary,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: POSColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: POSColors.border,
                            ),
                          ),
                          filled: true,
                          fillColor: POSColors.surface,
                        ),
                        items: simCards.map((sim) {
                          final slot = (sim['simSlotIndex'] as int? ?? 0) + 1;
                          final op =
                              sim['displayName'] ?? 'Bilinmeyen OperatÃ¶r';
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

                    // SMS Limit GiriÅŸi
                    _buildFormTextField(
                      controller: limitCtrl,
                      label: 'AylÄ±k SMS GÃ¶nderim Limiti (BoÅŸ = Limitsiz)',
                      icon: Icons.speed_rounded,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Limit Durum Ã‡ubuÄŸu
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
                                  'Bu Ayki SMS KullanÄ±mÄ±',
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
                      label: const Text('DEBUG: SIM KartlarÄ± Listele'),
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

                // Bakiye iletiÅŸimi
                const Text(
                  'MÃ¼ÅŸteri Bakiye Ä°letiÅŸimi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: POSColors.text,
                  ),
                ),
                const Divider(color: POSColors.border),
                _buildSwitchRow(
                  title: 'Bakiye HatÄ±rlatma Tercihlerini Kullan',
                  subtitle:
                      'Manuel hatÄ±rlatma listesinde belirlediÄŸiniz eÅŸikleri uygular',
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
                      labelText: 'Ã–nerilecek Minimum Bakiye (TL)',
                      helperText:
                          'HatÄ±rlatma ekranÄ± bu tutarÄ±n altÄ±ndaki mÃ¼ÅŸterileri baÅŸlangÄ±Ã§ta filtreler.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],

              if (widget.operationsOnly) ...[
                // MÃ¼ÅŸteri iletiÅŸimi
                const Text(
                  'MÃ¼ÅŸteri Ä°letiÅŸimi',
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
                          'Bakiye HatÄ±rlatmasÄ±',
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
                          'TanÄ±tÄ±m MesajÄ±',
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
                  Text(
                    selectedChannel == 'sms'
                        ? 'SMS otomasyonlarÄ±'
                        : 'WhatsApp otomasyonlarÄ±',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: POSColors.text,
                    ),
                  ),
                  if (selectedChannel == 'sms')
                    TextButton.icon(
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        size: 18,
                        color: POSColors.green,
                      ),
                      label: const Text(
                        'Åablon Ekle',
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
              Text(
                selectedChannel == 'sms'
                    ? 'Hangi iÅŸlemlerde otomatik SMS gÃ¶nderileceÄŸini seÃ§in ve mÃ¼ÅŸteriye gidecek metni dÃ¼zenleyin.'
                    : 'Hangi iÅŸlemlerde WhatsApp bildirimi gÃ¶nderileceÄŸini seÃ§in. YalnÄ±z Meta onaylÄ± ÅŸablonlar etkinleÅŸtirilebilir.',
                style: const TextStyle(
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
                    'TanÄ±mlÄ± ÅŸablon bulunamadÄ±. LÃ¼tfen yeni ÅŸablon ekleyin.',
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
                          final whatsappReady = whatsappStatus == 'approved' ||
                              whatsappStatus == 'active';
                          final isEnabled = selectedChannel == 'sms'
                              ? smsTemplateEnabled
                              : whatsappTemplateEnabled;
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
                                    if (selectedChannel == 'sms')
                                      IconButton(
                                        tooltip: 'Mesaj metnini dÃ¼zenle',
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
                                  selectedChannel == 'sms'
                                      ? tpl['template'] ?? ''
                                      : !whatsappSupported
                                          ? 'Bu iÅŸlem iÃ§in WhatsApp ÅŸablonu bulunmuyor.'
                                          : whatsappTemplateName == null ||
                                                  whatsappTemplateName.isEmpty
                                              ? 'Meta ÅŸablonu henÃ¼z oluÅŸturulmadÄ±.'
                                              : 'Meta ÅŸablonu: $whatsappTemplateName',
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
                                    if (selectedChannel == 'sms')
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
                                    if (selectedChannel == 'whatsapp')
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Switch.adaptive(
                                            value: whatsappTemplateEnabled,
                                            activeColor: const Color(
                                              0xFF16A34A,
                                            ),
                                            onChanged: whatsappConnected &&
                                                    whatsappSupported &&
                                                    whatsappReady
                                                ? (val) => setState(
                                                      () =>
                                                          tpl['whatsapp_enabled'] =
                                                              val,
                                                    )
                                                : null,
                                          ),
                                          Text(
                                            !whatsappSupported
                                                ? 'KullanÄ±lamÄ±yor'
                                                : whatsappStatus == null
                                                    ? 'Meta onayÄ± bekleniyor'
                                                    : _whatsappStatusLabel(
                                                        whatsappStatus,
                                                      ),
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
                                    Text(
                                      _triggerLabel(eventId),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: POSColors.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (selectedChannel == 'sms' &&
                                        tpl['id'] != 'sale' &&
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

