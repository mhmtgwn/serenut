part of '../../settings_page.dart';

extension SettingsPageDialogs on _SettingsPageState {
  void _showBusinessInfoSheet(Settings settings) async {
    if (!_citiesLoaded) {
      await _loadCities();
    }
    if (!mounted) return;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: settings.businessName);
    final phoneCtrl = TextEditingController(text: settings.businessPhone);
    final ownerCtrl = TextEditingController(text: settings.ownerName);
    final emailCtrl = TextEditingController(text: settings.businessEmail ?? '');
    final taxIdCtrl = TextEditingController(text: settings.businessTaxId ?? '');
    final addressCtrl = TextEditingController(text: settings.businessAddress);
    String? selectedLogoPath = settings.businessLogo;

    // Local dropdown values
    String? localCity =
        settings.businessCity.isEmpty ? null : settings.businessCity;
    String? localDistrict =
        settings.businessDistrict.isEmpty ? null : settings.businessDistrict;
    String? localType =
        settings.businessType.isEmpty ? null : settings.businessType;

    const businessTypes = [
      'Market',
      'Kafe',
      'Restoran',
      'Kuruyemişçi',
      'Pastane',
      'Büfe',
      'Kasap',
      'Manav',
      'Eczane',
      'Diğer',
    ];

    // DÜZELTME: Controller'lar push dönünce dispose ediliyor
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            final List<String> localDistricts =
                (localCity != null) ? (_cityMap[localCity] ?? []) : [];

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
                                  border: Border.all(
                                      color: _kBorderColor, width: 2),
                                ),
                                child: selectedLogoPath != null &&
                                        selectedLogoPath!.isNotEmpty &&
                                        (kIsWeb ||
                                            File(selectedLogoPath!)
                                                .existsSync())
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
                                  (kIsWeb ||
                                      File(selectedLogoPath!).existsSync()))
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
                          selectedLogoPath != null
                              ? 'Logo Seçildi (Değiştirmek için tıklayın)'
                              : 'İşletme Logosu Seçin',
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
                        validator: (v) =>
                            v!.isEmpty ? 'Gerekli alan (fişe yazılır)' : null,
                      ),
                      const SizedBox(height: 12),
                      if (_citiesLoaded)
                        _buildFormDropdown<String>(
                          label: 'Şehir *',
                          icon: Icons.location_city_rounded,
                          value: localCity,
                          items: _cities
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) => setModalState(() {
                            localCity = v;
                            localDistrict = null;
                          }),
                          validator: (v) => v == null ? 'Gerekli alan' : null,
                        )
                      else
                        const Text('Şehir listesi yükleniyor...',
                            style: TextStyle(
                                color: _kTextSecondary, fontSize: 13)),
                      const SizedBox(height: 12),
                      if (localDistricts.isNotEmpty) ...[
                        _buildFormDropdown<String>(
                          label: 'İlçe *',
                          icon: Icons.map_outlined,
                          value: localDistrict,
                          items: localDistricts
                              .map((d) =>
                                  DropdownMenuItem(value: d, child: Text(d)))
                              .toList(),
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
                        items: businessTypes
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
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
                            businessTaxId: taxIdCtrl.text.trim().isEmpty
                                ? null
                                : taxIdCtrl.text.trim(),
                            businessLogo: selectedLogoPath,
                            ownerName: ownerCtrl.text.trim(),
                            businessEmail: emailCtrl.text.trim().isEmpty
                                ? null
                                : emailCtrl.text.trim(),
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
      style: TextStyle(
          color: enabled ? _kTextPrimary : _kTextSecondary, fontSize: 14),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
