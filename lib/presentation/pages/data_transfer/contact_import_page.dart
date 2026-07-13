part of '../data_transfer_page.dart';

class ContactImportPage extends ConsumerStatefulWidget {
  const ContactImportPage({super.key});

  @override
  ConsumerState<ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends ConsumerState<ContactImportPage> {
  List<Map<String, String>> _contacts = [];
  final List<int> _selectedIndices = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _errorMessage;
  String? _loadedFileName;

  bool get _useFileImport => kIsWeb || (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_useFileImport) {
        // Desktop & Web: Bypassing native permission and start layout without simulated contacts.
        _contacts = [];
        _hasPermission = true;
      } else {
        // Native platforms (Mobile) permission handling
        var status = await Permission.contacts.status;
        if (!status.isGranted) {
          status = await Permission.contacts.request();
        }

        if (status.isGranted) {
          // Fetch real contacts
          final nativeContacts = await FlutterContacts.getContacts(
            withProperties: true,
            withPhoto: false,
          );
          
          final List<Map<String, String>> loaded = [];
          for (var c in nativeContacts) {
            final name = c.displayName.trim();
            
            // Find first valid phone number
            String phone = '';
            for (var p in c.phones) {
              // Extract digits/symbols only
              final cleaned = p.number.replaceAll(RegExp(r'\s+'), '');
              if (cleaned.isNotEmpty) {
                phone = cleaned;
                break;
              }
            }

            // Find first valid email
            String email = '';
            for (var e in c.emails) {
              final cleanedEmail = e.address.trim();
              if (cleanedEmail.isNotEmpty) {
                email = cleanedEmail;
                break;
              }
            }

            if (phone.isNotEmpty) {
              loaded.add({
                'name': name.isEmpty ? 'İsimsiz' : name,
                'phone': phone,
                'email': email,
              });
            }
          }
          
          // Sort by name case-insensitive
          loaded.sort((a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()));
          
          _contacts = loaded;
          _hasPermission = true;
        } else {
          _hasPermission = false;
        }
      }
    } catch (e) {
      _errorMessage = 'Kişiler yüklenirken bir hata oluştu: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    if (kIsWeb) return;
    final status = await Permission.contacts.request();
    if (status.isGranted) {
      _loadContacts();
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rehbere erişim izni reddedildi.'),
            backgroundColor: _kPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<Map<String, String>> _parseVcf(String text) {
    final List<Map<String, String>> contacts = [];
    final cards = text.split('BEGIN:VCARD');
    for (var card in cards) {
      if (!card.contains('END:VCARD')) continue;
      String name = '';
      String phone = '';
      String email = '';
      
      final lines = card.split('\n');
      for (var line in lines) {
        line = line.trim();
        if (line.startsWith('FN:')) {
          name = line.substring(3).trim();
        } else if (line.startsWith('N:') && name.isEmpty) {
          final parts = line.substring(2).split(';');
          name = parts.where((p) => p.isNotEmpty).join(' ').trim();
        } else if (line.startsWith('TEL')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            phone = parts.sublist(1).join(':').replaceAll(RegExp(r'\s+'), '');
          }
        } else if (line.startsWith('EMAIL')) {
          final parts = line.split(':');
          if (parts.length > 1) {
            email = parts.sublist(1).join(':').trim();
          }
        }
      }
      if (phone.isNotEmpty) {
        contacts.add({
          'name': name.isEmpty ? 'İsimsiz' : name,
          'phone': phone,
          'email': email,
        });
      }
    }
    return contacts;
  }

  List<Map<String, String>> _parseCsv(String text) {
    final List<Map<String, String>> contacts = [];
    final lines = text.split('\n');
    if (lines.isEmpty) return contacts;
    
    String separator = ',';
    final firstLine = lines.first;
    if (firstLine.contains(';')) {
      separator = ';';
    }
    
    int nameCol = -1;
    int phoneCol = -1;
    int emailCol = -1;
    
    final headers = firstLine.split(separator);
    for (int i = 0; i < headers.length; i++) {
      final cell = headers[i].toLowerCase().trim();
      if (cell.contains('isim') || cell.contains('ad') || cell.contains('name')) {
        nameCol = i;
      } else if (cell.contains('tel') || cell.contains('telefon') || cell.contains('phone')) {
        phoneCol = i;
      } else if (cell.contains('mail') || cell.contains('eposta') || cell.contains('email')) {
        emailCol = i;
      }
    }
    
    if (nameCol == -1 && phoneCol == -1) {
      nameCol = 0;
      phoneCol = 1;
      if (headers.length > 2) emailCol = 2;
    }
    
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      
      final cells = line.split(separator);
      if (cells.length <= nameCol || cells.length <= phoneCol) continue;
      
      final name = cells[nameCol].replaceAll('"', '').trim();
      final phone = cells[phoneCol].replaceAll('"', '').replaceAll(RegExp(r'\s+'), '').trim();
      final email = emailCol != -1 && cells.length > emailCol ? cells[emailCol].replaceAll('"', '').trim() : '';
      
      if (phone.isNotEmpty) {
        contacts.add({
          'name': name.isEmpty ? 'İsimsiz' : name,
          'phone': phone,
          'email': email,
        });
      }
    }
    return contacts;
  }

  List<Map<String, String>> _parseExcel(List<int> bytes) {
    final List<Map<String, String>> contacts = [];
    try {
      final excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null || sheet.maxRows <= 1) continue;
        
        int nameCol = -1;
        int phoneCol = -1;
        int emailCol = -1;
        
        final firstRow = sheet.rows.first;
        for (int i = 0; i < firstRow.length; i++) {
          final cellValue = firstRow[i]?.value?.toString().toLowerCase().trim() ?? '';
          if (cellValue.contains('isim') || cellValue.contains('ad') || cellValue.contains('name')) {
            nameCol = i;
          } else if (cellValue.contains('tel') || cellValue.contains('telefon') || cellValue.contains('phone')) {
            phoneCol = i;
          } else if (cellValue.contains('mail') || cellValue.contains('eposta') || cellValue.contains('email')) {
            emailCol = i;
          }
        }
        
        if (nameCol == -1 && phoneCol == -1) {
          nameCol = 0;
          phoneCol = 1;
          if (sheet.maxColumns > 2) emailCol = 2;
        }
        
        for (int r = 1; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          if (row.length <= nameCol || row.length <= phoneCol) continue;
          
          final name = row[nameCol]?.value?.toString().trim() ?? '';
          final phone = row[phoneCol]?.value?.toString().replaceAll(RegExp(r'\s+'), '') ?? '';
          final email = emailCol != -1 && row.length > emailCol ? row[emailCol]?.value?.toString().trim() ?? '' : '';
          
          if (phone.isNotEmpty) {
            contacts.add({
              'name': name.isEmpty ? 'İsimsiz' : name,
              'phone': phone,
              'email': email,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Excel parsing error: $e');
    }
    return contacts;
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'vcf'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final file = result.files.first;
      final Uint8List? bytes;
      if (kIsWeb) {
        bytes = file.bytes;
      } else {
        bytes = await File(file.path!).readAsBytes();
      }
      if (bytes == null) {
        throw Exception('Dosya içeriği okunamadı.');
      }

      final ext = file.extension?.toLowerCase() ?? '';
      List<Map<String, String>> parsed = [];

      if (ext == 'vcf') {
        final text = utf8.decode(bytes, allowMalformed: true);
        parsed = _parseVcf(text);
      } else if (ext == 'csv') {
        final text = utf8.decode(bytes, allowMalformed: true);
        parsed = _parseCsv(text);
      } else if (ext == 'xlsx' || ext == 'xls') {
        parsed = _parseExcel(bytes);
      } else {
        throw Exception('Desteklenmeyen dosya formatı.');
      }

      setState(() {
        _contacts = parsed;
        _selectedIndices.clear();
        _loadedFileName = file.name;
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${parsed.length} kişi dosyadan yüklendi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Dosya yüklenirken hata oluştu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter contacts based on search query
    final List<int> filteredIndices = [];
    for (int i = 0; i < _contacts.length; i++) {
      final c = _contacts[i];
      final nameMatches = c['name']!.toLowerCase().contains(_searchQuery.toLowerCase());
      final phoneMatches = c['phone']!.contains(_searchQuery);
      if (_searchQuery.isEmpty || nameMatches || phoneMatches) {
        filteredIndices.add(i);
      }
    }

    return FullScreenSettingsPage(
      title: 'Rehberden İçe Aktar',
      useScrollView: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Web Warn Banner
          if (kIsWeb && _loadedFileName == null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kOrange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: _kOrange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Web sürümünde cihaz rehberine erişim desteklenmediği için kendi yedek dosyanızı (.xlsx, .csv, .vcf) aktarabilirsiniz.',
                      style: TextStyle(color: _kOrange, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // 2. File Import Header (Only if file is loaded on Web/Windows)
          if (!_isLoading && _useFileImport && _loadedFileName != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.file_present_rounded, color: _kBlue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_loadedFileName dosyasından ${_contacts.length} kişi yüklendi.',
                      style: const TextStyle(color: _kBlue, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _kBlue, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _loadedFileName = null;
                      });
                      _loadContacts();
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: _kBorderColor),
          ],

          // 3. Conditional Content
          if (_isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                ),
              ),
            )
          else if (_useFileImport && _loadedFileName == null)
            // Web & Windows: Show Upload Card
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_upload_outlined, size: 72, color: _kBlue),
                        const SizedBox(height: 16),
                        const Text(
                          'Rehber Yedek Dosyası Yükle',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Müşterilerinizi toplu olarak eklemek için Excel (.xlsx), CSV (.csv) veya vCard (.vcf) formatındaki rehber dosyanızı seçin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: _kTextSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _importFromFile,
                          icon: const Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                          label: const Text(
                            'Dosya Seçin',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kBlue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (!_hasPermission && _loadedFileName == null)
            // Mobile (iOS/Android): Show permission required
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.contact_phone_rounded, size: 64, color: _kTextSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          'Rehber İzni Gerekli',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Müşterilerinizi hızlıca aktarabilmek için uygulamanın rehberinize erişmesine izin vermelisiniz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _requestPermission,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text(
                            'İzin Ver',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 64, color: _kPink),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            if (_loadedFileName != null) {
                              setState(() {
                                _loadedFileName = null;
                              });
                            }
                            _loadContacts();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Yeniden Dene', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else ...[
            // Arama kutusu
            Container(
              height: 38,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
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
                  setState(() {
                    _searchQuery = val.trim();
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
                    (_selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                        ? Icons.check_box_rounded 
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: _kGreen,
                  ),
                  label: Text(
                    (_selectedIndices.length == filteredIndices.length && filteredIndices.isNotEmpty)
                        ? 'Seçilenleri Temizle' 
                        : 'Tümünü Seç',
                    style: const TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () {
                    setState(() {
                      if (_selectedIndices.length == filteredIndices.length) {
                        _selectedIndices.clear();
                      } else {
                        _selectedIndices.clear();
                        _selectedIndices.addAll(filteredIndices);
                      }
                    });
                  },
                ),
                Text(
                  '${_selectedIndices.length} / ${filteredIndices.length} Seçildi',
                  style: const TextStyle(fontSize: 13, color: _kTextSecondary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(color: _kBorderColor),

            // Kişi Listesi (Virtualized & Scrollable)
            Expanded(
              child: filteredIndices.isEmpty
                  ? const Center(
                      child: Text(
                        'Aranan kişi bulunamadı.',
                        style: TextStyle(color: _kTextSecondary, fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: filteredIndices.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: _kBorderColor),
                      itemBuilder: (context, index) {
                        final contactIdx = filteredIndices[index];
                        final contact = _contacts[contactIdx];
                        final isSelected = _selectedIndices.contains(contactIdx);
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
                            setState(() {
                              if (checked == true) {
                                _selectedIndices.add(contactIdx);
                              } else {
                                _selectedIndices.remove(contactIdx);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            
            // İçe Aktarma Butonu
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _selectedIndices.isEmpty
                    ? null
                    : () async {
                        final customers = ref.read(customersControllerProvider).value ?? [];
                        int importedCount = 0;
                        int skippedCount = 0;

                        // Show dialog to block user interface during DB operations
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                            ),
                          ),
                        );

                        try {
                          for (final idx in _selectedIndices) {
                            final contact = _contacts[idx];
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
                        } finally {
                          if (context.mounted) {
                            Navigator.pop(context); // Dismiss the progress loading dialog
                          }
                        }

                        if (context.mounted) {
                          Navigator.pop(context); // Close the ContactImportPage
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
                  _selectedIndices.isEmpty 
                      ? 'Lütfen Kişi Seçin' 
                      : 'Seçilenleri İçe Aktar (${_selectedIndices.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
