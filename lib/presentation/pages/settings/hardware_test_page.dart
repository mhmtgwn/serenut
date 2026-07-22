import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/providers/device_status_provider.dart'
    show scannerModeLabelProvider;
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/domain/services/i_scanner_service.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';
import 'package:serenutos/providers/hardware_provider.dart';
import 'package:serenutos/providers/hardware_config_provider.dart';
import 'package:serenutos/providers/payment_terminal_provider.dart';

class HardwareTestPage extends ConsumerStatefulWidget {
  const HardwareTestPage({super.key});

  @override
  ConsumerState<HardwareTestPage> createState() => _HardwareTestPageState();
}

class _HardwareTestPageState extends ConsumerState<HardwareTestPage> {
  int _selectedPaperWidth = 58;
  bool _isPrinting = false;
  final List<String> _scannedBarcodes = [];
  StreamSubscription<ScanEvent>? _scannerSubscription;
  final FocusNode _scannerFocusNode = FocusNode();
  final _scaleHostController = TextEditingController();
  final _scalePortController = TextEditingController(text: '4001');
  final _scaleSerialPortController = TextEditingController();
  final _scaleBaudController = TextEditingController(text: '9600');
  final _posHostController = TextEditingController();
  final _posPortController = TextEditingController(text: '4100');
  bool _hardwareConfigLoaded = false;
  String _scaleConnection = 'tcp';
  int _scaleDataBits = 8;
  int _scaleStopBits = 1;
  String _scaleParity = 'none';
  String _scaleDefaultUnit = 'kg';
  String _posVendor = 'generic';
  String _posProtocol = 'vendor_sdk';

  @override
  void initState() {
    super.initState();
    // Initialize scanner service and listen to scans
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scannerServiceProvider).initialize();
      _scannerSubscription =
          ref.read(scannerServiceProvider).scanStream.listen((event) {
        setState(() {
          _scannedBarcodes.insert(0,
              '${DateFormat('HH:mm:ss').format(DateTime.now())} - ${event.barcode}');
          if (_scannedBarcodes.length > 5) {
            _scannedBarcodes.removeLast();
          }
        });
      });
      _scannerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scannerSubscription?.cancel();
    _scannerFocusNode.dispose();
    _scaleHostController.dispose();
    _scalePortController.dispose();
    _scaleSerialPortController.dispose();
    _scaleBaudController.dispose();
    _posHostController.dispose();
    _posPortController.dispose();
    super.dispose();
  }

  Future<void> _runPrinterTest() async {
    final settingsAsync = ref.read(settingsNotifierProvider);
    final settings = settingsAsync.value;
    if (settings == null) return;

    setState(() {
      _isPrinting = true;
    });

    try {
      final printer = ref.read(printerServiceProvider);
      printer.enqueue(
        'Teşhis Fişi (${_selectedPaperWidth}mm)',
        () => printer.printDiagnosticsTest(settings, _selectedPaperWidth),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Yazdırma sıraya eklendi: ${_selectedPaperWidth}mm')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazıcı testi başarısız oldu: $e')),
        );
      }
    } finally {
      setState(() {
        _isPrinting = false;
      });
    }
  }

  Future<void> _saveHardwareConfig() async {
    final scalePort = int.tryParse(_scalePortController.text);
    final scaleBaud = int.tryParse(_scaleBaudController.text);
    final posPort = int.tryParse(_posPortController.text);
    if (scalePort == null || scaleBaud == null || posPort == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Port değerleri sayı olmalıdır.')));
      return;
    }
    await saveHardwareConfig(HardwareConfig(
      scaleConnection: _scaleConnection,
      scaleHost: _scaleHostController.text,
      scalePort: scalePort,
      scaleSerialPort: _scaleSerialPortController.text,
      scaleBaudRate: scaleBaud,
      scaleDataBits: _scaleDataBits,
      scaleStopBits: _scaleStopBits,
      scaleParity: _scaleParity,
      scaleDefaultUnit: _scaleDefaultUnit,
      posBridgeHost: _posHostController.text,
      posBridgePort: posPort,
      posVendor: _posVendor,
      posProtocol: _posProtocol,
    ));
    ref.invalidate(hardwareConfigProvider);
    ref.invalidate(scaleAdapterProvider);
    ref.invalidate(scaleHardwareProvider);
    ref.invalidate(paymentTerminalAdapterProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Donanım bağlantıları kaydedildi ve yenilendi.')));
    }
  }

  Future<void> _runPosTest() async {
    try {
      final result = await ref.read(paymentTerminalAdapterProvider).probe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result.paired && result.saleSupported
              ? 'POS hazır: ${result.vendor} ${result.model} (${result.protocol})'
              : 'POS yanıt verdi fakat eşleşmiş/satışa hazır değil.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('POS bağlantı testi başarısız: $error')));
    }
  }

  Future<void> _selectSerialPort() async {
    try {
      final ports = SerialScaleAdapter.availablePorts;
      if (!mounted) return;
      if (ports.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Windows üzerinde kullanılabilir COM portu bulunamadı.')));
        return;
      }
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Terazi COM portunu seçin'),
          children: [
            for (final port in ports)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, port),
                child: Text(port),
              ),
          ],
        ),
      );
      if (selected != null) _scaleSerialPortController.text = selected;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('COM portları taranamadı: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scannerLabel = ref.watch(scannerModeLabelProvider);
    final settings = ref.watch(settingsNotifierProvider).value;
    final scaleState = ref.watch(scaleHardwareProvider);
    final reading = scaleState.reading;
    final hardwareConfig = ref.watch(hardwareConfigProvider).valueOrNull;
    if (!_hardwareConfigLoaded && hardwareConfig != null) {
      _hardwareConfigLoaded = true;
      _scaleHostController.text = hardwareConfig.scaleHost;
      _scalePortController.text = hardwareConfig.scalePort.toString();
      _scaleConnection = hardwareConfig.scaleConnection;
      _scaleSerialPortController.text = hardwareConfig.scaleSerialPort;
      _scaleBaudController.text = hardwareConfig.scaleBaudRate.toString();
      _scaleDataBits = hardwareConfig.scaleDataBits;
      _scaleStopBits = hardwareConfig.scaleStopBits;
      _scaleParity = hardwareConfig.scaleParity;
      _scaleDefaultUnit = hardwareConfig.scaleDefaultUnit;
      _posHostController.text = hardwareConfig.posBridgeHost;
      _posPortController.text = hardwareConfig.posBridgePort.toString();
      _posVendor = hardwareConfig.posVendor;
      _posProtocol = hardwareConfig.posProtocol;
    }

    return FullScreenSettingsPage(
      title: 'Donanım Testleri',
      child: GestureDetector(
        onTap: () => _scannerFocusNode.requestFocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Explanation Card ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderColor),
              ),
              child: const Row(
                children: [
                  Icon(Icons.settings_input_hdmi_rounded,
                      color: kGreen, size: 40),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gerçek Cihaz Testleri',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: kTextPrimary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Terazi, fiziksel POS ve yazıcıları sahada deneyip çalışan/çalışmayan olarak raporlayın.',
                          style: TextStyle(fontSize: 12, color: kTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            _buildConnectionSettings(),
            const SizedBox(height: 20),

            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 760;
                final cards = [
                  _buildHardwareCard(
                    icon: Icons.scale_rounded,
                    title: 'Canlı Terazi',
                    subtitle: scaleState.connected
                        ? 'Bağlı · ${reading?.netGrams ?? 0} g · ${hardwareConfig?.scaleConnection == 'serial' ? hardwareConfig?.scaleSerialPort : hardwareConfig?.scaleHost}'
                        : 'Bağlı değil',
                    detail: reading?.stable == true
                        ? 'Ham veri: ${scaleState.rawFrame ?? reading?.rawFrame ?? '(çerçeve yok)'}'
                        : (scaleState.error?.toString() ??
                            'Tartılı ürün seçildiğinde canlı okuma başlar.'),
                    color: kGreen,
                    actions: [
                      FilledButton(
                        onPressed: () => ref.invalidate(scaleHardwareProvider),
                        child: const Text('Yeniden bağlan'),
                      ),
                    ],
                  ),
                  _buildHardwareCard(
                    icon: Icons.credit_card_rounded,
                    title: 'Fiziksel POS',
                    subtitle: hardwareConfig?.hasPosBridge == true
                        ? '${hardwareConfig!.posBridgeHost}:${hardwareConfig.posBridgePort}'
                        : 'POS köprüsü yapılandırılmadı',
                    detail:
                        'Terminal onay ve provizyon kodu vermeden kart satışı kaydedilmez.',
                    color: const Color(0xFFF59E0B),
                    actions: [
                      FilledButton.icon(
                        onPressed: _runPosTest,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('POS test'),
                      ),
                    ],
                  ),
                  _buildHardwareCard(
                    icon: Icons.print_rounded,
                    title: 'Yazıcı',
                    subtitle: settings?.printerName ?? 'Yazıcı seçilmedi',
                    detail:
                        'Windows yazıcı, TCP 9100, Bluetooth ve Sunmi çıktıları gerçek cihazda test edilir.',
                    color: const Color(0xFF3B82F6),
                    actions: [
                      FilledButton.icon(
                        onPressed: _isPrinting ? null : _runPrinterTest,
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Test fişi'),
                      ),
                    ],
                  ),
                ];
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final card in cards) Expanded(child: card),
                        ],
                      )
                    : Column(children: cards);
              },
            ),
            const SizedBox(height: 24),

            // ── SECTION 1: PRINTER TESTS ──
            const Text(
              'FİŞ YAZICI TESTLERİ',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextSecondary,
                  letterSpacing: 0.3),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusRow(
                    icon: Icons.print_rounded,
                    label: 'Yazıcı Modeli',
                    value: settings?.printerName ?? 'Belirtilmedi',
                  ),
                  const Divider(height: 24),
                  _buildStatusRow(
                    icon: Icons.lan_rounded,
                    label: 'Yazıcı IP & Port',
                    value: settings?.printerIp != null &&
                            settings!.printerIp!.isNotEmpty
                        ? '${settings.printerIp}:${settings.printerPort}'
                        : 'Belirtilmedi (USB/BT/Gömülü)',
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Test Kağıt Genişliği Seçimi',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('58 mm')),
                          selected: _selectedPaperWidth == 58,
                          selectedColor: const Color(0xFFD1FAE5),
                          labelStyle: TextStyle(
                            color: _selectedPaperWidth == 58
                                ? kGreen
                                : kTextSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(() => _selectedPaperWidth = 58);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('80 mm')),
                          selected: _selectedPaperWidth == 80,
                          selectedColor: const Color(0xFFD1FAE5),
                          labelStyle: TextStyle(
                            color: _selectedPaperWidth == 80
                                ? kGreen
                                : kTextSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            if (selected)
                              setState(() => _selectedPaperWidth = 80);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _isPrinting ? null : _runPrinterTest,
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Deneme Fişi Yazdır (Buzzer & Kesme)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── SECTION 2: BARCODE SCANNER ──
            const Text(
              'BARKOD OKUYUCU TESTLERİ',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: kTextSecondary,
                  letterSpacing: 0.3),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusRow(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Aktif Tarayıcı Modu',
                    value: scannerLabel,
                  ),
                  const Divider(height: 24),
                  const Text(
                    'Canlı Barkod Sinyalleri (Okutun)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary),
                  ),
                  const SizedBox(height: 10),
                  // Dummy hidden focus target to capture USB keyboard scanner inputs
                  Opacity(
                    opacity: 0,
                    child: SizedBox(
                      height: 1,
                      width: 1,
                      child: Focus(
                        focusNode: _scannerFocusNode,
                        autofocus: true,
                        onKeyEvent: (node, event) {
                          // Allow intercepts from usb keyboard scanner service
                          return KeyEventResult.ignored;
                        },
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  if (_scannedBarcodes.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      decoration: BoxDecoration(
                        color: kBgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kBorderColor),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.barcode_reader,
                              size: 36, color: Colors.grey[300]),
                          const SizedBox(height: 8),
                          const Text(
                            'Barkod okutulması bekleniyor...',
                            style:
                                TextStyle(fontSize: 12, color: kTextSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kBgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _scannedBarcodes.map((barcode) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded,
                                    color: kGreen, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  barcode,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: kTextPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('CANLI DONANIM BAĞLANTILARI',
            style: TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary)),
        const SizedBox(height: 6),
        const Text(
          'Teraziyi doğrudan Windows COM/USB-Serial ile veya TCP ağ üzerinden bağlayın. POS için Windows donanım köprüsünün adresini girin.',
          style: TextStyle(fontSize: 12, color: kTextSecondary),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'serial', label: Text('COM / USB')),
            ButtonSegment(value: 'tcp', label: Text('TCP / Ağ')),
          ],
          selected: {_scaleConnection},
          onSelectionChanged: (value) =>
              setState(() => _scaleConnection = value.first),
        ),
        const SizedBox(height: 10),
        if (_scaleConnection == 'serial')
          Row(children: [
            Expanded(
                flex: 3,
                child: TextField(
                    controller: _scaleSerialPortController,
                    decoration: const InputDecoration(labelText: 'COM portu'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _scaleBaudController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Baud'))),
            IconButton(
                tooltip: 'COM portlarını tara',
                onPressed: _selectSerialPort,
                icon: const Icon(Icons.refresh_rounded)),
          ])
        else
          Row(children: [
            Expanded(
                flex: 3,
                child: TextField(
                    controller: _scaleHostController,
                    decoration: const InputDecoration(labelText: 'Terazi IP'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _scalePortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'))),
          ]),
        if (_scaleConnection == 'serial') ...[
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            DropdownButton<int>(
              value: _scaleDataBits,
              items: const [7, 8]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v bit')))
                  .toList(),
              onChanged: (v) => setState(() => _scaleDataBits = v ?? 8),
            ),
            DropdownButton<int>(
              value: _scaleStopBits,
              items: const [1, 2]
                  .map(
                      (v) => DropdownMenuItem(value: v, child: Text('$v stop')))
                  .toList(),
              onChanged: (v) => setState(() => _scaleStopBits = v ?? 1),
            ),
            DropdownButton<String>(
              value: _scaleParity,
              items: const {
                'none': 'Parity yok',
                'even': 'Çift parity',
                'odd': 'Tek parity',
              }
                  .entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _scaleParity = v ?? 'none'),
            ),
            DropdownButton<String>(
              value: _scaleDefaultUnit,
              items: const [
                DropdownMenuItem(value: 'kg', child: Text('Varsayılan kg')),
                DropdownMenuItem(value: 'g', child: Text('Varsayılan g')),
              ],
              onChanged: (v) => setState(() => _scaleDefaultUnit = v ?? 'kg'),
            ),
          ]),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          DropdownButton<String>(
            value: _posVendor,
            items: const {
              'generic': 'Genel POS',
              'beko_token': 'Beko / Token',
              'ingenico': 'Ingenico',
              'verifone_profilo': 'Verifone / Profilo',
              'hugin': 'Hugin',
              'vera': 'Vera',
            }
                .entries
                .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _posVendor = v ?? 'generic'),
          ),
          DropdownButton<String>(
            value: _posProtocol,
            items: const [
              DropdownMenuItem(value: 'vendor_sdk', child: Text('Üretici SDK')),
              DropdownMenuItem(value: 'gmp3', child: Text('GMP-3')),
              DropdownMenuItem(value: 'ecr', child: Text('ECR')),
            ],
            onChanged: (v) => setState(() => _posProtocol = v ?? 'vendor_sdk'),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              flex: 3,
              child: TextField(
                  controller: _posHostController,
                  decoration:
                      const InputDecoration(labelText: 'POS köprüsü IP'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: _posPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'))),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saveHardwareConfig,
          icon: const Icon(Icons.save_rounded),
          label: const Text('Kaydet ve Bağlan'),
        ),
      ]),
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: kGreen, size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: kTextSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: kTextPrimary),
        ),
      ],
    );
  }

  Widget _buildHardwareCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String detail,
    required Color color,
    required List<Widget> actions,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 10, bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(
              color: kTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}
