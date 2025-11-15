import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../utils/error_handler.dart';

/// Yazıcı seçimi dialog'u
class PrinterSelectionDialog extends StatefulWidget {
  final String? selectedPrinterId;
  
  const PrinterSelectionDialog({
    Key? key,
    this.selectedPrinterId,
  }) : super(key: key);

  @override
  State<PrinterSelectionDialog> createState() => _PrinterSelectionDialogState();
}

class _PrinterSelectionDialogState extends State<PrinterSelectionDialog> {
  List<Map<String, dynamic>> _printers = [];
  String? _selectedPrinterId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedPrinterId = widget.selectedPrinterId;
    _loadPrinters();
  }

  /// Mevcut yazıcıları yükle
  Future<void> _loadPrinters() async {
    try {
      final db = DatabaseService.instance;
      final allDevices = await db.getAllDevices();
      
      // Sadece yazıcıları filtrele
      final printers = allDevices.where((device) => 
        device['type'] == 'printer'
      ).toList();
      
      setState(() {
        _printers = printers;
        _isLoading = false;
      });
      
      // Eğer seçili yazıcı yoksa ve yazıcılar varsa, ilkini seç
      if (_selectedPrinterId == null && printers.isNotEmpty) {
        setState(() {
          _selectedPrinterId = printers.first['id'];
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ErrorHandler.reportError(
        'Yazıcı Listesi Hatası',
        'Yazıcılar yüklenirken bir sorun oluştu.',
        details: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.print, color: Colors.blue),
          SizedBox(width: 8),
          Text('Yazıcı Seçin'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            : _printers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.print_disabled,
                          size: 48,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Yazıcı bulunamadı',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Lütfen önce ayarlardan bir yazıcı ekleyin.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Fiş yazdırmak için kullanılacak yazıcıyı seçin:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(_printers.length, (index) {
                        final printer = _printers[index];
                        final isSelected = _selectedPrinterId == printer['id'];
                        final isConnected = printer['status'] == 'connected';
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: RadioListTile<String>(
                            value: printer['id'],
                            groupValue: _selectedPrinterId,
                            onChanged: (value) {
                              setState(() {
                                _selectedPrinterId = value;
                              });
                            },
                            title: Text(
                              printer['name'] ?? 'Bilinmeyen Yazıcı',
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Model: ${printer['model'] ?? 'Bilinmiyor'}'),
                                Row(
                                  children: [
                                    Icon(
                                      isConnected ? Icons.check_circle : Icons.error,
                                      size: 16,
                                      color: isConnected ? Colors.green : Colors.red,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isConnected ? 'Bağlı' : 'Bağlı değil',
                                      style: TextStyle(
                                        color: isConnected ? Colors.green : Colors.red,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            secondary: _buildPrinterIcon(printer),
                          ),
                        );
                      }),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        if (_printers.isNotEmpty) ...[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showPrinterSettings();
            },
            child: const Text('Ayarlar'),
          ),
          ElevatedButton(
            onPressed: _selectedPrinterId != null
                ? () => Navigator.of(context).pop(_selectedPrinterId)
                : null,
            child: const Text('Seç'),
          ),
        ],
      ],
    );
  }

  /// Yazıcı tipine göre ikon
  Widget _buildPrinterIcon(Map<String, dynamic> printer) {
    final isInternal = printer['isInternal'] == 1;
    final connection = printer['connection'] ?? '';
    
    if (isInternal) {
      return const Icon(Icons.print, color: Colors.blue);
    } else if (connection == 'bluetooth') {
      return const Icon(Icons.bluetooth, color: Colors.indigo);
    } else if (connection == 'network') {
      return const Icon(Icons.wifi, color: Colors.green);
    } else {
      return const Icon(Icons.print_outlined, color: Colors.grey);
    }
  }

  /// Yazıcı ayarlarını aç
  void _showPrinterSettings() {
    // Ayarlar sayfasına yönlendir
    Navigator.of(context).pushNamed('/settings');
  }
}

/// Yazıcı seçimi göster
Future<String?> showPrinterSelectionDialog(
  BuildContext context, {
  String? selectedPrinterId,
}) async {
  return await showDialog<String>(
    context: context,
    builder: (context) => PrinterSelectionDialog(
      selectedPrinterId: selectedPrinterId,
    ),
  );
}
