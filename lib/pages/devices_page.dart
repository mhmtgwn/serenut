import 'package:flutter/material.dart';
import '../services/device_manager_service.dart';
import '../services/sunmi_printer_service.dart';

/// Aygıtlar sayfası - Dahili ve harici donanımları listeler
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceManagerService _deviceManager = DeviceManagerService();
  final SunmiPrinterService _printerService = SunmiPrinterService();

  List<Map<String, dynamic>> _devices = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);

    try {
      final devices = await _deviceManager.getAllDevices();

      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Aygıt yükleme hatası: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshDevices() async {
    setState(() => _isRefreshing = true);

    try {
      await _deviceManager.refreshAllDevices();
      await _loadDevices();
    } catch (e) {
      debugPrint('Aygıt yenileme hatası: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Future<void> _testDevice(String deviceId) async {
    try {
      final success = await _deviceManager.testPrinter(deviceId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Test başarılı!' : 'Test başarısız'),
            backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
          ),
        );
      }

      // Test sonrası durumu güncelle
      await _refreshDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _setDefaultPrinter(String deviceId) async {
    try {
      await _deviceManager.setDefaultPrinter(deviceId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Varsayılan yazıcı ayarlandı'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }

      await _loadDevices();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aygıtlar'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : _refreshDevices,
            tooltip: 'Yenile',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? _buildEmptyState()
              : _buildDeviceList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.devices_rounded,
              size: 64,
              color: Color(0xFF10B981),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Aygıt Bulunamadı',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Henüz kayıtlı aygıt yok',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshDevices,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Yenile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    // Dahili ve harici aygıtları ayır
    final internalDevices =
        _devices.where((d) => d['connection'] == 'internal').toList();
    final externalDevices =
        _devices.where((d) => d['connection'] != 'internal').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Dahili Aygıtlar
        if (internalDevices.isNotEmpty) ...[
          _buildSectionHeader('Dahili Aygıtlar', Icons.smartphone_rounded),
          const SizedBox(height: 12),
          ...internalDevices
              .map((device) => _buildDeviceCard(device, isInternal: true)),
          const SizedBox(height: 24),
        ],

        // Harici Aygıtlar
        if (externalDevices.isNotEmpty) ...[
          _buildSectionHeader('Harici Aygıtlar', Icons.bluetooth_rounded),
          const SizedBox(height: 12),
          ...externalDevices
              .map((device) => _buildDeviceCard(device, isInternal: false)),
        ],

        // Bluetooth tarama butonu (gelecekte)
        if (externalDevices.isEmpty) ...[
          _buildSectionHeader('Harici Aygıtlar', Icons.bluetooth_rounded),
          const SizedBox(height: 12),
          _buildAddDeviceCard(),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF10B981)),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device,
      {required bool isInternal}) {
    final isConnected = device['status'] == 'connected';
    final isDefault = device['isDefault'] == true;
    final deviceType = device['type'] ?? 'printer';
    final deviceName = device['name'] ?? 'Bilinmeyen Aygıt';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDefault ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
          width: isDefault ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Aygıt detay sayfasına git (gelecekte)
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Aygıt ikonu
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : const Color(0xFF64748B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getDeviceIcon(deviceType),
                        size: 24,
                        color: isConnected
                            ? const Color(0xFF10B981)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Aygıt bilgileri
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  deviceName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Varsayılan',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF64748B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isConnected ? 'Bağlı' : 'Bağlı Değil',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isConnected
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                isInternal
                                    ? Icons.smartphone_rounded
                                    : Icons.bluetooth_rounded,
                                size: 14,
                                color: const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isInternal ? 'Dahili' : 'Harici',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Aksiyon butonları
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _testDevice(device['id']),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Test'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!isDefault)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _setDefaultPrinter(device['id']),
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: const Text('Varsayılan Yap'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddDeviceCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Bluetooth tarama başlat (gelecekte)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bluetooth aygıt tarama yakında eklenecek'),
                backgroundColor: Color(0xFF3B82F6),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 32,
                    color: Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Yeni Aygıt Ekle',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bluetooth yazıcı veya diğer aygıtları ekleyin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'printer':
        return Icons.print_rounded;
      case 'scanner':
        return Icons.qr_code_scanner_rounded;
      case 'nfc':
        return Icons.nfc_rounded;
      case 'drawer':
        return Icons.point_of_sale_rounded;
      default:
        return Icons.devices_rounded;
    }
  }
}
