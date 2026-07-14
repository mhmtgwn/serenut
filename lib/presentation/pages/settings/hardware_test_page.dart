import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/providers/device_status_provider.dart';
import 'package:serenutos/providers/service_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/presentation/pages/settings/widgets/settings_widgets.dart';
import 'package:serenutos/domain/services/i_scanner_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceStatusProvider);
    final scannerLabel = ref.watch(scannerModeLabelProvider);
    final settings = ref.watch(settingsNotifierProvider).value;

    return FullScreenSettingsPage(
      title: 'Donanım Diagnostics Testleri',
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
                          'Donanım Teşhis Laboratuvarı',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: kTextPrimary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Bağlı yazıcıları, kağıt genişliklerini ve barkod okuyucu sinyallerini canlı test edin.',
                          style: TextStyle(fontSize: 12, color: kTextSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── SECTION 1: PRINTER DIAGNOSTICS ──
            const Text(
              'FİŞ YAZICI DIAGNOSTICS',
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
                        ? '${settings.printerIp}:${settings.printerPort ?? 9100}'
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
              'BARKOD OKUYUCU DIAGNOSTICS',
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
}
