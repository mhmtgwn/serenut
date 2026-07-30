part of '../../settings_page.dart';

extension _SettingsPageDialogs on _SettingsPageState {
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
                            if (!context.mounted) return;
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
                                        (selectedLogoPath!
                                                .startsWith('data:image/') ||
                                            selectedLogoPath!
                                                .startsWith('http://') ||
                                            selectedLogoPath!
                                                .startsWith('https://') ||
                                            kIsWeb ||
                                            File(selectedLogoPath!)
                                                .existsSync())
                                    ? ClipOval(
                                        child: selectedLogoPath!
                                                .startsWith('data:image/')
                                            ? Image.memory(
                                                base64Decode(selectedLogoPath!
                                                    .split(',')
                                                    .last),
                                                width: 86,
                                                height: 86,
                                                fit: BoxFit.cover,
                                              )
                                            : kIsWeb ||
                                                    selectedLogoPath!
                                                        .startsWith(
                                                            'http://') ||
                                                    selectedLogoPath!
                                                        .startsWith('https://')
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
                                    : Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Image.asset(
                                          'assets/logo.png',
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.storefront_rounded,
                                            color: _kGreen,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                              ),
                              if (selectedLogoPath != null &&
                                  selectedLogoPath!.isNotEmpty &&
                                  (selectedLogoPath!
                                          .startsWith('data:image/') ||
                                      selectedLogoPath!.startsWith('http://') ||
                                      selectedLogoPath!
                                          .startsWith('https://') ||
                                      kIsWeb ||
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
                            businessType: '',
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

  void _showReceiptSettings(Settings settings) {
    var paperWidth = settings.paperWidth;
    var font = settings.receiptFont;
    var textSize = settings.receiptTextSize;
    var itemLayout = settings.receiptItemLayout;
    var printLogo = settings.printLogo;
    var printBalance = settings.printCustomerBalance;
    var printQr = settings.printQRCode;
    var printBarcode = settings.printBarcode;
    var autoCut = settings.autoCutReceipt;
    var openDrawer = settings.openCashDrawer;
    var feedLines = settings.receiptFeedLines.clamp(0, 8);
    var copies = settings.printCopies.clamp(1, 10);
    final footerCtrl = TextEditingController(text: settings.receiptFooterText);

    Navigator.of(context)
        .push(MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) =>
              StatefulBuilder(builder: (context, setModalState) {
            Widget toggle(
                    String title, bool value, ValueChanged<bool> onChanged) =>
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(title),
                  value: value,
                  activeColor: _kGreen,
                  onChanged: onChanged,
                );
            return FullScreenSettingsPage(
              title: 'Fiş Tasarımı',
              child: SingleChildScrollView(
                child: Column(children: [
                  _buildFormDropdown<int>(
                    label: 'Kağıt genişliği',
                    icon: Icons.straighten_rounded,
                    value: paperWidth,
                    items: const [
                      DropdownMenuItem(value: 58, child: Text('58 mm')),
                      DropdownMenuItem(value: 80, child: Text('80 mm')),
                    ],
                    onChanged: (v) => setModalState(() => paperWidth = v ?? 80),
                  ),
                  const SizedBox(height: 12),
                  _buildFormDropdown<String>(
                    label: 'Yazı tipi',
                    icon: Icons.font_download_outlined,
                    value: font,
                    items: const [
                      DropdownMenuItem(
                          value: 'a', child: Text('Font A (standart)')),
                      DropdownMenuItem(value: 'b', child: Text('Font B (dar)')),
                    ],
                    onChanged: (v) => setModalState(() => font = v ?? 'a'),
                  ),
                  const SizedBox(height: 12),
                  _buildFormDropdown<String>(
                    label: 'Yazı boyutu',
                    icon: Icons.format_size_rounded,
                    value: textSize,
                    items: const [
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'large', child: Text('Büyük')),
                    ],
                    onChanged: (v) =>
                        setModalState(() => textSize = v ?? 'normal'),
                  ),
                  const SizedBox(height: 12),
                  _buildFormDropdown<String>(
                    label: 'Ürün satırı',
                    icon: Icons.view_stream_outlined,
                    value: itemLayout,
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Otomatik')),
                      DropdownMenuItem(
                          value: 'single', child: Text('Tek satır')),
                      DropdownMenuItem(
                          value: 'double', child: Text('İki satır')),
                    ],
                    onChanged: (v) =>
                        setModalState(() => itemLayout = v ?? 'auto'),
                  ),
                  const SizedBox(height: 12),
                  _buildFormTextField(
                    controller: footerCtrl,
                    label: 'Fiş sonu mesajı',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Text('Alt boş satır: $feedLines')),
                    IconButton(
                        onPressed: feedLines > 0
                            ? () => setModalState(() => feedLines--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    IconButton(
                        onPressed: feedLines < 8
                            ? () => setModalState(() => feedLines++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  Row(children: [
                    Expanded(child: Text('Kopya sayısı: $copies')),
                    IconButton(
                        onPressed: copies > 1
                            ? () => setModalState(() => copies--)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    IconButton(
                        onPressed: copies < 10
                            ? () => setModalState(() => copies++)
                            : null,
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                  toggle('İşletme logosunu yazdır', printLogo,
                      (v) => setModalState(() => printLogo = v)),
                  toggle('Müşteri bakiyesini yazdır', printBalance,
                      (v) => setModalState(() => printBalance = v)),
                  toggle('QR kod yazdır', printQr,
                      (v) => setModalState(() => printQr = v)),
                  toggle('Ürün barkodu yazdır', printBarcode,
                      (v) => setModalState(() => printBarcode = v)),
                  toggle('Fiş sonunda otomatik kes', autoCut,
                      (v) => setModalState(() => autoCut = v)),
                  toggle('Nakit satışta çekmeceyi aç', openDrawer,
                      (v) => setModalState(() => openDrawer = v)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final candidate = settings.copyWith(
                        paperWidth: paperWidth,
                        receiptFont: font,
                        receiptTextSize: textSize,
                      );
                      try {
                        await ref
                            .read(printerServiceProvider)
                            .testPrinterConnection(candidate);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Fiş yazıcısı testi başarılı.')),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Yazıcı testi başarısız: $error')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Fiş yazıcısını test et'),
                  ),
                  const SizedBox(height: 10),
                  _buildModalSaveButton(onTap: () async {
                    await _updateSettingField(settings.copyWith(
                      paperWidth: paperWidth,
                      receiptFont: font,
                      receiptTextSize: textSize,
                      receiptItemLayout: itemLayout,
                      receiptFooterText: footerCtrl.text.trim(),
                      receiptFeedLines: feedLines,
                      printCopies: copies,
                      printLogo: printLogo,
                      printCustomerBalance: printBalance,
                      printQRCode: printQr,
                      printBarcode: printBarcode,
                      autoCutReceipt: autoCut,
                      openCashDrawer: openDrawer,
                    ));
                    if (context.mounted) Navigator.pop(context);
                  }),
                  const SizedBox(height: 24),
                ]),
              ),
            );
          }),
        ))
        .whenComplete(footerCtrl.dispose);
  }

  void _showLabelSettings(Settings settings) {
    var width = settings.labelWidthMm.clamp(20, 100);
    var height = settings.labelHeightMm.clamp(15, 100);
    var gap = settings.labelGapMm.clamp(0, 10);
    var dpi = settings.labelDpi;
    var language = settings.labelPrinterLanguage;
    var copies = settings.labelPrinterCopies.clamp(1, 20);

    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => FullScreenSettingsPage(
          title: 'Etiket Tasarımı',
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _kGreen.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: AspectRatio(
                    aspectRatio: width / height,
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _kTextPrimary, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                settings.businessName.isNotEmpty
                                    ? settings.businessName
                                    : 'SERENUT OS',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                '01.02.2026',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: _kTextSecondary,
                                ),
                              ),
                            ],
                          ),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Örnek Ürün Adı Ve',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                'Çeşidi Açıklaması',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'adet 200.00 TL',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: POSColors.greenDark,
                              ),
                            ),
                          ),
                          Container(
                            height: 16,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Genişlik: $width mm'),
                Slider(
                    value: width.toDouble(),
                    min: 20,
                    max: 100,
                    divisions: 80,
                    activeColor: _kGreen,
                    onChanged: (v) => setModalState(() => width = v.round())),
                Text('Yükseklik: $height mm'),
                Slider(
                    value: height.toDouble(),
                    min: 15,
                    max: 100,
                    divisions: 85,
                    activeColor: _kGreen,
                    onChanged: (v) => setModalState(() => height = v.round())),
                Text('Etiket aralığı: $gap mm'),
                Slider(
                    value: gap.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    activeColor: _kGreen,
                    onChanged: (v) => setModalState(() => gap = v.round())),
                _buildFormDropdown<int>(
                  label: 'Baskı çözünürlüğü',
                  icon: Icons.high_quality_rounded,
                  value: <int>[203, 300, 600].contains(dpi) ? dpi : 203,
                  items: const [
                    DropdownMenuItem(value: 203, child: Text('203 DPI')),
                    DropdownMenuItem(value: 300, child: Text('300 DPI')),
                    DropdownMenuItem(value: 600, child: Text('600 DPI')),
                  ],
                  onChanged: (v) => setModalState(() => dpi = v ?? 203),
                ),
                const SizedBox(height: 12),
                _buildFormDropdown<String>(
                  label: 'Yazıcı dili',
                  icon: Icons.code_rounded,
                  value: ['tspl', 'escpos', 'zpl'].contains(language) ? language : 'tspl',
                  items: const [
                    DropdownMenuItem(value: 'tspl', child: Text('TSPL')),
                    DropdownMenuItem(
                        value: 'escpos', child: Text('ESC/POS (Termal)')),
                    DropdownMenuItem(value: 'zpl', child: Text('ZPL')),
                  ],
                  onChanged: (v) => setModalState(() => language = v ?? 'tspl'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: Text('Varsayılan kopya: $copies')),
                  IconButton(
                      onPressed: copies > 1
                          ? () => setModalState(() => copies--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline)),
                  IconButton(
                      onPressed: copies < 20
                          ? () => setModalState(() => copies++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline)),
                ]),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final candidate = settings.copyWith(
                      labelPrinterEnabled: true,
                      labelWidthMm: width,
                      labelHeightMm: height,
                      labelGapMm: gap,
                      labelDpi: dpi,
                      labelPrinterLanguage: language,
                    );
                    try {
                      await ref
                          .read(printerServiceProvider)
                          .testLabelPrinterConnection(candidate);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Etiket yazıcısı testi başarılı.')),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Etiket testi başarısız: $error')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.label_rounded),
                  label: const Text('Etiket yazıcısını test et'),
                ),
                const SizedBox(height: 10),
                _buildModalSaveButton(onTap: () async {
                  await _updateSettingField(settings.copyWith(
                    labelWidthMm: width,
                    labelHeightMm: height,
                    labelGapMm: gap,
                    labelDpi: dpi,
                    labelPrinterLanguage: language,
                    labelPrinterCopies: copies,
                  ));
                  if (context.mounted) Navigator.pop(context);
                }),
              ],
            ),
          ),
        ),
      ),
    ));
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
