part of '../../settings_page.dart';

extension SettingsPageDialogs on _SettingsPageState {
  void _showBusinessInfoSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: settings.businessName);
    final phoneCtrl = TextEditingController(text: settings.businessPhone);
    final ownerCtrl = TextEditingController(text: settings.ownerName);
    final emailCtrl = TextEditingController(text: settings.businessEmail ?? '');
    final taxIdCtrl = TextEditingController(text: settings.businessTaxId ?? '');
    final addressCtrl = TextEditingController(text: settings.businessAddress);
    String? selectedLogoPath = settings.businessLogo;

    // Local dropdown values
    String? localCity = settings.businessCity.isEmpty ? null : settings.businessCity;
    String? localDistrict = settings.businessDistrict.isEmpty ? null : settings.businessDistrict;
    String? localType = settings.businessType.isEmpty ? null : settings.businessType;

    const businessTypes = [
      'Market', 'Kafe', 'Restoran', 'Kuruyemişçi', 'Pastane',
      'Büfe', 'Kasap', 'Manav', 'Eczane', 'Diğer',
    ];

    // DÜZELTME: Controller'lar push dönünce dispose ediliyor
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            final List<String> localDistricts = (localCity != null) ? (_cityMap[localCity] ?? []) : [];

            return FullScreenSettingsPage(
              title: 'İşletme Bilgileri',
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          try {
                            final picker = ImagePicker();
                            final pickedFile = await picker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 512,
                              maxHeight: 512,
                            );
                            if (pickedFile != null) {
                              setModalState(() {
                                selectedLogoPath = pickedFile.path;
                              });
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Logo seçilirken hata: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                        child: Center(
                          child: Stack(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _kBorderColor, width: 2),
                                ),
                                child: selectedLogoPath != null &&
                                        selectedLogoPath!.isNotEmpty &&
                                        (kIsWeb || File(selectedLogoPath!).existsSync())
                                    ? ClipOval(
                                        child: kIsWeb
                                            ? Image.network(
                                                selectedLogoPath!,
                                                width: 86,
                                                height: 86,
                                                fit: BoxFit.cover,
                                              )
                                            : Image.file(
                                                File(selectedLogoPath!),
                                                width: 86,
                                                height: 86,
                                                fit: BoxFit.cover,
                                              ),
                                      )
                                    : const Icon(
                                        Icons.add_photo_alternate_rounded,
                                        color: _kGreen,
                                        size: 36,
                                      ),
                              ),
                              if (selectedLogoPath != null &&
                                  selectedLogoPath!.isNotEmpty &&
                                  (kIsWeb || File(selectedLogoPath!).existsSync()))
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setModalState(() {
                                        selectedLogoPath = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.delete_forever_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          selectedLogoPath != null ? 'Logo Seçildi (Değiştirmek için tıklayın)' : 'İşletme Logosu Seçin',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildFormTextField(
                        controller: nameCtrl,
                        label: 'İşletme Adı *',
                        icon: Icons.store_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: ownerCtrl,
                        label: 'Yetkili Adı Soyadı *',
                        icon: Icons.person_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: phoneCtrl,
                        label: 'Telefon Numarası *',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: emailCtrl,
                        label: 'E-posta (İsteğe bağlı)',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: taxIdCtrl,
                        label: 'Vergi Dairesi / No *',
                        icon: Icons.badge_rounded,
                        validator: (v) => v!.isEmpty ? 'Gerekli alan (fişe yazılır)' : null,
                      ),
                      const SizedBox(height: 12),
                      if (_citiesLoaded)
                        _buildFormDropdown<String>(
                          label: 'Şehir *',
                          icon: Icons.location_city_rounded,
                          value: localCity,
                          items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setModalState(() {
                            localCity = v;
                            localDistrict = null;
                          }),
                          validator: (v) => v == null ? 'Gerekli alan' : null,
                        )
                      else
                        const Text('Şehir listesi yükleniyor...', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      if (localDistricts.isNotEmpty) ...[
                        _buildFormDropdown<String>(
                          label: 'İlçe *',
                          icon: Icons.map_outlined,
                          value: localDistrict,
                          items: localDistricts.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                          onChanged: (v) => setModalState(() {
                            localDistrict = v;
                          }),
                          validator: (v) => v == null ? 'Gerekli alan' : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildFormDropdown<String>(
                        label: 'İşletme Türü',
                        icon: Icons.category_rounded,
                        value: localType,
                        items: businessTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setModalState(() {
                          localType = v;
                        }),
                      ),
                      const SizedBox(height: 12),
                      _buildFormTextField(
                        controller: addressCtrl,
                        label: 'Detaylı İşletme Adresi',
                        icon: Icons.location_on_rounded,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 24),
                      _buildModalSaveButton(onTap: () async {
                        if (formKey.currentState!.validate()) {
                          final updated = settings.copyWith(
                            businessName: nameCtrl.text.trim(),
                            businessPhone: phoneCtrl.text.trim(),
                            businessAddress: addressCtrl.text.trim(),
                            businessTaxId: taxIdCtrl.text.trim().isEmpty ? null : taxIdCtrl.text.trim(),
                            businessLogo: selectedLogoPath,
                            ownerName: ownerCtrl.text.trim(),
                            businessEmail: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                            businessCity: localCity ?? '',
                            businessDistrict: localDistrict ?? '',
                            businessType: localType ?? '',
                          );
                          await _updateSettingField(updated);
                          if (context.mounted) Navigator.pop(context);
                        }
                      }),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // �”€�”€ Para Birimi & Muhasebe Düzenleme Ekranı �”€�”€
  void _showCurrencyVatSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final currencyCtrl = TextEditingController(text: settings.currency);
    
    // Parse vatCategories from JSON
    List<Map<String, dynamic>> vatList = [];
    try {
      if (settings.vatCategories.isNotEmpty) {
        final decoded = jsonDecode(settings.vatCategories);
        if (decoded is List) {
          vatList = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {
      // If it is stored as flat comma-separated values from the old bug,
      // convert them to structured format
      final oldVals = settings.vatCategories.split(',');
      for (final v in oldVals) {
        final rate = int.tryParse(v.trim());
        if (rate != null) {
          vatList.add({'name': 'Oran %$rate', 'rate': rate});
        }
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Consumer(
          builder: (routeCtx, ref, child) => StatefulBuilder(
            builder: (ctx, setModalState) {
              // Get category pool
              final poolCategories = ref.read(categoryPoolProvider);
            
            // Build the complete list of display categories by merging pool categories
            // with the local vatList keys
            final displayCategories = <String>{
              ...poolCategories,
              ...vatList.map((e) => e['name']?.toString() ?? ''),
            }.where((c) => c.isNotEmpty).toList()..sort();

            return FullScreenSettingsPage(
              title: 'Para Birimi & KDV',
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormTextField(
                      controller: currencyCtrl,
                      label: 'Para Birimi *',
                      icon: Icons.monetization_on_rounded,
                      validator: (v) => v!.isEmpty ? 'Gerekli alan' : null,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Kategoriye Göre KDV Oranları',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _kTextPrimary),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: _kGreen),
                          label: const Text('Yeni Kategori Ekle', style: TextStyle(color: _kGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () => _showAddVatCategoryDialog(context, displayCategories, (newVat) {
                            setModalState(() {
                              vatList.add(newVat);
                            });
                          }),
                        ),
                      ],
                    ),
                    const Divider(color: _kBorderColor),
                    const SizedBox(height: 8),
                    if (displayCategories.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Kategori bulunamadı.',
                            style: TextStyle(color: _kTextSecondary, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayCategories.length,
                          separatorBuilder: (c, i) => const Divider(height: 1, color: _kBorderColor),
                          itemBuilder: (c, idx) {
                            final catName = displayCategories[idx];
                            final mapped = vatList.firstWhere(
                              (e) => e['name']?.toString() == catName,
                              orElse: () => {},
                            );
                            final hasRate = mapped.isNotEmpty;
                            final rate = hasRate ? (mapped['rate'] as int) : 0;

                            return ListTile(
                              onTap: () {
                                _showEditVatDialog(context, catName, hasRate ? rate : null, (newRate) {
                                  setModalState(() {
                                    vatList.removeWhere((e) => e['name']?.toString() == catName);
                                    vatList.add({'name': catName, 'rate': newRate});
                                  });
                                });
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: hasRate ? _kGreen.withOpacity(0.12) : _kGray.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.percent_rounded, 
                                  color: hasRate ? _kGreen : _kGray, 
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                catName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: _kTextPrimary),
                              ),
                              subtitle: Text(
                                hasRate ? 'KDV Oranı: %$rate' : 'KDV Oranı: Tanımlanmamı�Ÿ (%0)',
                                style: TextStyle(
                                  color: hasRate ? _kGreen : _kTextSecondary, 
                                  fontSize: 13,
                                  fontWeight: hasRate ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (hasRate)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: _kPink),
                                      onPressed: () {
                                        setModalState(() {
                                          vatList.removeWhere((e) => e['name']?.toString() == catName);
                                        });
                                      },
                                    )
                                  else
                                    const Icon(
                                      Icons.chevron_right_rounded, 
                                      color: _kTextSecondary,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 32),
                    _buildModalSaveButton(onTap: () async {
                      if (formKey.currentState!.validate()) {
                        final updated = settings.copyWith(
                          currency: currencyCtrl.text.trim(),
                          vatCategories: jsonEncode(vatList),
                        );
                        await _updateSettingField(updated);
                        if (context.mounted) Navigator.pop(context);
                      }
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

  void _showAddVatCategoryDialog(
    BuildContext context,
    List<String> displayCategories,
    ValueChanged<Map<String, dynamic>> onAdd,
  ) {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yeni Kategori Ekle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Kategori Adı',
                  hintText: 'örn: Gıda, Kozmetik',
                  prefixIcon: const Icon(Icons.category_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Kategori adı gerekli';
                  final name = v.trim().toLowerCase();
                  if (displayCategories.any((cat) => cat.toLowerCase() == name)) {
                    return 'Bu kategori zaten mevcut';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'KDV Oranı (%)',
                  hintText: 'örn: 1, 8, 18, 20',
                  prefixIcon: const Icon(Icons.percent_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (v) {
                  if (v!.trim().isEmpty) return 'KDV oranı gerekli';
                  final rate = int.tryParse(v);
                  if (rate == null || rate < 0 || rate > 100) return 'Geçersiz oran';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                onAdd({
                  'name': nameCtrl.text.trim(),
                  'rate': int.parse(rateCtrl.text.trim()),
                });
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ekle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      // DÜZELTME: Dialog kapanınca controller'lar dispose ediliyor
      nameCtrl.dispose();
      rateCtrl.dispose();
    });
  }

  void _showEditVatDialog(
    BuildContext context,
    String categoryName,
    int? currentRate,
    ValueChanged<int> onSave,
  ) {
    final rateCtrl = TextEditingController(text: currentRate != null ? currentRate.toString() : '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$categoryName KDV Oranı', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: rateCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'KDV Oranı (%)',
              hintText: 'örn: 1, 8, 18, 20',
              prefixIcon: const Icon(Icons.percent_rounded, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            validator: (v) {
              if (v!.trim().isEmpty) return 'KDV oranı gerekli';
              final rate = int.tryParse(v);
              if (rate == null || rate < 0 || rate > 100) return 'Geçersiz oran';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: _kTextSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                onSave(int.parse(rateCtrl.text.trim()));
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      // DÜZELTME: Dialog kapanınca controller dispose ediliyor
      rateCtrl.dispose();
    });
  }




  // �”€�”€ Form Input Widget Yardımcıları �”€�”€
  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      enabled: enabled,
      validator: validator,
      style: TextStyle(color: enabled ? _kTextPrimary : _kTextSecondary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 1.5),
        ),
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFEFEFEF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildFormDropdown<T>({
    required String label,
    required IconData icon,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? hintText,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      dropdownColor: Colors.white,
      style: const TextStyle(color: _kTextPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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
          backgroundColor: _kGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('Kaydet'),
      ),
    );
  }

  void _showLedgerReplayDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        bool isRunning = false;
        Map<String, double>? driftResults;
        final Map<String, String> customerNames = {};
        final Map<String, double> oldBalances = {};

        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.account_balance_rounded, color: _kPurple),
                  SizedBox(width: 8),
                  Text('Cari Hesap Bütünlüğü (Replay)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isRunning && driftResults == null) ...[
                        const Text(
                          'Bu işlem, sistemdeki tüm satışları, tahsilatları ve cari hareketleri (Ledger) baştan sona tarayarak '
                          'müşteri bakiyelerini yeniden hesaplar. Senkronizasyon veya beklenmedik elektrik kesintileri '
                          'kaynaklı olası bakiye sapmalarını tespit eder ve otomatik olarak onarır.',
                          style: TextStyle(fontSize: 13, color: _kTextSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: const Text('Denetim ve Onarımı Başlat'),
                          onPressed: () async {
                            setModalState(() {
                              isRunning = true;
                            });

                            try {
                              // Fetch customers before check to capture their names & old balances
                              final customerRepo = await ref.read(customerRepositoryProvider.future);
                              final allCustomers = await customerRepo.findAll();
                              for (final c in allCustomers) {
                                customerNames[c.id] = c.name;
                                oldBalances[c.id] = c.balance;
                              }

                              final dataIntegrity = await ref.read(dataIntegrityServiceProvider.future);
                              final results = await dataIntegrity.runGlobalDriftCheck();
                              
                              // Invalidate customers controller so the POS UI updates
                              ref.invalidate(customersControllerProvider);

                              setModalState(() {
                                isRunning = false;
                                driftResults = results;
                              });
                            } catch (e) {
                              setModalState(() {
                                isRunning = false;
                                driftResults = {};
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: _kPink),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ] else if (isRunning) ...[
                        const Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_kPurple)),
                              SizedBox(height: 16),
                              Text(
                                'İşlem hareketleri taranıyor, bakiyeler yeniden hesaplanıyor...',
                                style: TextStyle(fontSize: 13, color: _kTextSecondary),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ] else if (driftResults != null) ...[
                        if (driftResults!.isEmpty) ...[
                          const Center(
                            child: Column(
                              children: [
                                Icon(Icons.check_circle_rounded, color: _kGreen, size: 48),
                                SizedBox(height: 12),
                                Text(
                                  'Harika! Herhangi bir bakiye sapması veya veri tutarsızlığı bulunamadı. Tüm bakiyeleriniz güncel.',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const Center(
                            child: Icon(Icons.info_outline_rounded, color: _kOrange, size: 40),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Toplam ${driftResults!.length} müşterinin bakiyesinde sapma tespit edildi ve veritabanı otomatik olarak eşitlendi:',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextPrimary),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 180),
                            decoration: BoxDecoration(
                              border: Border.all(color: _kBorderColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final entry in driftResults!.entries)
                                  ListTile(
                                    title: Text(customerNames[entry.key] ?? 'Bilinmeyen Müşteri', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      'Eski: ${oldBalances[entry.key]?.toStringAsFixed(2)} ₺ | Yeni: ${entry.value.toStringAsFixed(2)} ₺',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    trailing: Text(
                                      'Fark: ${(entry.value - (oldBalances[entry.key] ?? 0.0)).toStringAsFixed(2)} ₺',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: (entry.value - (oldBalances[entry.key] ?? 0.0)) >= 0 ? _kGreen : _kPink,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kTextPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Kapat'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// �”€�”€ iOS Bölücü �‡izgisi �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
class _IOSDivider extends StatelessWidget {
  const _IOSDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 56),
      height: 0.5,
      color: _kBorderColor,
    );
  }
}

// �”€�”€ iOS Modal Sheet Wrapper �”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€�”€
class _iOSModalWrapper extends StatelessWidget {
  final String title;
  final Widget child;

  const _iOSModalWrapper({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final modalHeight = screenHeight - statusBarHeight - 16; // Takes full screen except status bar padding

    return Container(
      height: modalHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          // Title Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _kTextPrimary),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE5E5EA),
                    ),
                    child: const Icon(Icons.close_rounded, size: 16, color: _kTextSecondary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorderColor),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

