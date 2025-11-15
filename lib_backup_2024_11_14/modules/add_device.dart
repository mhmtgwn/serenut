import 'package:flutter/material.dart';
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';

/// Yeni cihaz ekleme sayfası - Basitleştirilmiş
class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _formKey = GlobalKey<FormState>();
  String _selectedType = 'printer';
  bool _isLoading = false;
  bool _isScanning = false;
  
  // Sabit değerler
  final String _selectedConnection = 'bluetooth';
  final String _selectedProtocol = 'esc_pos';
  final String _selectedEncoding = 'UTF-8';
  final int _paperWidth = 58;
  
  // Bluetooth değişkenleri
  List<BluetoothDevice> _bluetoothDevices = [];
  StreamSubscription<List<BluetoothDevice>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  BluetoothDevice? _selectedBluetoothDevice;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    super.dispose();
  }
  
  /// Bluetooth Print Plus dinleyicilerini başlatır
  Future<void> _initBluetooth() async {
    // Bluetooth izinlerini iste
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
    
    // Bluetooth tarama sonuçlarını dinle
    _scanResultsSubscription = BluetoothPrintPlus.scanResults.listen((devices) {
      if (mounted) {
        setState(() {
          _bluetoothDevices = devices;
        });
      }
    });
    
    // Tarama durumunu dinle
    _isScanningSubscription = BluetoothPrintPlus.isScanning.listen((scanning) {
      if (mounted) {
        setState(() {
          _isScanning = scanning;
        });
      }
    });
    
    // Cihazları taramaya başla
    _startScanBluetoothDevices();
  }
  
  /// Bluetooth cihazlarını taramaya başlar
  Future<void> _startScanBluetoothDevices() async {
    try {
      if (!BluetoothPrintPlus.isBlueOn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth kapalı. Lütfen açın.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      
      if (!_isScanning) {
        await BluetoothPrintPlus.startScan(timeout: const Duration(seconds: 15));
      }
    } catch (e) {
      debugPrint('Bluetooth tarama hatası: $e');
    }
  }

  /// Cihaz ekleme işlemini gerçekleştirir
  void _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Bluetooth cihazı seçilmiş mi kontrol et
      if (_selectedBluetoothDevice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen bir bluetooth cihazı seçin'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.amber,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }
      
      // Önce cihazın eşleştirilmiş olup olmadığını kontrol et
      final bool isPaired = await _checkDevicePaired(_selectedBluetoothDevice!);
      
      // Eşleştirilmemiş ise eşleştirmeyi dene
      if (!isPaired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cihaz eşleştiriliyor...'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 1),
          ),
        );
        
        // Cihazı eşleştir
        final bool pairingResult = await _pairDevice(_selectedBluetoothDevice!);
        
        if (!pairingResult) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cihaz eşleştirilemedi. Lütfen sistem ayarlarından manuel olarak eşleştirin.'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.amber,
              duration: Duration(seconds: 5),
            ),
          );
          // Eşleştirme başarısız olsa bile devam et, belki manuel olarak eşleştirilmiştir
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cihaz başarıyla eşleştirildi'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }

      // Cihaz bilgilerini hazırla
      final Map<String, dynamic> device = {
        'id': _selectedBluetoothDevice!.address,
        'name': _selectedBluetoothDevice!.name.isNotEmpty ? _selectedBluetoothDevice!.name : 'Bluetooth Cihazı',
        'type': _selectedType,
        'connection': _selectedConnection,
        'protocol': _selectedProtocol,
        'encoding': _selectedEncoding,
        'paperWidth': _paperWidth,
        'status': 'disconnected',
        'bluetoothName': _selectedBluetoothDevice!.name,
        'bluetoothAddress': _selectedBluetoothDevice!.address,
        'bluetoothDevice': _selectedBluetoothDevice,
        'isInternal': false,
      };

      // Başarılı sonuç döndür
      Navigator.pop(context, device);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cihaz eklenirken hata oluştu: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  /// Cihazın eşleştirilmiş olup olmadığını kontrol eder
  Future<bool> _checkDevicePaired(BluetoothDevice device) async {
    try {
      // BluetoothPrintPlus kütüphanesi üzerinden eşleştirme durumunu kontrol et
      // Not: Bu kütüphanede doğrudan kontrol metodu olmayabilir, bu durumda
      // bağlantı kurmayı deneyerek kontrol edebiliriz
      
      // Kısa bir bağlantı denemesi yap
      try {
        await BluetoothPrintPlus.connect(device);
        await Future.delayed(const Duration(milliseconds: 500));
        await BluetoothPrintPlus.disconnect();
        return true; // Bağlantı kurulabildi, demek ki eşleştirilmiş
      } catch (e) {
        debugPrint('Bağlantı denemesi başarısız, cihaz eşleştirilmemiş olabilir: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Eşleştirme durumu kontrol edilirken hata: $e');
      return false;
    }
  }
  
  /// Cihazı eşleştirir
  Future<bool> _pairDevice(BluetoothDevice device) async {
    try {
      // BluetoothPrintPlus kütüphanesi üzerinden eşleştirme işlemini başlat
      // Not: Bu kütüphanede doğrudan eşleştirme metodu olmayabilir
      
      // Kullanıcıya sistem eşleştirme diyaloğunu açması için bilgi ver
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Bluetooth Eşleştirme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Lütfen sistem bildirimlerini kontrol edin ve cihaz eşleştirme isteğini onaylayın.'),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
      
      // Eşleştirme işlemi için biraz bekle
      await Future.delayed(const Duration(seconds: 5));
      
      // Diyaloğu kapat
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // Eşleştirme işleminin başarılı olup olmadığını kontrol et
      return await _checkDevicePaired(device);
    } catch (e) {
      debugPrint('Eşleştirme işlemi sırasında hata: $e');
      
      // Diyaloğu kapat
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Harici Aygıt Ekle'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cihaz türü seçimi - Card içinde daha çekici görünüm
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aygıt Türünü Seçin',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDeviceTypeOption(
                                    'printer',
                                    'Yazıcı',
                                    Icons.print,
                                    Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildDeviceTypeOption(
                                    'scanner',
                                    'Barkod Okuyucu',
                                    Icons.qr_code_scanner,
                                    Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Bluetooth cihazları listesi
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Bluetooth Cihazları',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_isScanning)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _startScanBluetoothDevices,
                                tooltip: 'Yeniden Tara',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Tarama durumu göstergesi
                  if (_isScanning)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12, 
                            height: 12,
                            margin: const EdgeInsets.only(right: 8),
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const Text("Bluetooth cihazları taranıyor..."),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              BluetoothPrintPlus.stopScan();
                            },
                            child: const Text("Durdur"),
                          ),
                        ],
                      ),
                    ),
                  
                  // Bluetooth cihazları listesi
                  Expanded(
                    child: _bluetoothDevices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.bluetooth_searching,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _isScanning 
                                      ? 'Bluetooth cihazları aranıyor...' 
                                      : 'Bluetooth cihazı bulunamadı',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                                if (!_isScanning) ...[
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _startScanBluetoothDevices,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Yeniden Tara'),
                                  ),
                                ]
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _bluetoothDevices.length,
                            itemBuilder: (context, index) {
                              final device = _bluetoothDevices[index];
                              // Cihaz adı boş ise gösterme
                              if (device.name.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              
                              final isSelected = _selectedBluetoothDevice?.address == device.address;
                              
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected ? Colors.blue : Colors.transparent,
                                    width: isSelected ? 2 : 0,
                                  ),
                                ),
                                color: isSelected ? Colors.blue.shade50 : null,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                  leading: Icon(
                                    _selectedType == 'printer' ? Icons.print : Icons.qr_code_scanner,
                                    color: isSelected ? Colors.blue : Colors.grey,
                                    size: 32,
                                  ),
                                  title: Text(
                                    device.name,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text(device.address),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle, color: Colors.green)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedBluetoothDevice = device;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),

                  // Ekle butonu
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton(
                        onPressed: _addDevice,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'AYGIT EKLE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  /// Cihaz türü seçimi için görsel kart oluşturur
  Widget _buildDeviceTypeOption(String type, String label, IconData icon, Color color) {
    final bool isSelected = _selectedType == type;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          color: Colors.black.withAlpha(26),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 