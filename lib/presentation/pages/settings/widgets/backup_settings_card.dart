part of '../../settings_page.dart';

// Extracted Backup and SMS Settings Card sheets for SettingsPage
extension SettingsBackupSmsSheets on _SettingsPageState {
  void _showSmsSettingsSheet(Settings settings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => SmsSettingsSheet(settings: settings),
      ),
    );
  }

  void _showContactImportSheet() {
    final List<Map<String, String>> simulatedContacts = [
      {
        'name': 'Ahmet Yılmaz',
        'phone': '05321112233',
        'email': 'ahmet.yilmaz@gmail.com'
      },
      {
        'name': 'Elif Demir',
        'phone': '05422223344',
        'email': 'elif.demir@hotmail.com'
      },
      {
        'name': 'Mehmet Kaya',
        'phone': '05053334455',
        'email': 'mehmet.kaya@yahoo.com'
      },
      {
        'name': 'Zeynep Çelik',
        'phone': '05304445566',
        'email': 'zeynep.celik@gmail.com'
      },
      {
        'name': 'Mustafa Öztürk',
        'phone': '05555556677',
        'email': 'mustafa.ozturk@outlook.com'
      },
      {
        'name': 'Fatma Yıldız',
        'phone': '05336667788',
        'email': 'fatmayildiz@gmail.com'
      },
      {
        'name': 'Can Arslan',
        'phone': '05447778899',
        'email': 'can.arslan@gmail.com'
      },
      {
        'name': 'Selin Yurt',
        'phone': '05359998877',
        'email': 'selin.yurt@gmail.com'
      },
      {
        'name': 'Burak Şahin',
        'phone': '05411234567',
        'email': 'burak.sahin@hotmail.com'
      },
      {
        'name': 'Aslı Karaca',
        'phone': '05399876543',
        'email': 'asli.karaca@gmail.com'
      },
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
                    c['name']!
                        .toLowerCase()
                        .contains(searchQuery.toLowerCase()) ||
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
                          style:
                              TextStyle(fontSize: 13, color: _kTextSecondary),
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
                        style:
                            const TextStyle(fontSize: 14, color: _kTextPrimary),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded,
                              color: _kTextSecondary, size: 18),
                          hintText: 'Rehberde Ara...',
                          hintStyle:
                              TextStyle(color: _kTextSecondary, fontSize: 14),
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
                            (selectedIndices.length == filteredIndices.length &&
                                    filteredIndices.isNotEmpty)
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 20,
                            color: _kGreen,
                          ),
                          label: Text(
                            (selectedIndices.length == filteredIndices.length &&
                                    filteredIndices.isNotEmpty)
                                ? 'Seçilenleri Temizle'
                                : 'Tümünü Seç',
                            style: const TextStyle(
                                color: _kGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          onPressed: () {
                            setModalState(() {
                              if (selectedIndices.length ==
                                  filteredIndices.length) {
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
                          style: const TextStyle(
                              fontSize: 13,
                              color: _kTextSecondary,
                              fontWeight: FontWeight.bold),
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
                            style:
                                TextStyle(color: _kTextSecondary, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (final contactIdx in filteredIndices) ...[
                            Builder(builder: (context) {
                              final contact = simulatedContacts[contactIdx];
                              final isSelected =
                                  selectedIndices.contains(contactIdx);
                              return CheckboxListTile(
                                value: isSelected,
                                activeColor: _kGreen,
                                title: Text(
                                  contact['name']!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: _kTextPrimary),
                                ),
                                subtitle: Text(
                                  contact['phone']!,
                                  style: const TextStyle(
                                      color: _kTextSecondary, fontSize: 13),
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
                                      contact['name']!.isNotEmpty
                                          ? contact['name']![0].toUpperCase()
                                          : '👤',
                                      style: const TextStyle(
                                          color: _kBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
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
                            }),
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
                                final customers = ref
                                        .read(customersControllerProvider)
                                        .value ??
                                    [];
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
                                  await ref
                                      .read(
                                          customersControllerProvider.notifier)
                                      .addCustomer(newCustomer);
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
                                      backgroundColor: importedCount > 0
                                          ? _kGreen
                                          : _kOrange,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          disabledBackgroundColor: Colors.grey[300],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          selectedIndices.isEmpty
                              ? 'Lütfen Kişi Seçin'
                              : 'Seçilenleri İçe Aktar (${selectedIndices.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white),
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

  void _showBackupRestoreSheet() {
    requirePermissionAccess(
      context,
      permission: Permission.settingsDatabase,
      title: 'Yedekleme Yönetimi',
      requirePin: true,
      onGranted: (approvedByUserId, approvedByUserName) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => const BackupManagePage(),
          ),
        );
      },
    );
  }
}
