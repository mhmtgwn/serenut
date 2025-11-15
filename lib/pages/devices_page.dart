import 'package:flutter/material.dart';
import '../services/device_manager_service.dart';
import 'device_settings_page.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceManagerService _deviceManager = DeviceManagerService();

  List<Map<String, dynamic>> _devices = [];
  bool _isLoading = false;

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
      debugPrint('Hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openDeviceSettings(Map<String, dynamic> device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DeviceSettingsPage(),
      ),
    ).then((_) => _loadDevices());
  }

  IconData _getDeviceIcon(Map<String, dynamic> device) {
    switch (device['type']) {
      case 'printer':
        return Icons.print;
      case 'scanner':
        return Icons.qr_code_scanner;
      case 'nfc':
        return Icons.nfc;
      case 'drawer':
        return Icons.point_of_sale;
      default:
        return Icons.devices;
    }
  }

  Color _getDeviceStatusColor(Map<String, dynamic> device) {
    return device['status'] == 'connected' ? Colors.green : Colors.grey;
  }

  String _getDeviceDescription(Map<String, dynamic> device) {
    final status = device['status'] == 'connected' ? 'Bagli' : 'Bagli Degil';
    final connection = device['connection'] == 'internal' ? 'Dahili' : 'Harici';
    return '$status - $connection';
  }

  @override
  Widget build(BuildContext context) {
    final internalDevices =
        _devices.where((d) => d['connection'] == 'internal').toList();
    final externalDevices =
        _devices.where((d) => d['connection'] != 'internal').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aygitlar'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DAHILI AYGITLAR
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'DAHILI AYGITLAR',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  if (internalDevices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'Dahili aygit bulunamadi',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: internalDevices.length,
                      itemBuilder: (context, index) {
                        final device = internalDevices[index];
                        return ListTile(
                          leading: Icon(
                            _getDeviceIcon(device),
                            color: _getDeviceStatusColor(device),
                          ),
                          title: Text(device['name'] ?? 'Isimsiz Cihaz'),
                          subtitle: Text(_getDeviceDescription(device)),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _openDeviceSettings(device),
                        );
                      },
                    ),

                  // HARICI AYGITLAR
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'HARICI AYGITLAR',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Harici aygit ekleme yakinda'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  if (externalDevices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'Harici aygit eklenmemis',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: externalDevices.length,
                      itemBuilder: (context, index) {
                        final device = externalDevices[index];
                        return ListTile(
                          leading: Icon(
                            _getDeviceIcon(device),
                            color: _getDeviceStatusColor(device),
                          ),
                          title: Text(device['name'] ?? 'Isimsiz Cihaz'),
                          subtitle: Text(_getDeviceDescription(device)),
                          trailing:
                              const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _openDeviceSettings(device),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
