import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/constants/theme_provider.dart';
import '../../shared/utils/debug_config.dart';
import '../../data/datasources/printer_test_service.dart';
import '../../data/datasources/internal_printer_test_service.dart';
import '../../data/datasources/database_service.dart';

/// Cihaz ayarları sayfası - Yazıcı protokol ve ayarlarını yönetir
class DeviceSettingsPage extends StatefulWidget {
  final Map<String, dynamic> device;

  const DeviceSettingsPage({
    super.key,
    required this.device,
  });

  @override
  State<DeviceSettingsPage> createState() => _DeviceSettingsPageState();
}

class _DeviceSettingsPageState extends State<DeviceSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _paperHeightController;
  late TextEditingController _gapController;
  late String _protocol;
  late String _encoding;
  late int _paperWidth;
  late int _paperHeight;
  late double _gap;
  bool _isReceiptPrinter = false;
  bool _isLabelPrinter = false;
  bool _isLoading = false;
  bool _isTesting = false;

  // Protokol seçenekleri
  final List<Map<String, String>> _internalProtocols = [
    {'value': 'esc_pos', 'label': 'ESC/POS'},
    {'value': 'tspl', 'label': 'TSPL'},
  ];

  final List<Map<String, String>> _externalProtocols = [
    {'value': 'esc_pos', 'label': 'ESC/POS'},
    {'value': 'tsc', 'label': 'TSC'},
    {'value': 'cpcl', 'label': 'CPCL'},
    {'value': 'zpl', 'label': 'ZPL'},
  ];

  // Encoding seçenekleri
  final List<String> _encodings = [
    'UTF-8',
    'ISO-8859-9',
    'Windows-1254',
    'ASCII',
  ];

  // Kağıt genişliği seçenekleri (mm)
  final List<int> _paperWidths = [58, 76, 80, 110, 112];

  @override
  void initState() {
    super.initState();

    try {
      _nameController = TextEditingController(text: widget.device['name']);

      // Ayarları yükle - device map'inden al, varsayılanlar: 58mm, 0mm, 0mm
      _protocol = widget.device['protocol']?.toString() ?? 'esc_pos';
      _encoding = widget.device['encoding']?.toString() ?? 'UTF-8';

      // Kağıt genişliği - varsayılan 58mm
      _paperWidth = widget.device['paperWidth'] is int
          ? widget.device['paperWidth']
          : int.tryParse(widget.device['paperWidth']?.toString() ?? '58') ?? 58;

      // Sayfa yüksekliği - varsayılan 0 (fiş)
      _paperHeight = widget.device['paperHeight'] is int
          ? widget.device['paperHeight']
          : int.tryParse(widget.device['paperHeight']?.toString() ?? '0') ?? 0;

      // GAP - varsayılan 0 (fiş)
      _gap = widget.device['gap'] is double
          ? widget.device['gap']
          : double.tryParse(widget.device['gap']?.toString() ?? '0') ?? 0.0;

      // Yazıcı türleri
      _isReceiptPrinter = (widget.device['isReceiptPrinter'] ?? 0) == 1;
      _isLabelPrinter = (widget.device['isLabelPrinter'] ?? 0) == 1;

      // Controller'ları oluştur
      _paperHeightController =
          TextEditingController(text: _paperHeight.toString());
      _gapController = TextEditingController(text: _gap.toString());

      DebugConfig.logDebug(
          'Ayarlar yüklendi: $_protocol, $_encoding, ${_paperWidth}mm, ${_paperHeight}mm, GAP: ${_gap}mm');
    } catch (e) {
      DebugConfig.logError('initState hatası', e);
      // Hata durumunda varsayılan değerler
      _nameController = TextEditingController(text: 'Cihaz');
      _protocol = 'esc_pos';
      _encoding = 'UTF-8';
      _paperWidth = 58;
      _paperHeight = 0;
      _gap = 0.0;
      _paperHeightController = TextEditingController(text: '0');
      _gapController = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    try {
      _nameController.dispose();
      _paperHeightController.dispose();
      _gapController.dispose();
    } catch (e) {
      DebugConfig.logError('dispose hatası', e);
    }
    super.dispose();
  }

  bool get _isInternal => widget.device['connection'] == 'internal';
  bool get _isPrinter => widget.device['type'] == 'printer';

  // Etiket protokolleri: TSC, TSPL, CPCL, ZPL
  bool get _isLabelProtocol =>
      ['tsc', 'tspl', 'cpcl', 'zpl'].contains(_protocol.toLowerCase());

  List<Map<String, String>> get _availableProtocols =>
      _isInternal ? _internalProtocols : _externalProtocols;

  String _getConnectionName(String? connection) {
    switch (connection) {
      case 'bluetooth':
        return 'Bluetooth';
      case 'usb':
        return 'USB';
      case 'wifi':
        return 'Wi-Fi';
      case 'internal':
        return 'Dahili';
      default:
        return 'Bilinmiyor';
    }
  }

  Future<void> _testDevice() async {
    setState(() {
      _isTesting = true;
    });

    try {
      DebugConfig.logDebug('Test yazdırma başlatılıyor...');

      final String connection = widget.device['connection'] ?? 'bluetooth';
      bool success = false;

      // Dahili mi harici mi kontrol et
      if (connection == 'internal') {
        // Dahili yazıcı (Sunmi) - ESC/POS ve TSPL
        success = await InternalPrinterTestService.instance.printTestPage(
          printerName: _nameController.text,
          protocol: _protocol,
          paperWidth: _paperWidth,
          paperHeight: _paperHeight,
          gap: _gap,
        );
      } else {
        // Harici yazıcı (Bluetooth) - Tüm protokoller
        final bluetoothDevice = widget.device['bluetoothDevice'];
        if (bluetoothDevice == null) {
          throw Exception('Bluetooth cihazı bulunamadı');
        }

        success = await PrinterTestService.instance.printTestPage(
          printerName: _nameController.text,
          address: bluetoothDevice.address,
          bluetoothDevice: bluetoothDevice,
          protocol: _protocol,
          encoding: _encoding,
          paperWidth: _paperWidth,
          paperHeight: _paperHeight,
          gap: _gap,
        );
      }

      // Test sonucu SnackBar ile gösteriliyor

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Test başarılı' : 'Test başarısız'),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      DebugConfig.logError('Test hatası', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test başarısız: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Ayarları database'e kaydet
      final deviceId = widget.device['id'];
      if (deviceId != null) {
        try {
          await DatabaseService.instance.updateDevice(deviceId, {
            'name': _nameController.text,
            'protocol': _protocol,
            'encoding': _encoding,
            'paperWidth': _paperWidth,
            'paperHeight': _paperHeight,
            'gap': _gap,
            'isReceiptPrinter': _isReceiptPrinter ? 1 : 0,
            'isLabelPrinter': _isLabelPrinter ? 1 : 0,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          DebugConfig.logSuccess('Veritabanına kaydedildi: $deviceId');
        } catch (dbError) {
          DebugConfig.logError('Veritabanı kaydetme hatası', dbError);
        }
      }

      // Widget state'i güncelle
      widget.device['name'] = _nameController.text;
      widget.device['protocol'] = _protocol;
      widget.device['encoding'] = _encoding;
      widget.device['paper_width'] = _paperWidth;
      widget.device['paper_height'] = _paperHeight;
      widget.device['gap'] = _gap;
      widget.device['is_receipt_printer'] = _isReceiptPrinter;
      widget.device['is_label_printer'] = _isLabelPrinter;

      DebugConfig.logSuccess(
          'Cihaz ayarları kaydedildi: $_protocol, $_encoding, ${_paperWidth}mm');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      DebugConfig.logError('Ayarları kaydetme hatası', e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final backgroundColor = isDarkMode
        ? AppTheme.darkBackgroundColor
        : AppTheme.lightBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Cihaz Ayarları'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cihaz Bilgileri
                    Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cihaz Bilgileri',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Cihaz Adı',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.devices),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Lütfen bir cihaz adı girin';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              'Bağlantı',
                              _getConnectionName(widget.device['connection']),
                              Icons.link,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              'Model',
                              widget.device['model'] ?? 'Bilinmiyor',
                              Icons.print,
                            ),
                            if (widget.device['id'] != null) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                'Kimlik',
                                widget.device['id'].toString(),
                                Icons.fingerprint,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    // Yazıcı Ayarları
                    if (_isPrinter) ...[
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Yazıcı Ayarları',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Tooltip(
                                    message:
                                        'Bu ayarları değiştirdikten sonra "Kaydet" butonuna basın.',
                                    child: Icon(
                                      Icons.info_outline,
                                      size: 18,
                                      color: AppTheme.greenColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Yazıcı protokolü ve kağıt ayarlarını yapılandırın',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Protokol Seçimi
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Protokol',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.settings_ethernet),
                                  helperText:
                                      'Yazıcınızın desteklediği protokolü seçin',
                                ),
                                value: _protocol,
                                items: _availableProtocols
                                    .map((protocol) => DropdownMenuItem<String>(
                                          value: protocol['value'],
                                          child: Text(protocol['label']!),
                                        ))
                                    .toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _protocol = newValue;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Karakter Kodlaması
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Karakter Kodlaması',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.text_fields),
                                  helperText:
                                      'Türkçe karakterler için UTF-8 önerilir',
                                ),
                                value: _encoding,
                                items: _encodings
                                    .map((encoding) => DropdownMenuItem<String>(
                                          value: encoding,
                                          child: Text(encoding),
                                        ))
                                    .toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _encoding = newValue;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Kağıt Genişliği
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Kağıt Genişliği',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.straighten),
                                  helperText: 'Termal kağıt genişliği (mm)',
                                ),
                                value: _paperWidth,
                                items: _paperWidths
                                    .map((width) => DropdownMenuItem<int>(
                                          value: width,
                                          child: Text('$width mm'),
                                        ))
                                    .toList(),
                                onChanged: (int? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _paperWidth = newValue;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Sayfa Yüksekliği - Sadece etiket protokolleri için
                              if (_isLabelProtocol) ...[
                                TextFormField(
                                  controller: _paperHeightController,
                                  decoration: const InputDecoration(
                                    labelText: 'Sayfa Yüksekliği (mm)',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.height),
                                    helperText:
                                        'Etiket yüksekliği (örn: 40, 50, 100)',
                                    hintText: '50',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (value) {
                                    _paperHeight = int.tryParse(value) ?? 0;
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],

                              // GAP - Sadece etiket protokolleri için
                              if (_isLabelProtocol) ...[
                                TextFormField(
                                  controller: _gapController,
                                  decoration: const InputDecoration(
                                    labelText: 'GAP (mm)',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.space_bar),
                                    helperText:
                                        'Etiketler arası boşluk (örn: 2, 3)',
                                    hintText: '2',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (value) {
                                    _gap = double.tryParse(value) ?? 0.0;
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              const SizedBox(height: 24),

                              // Yazıcı Türü Başlığı
                              const Text(
                                'Yazıcı Türü',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Fiş Yazıcısı
                              CheckboxListTile(
                                title: const Text('Fiş Yazıcısı'),
                                subtitle:
                                    const Text('Sipariş fişleri için kullan'),
                                value: _isReceiptPrinter,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _isReceiptPrinter = value ?? false;
                                  });
                                },
                                secondary: const Icon(Icons.receipt_long),
                              ),

                              // Etiket Yazıcısı (Dahili yazıcı için devre dışı)
                              CheckboxListTile(
                                title: const Text('Etiket Yazıcısı'),
                                subtitle: Text(
                                    widget.device['isInternal'] == true
                                        ? 'Dahili yazıcı etiket desteklemiyor'
                                        : 'Ürün etiketleri için kullan (TSPL)'),
                                value: _isLabelPrinter,
                                enabled: widget.device['isInternal'] != true,
                                onChanged: widget.device['isInternal'] == true
                                    ? null
                                    : (bool? value) {
                                        setState(() {
                                          _isLabelPrinter = value ?? false;

                                          // Etiket yazıcısı seçildiğinde minimum değerleri ayarla
                                          if (_isLabelPrinter) {
                                            // Minimum değerler: GAP 2mm, Yükseklik 30mm, Genişlik 58mm
                                            if (_gap < 2.0) {
                                              _gap = 2.0;
                                              _gapController.text = '2.0';
                                            }
                                            if (_paperHeight < 30) {
                                              _paperHeight = 30;
                                              _paperHeightController.text =
                                                  '30';
                                            }
                                            if (_paperWidth < 58) {
                                              _paperWidth = 58;
                                            }

                                            // Protokolü TSPL yap (etiket için)
                                            if (widget.device['isInternal'] ==
                                                true) {
                                              // _protocol = 'tspl';
                                            }
                                          } else {
                                            // Fiş yazıcısına dönüldüğünde sıfırla
                                            _gap = 0.0;
                                            _gapController.text = '0';
                                            _paperHeight = 0;
                                            _paperHeightController.text = '0';

                                            // Protokolü ESC/POS yap (fiş için)
                                            if (widget.device['isInternal'] ==
                                                true) {
                                              _protocol = 'esc_pos';
                                            }
                                          }
                                        });
                                      },
                                secondary: const Icon(Icons.label),
                              ),

                              // Etiket yazıcısı seçiliyse bilgilendirme
                              if (_isLabelPrinter)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.blue.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.info_outline,
                                            color: Colors.blue.shade700,
                                            size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Etiket modu: GAP ≥ 2mm, Yükseklik ≥ 30mm, Genişlik ≥ 58mm',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Test ve Kaydet Butonları - Altta
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.print),
                            label: Text(
                                _isTesting ? 'Test Ediliyor...' : 'Test Et'),
                            onPressed: _isTesting ? null : _testDevice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Kaydet'),
                            onPressed: _isLoading ? null : _saveSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.greenColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Test ve Kaydet Butonları
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isTesting ? null : _testDevice,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.print),
                            label: Text(_isTesting ? 'Test...' : 'Test Et'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveSettings,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label:
                                Text(_isLoading ? 'Kaydediliyor...' : 'Kaydet'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: AppTheme.greenColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}
