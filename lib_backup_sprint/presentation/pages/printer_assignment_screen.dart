import 'package:flutter/material.dart';
import '../../data/datasources/database_service.dart';
import '../../data/datasources/printer_service.dart';

class PrinterAssignmentScreen extends StatefulWidget {
  const PrinterAssignmentScreen({Key? key}) : super(key: key);

  @override
  State<PrinterAssignmentScreen> createState() => _PrinterAssignmentScreenState();
}

class _PrinterAssignmentScreenState extends State<PrinterAssignmentScreen> {
  final _dbService = DatabaseService.instance;
  final _printerService = PrinterService.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _printers = [];
  Map<String, String?> _assignments = {
    'receipt': null,
    'label': null,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Yazıcıları yükle
      final printers = await _dbService.getPrinters();
      
      // Mevcut atamaları yükle
      final receiptPrinter = await _printerService.getReceiptPrinter();
      final labelPrinter = await _printerService.getLabelPrinter();
      
      setState(() {
        _printers = printers;
        _assignments['receipt'] = receiptPrinter != null ? receiptPrinter['id'] as String : null;
        _assignments['label'] = labelPrinter != null ? labelPrinter['id'] as String : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Yazıcı bilgileri yüklenirken hata: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yazıcı bilgileri yüklenemedi: $e'))
        );
      }
    }
  }

  Future<void> _assignPrinter(String type, String? deviceId) async {
    bool success = false;
    
    try {
      if (deviceId == null) {
        // Atama silinecek
        if (type == 'receipt') {
          success = await _printerService.removeReceiptPrinter();
        } else {
          success = await _printerService.removeLabelPrinter();
        }
      } else {
        // Yeni atama yapılacak
        if (type == 'receipt') {
          success = await _printerService.assignReceiptPrinter(deviceId);
        } else {
          success = await _printerService.assignLabelPrinter(deviceId);
        }
      }
      
      if (success) {
        setState(() {
          _assignments[type] = deviceId;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${type == 'receipt' ? 'Fiş' : 'Etiket'} yazıcısı atandı'))
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${type == 'receipt' ? 'Fiş' : 'Etiket'} yazıcısı atanamadı'),
              backgroundColor: Colors.red,
            )
          );
        }
      }
    } catch (e) {
      debugPrint('Yazıcı atanırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yazıcı Atamaları'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _printers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Henüz yazıcı bulunamadı.'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/devices'),
                        child: const Text('Cihaz Ekle'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Yazıcı atamaları yapın',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),
                      
                      // Fiş yazıcısı atama
                      _buildPrinterAssignment(
                        title: 'Fiş Yazıcısı',
                        type: 'receipt',
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Etiket yazıcısı atama
                      _buildPrinterAssignment(
                        title: 'Etiket Yazıcısı',
                        type: 'label',
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildPrinterAssignment({
    required String title,
    required String type,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              value: _assignments[type],
              hint: const Text('Yazıcı seçin'),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Atanmamış'),
                ),
                ..._printers.map((printer) {
                  return DropdownMenuItem<String?>(
                    value: printer['id'] as String,
                    child: Text(printer['name'] as String),
                  );
                }).toList(),
              ],
              onChanged: (value) => _assignPrinter(type, value),
            ),
            if (_assignments[type] != null) ...[
              const SizedBox(height: 8),
              _buildPrinterInfo(_assignments[type]!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterInfo(String deviceId) {
    final printer = _printers.firstWhere(
      (p) => p['id'] == deviceId,
      orElse: () => <String, dynamic>{},
    );
    
    if (printer.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text('Model: ${printer['model'] ?? 'Bilinmiyor'}'),
        if (printer['connection'] != null)
          Text('Bağlantı: ${printer['connection']}'),
        if (printer['paperWidth'] != null)
          Text('Kağıt Genişliği: ${printer['paperWidth']} mm'),
      ],
    );
  }
} 