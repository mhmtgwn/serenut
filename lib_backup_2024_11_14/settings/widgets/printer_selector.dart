import 'package:flutter/material.dart';

class PrinterSelector extends StatefulWidget {
  final String selectedPrinter;
  final String paperType;
  final Function(String) onChanged;

  const PrinterSelector({
    Key? key,
    required this.selectedPrinter,
    this.paperType = 'thermal_80mm',
    required this.onChanged,
  }) : super(key: key);

  @override
  State<PrinterSelector> createState() => _PrinterSelectorState();
}

class _PrinterSelectorState extends State<PrinterSelector> {
  late String _selectedPrinter;
  bool _isLoading = false;
  List<String> _availablePrinters = [];

  @override
  void initState() {
    super.initState();
    _selectedPrinter = widget.selectedPrinter;
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    setState(() {
      _isLoading = true;
    });

    // Normalde burada gerçek yazıcıları yükleyeceğiz
    // Using sample data for now
    await Future.delayed(const Duration(seconds: 1));
    
    // Kağıt tipine göre yazıcıları filtrele
    List<String> printers = [];
    if (widget.paperType.startsWith('thermal')) {
      printers.addAll([
        'Termal Yazıcı (58mm)',
        'Termal Yazıcı (80mm)',
        'Epson TM-T20III',
      ]);
    } else if (widget.paperType.startsWith('label')) {
      printers.addAll([
        'Etiket Yazıcısı',
        'Zebra ZD420',
      ]);
    } else {
      printers.addAll([
        'Termal Yazıcı (58mm)',
        'Termal Yazıcı (80mm)',
        'Etiket Yazıcısı',
        'HP LaserJet Pro',
        'Epson TM-T20III',
        'Zebra ZD420',
      ]);
    }
    
    setState(() {
      _availablePrinters = printers;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.print_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('Yazıcı Seçimi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Yazıcıları Yenile',
              onPressed: _loadPrinters,
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Yazıcı seçim listesi
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_availablePrinters.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(8),
              color: Colors.red.shade50,
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Yazıcı bulunamadı. Yazıcınızın açık ve bağlı olduğundan emin olun.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _availablePrinters.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade300),
              itemBuilder: (context, index) {
                final printer = _availablePrinters[index];
                final isSelected = printer == _selectedPrinter;
                
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : null,
                  ),
                  title: Text(printer),
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedPrinter = printer;
                    });
                    widget.onChanged(printer);
                  },
                );
              },
            ),
          ),
          
        const SizedBox(height: 16),
        
        // Kağıt tipi bilgisi
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(
                'Kağıt Tipi: ${_getPaperTypeText(widget.paperType)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Yazıcı ayarları butonu
        OutlinedButton.icon(
          icon: const Icon(Icons.settings),
          label: const Text('Yazıcı Ayarları'),
          onPressed: () {
            _showPrinterSettings(context);
          },
        ),
      ],
    );
  }
  
  // Kağıt tipi metni
  String _getPaperTypeText(String paperType) {
    switch (paperType) {
      case 'thermal_80mm':
        return 'Termal Kağıt (80mm)';
      case 'thermal_58mm':
        return 'Termal Kağıt (58mm)';
      case 'label_100x150':
        return 'Etiket (100x150mm)';
      case 'label_60x40':
        return 'Raf Etiketi (60x40mm)';
      case 'label_100x200':
        return 'Etiket (100x200mm)';
      default:
        return paperType;
    }
  }

  void _showPrinterSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazıcı Ayarları'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yazıcı: $_selectedPrinter'),
            const SizedBox(height: 16),
            const Text('Bağlantı Türü:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              value: 'usb',
              items: const [
                DropdownMenuItem(value: 'usb', child: Text('USB')),
                DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
                DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi')),
                DropdownMenuItem(value: 'network', child: Text('Ağ Yazıcısı')),
              ],
              onChanged: (value) {
                // Bağlantı türü değişimi
              },
            ),
            const SizedBox(height: 16),
            const Text('IP Adresi (Ağ yazıcıları için):'),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '192.168.1.100',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yazıcı ayarları kaydedildi')),
              );
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
} 