import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../helpers/printer_helper.dart';
import '../services/database_service.dart';
import '../helpers/printer_helper_utils.dart';
import '../helpers/bluetooth_connection_handler.dart';
import 'dart:async';

/// Cihaz ayarları sayfası
class DeviceSettings extends StatefulWidget {
  final Map<String, dynamic> device;

  const DeviceSettings({
    super.key,
    required this.device,
  });

  @override
  State<DeviceSettings> createState() => _DeviceSettingsState();
}

class _DeviceSettingsState extends State<DeviceSettings> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late String _protocol;
  late String _encoding;
  late int _paperWidth;
  bool _isLoading = false;
  bool _isTesting = false;
  String _testResult = '';
  bool _testSuccess = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  
  // PrinterHelper sınıfı
  
  // Platform kanalları
  
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device['name']);
    _protocol = widget.device['protocol'] ?? 'esc_pos';
    _encoding = widget.device['encoding'] ?? 'UTF-8';
    _paperWidth = widget.device['paperWidth'] ?? 58;
  }

  @override
  void dispose() {
    _nameController.dispose();
    // Sayfadan çıkarken bağlantıyı kapat
    if (!widget.device['isInternal']) {
      _disconnect();
    }
    super.dispose();
  }

  // Bağlantı kontrolü ve bağlanma
  Future<bool> _checkConnection() async {
    if (widget.device['isInternal'] == true) {
      // Dahili yazıcı için bağlantı kontrolü gerekmez
      return true;
    }
    
    setState(() {
      _isConnecting = true;
      _testResult = 'Cihaza bağlanılıyor...';
      _testSuccess = false;
    });
    
    try {
      bool connected = false;
      
      // Bluetooth bağlantısı
      if (widget.device['connection'] == 'bluetooth') {
        // Adres kontrolü
        final String? address = widget.device['bluetoothAddress'];
        if (address == null || address.isEmpty) {
          setState(() {
            _isConnecting = false;
            _testResult = 'Geçersiz Bluetooth adresi';
            _testSuccess = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Geçersiz Bluetooth adresi'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          return false;
        }
        
        // Bağlantı denemesi
        int retryCount = 0;
        const int maxRetries = 2;
        
        while (retryCount < maxRetries && !connected) {
          if (retryCount > 0) {
            setState(() {
              _testResult = 'Yeniden bağlanılıyor (${retryCount + 1}/$maxRetries)...';
            });
            // Yeniden denemeden önce kısa bir bekleme
            await Future.delayed(const Duration(seconds: 1));
          }
          
          try {
            connected = await connectToPrinter(widget.device);
            if (connected) {
              setState(() {
                _testResult = 'Bağlantı başarılı';
                _testSuccess = true;
              });
              break;
            }
          } catch (e) {
            debugPrint('Bağlantı denemesi ${retryCount + 1} hatası: $e');
            // Hatayı yut ve tekrar dene
          }
          
          retryCount++;
        }
        
        if (!connected) {
          setState(() {
            _testResult = 'Bağlantı başarısız';
            _testSuccess = false;
          });
          
          // Kullanıcıya bilgi ver
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.device["name"]} cihazına bağlanılamadı. Cihazın açık ve erişilebilir olduğundan emin olun.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      
      setState(() {
        _isConnecting = false;
      });
      
      return connected;
    } catch (e) {
      debugPrint('Bağlantı kontrolü sırasında hata: $e');
      setState(() {
        _isConnecting = false;
        _testResult = 'Bağlantı hatası: ${e.toString().split('\n')[0]}';
        _testSuccess = false;
      });
      
      // Kullanıcıya bilgi ver
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bağlantı hatası: ${e.toString().split('\n')[0]}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      return false;
    }
  }

  // Bağlantı kesme
  Future<void> _disconnect() async {
    if (widget.device['isInternal'] == true) {
      // Dahili yazıcı için bağlantı kesme gerekmez
      return;
    }
    
    try {
      await disconnectPrinter(widget.device);
    } catch (e) {
      debugPrint('Bağlantı kesme sırasında hata: $e');
    }
  }

  // Test yazdırma
  Future<bool> _testDevicePrint(Map<String, dynamic> device) async {
    return await testPrint(device);
  }

  /// Cihaz testini gerçekleştirir
  Future<void> _testDevice() async {
    setState(() {
      _isTesting = true;
      _testResult = '';
      _testSuccess = false;
      _isConnecting = !widget.device['isInternal'];
    });

    try {
      // Harici cihaz için bağlantı kontrolü
      if (!widget.device['isInternal']) {
        setState(() {
          _testResult = 'Bağlantı kuruluyor...';
        });
        
        final connected = await _checkConnection();
        if (!connected) {
          setState(() {
            _testResult = '${widget.device['name']} cihazına bağlanılamadı';
            _testSuccess = false;
            _isConnecting = false;
          });
          
          // Kullanıcıya bilgi ver
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.device["name"]} cihazına bağlanılamadı. Cihazın açık ve erişilebilir olduğundan emin olun.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
      }
      
      setState(() {
        _isConnecting = false;
        _testResult = 'Test yazdırma başlatılıyor...';
      });
      
      try {
        final result = await _testDevicePrint(widget.device);
        setState(() {
          _testResult = result ? 'Test başarılı' : 'Test başarısız';
          _testSuccess = result;
        });
        
        // Kullanıcıya bilgi ver
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result 
              ? '${widget.device["name"]} test yazdırması başarılı'
              : '${widget.device["name"]} test yazdırması başarısız'),
            backgroundColor: result ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (printError) {
        debugPrint('Test yazdırma hatası: $printError');
        setState(() {
          _testResult = 'Yazdırma hatası: ${printError.toString().split('\n')[0]}';
          _testSuccess = false;
        });
        
        // Kullanıcıya bilgi ver
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yazdırma hatası: ${printError.toString().split('\n')[0]}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Test sırasında genel hata: $e');
      setState(() {
        _testResult = 'Test sırasında hata oluştu: ${e.toString().split('\n')[0]}';
        _testSuccess = false;
      });
      
      // Kullanıcıya bilgi ver
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test sırasında hata: ${e.toString().split('\n')[0]}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() {
        _isTesting = false;
        _isConnecting = false;
      });
    }
  }

  
  




  /// Test sayfası yazdır
  Future<void> _printTestPage() async {
    // Önce bağlantı kontrolü yap
    setState(() {
      _isConnecting = true;
      _testResult = 'Bağlantı kuruluyor...';
      _testSuccess = false;
    });
    
    try {
      if (!widget.device['isInternal']) {
        // Harici cihaz için bağlantı kontrolü
        final connected = await _checkConnection();
        if (!connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.device['name']} cihazına bağlanılamadı'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() {
            _isConnecting = false;
            _testResult = 'Bağlantı başarısız';
            _testSuccess = false;
          });
          return;
        }
      }
      
      // Bağlantı başarılı, yazdırma işlemine geç
      setState(() {
        _isConnecting = false;
        _isPrinting = true;
        _testResult = 'Test sayfası yazdırılıyor...';
      });
      
      bool result = false;
      try {
        result = await PrinterHelper().printTest(
          printerId: widget.device['id'],
          paperWidth: _paperWidth,
          keepConnection: true,
        );
      } catch (printError) {
        debugPrint('Test yazdırma hatası: $printError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yazdırma hatası: ${printError.toString().split('\n')[0]}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() {
          _testResult = 'Yazdırma hatası: ${printError.toString().split('\n')[0]}';
          _testSuccess = false;
        });
        return;
      }
      
      if (result) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test sayfası başarıyla yazdırıldı'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _testResult = 'Test sayfası başarıyla yazdırıldı';
          _testSuccess = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test sayfası yazdırılamadı'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {
          _testResult = 'Test sayfası yazdırılamadı';
          _testSuccess = false;
        });
      }
    } catch (e) {
      debugPrint('Test sayfası yazdırma genel hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yazdırma hatası: ${e.toString().split('\n')[0]}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() {
        _testResult = 'Yazdırma hatası: ${e.toString().split('\n')[0]}';
        _testSuccess = false;
      });
    } finally {
      setState(() {
        _isPrinting = false;
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPrinter = widget.device['type'] == 'printer';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cihaz Ayarları'),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('KAYDET'),
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
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
                    // Cihaz bilgileri
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
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Lütfen bir cihaz adı girin';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            Text('Bağlantı: ${_getConnectionName(widget.device['connection'])}'),
                            const SizedBox(height: 8),
                            Text('Model: ${widget.device['model']}'),
                            if (widget.device['version'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('Versiyon: ${widget.device['version']}'),
                              ),
                            if (widget.device['id'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('Kimlik: ${widget.device['id']}'),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Yazıcı ayarları (eğer yazıcı ise)
                    if (isPrinter) ...[
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
                                  const Tooltip(
                                    message: 'Bu ayarları değiştirdikten sonra "Kaydet" butonuna basarak veritabanına kaydetmelisiniz.',
                                    child: Icon(Icons.info_outline, size: 18, color: Colors.blue),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Aşağıdaki ayarları değiştirdiğinizde kaydetmek için sağ üstteki "Kaydet" butonunu kullanın.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Protokol',
                                  border: OutlineInputBorder(),
                                ),
                                value: _protocol,
                                items: widget.device['isInternal'] == true
                                  ? [
                                      'ESC/POS',
                                      'TSPL',
                                    ].map<DropdownMenuItem<String>>((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value.toLowerCase().replaceAll('/', '_'),
                                        child: Text(value),
                                      );
                                    }).toList()
                                  : [
                                      'ESC/POS',
                                      'TSC',
                                      'CPCL',
                                    ].map<DropdownMenuItem<String>>((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value.toLowerCase().replaceAll('/', '_'),
                                        child: Text(value),
                                      );
                                    }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    // Protokol uyumluluk kontrolü yap
                                    bool isProtocolSupported = false;
                                    
                                    if (widget.device['isInternal'] == true) {
                                      isProtocolSupported = PrinterHelper.isProtocolSupportedForInternal(newValue);
                                    } else {
                                      isProtocolSupported = PrinterHelper.isProtocolSupportedForExternal(newValue);
                                    }
                                    
                                    if (!isProtocolSupported) {
                                      // Protokol uyumlu değilse uyarı göster
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${widget.device['isInternal'] == true ? 'Dahili' : 'Harici'} yazıcı için desteklenmeyen protokol: ${_getProtocolName(newValue)}'
                                          ),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } else {
                                      // Protokol uyumluysa güncelle
                                      setState(() {
                                        _protocol = newValue;
                                      });
                                    }
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Karakter Kodlaması',
                                  border: OutlineInputBorder(),
                                ),
                                value: _encoding,
                                items: [
                                  'UTF-8',
                                  'ISO-8859-9',
                                  'Windows-1254',
                                  'ASCII',
                                ].map<DropdownMenuItem<String>>((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _encoding = newValue;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Kağıt Genişliği (mm)',
                                  border: OutlineInputBorder(),
                                ),
                                value: _paperWidth,
                                items: [
                                  58,
                                  80,
                                  76,
                                  110,
                                  112,
                                ].map<DropdownMenuItem<int>>((int value) {
                                  return DropdownMenuItem<int>(
                                    value: value,
                                    child: Text('$value mm'),
                                  );
                                }).toList(),
                                onChanged: (int? newValue) {
                                  if (newValue != null) {
                                    setState(() {
                                      _paperWidth = newValue;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.print),
                                  label: const Text('Test Sayfası Yazdır'),
                                  onPressed: _isPrinting ? null : _printTestPage,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              if (_isPrinting || _isConnecting)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        const CircularProgressIndicator(strokeWidth: 2),
                                        const SizedBox(height: 8),
                                        Text(_isConnecting 
                                            ? 'Bağlanıyor...' 
                                            : 'Yazdırılıyor...', 
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontSize: 12,
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

                    // Test sonucu
                    if (_testResult.isNotEmpty)
                      Card(
                        // ignore: deprecated_member_use
                        color: _testSuccess ? Colors.green.withAlpha(26) : Colors.red.withAlpha(26),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                _testSuccess ? Icons.check_circle : Icons.error,
                                color: _testSuccess ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _testResult,
                                  style: TextStyle(
                                    color: _testSuccess ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Test butonu
                    ElevatedButton.icon(
                      onPressed: _isTesting ? null : _testDevice,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(_isTesting ? 'Test Ediliyor...' : 'Cihazı Test Et'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Bağlantı türü adını döndürür
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

  /// Protokol adını döndürür
  String _getProtocolName(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'esc_pos':
        return 'ESC/POS';
      case 'tsc':
        return 'TSC';
      case 'tspl':
        return 'TSPL';
      case 'cpcl':
        return 'CPCL';
      case 'zpl':
        return 'ZPL';
      default:
        return protocol;
    }
  }

  /// Ayarları kaydet
  Future<void> _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      try {
        // Cihaz bilgilerini güncelle
        widget.device['name'] = _nameController.text;
        
        if (widget.device['type'] == 'printer') {
          widget.device['protocol'] = _protocol;
          widget.device['encoding'] = _encoding;
          widget.device['paperWidth'] = _paperWidth;
        }
        
        // Değişiklikleri veritabanına kaydet
        final Map<String, dynamic> updatedData = {
          'name': _nameController.text,
          'updatedAt': DateTime.now().toIso8601String(),
        };
        
        // Yazıcı ayarlarını ekle
        if (widget.device['type'] == 'printer') {
          updatedData['protocol'] = _protocol;
          updatedData['encoding'] = _encoding;
          updatedData['paperWidth'] = _paperWidth;
        }
        
        // Veritabanına kaydet
        final deviceId = widget.device['id'];
        final result = await DatabaseService.instance.updateDevice(deviceId, updatedData);
        
        // SharedPreferences'a da kaydet (yedek)
        await _saveToSharedPreferences();
        
        if (result > 0) {
          debugPrint('Cihaz ayarları veritabanına kaydedildi: $deviceId');
          
          // Kaydetme başarılı mesajı
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ayarlar başarıyla kaydedildi'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
        } else {
          debugPrint('Cihaz veritabanında güncellenemedi: $deviceId');
          
          // Veritabanı güncellemesi başarısız
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ayarlar kaydedildi, ancak veritabanı güncellenemedi'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        // Önceki sayfaya dön ve güncelleme gerektiğini bildir
        Navigator.pop(context, true);
      } catch (e) {
        debugPrint('Ayarları kaydetme hatası: $e');
        
        // Hata mesajı
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
        
        // Hata durumunda veritabanına kaydedemesek bile UI değişikliklerini koru
        if (mounted) {
          setState(() => _isLoading = false);
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }
  
  /// Cihaz ayarlarını SharedPreferences'a kaydeder (yedek)
  Future<void> _saveToSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Mevcut cihazları yükle
      final deviceListJson = prefs.getString('devices');
      List<Map<String, dynamic>> devicesList = [];
      
      if (deviceListJson != null) {
        final List<dynamic> parsedList = jsonDecode(deviceListJson);
        devicesList = parsedList.map((item) => Map<String, dynamic>.from(item)).toList();
      }
      
      // Güncellenecek cihazı bul
      final deviceId = widget.device['id'];
      final deviceIndex = devicesList.indexWhere((device) => device['id'] == deviceId);
      
      // BluetoothDevice nesnesini geçici olarak kaldır, JSON'a dönüştürülemez
      final Map<String, dynamic> updatedDevice = Map<String, dynamic>.from(widget.device);
      if (updatedDevice.containsKey('bluetoothDevice')) {
        updatedDevice['bluetoothAddress'] = updatedDevice['bluetoothDevice']?.address ?? '';
        updatedDevice.remove('bluetoothDevice');
      }
      
      // Cihaz listesini güncelle
      if (deviceIndex >= 0) {
        devicesList[deviceIndex] = updatedDevice;
      } else {
        devicesList.add(updatedDevice);
      }
      
      // Güncellenmiş listeyi kaydet
      await prefs.setString('devices', jsonEncode(devicesList));
      debugPrint('Cihaz ayarları SharedPreferences\'a kaydedildi: $deviceId');
    } catch (e) {
      debugPrint('SharedPreferences\'a kaydetme hatası: $e');
    }
  }
} 