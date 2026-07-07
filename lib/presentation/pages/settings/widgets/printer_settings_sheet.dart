part of '../../settings_page.dart';

// Extracted Printer Settings Sheets for SettingsPage
extension SettingsPrinterSheets on _SettingsPageState {
  void _showReceiptPrinterSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: settings.printerName ?? '');
    final ipCtrl = TextEditingController(text: settings.printerIp ?? '');
    final portCtrl = TextEditingController(text: settings.printerPort.toString());
    final copiesCtrl = TextEditingController(text: settings.printCopies.toString());
    int paperWidth = settings.paperWidth;

    // Determine initial connection type
    String connectionType = 'network';
    if (settings.printerName == 'sunmi') {
      connectionType = 'sunmi';
    } else if (settings.printerName != null && settings.printerName!.contains(':')) {
      connectionType = 'bluetooth';
    }

    List<Map<String, String>> pairedDevices = [];
    bool isLoadingDevices = false;
    String? selectedDeviceMac = connectionType == 'bluetooth' ? settings.printerName : null;
    bool isBluetoothSupported = true;
    bool hasCalledFetch = false;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => Consumer(
          builder: (routeCtx, ref, child) => StatefulBuilder(
            builder: (ctx, setModalState) {
              Future<void> fetchDevices() async {
                setModalState(() {
                  isLoadingDevices = true;
                });
                try {
                  final available = await NativePrinterBridge.isBluetoothAvailable();
                  if (!available) {
                    setModalState(() {
                      isBluetoothSupported = false;
                      isLoadingDevices = false;
                    });
                    return;
                  }
                  final list = await NativePrinterBridge.getPairedBluetoothDevices();
                  setModalState(() {
                    pairedDevices = list;
                    isLoadingDevices = false;
                    isBluetoothSupported = true;
                  });
                } catch (e) {
                  setModalState(() {
                    isLoadingDevices = false;
                  });
                }
              }

              if (connectionType == 'bluetooth' && !hasCalledFetch) {
                hasCalledFetch = true;
                Future.microtask(() => fetchDevices());
              }

              return FullScreenSettingsPage(
                title: 'Fiş Yazıcı Ayarları',
                child: Form(
                  key: formKey,
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
                          prefixIcon: const Icon(Icons.compare_arrows_rounded, size: 18, color: _kTextSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'network', child: Text('WiFi / Network (Ethernet)')),
                          DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth (Mobil Termal)')),
                          DropdownMenuItem(value: 'sunmi', child: Text('Sunmi Gömülü Yazıcı')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              connectionType = val;
                              if (connectionType == 'bluetooth' && pairedDevices.isEmpty) {
                                fetchDevices();
                              }
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Bağlantı Tipi İçeriği
                      if (connectionType == 'network') ...[
                        _buildFormTextField(
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
                              child: _buildFormTextField(
                                controller: ipCtrl,
                                label: 'Yazıcı IP Adresi',
                                icon: Icons.settings_ethernet_rounded,
                                hintText: '192.168.1.100',
                                validator: (v) => v!.isEmpty ? 'IP Adresi gerekli' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildFormTextField(
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
                                CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_kBlue)),
                                SizedBox(height: 12),
                                Text('Eşleşmiş cihazlar listeleniyor...', style: TextStyle(color: _kTextSecondary, fontSize: 13)),
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
                                Icon(Icons.bluetooth_disabled_rounded, color: _kPink, size: 24),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Bu cihazda Bluetooth bulunamadı veya etkinleştirilmedi.',
                                    style: TextStyle(color: _kPink, fontSize: 13, fontWeight: FontWeight.w500),
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
                                label: const Text('Yeniden Tara', style: TextStyle(color: _kBlue, fontWeight: FontWeight.bold)),
                                onPressed: () => fetchDevices(),
                              ),
                            ],
                          )
                        else
                          DropdownButtonFormField<String>(
                            value: pairedDevices.any((d) => d['address'] == selectedDeviceMac) ? selectedDeviceMac : null,
                            dropdownColor: Colors.white,
                            hint: const Text('Bluetooth Yazıcı Seçin'),
                            style: const TextStyle(color: _kTextPrimary, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Eşleşmiş Bluetooth Cihazları',
                              prefixIcon: const Icon(Icons.bluetooth_rounded, size: 18, color: _kBlue),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.refresh_rounded, size: 18, color: _kBlue),
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
                                setModalState(() {
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
                                  style: TextStyle(color: _kGreen, fontSize: 13, fontWeight: FontWeight.w500),
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
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBorderColor)),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                              ),
                              items: const [
                                DropdownMenuItem(value: 80, child: Text('80 mm')),
                                DropdownMenuItem(value: 58, child: Text('58 mm')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => paperWidth = val);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFormTextField(
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final testSet = settings.copyWith(
                            printerName: connectionType == 'sunmi' ? 'sunmi' : (connectionType == 'bluetooth' ? selectedDeviceMac : nameCtrl.text.trim()),
                            printerIp: connectionType == 'network' ? ipCtrl.text.trim() : null,
                            printerPort: int.tryParse(portCtrl.text) ?? 9100,
                            paperWidth: paperWidth,
                          );
                          try {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Test fişi kuyruğa eklendi...'), backgroundColor: _kBlue, behavior: SnackBarBehavior.floating),
                            );
                            await ref.read(printerServiceProvider).testPrinterConnection(testSet);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Test fişi başarıyla yazdırıldı.'), backgroundColor: _kGreen, behavior: SnackBarBehavior.floating),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Test başarısız: $e'), backgroundColor: _kPink, behavior: SnackBarBehavior.floating),
                              );
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      _buildModalSaveButton(onTap: () async {
                        if (formKey.currentState!.validate()) {
                          final updated = settings.copyWith(
                            printerName: connectionType == 'sunmi' ? 'sunmi' : (connectionType == 'bluetooth' ? selectedDeviceMac : nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim()),
                            printerIp: connectionType == 'network' ? ipCtrl.text.trim() : null,
                            printerPort: connectionType == 'network' ? (int.tryParse(portCtrl.text) ?? 9100) : 9100,
                            printCopies: int.tryParse(copiesCtrl.text) ?? 1,
                            paperWidth: paperWidth,
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

  void _showLabelPrinterSheet(Settings settings) {
    final formKey = GlobalKey<FormState>();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '9100');

    SharedPreferences.getInstance().then((prefs) {
      ipCtrl.text = prefs.getString('label_printer_ip') ?? '';
      portCtrl.text = prefs.getString('label_printer_port') ?? '9100';
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FullScreenSettingsPage(
          title: 'Etiket Yazıcı Ayarları',
          child: Form(
            key: formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildFormTextField(
                        controller: ipCtrl,
                        label: 'Etiket Yazıcı IP Adresi',
                        icon: Icons.settings_ethernet_rounded,
                        hintText: '192.168.1.101',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFormTextField(
                        controller: portCtrl,
                        label: 'Port',
                        icon: Icons.input_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildModalSaveButton(onTap: () async {
                  if (formKey.currentState!.validate()) {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('label_printer_ip', ipCtrl.text.trim());
                      await prefs.setString('label_printer_port', portCtrl.text.trim());
                      if (context.mounted) {
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Kaydedilemedi: $e'), backgroundColor: _kPink),
                        );
                      }
                    }
                  }
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
