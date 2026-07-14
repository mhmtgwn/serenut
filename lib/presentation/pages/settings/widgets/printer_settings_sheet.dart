part of '../../settings_page.dart';

// Extracted Printer Settings Sheets for SettingsPage
extension SettingsPrinterSheets on _SettingsPageState {
  void _showReceiptPrinterSheet(Settings settings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            _ReceiptPrinterSheet(settings: settings, pageState: this),
      ),
    );
  }

  void _showLabelPrinterSheet(Settings settings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            _LabelPrinterSheet(settings: settings, pageState: this),
      ),
    );
  }
}

class _ReceiptPrinterSheet extends ConsumerStatefulWidget {
  final Settings settings;
  final _SettingsPageState pageState;

  const _ReceiptPrinterSheet({required this.settings, required this.pageState});

  @override
  ConsumerState<_ReceiptPrinterSheet> createState() =>
      _ReceiptPrinterSheetState();
}

class _ReceiptPrinterSheetState extends ConsumerState<_ReceiptPrinterSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameCtrl;
  late final TextEditingController ipCtrl;
  late final TextEditingController portCtrl;
  late final TextEditingController copiesCtrl;
  late int paperWidth;
  late String connectionType;

  List<Map<String, String>> pairedDevices = [];
  bool isLoadingDevices = false;
  late String? selectedDeviceMac;
  bool isBluetoothSupported = true;
  bool hasCalledFetch = false;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.settings.printerName ?? '');
    ipCtrl = TextEditingController(text: widget.settings.printerIp ?? '');
    portCtrl =
        TextEditingController(text: widget.settings.printerPort.toString());
    copiesCtrl =
        TextEditingController(text: widget.settings.printCopies.toString());
    paperWidth = widget.settings.paperWidth;

    connectionType = 'network';
    if (widget.settings.printerName == 'sunmi') {
      connectionType = 'sunmi';
    } else if (widget.settings.printerName != null &&
        widget.settings.printerName!.contains(':')) {
      connectionType = 'bluetooth';
    }
    selectedDeviceMac =
        connectionType == 'bluetooth' ? widget.settings.printerName : null;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ipCtrl.dispose();
    portCtrl.dispose();
    copiesCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchDevices() async {
    if (!mounted) return;
    setState(() {
      isLoadingDevices = true;
    });
    try {
      final available = await NativePrinterBridge.isBluetoothAvailable();
      if (!available) {
        if (mounted) {
          setState(() {
            isBluetoothSupported = false;
            isLoadingDevices = false;
          });
        }
        return;
      }
      final list = await NativePrinterBridge.getPairedBluetoothDevices();
      if (mounted) {
        setState(() {
          pairedDevices = list;
          isLoadingDevices = false;
          isBluetoothSupported = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoadingDevices = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (connectionType == 'bluetooth' && !hasCalledFetch) {
      hasCalledFetch = true;
      Future.microtask(() => fetchDevices());
    }

    return FullScreenSettingsPage(
      title: 'Fiş Yazıcı Ayarları',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bağlantı Tipi Dropdown
            DropdownButtonFormField<String>(
              value: connectionType,
              dropdownColor: Colors.white,
              style: const TextStyle(color: _kTextPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Bağlantı Tipi',
                prefixIcon: const Icon(Icons.compare_arrows_rounded,
                    size: 18, color: _kTextSecondary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorderColor)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kBorderColor)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'network', child: Text('WiFi / Network (Ethernet)')),
                DropdownMenuItem(
                    value: 'bluetooth',
                    child: Text('Bluetooth (Mobil Termal)')),
                DropdownMenuItem(
                    value: 'sunmi', child: Text('Sunmi Gömülü Yazıcı')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    connectionType = val;
                    if (connectionType == 'bluetooth' &&
                        pairedDevices.isEmpty) {
                      fetchDevices();
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // Bağlantı Tipi İçeriği
            if (connectionType == 'network') ...[
              widget.pageState._buildFormTextField(
                controller: nameCtrl,
                label: 'Yazıcı Tanımı',
                icon: Icons.print_rounded,
                hintText: 'Ağ Yazıcısı',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: widget.pageState._buildFormTextField(
                      controller: ipCtrl,
                      label: 'Yazıcı IP Adresi',
                      icon: Icons.settings_ethernet_rounded,
                      hintText: '192.168.1.100',
                      validator: (v) => v!.isEmpty ? 'IP Adresi gerekli' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: widget.pageState._buildFormTextField(
                      controller: portCtrl,
                      label: 'Port',
                      icon: Icons.input_rounded,
                      keyboardType: TextInputType.number,
                      validator: (v) => v!.isEmpty ? 'Port gerekli' : null,
                    ),
                  ),
                ],
              ),
            ] else if (connectionType == 'bluetooth') ...[
              if (isLoadingDevices)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_kBlue)),
                      SizedBox(height: 12),
                      Text('Eşleşmiş cihazlar listeleniyor...',
                          style:
                              TextStyle(color: _kTextSecondary, fontSize: 13)),
                    ],
                  ),
                )
              else if (!isBluetoothSupported)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kPink.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kPink.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.bluetooth_disabled_rounded,
                          color: _kPink, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bu cihazda Bluetooth bulunamadı veya etkinleştirilmedi.',
                          style: TextStyle(
                              color: _kPink,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              else if (pairedDevices.isEmpty)
                Column(
                  children: [
                    const Text(
                      'Eşleşmiş Bluetooth cihazı bulunamadı. Lütfen telefon ayarlarından yazıcınızı eşleştirip tekrar deneyin.',
                      style: TextStyle(color: _kTextSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh_rounded, color: _kBlue),
                      label: const Text('Yeniden Tara',
                          style: TextStyle(
                              color: _kBlue, fontWeight: FontWeight.bold)),
                      onPressed: () => fetchDevices(),
                    ),
                  ],
                )
              else
                DropdownButtonFormField<String>(
                  value: pairedDevices
                          .any((d) => d['address'] == selectedDeviceMac)
                      ? selectedDeviceMac
                      : null,
                  dropdownColor: Colors.white,
                  hint: const Text('Bluetooth Yazıcı Seçin'),
                  style: const TextStyle(color: _kTextPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Eşleşmiş Bluetooth Cihazları',
                    prefixIcon: const Icon(Icons.bluetooth_rounded,
                        size: 18, color: _kBlue),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorderColor)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorderColor)),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          size: 18, color: _kBlue),
                      onPressed: () => fetchDevices(),
                    ),
                  ),
                  items: pairedDevices.map((d) {
                    return DropdownMenuItem<String>(
                      value: d['address'],
                      child: Text('${d['name']} (${d['address']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedDeviceMac = val;
                      });
                    }
                  },
                  validator: (v) => v == null ? 'Lütfen bir cihaz seçin' : null,
                ),
            ] else if (connectionType == 'sunmi') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: _kGreen, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sunmi entegre termal yazıcı modu aktif. Herhangi bir ekstra kablo veya IP bağlantısı gerekmez.',
                        style: TextStyle(
                            color: _kGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: paperWidth,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: _kTextPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Genişlik',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorderColor)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kBorderColor)),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                    ),
                    items: const [
                      DropdownMenuItem(value: 80, child: Text('80 mm')),
                      DropdownMenuItem(value: 58, child: Text('58 mm')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => paperWidth = val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: widget.pageState._buildFormTextField(
                    controller: copiesCtrl,
                    label: 'Kopya Sayısı',
                    icon: Icons.file_copy_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Test Yazdırma Butonu
            OutlinedButton.icon(
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('Bağlantı Testi Yazdır'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kBlue,
                side: const BorderSide(color: _kBlue),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final currentUser = ref.read(currentUserProvider);
                final hasAccess = currentUser != null &&
                    (currentUser.role == UserRole.sysadmin ||
                        currentUser.role == UserRole.owner ||
                        currentUser.role == UserRole.admin ||
                        currentUser
                            .hasPermission(Permission.settingsPrinter.value));
                if (!hasAccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Yazıcı ayarlarını test etmek için yetkiniz yok.'),
                        backgroundColor: _kPink,
                        behavior: SnackBarBehavior.floating),
                  );
                  return;
                }
                final testSet = widget.settings.copyWith(
                  printerName: connectionType == 'sunmi'
                      ? 'sunmi'
                      : (connectionType == 'bluetooth'
                          ? selectedDeviceMac
                          : nameCtrl.text.trim()),
                  printerIp:
                      connectionType == 'network' ? ipCtrl.text.trim() : null,
                  printerPort: int.tryParse(portCtrl.text) ?? 9100,
                  paperWidth: paperWidth,
                );
                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Test fişi kuyruğa eklendi...'),
                        backgroundColor: _kBlue,
                        behavior: SnackBarBehavior.floating),
                  );
                  await ref
                      .read(printerServiceProvider)
                      .testPrinterConnection(testSet);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Test fişi başarıyla yazdırıldı.'),
                          backgroundColor: _kGreen,
                          behavior: SnackBarBehavior.floating),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Test başarısız: $e'),
                          backgroundColor: _kPink,
                          behavior: SnackBarBehavior.floating),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),

            widget.pageState._buildModalSaveButton(onTap: () async {
              final currentUser = ref.read(currentUserProvider);
              final hasAccess = currentUser != null &&
                  (currentUser.role == UserRole.sysadmin ||
                      currentUser.role == UserRole.owner ||
                      currentUser.role == UserRole.admin ||
                      currentUser
                          .hasPermission(Permission.settingsPrinter.value));
              if (!hasAccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Yazıcı ayarlarını kaydetmek için yetkiniz yok.'),
                      backgroundColor: _kPink,
                      behavior: SnackBarBehavior.floating),
                );
                return;
              }
              if (_formKey.currentState!.validate()) {
                final updated = widget.settings.copyWith(
                  printerName: connectionType == 'sunmi'
                      ? 'sunmi'
                      : (connectionType == 'bluetooth'
                          ? selectedDeviceMac
                          : nameCtrl.text.trim().isEmpty
                              ? null
                              : nameCtrl.text.trim()),
                  printerIp:
                      connectionType == 'network' ? ipCtrl.text.trim() : null,
                  printerPort: connectionType == 'network'
                      ? (int.tryParse(portCtrl.text) ?? 9100)
                      : 9100,
                  printCopies: int.tryParse(copiesCtrl.text) ?? 1,
                  paperWidth: paperWidth,
                );
                try {
                  await ref
                      .read(settingsNotifierProvider.notifier)
                      .updateSettings(updated);
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Kaydedilemedi: $e'),
                          backgroundColor: _kPink),
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

class _LabelPrinterSheet extends ConsumerStatefulWidget {
  final Settings settings;
  final _SettingsPageState pageState;

  const _LabelPrinterSheet({required this.settings, required this.pageState});

  @override
  ConsumerState<_LabelPrinterSheet> createState() => _LabelPrinterSheetState();
}

class _LabelPrinterSheetState extends ConsumerState<_LabelPrinterSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController ipCtrl;
  late final TextEditingController portCtrl;

  @override
  void initState() {
    super.initState();
    ipCtrl = TextEditingController(text: widget.settings.labelPrinterIp ?? '');
    portCtrl = TextEditingController(
        text: (widget.settings.labelPrinterPort ?? 9100).toString());
  }

  @override
  void dispose() {
    ipCtrl.dispose();
    portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenSettingsPage(
      title: 'Etiket Yazıcı Ayarları',
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: widget.pageState._buildFormTextField(
                    controller: ipCtrl,
                    label: 'Etiket Yazıcı IP Adresi',
                    icon: Icons.settings_ethernet_rounded,
                    hintText: '192.168.1.101',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: widget.pageState._buildFormTextField(
                    controller: portCtrl,
                    label: 'Port',
                    icon: Icons.input_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            widget.pageState._buildModalSaveButton(onTap: () async {
              final currentUser = ref.read(currentUserProvider);
              final hasAccess = currentUser != null &&
                  (currentUser.role == UserRole.sysadmin ||
                      currentUser.role == UserRole.owner ||
                      currentUser.role == UserRole.admin ||
                      currentUser
                          .hasPermission(Permission.settingsPrinter.value));
              if (!hasAccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Yazıcı ayarlarını kaydetmek için yetkiniz yok.'),
                      backgroundColor: _kPink,
                      behavior: SnackBarBehavior.floating),
                );
                return;
              }
              if (_formKey.currentState!.validate()) {
                try {
                  final port = int.tryParse(portCtrl.text.trim()) ?? 9100;
                  final updated = widget.settings.copyWith(
                    labelPrinterIp: ipCtrl.text.trim(),
                    labelPrinterPort: port,
                  );
                  await ref
                      .read(settingsNotifierProvider.notifier)
                      .updateSettings(updated);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Etiket yazıcısı ayarları kaydedildi.'),
                        backgroundColor: _kGreen,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Kaydedilemedi: $e'),
                          backgroundColor: _kPink),
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
