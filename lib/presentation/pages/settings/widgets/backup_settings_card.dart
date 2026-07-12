part of '../../settings_page.dart';

// Extracted Backup and SMS Settings Card sheets for SettingsPage
extension SettingsBackupSmsSheets on _SettingsPageState {
  void _showSmsSettingsSheet(Settings settings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _SmsSettingsSheet(settings: settings, pageState: this),
      ),
    );
  }

  void _showEditTemplateDialog(Map<String, dynamic>? existingTpl, ValueChanged<Map<String, dynamic>> onSave) {
    showDialog(
      context: context,
      builder: (ctx) => _EditTemplateDialog(existingTpl: existingTpl, onSave: onSave, pageState: this),
    );
  }

  Widget _buildVariableChip(TextEditingController controller, String token, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, color: _kGreen)),
      backgroundColor: _kGreen.withOpacity(0.08),
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

  void _showContactImportSheet() {
    final List<Map<String, String>> simulatedContacts = [
      {'name': 'Ahmet Yılmaz', 'phone': '05321112233', 'email': 'ahmet.yilmaz@gmail.com'},
      {'name': 'Elif Demir', 'phone': '05422223344', 'email': 'elif.demir@hotmail.com'},
      {'name': 'Mehmet Kaya', 'phone': '05053334455', 'email': 'mehmet.kaya@yahoo.com'},
      {'name': 'Zeynep Çelik', 'phone': '05304445566', 'email': 'zeynep.celik@gmail.com'},
      {'name': 'Mustafa Öztürk', 'phone': '05555556677', 'email': 'mustafa.ozturk@outlook.com'},
      {'name': 'Fatma Yıldız', 'phone': '05336667788', 'email': 'fatmayildiz@gmail.com'},
      {'name': 'Can Arslan', 'phone': '05447778899', 'email': 'can.arslan@gmail.com'},
      {'name': 'Selin Yurt', 'phone': '05359998877', 'email': 'selin.yurt@gmail.com'},
      {'name': 'Burak Şahin', 'phone': '05411234567', 'email': 'burak.sahin@hotmail.com'},
      {'name': 'Aslı Karaca', 'phone': '05399876543', 'email': 'asli.karaca@gmail.com'},
    ];

    final List<int> selectedIndices = [];
    String searchQuery = '';

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Consumer(
          builder: (routeCtx, ref, child) => StatefulBuilder(
            builder: (ctx, setModalState) {
              final List<int> filteredIndices = [];
              for (int i = 0; i < simulatedContacts.length; i++) {
                final c = simulatedContacts[i];
                if (searchQuery.isEmpty ||
                    c['name']!.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    c['phone']!.contains(searchQuery)) {
                  filteredIndices.add(i);
                }
              }

              return FullScreenSettingsPage(
                title: 'Rehberden İçe Aktar',
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Cihazınızdaki kişileri sisteme müşteri olarak ekleyin. Çakışan telefon numaraları otomatik olarak filtrelenecektir.',
                          style: TextStyle(fontSize: 13, color: _kTextSecondary),
                        ),
                      ),
                    ),
                    
                    // Arama kutusu
                    Container(
                      height: 38,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3E3E9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        style: const TextStyle(fontSize: 14, color: _kTextPrimary),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, color: _kTextSecondary, size: 18),
                          hintText: 'Rehberde Ara...',
                          hintStyle: TextStyle(color: _kTextSecondary, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 9),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            searchQuery = val.trim();
                          });
                        },
                      ),
                    ),

                    // Seçim kontrolleri
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: Icon(
                            (selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                                ? Icons.check_box_rounded 
                                : Icons.check_box_outline_blank_rounded,
                            size: 20,
                            color: _kGreen,
                          ),
                          label: Text(
                            (selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                                ? 'Seçilenleri Temizle' 
                                : 'Tümünü Seç',
                            style: const TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () {
                            setModalState(() {
                              if (selectedIndices.length == filteredIndices.length) {
                                selectedIndices.clear();
                              } else {
                                selectedIndices.clear();
                                selectedIndices.addAll(filteredIndices);
                              }
                            });
                          },
                        ),
                        Text(
                          '${selectedIndices.length} / ${filteredIndices.length} Seçildi',
                          style: const TextStyle(fontSize: 13, color: _kTextSecondary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(color: _kBorderColor),

                    // Kişi Listesi
                    if (filteredIndices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'Aranan kişi bulunamadı.',
                            style: TextStyle(color: _kTextSecondary, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (final contactIdx in filteredIndices) ...[
                            Builder(
                              builder: (context) {
                                final contact = simulatedContacts[contactIdx];
                                final isSelected = selectedIndices.contains(contactIdx);
                                return CheckboxListTile(
                                  value: isSelected,
                                  activeColor: _kGreen,
                                  title: Text(
                                    contact['name']!,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
                                  ),
                                  subtitle: Text(
                                    contact['phone']!,
                                    style: const TextStyle(color: _kTextSecondary, fontSize: 13),
                                  ),
                                  secondary: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _kBlue.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        contact['name']!.isNotEmpty ? contact['name']![0].toUpperCase() : '👤',
                                        style: const TextStyle(color: _kBlue, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  onChanged: (checked) {
                                    setModalState(() {
                                      if (checked == true) {
                                        selectedIndices.add(contactIdx);
                                      } else {
                                        selectedIndices.remove(contactIdx);
                                      }
                                    });
                                  },
                                );
                              }
                            ),
                            const Divider(height: 1, color: _kBorderColor),
                          ]
                        ],
                      ),
                    const SizedBox(height: 16),
                    
                    // İçe Aktarma Butonu
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: selectedIndices.isEmpty
                            ? null
                            : () async {
                                final customers = ref.read(customersControllerProvider).value ?? [];
                                int importedCount = 0;
                                int skippedCount = 0;

                                for (final idx in selectedIndices) {
                                  final contact = simulatedContacts[idx];
                                  final phone = contact['phone']!;
                                  
                                  if (customers.any((c) => c.phone == phone)) {
                                    skippedCount++;
                                    continue;
                                  }

                                  final newCustomer = CustomerEntity(
                                    id: const Uuid().v4(),
                                    name: contact['name']!,
                                    email: contact['email']!,
                                    phone: phone,
                                    balance: 0.0,
                                    createdAt: DateTime.now(),
                                  );
                                  await ref.read(customersControllerProvider.notifier).addCustomer(newCustomer);
                                  importedCount++;
                                }

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        importedCount > 0
                                            ? '$importedCount kişi rehberden başarıyla içe aktarıldı.${skippedCount > 0 ? " ($skippedCount kişi zaten kayıtlı olduğu için atlandı.)" : ""}'
                                            : 'Seçilen kişilerin tamamı zaten sistemde kayıtlı.',
                                      ),
                                      backgroundColor: importedCount > 0 ? _kGreen : _kOrange,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          selectedIndices.isEmpty 
                              ? 'Lütfen Kişi Seçin' 
                              : 'Seçilenleri İçe Aktar (${selectedIndices.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
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
        // Ensure all default templates are present in the list (if missing, add them)
        for (final def in defaultTemplates) {
          if (!list.any((t) => t['id'] == def['id'])) {
            list.add(def);
          }
        }
        return list;
      } else if (decoded is Map) {
        return [
          {
            'id': 'sale',
            'name': 'Satış Tamamlandı',
            'template': decoded['sale']?.toString() ?? defaultTemplates[0]['template'],
            'enabled': true,
          },
          {
            'id': 'discount',
            'name': 'İndirim Uygulandı',
            'template': decoded['discount']?.toString() ?? defaultTemplates[1]['template'],
            'enabled': true,
          },
          {
            'id': 'debt',
            'name': 'Borç/Veresiye Kaydı',
            'template': decoded['debt']?.toString() ?? defaultTemplates[2]['template'],
            'enabled': true,
          },
          {
            'id': 'collection',
            'name': 'Alacak / Tahsilat Alındı',
            'template': decoded['collection']?.toString() ?? defaultTemplates[3]['template'],
            'enabled': true,
          },
          {
            'id': 'order',
            'name': 'Sipariş Alındı',
            'template': decoded['order']?.toString() ?? defaultTemplates[4]['template'],
            'enabled': true,
          },
          defaultTemplates[5], // order_preparing
          defaultTemplates[6], // order_ready
          defaultTemplates[7], // order_delivered
          defaultTemplates[8], // order_cancelled
        ];
      }
    } catch (_) {
      return [
        {
          'id': 'sale',
          'name': 'Satış Tamamlandı',
          'template': templateStr,
          'enabled': true,
        },
        defaultTemplates[1],
        defaultTemplates[2],
        defaultTemplates[3],
        defaultTemplates[4],
        defaultTemplates[5],
        defaultTemplates[6],
        defaultTemplates[7],
        defaultTemplates[8],
      ];
    }
    return defaultTemplates;
  }

  void _showBackupRestoreSheet() {
    PinGateDialog.checkAndShow(context, title: 'Yedekleme Yönetimi', onVerified: () {
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => const BackupManagePage(),
        ),
      );
    });
  }

  Future<void> _sendBulkDebtReminder(BuildContext context) async {
    try {
      final customerRepo = await ref.read(customerRepositoryProvider.future);
      final customers = await customerRepo.findAll();
      final debtors = customers.where((c) => c.balance < 0 && c.phone.trim().isNotEmpty).toList();

      if (debtors.isEmpty) {
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
          content: Text('${debtors.length} adet borçlu müşteriye SMS hatırlatma mesajı gönderilecektir. Devam edilsin mi?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç', style: TextStyle(color: _kTextSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Devam Et', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      final smsService = ref.read(smsServiceProvider);
      final logRepo = ref.read(smsLogRepositoryProvider);

      int sentCount = 0;
      for (final customer in debtors) {
        final debtAmount = customer.balance.abs();
        final message = 'Sn. ${customer.name}, veresiye hesabınızda ${debtAmount.toStringAsFixed(2).replaceAll('.', ',')} ₺ borç bulunmaktadır. Ödemenizi rica ederiz.';

        // Rate limiting delay to protect API and device SIM channel
        await Future.delayed(const Duration(milliseconds: 300));

        final logId = const Uuid().v4();
        await logRepo.insertLog(SmsLogEntry(
          id: logId,
          phone: customer.phone,
          eventType: 'bulk_debt_reminder',
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
          SnackBar(content: Text('$sentCount adet borç hatırlatma mesajı gönderim sırasına alındı.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: _kPink, behavior: SnackBarBehavior.floating),
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

        // Rate limiting delay to protect API and device SIM channel
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
          SnackBar(content: Text('Hata: $e'), backgroundColor: _kPink, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _SmsSettingsSheet extends ConsumerStatefulWidget {
  final Settings settings;
  final _SettingsPageState pageState;

  const _SmsSettingsSheet({required this.settings, required this.pageState});

  @override
  ConsumerState<_SmsSettingsSheet> createState() => _SmsSettingsSheetState();
}

class _SmsSettingsSheetState extends ConsumerState<_SmsSettingsSheet> {
  final _formKey = GlobalKey<FormState>();
  late List<Map<String, dynamic>> listTemplates;
  late final TextEditingController apiKeyCtrl;
  late final TextEditingController minAmountCtrl;
  late final TextEditingController ageDaysCtrl;
  late bool smsEnabled;
  late String selectedProvider;
  late bool autoDebtReminderEnabled;
  bool isSendingBulk = false;

  @override
  void initState() {
    super.initState();
    listTemplates = widget.pageState._parseFlexibleSmsTemplates(widget.settings.smsTemplate);
    apiKeyCtrl = TextEditingController(text: widget.settings.smsApiKey ?? '');
    smsEnabled = widget.settings.smsEnabled;
    selectedProvider = widget.settings.smsProvider ?? 'sim';
    autoDebtReminderEnabled = widget.settings.smsAutoDebtReminderEnabled;
    minAmountCtrl = TextEditingController(text: widget.settings.smsAutoDebtReminderMinAmount.toStringAsFixed(0));
    ageDaysCtrl = TextEditingController(text: widget.settings.smsAutoDebtReminderDays.toString());
  }

  @override
  void dispose() {
    apiKeyCtrl.dispose();
    minAmountCtrl.dispose();
    ageDaysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenSettingsPage(
      title: 'SMS Servis Ayarları',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.pageState._buildSwitchRow(
              title: 'SMS Bildirimlerini Etkinleştir',
              subtitle: 'İşlem sonrası otomatik mesaj gönderimi',
              icon: Icons.message_rounded,
              color: _kOrange,
              value: smsEnabled,
              onChanged: (val) {
                setState(() => smsEnabled = val);
              },
            ),
            const SizedBox(height: 12),
            
            // SMS Sağlayıcı Dropdown
            DropdownButtonFormField<String>(
              value: selectedProvider,
              dropdownColor: Colors.white,
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'SMS Servis Sağlayıcı',
                prefixIcon: const Icon(Icons.business_center_rounded, size: 18, color: _kTextSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              items: const [
                DropdownMenuItem(value: 'sim', child: Text('Cihazın SIM Kartı (Yerel / SIM)')),
                DropdownMenuItem(value: 'netgsm', child: Text('NetGSM')),
                DropdownMenuItem(value: 'twilio', child: Text('Twilio')),
                DropdownMenuItem(value: 'custom', child: Text('Diğer Gateway')),
              ],
              onChanged: smsEnabled ? (val) {
                if (val != null) {
                  setState(() => selectedProvider = val);
                }
              } : null,
            ),
            const SizedBox(height: 12),
            
            // API Şifre alanı
            widget.pageState._buildFormTextField(
              controller: apiKeyCtrl,
              label: selectedProvider == 'sim' 
                  ? 'API Anahtarı / Şifre (SIM Kart için gerekli değil)' 
                  : 'API Anahtarı / Şifre',
              icon: Icons.key_rounded,
              enabled: smsEnabled && selectedProvider != 'sim',
            ),
            const SizedBox(height: 16),

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
                backgroundColor: _kTextPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),

            // Tetikleyiciler & Otomatik Kurallar
            const Text(
              'Tetikleyiciler & Kurallar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
            ),
            const Divider(color: _kBorderColor),
            widget.pageState._buildSwitchRow(
              title: 'Otomatik Borç Hatırlatıcısı Gönder',
              subtitle: 'Belirli koşullara göre müşteriye otomatik hatırlatma gönderimi',
              icon: Icons.notifications_active_rounded,
              color: _kBlue,
              value: autoDebtReminderEnabled,
              onChanged: (val) {
                if (smsEnabled) {
                  setState(() => autoDebtReminderEnabled = val);
                }
              },
            ),
            if (autoDebtReminderEnabled && smsEnabled) ...[
              const SizedBox(height: 8),
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
            const SizedBox(height: 24),

            // Toplu SMS İşlemleri
            const Text(
              'Toplu SMS İşlemleri',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
            ),
            const Divider(color: _kBorderColor),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: isSendingBulk 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple))
                        : const Icon(Icons.people_alt_rounded, size: 16, color: _kPurple),
                    label: Text(isSendingBulk ? 'Gönderiliyor...' : 'Borçlulara SMS', style: const TextStyle(color: _kTextPrimary, fontSize: 12)),
                    onPressed: (smsEnabled && !isSendingBulk) ? () async {
                      setState(() => isSendingBulk = true);
                      await widget.pageState._sendBulkDebtReminder(context);
                      if (mounted) setState(() => isSendingBulk = false);
                    } : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kBorderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: isSendingBulk 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen))
                        : const Icon(Icons.campaign_rounded, size: 16, color: _kGreen),
                    label: Text(isSendingBulk ? 'Gönderiliyor...' : 'Toplu Duyuru SMS', style: const TextStyle(color: _kTextPrimary, fontSize: 12)),
                    onPressed: (smsEnabled && !isSendingBulk) ? () async {
                      setState(() => isSendingBulk = true);
                      await widget.pageState._sendBulkAnnouncement(context);
                      if (mounted) setState(() => isSendingBulk = false);
                    } : null,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _kBorderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Flexible Templates Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Esnek SMS Şablonları',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
                ),
                if (smsEnabled)
                  TextButton.icon(
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: _kGreen),
                    label: const Text('Şablon Ekle', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => widget.pageState._showEditTemplateDialog(null, (newTpl) {
                      setState(() {
                        listTemplates.add(newTpl);
                      });
                    }),
                  ),
              ],
            ),
            const Divider(color: _kBorderColor),
            
            // Templates list view
            if (!smsEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('SMS etkinleştirildiğinde şablonlar görüntülenebilir.', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
              )
            else if (listTemplates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Tanımlı şablon bulunamadı. Lütfen yeni şablon ekleyin.', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
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
                            color: isEnabled ? const Color(0xFFF8FAFC) : Colors.grey[50]!,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isEnabled ? _kBorderColor : Colors.grey[200]!),
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
                                      color: isEnabled ? _kTextPrimary : Colors.grey[400]!,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Switch.adaptive(
                                        value: isEnabled,
                                        activeColor: _kGreen,
                                        onChanged: (val) {
                                          setState(() {
                                            listTemplates[i]['enabled'] = val;
                                          });
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit_rounded, size: 18, color: isEnabled ? _kBlue : Colors.grey[300]!),
                                        onPressed: isEnabled ? () {
                                          widget.pageState._showEditTemplateDialog(tpl, (updatedTpl) {
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
                                  color: isEnabled ? _kTextSecondary : Colors.grey[400]!,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isEnabled ? _kBlue.withOpacity(0.08) : Colors.grey[100]!,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      tpl['id'] ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isEnabled ? _kBlue : Colors.grey[400]!,
                                      ),
                                    ),
                                  ),
                                  if (tpl['id'] != 'sale' &&
                                      tpl['id'] != 'discount' &&
                                      tpl['id'] != 'debt' &&
                                      tpl['id'] != 'collection' &&
                                      tpl['id'] != 'order')
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 14, color: _kPink),
                                      label: const Text('Sil', style: TextStyle(fontSize: 12, color: _kPink)),
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
                    
                    const SizedBox(height: 24),
                    widget.pageState._buildModalSaveButton(onTap: () async {
                      if (_formKey.currentState!.validate()) {
                        final templateJson = jsonEncode(listTemplates);
                        final updated = widget.settings.copyWith(
                          smsEnabled: smsEnabled,
                          smsProvider: selectedProvider,
                          smsApiKey: apiKeyCtrl.text.trim().isEmpty ? null : apiKeyCtrl.text.trim(),
                          smsTemplate: templateJson,
                        );
                        // Save SMS reminder settings to SQLite settings (single source of truth)
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
                              SnackBar(content: Text('Hata: $e'), backgroundColor: _kPink),
                            );
                          }
                        }
                      }
                    }),
                  ],
                ),
              ),
            );
          }
}

class _EditTemplateDialog extends StatefulWidget {
  final Map<String, dynamic>? existingTpl;
  final ValueChanged<Map<String, dynamic>> onSave;
  final _SettingsPageState pageState;

  const _EditTemplateDialog({
    required this.existingTpl,
    required this.onSave,
    required this.pageState,
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
              
              // Değişken Token Çipleri
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Kullanılabilir Değişkenler:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _kTextSecondary)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  widget.pageState._buildVariableChip(templateCtrl, '{customer}', 'Müşteri'),
                  widget.pageState._buildVariableChip(templateCtrl, '{amount}', 'Tutar'),
                  widget.pageState._buildVariableChip(templateCtrl, '{discount}', 'İndirim'),
                  widget.pageState._buildVariableChip(templateCtrl, '{debt}', 'Borç/Bakiye'),
                  widget.pageState._buildVariableChip(templateCtrl, '{id}', 'Fiş/İşlem No'),
                  widget.pageState._buildVariableChip(templateCtrl, '{business}', 'İşletme Adı'),
                  widget.pageState._buildVariableChip(templateCtrl, '{date}', 'İşlem Tarihi'),
                  widget.pageState._buildVariableChip(templateCtrl, '{items}', 'Ürünler'),
                  widget.pageState._buildVariableChip(templateCtrl, '{phone}', 'Telefon'),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
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
            backgroundColor: _kGreen,
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
          child: const Text('Vazgeç', style: TextStyle(color: _kTextSecondary)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, msgCtrl.text.trim());
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: _kTextPrimary, foregroundColor: Colors.white),
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}
}
