import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/printer_helper.dart';
import '../services/database_service.dart';

class ReceiptLabelDesigner extends StatefulWidget {
  const ReceiptLabelDesigner({super.key});

  @override
  State<ReceiptLabelDesigner> createState() => _ReceiptLabelDesignerState();
}

class _ReceiptLabelDesignerState extends State<ReceiptLabelDesigner> {
  // Yazıcı seçimi
  String _selectedReceiptPrinterId = '';
  String _selectedReceiptPrinterName = '';
  String _selectedProductLabelPrinterId = '';
  String _selectedProductLabelPrinterName = '';
  String _selectedShelfLabelPrinterId = '';
  String _selectedShelfLabelPrinterName = '';
  String _selectedOrderLabelPrinterId = '';
  String _selectedOrderLabelPrinterName = '';
  List<Map<String, dynamic>> _availablePrinters = [];
  
  // Etiket türü
  String _designType = 'receipt';
  
  // Kağıt boyutları
  double _paperWidth = 60.0; // Fiş için varsayılan genişlik
  double _paperHeight = 0.0; // Fiş için otomatik hesaplanacak
  
  // Ölçeklendirme faktörü (mm'den piksel'e)
  final double _scaleFactor = 3.0;

  // Etiket türlerine göre varsayılan boyutlar
  final Map<String, Map<String, double>> _defaultSizesByType = {
    'receipt': {
      'width': 60.0,
      'height': 0.0, // Fiş için otomatik hesaplanacak
    },
    'product_label': {
      'width': 60.0,
      'height': 40.0,
    },
    'shelf_label': {
      'width': 60.0,
      'height': 40.0,
    },
    'order_label': {
      'width': 60.0,
      'height': 40.0,
    },
  };
  
  // Accordion menü durumları
  bool _isPrinterSelectorExpanded = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPrinters();
  }

  // Kaydedilmiş ayarları yükle
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Tasarım tipini yükle
      final savedDesignType = prefs.getString('designType');
      if (savedDesignType != null && _defaultSizesByType.containsKey(savedDesignType)) {
        setState(() {
          _designType = savedDesignType;
          _paperWidth = _defaultSizesByType[savedDesignType]!['width']!;
          _paperHeight = _defaultSizesByType[savedDesignType]!['height']!;
        });
      }
      
      // Kağıt boyutlarını yükle
      final savedWidth = prefs.getDouble('paperWidth');
      final savedHeight = prefs.getDouble('paperHeight');
      
      if (savedWidth != null) {
        setState(() {
          _paperWidth = savedWidth;
        });
      }
      
      if (savedHeight != null) {
        setState(() {
          _paperHeight = savedHeight;
        });
      }
      
      // Atanmış yazıcıları yükle
      await _loadAssignedPrinters();
    } catch (e) {
      debugPrint('Ayarlar yüklenirken hata: $e');
    }
  }
  
  // Atanmış yazıcıları yükle
  Future<void> _loadAssignedPrinters() async {
    final db = DatabaseService.instance;
    
    // Fiş yazıcısını yükle
    final receiptPrinter = await db.getReceiptPrinter();
    if (receiptPrinter != null) {
          setState(() {
        _selectedReceiptPrinterId = receiptPrinter['id'] as String;
        _selectedReceiptPrinterName = receiptPrinter['name'] as String;
          });
    }
    
    // Etiket yazıcılarını yükle (Şu an etiket yazıcıları için özel alan yok, labelPrinter kullanıyoruz)
    // Daha sonra veritabanında productLabelPrinter, shelfLabelPrinter, orderLabelPrinter gibi
    // alanlar eklenebilir. Şimdilik hepsi için aynı etiket yazıcısını kullanıyoruz
    final labelPrinter = await db.getLabelPrinter();
    if (labelPrinter != null) {
          setState(() {
        _selectedProductLabelPrinterId = labelPrinter['id'] as String;
        _selectedProductLabelPrinterName = labelPrinter['name'] as String;
        _selectedShelfLabelPrinterId = labelPrinter['id'] as String;
        _selectedShelfLabelPrinterName = labelPrinter['name'] as String;
        _selectedOrderLabelPrinterId = labelPrinter['id'] as String;
        _selectedOrderLabelPrinterName = labelPrinter['name'] as String;
          });
        }
      }
  
  // Yazıcıları yükle
  Future<void> _loadPrinters() async {
    try {
      final printers = await DatabaseService.instance.getPrinters();
      setState(() {
        _availablePrinters = printers;
      });
    } catch (e) {
      debugPrint('Yazıcılar yüklenirken hata: $e');
    }
  }
  
  // Yazıcı ata
  Future<void> _assignPrinter(String type, String printerId) async {
    try {
      final db = DatabaseService.instance;
      final selectedPrinter = _availablePrinters.firstWhere(
        (p) => p['id'] == printerId,
        orElse: () => <String, dynamic>{'name': 'Yazıcı bulunamadı'},
    );
    
      switch (type) {
        case 'receipt':
          await db.assignReceiptPrinter(printerId);
        setState(() {
            _selectedReceiptPrinterId = printerId;
            _selectedReceiptPrinterName = selectedPrinter['name'] as String;
        });
          break;
          
        case 'product_label':
        case 'shelf_label':
        case 'order_label':
          // Not: Şu an veritabanında sadece label printer var, ileride her etiket türü için
          // ayrı yazıcı ataması eklenebilir
          await db.assignLabelPrinter(printerId);
          
          if (type == 'product_label') {
            setState(() {
              _selectedProductLabelPrinterId = printerId;
              _selectedProductLabelPrinterName = selectedPrinter['name'] as String;
            });
          } else if (type == 'shelf_label') {
            setState(() {
              _selectedShelfLabelPrinterId = printerId;
              _selectedShelfLabelPrinterName = selectedPrinter['name'] as String;
            });
          } else if (type == 'order_label') {
            setState(() {
              _selectedOrderLabelPrinterId = printerId;
              _selectedOrderLabelPrinterName = selectedPrinter['name'] as String;
                });
              }
          break;
      }
      
      _isPrinterSelectorExpanded = false;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          content: Text('${selectedPrinter['name']} yazıcısı atandı'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      debugPrint('Yazıcı atanırken hata: $e');
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yazıcı atanamadı: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
          ),
        );
    }
  }
  
  // Etiket türü değiştiğinde
  Future<void> _onDesignTypeChanged(String? type) async {
    if (type == null) return;
    
    setState(() {
      _designType = type;
      _paperWidth = _defaultSizesByType[type]!['width']!;
      _paperHeight = _defaultSizesByType[type]!['height']!;
      _isPrinterSelectorExpanded = false; // Yazıcı seçimini kapat
    });
      
    // Etiket türünü ve boyutlarını kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('designType', type);
    await prefs.setDouble('paperWidth', _paperWidth);
    await prefs.setDouble('paperHeight', _paperHeight);
  }
  
  // Kağıt genişliği değiştiğinde
  Future<void> _onPaperWidthChanged(String value) async {
    final width = double.tryParse(value);
    if (width == null) return;
    
    setState(() {
      _paperWidth = width;
    });
    
    // Kağıt genişliğini kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('paperWidth', width);
  }
  
  // Kağıt yüksekliği değiştiğinde
  Future<void> _onPaperHeightChanged(String value) async {
    final height = double.tryParse(value);
    if (height == null) return;
    
    setState(() {
      _paperHeight = height;
    });
    
    // Kağıt yüksekliğini kaydet
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('paperHeight', height);
  }
  
  // Fiş içeriği önizlemesi
  Widget _buildReceiptPreview() {
    // Fiş için içerik genişliğini ayarla
    final contentWidth = _paperWidth * _scaleFactor - 16;
    
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: contentWidth,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MARKET AŞ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
      ),
          const SizedBox(height: 2),
          Text(
            'Atatürk Cad. No:123',
            style: const TextStyle(fontSize: 8),
            textAlign: TextAlign.center,
          ),
          Text(
            'Tel: 0212 123 45 67',
            style: const TextStyle(fontSize: 8),
          ),
          const Divider(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Fiş No: 12345',
                style: const TextStyle(fontSize: 8),
              ),
              Text(
                '01.01.2024',
                style: const TextStyle(fontSize: 8),
              ),
            ],
          ),
          const Divider(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Ürün',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Adet',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Fiyat',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.right,
                ),
                  ),
            ],
                ),
          const SizedBox(height: 2),
          Row(
                  children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Süt 1L',
                  style: const TextStyle(fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  '2',
                  style: const TextStyle(fontSize: 8),
                  textAlign: TextAlign.center,
                      ),
                    ),
              Expanded(
                flex: 1,
                child: Text(
                  '30,00',
                  style: const TextStyle(fontSize: 8),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Ekmek',
                  style: const TextStyle(fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  '1',
                  style: const TextStyle(fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  '7,50',
                  style: const TextStyle(fontSize: 8),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const Divider(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                'Toplam:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              ),
              Text(
                '37,50 TL',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ödeme: Nakit',
            style: const TextStyle(fontSize: 8),
                    ),
          const SizedBox(height: 4),
                      Text(
            'Teşekkürler',
            style: const TextStyle(fontSize: 8),
            textAlign: TextAlign.center,
                      ),
          const SizedBox(height: 4),
          Container(
            height: 20,
            width: contentWidth * 0.8,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
            child: const Center(
              child: Text('BARKOD', style: TextStyle(fontSize: 8)),
            ),
          ),
        ],
      ),
    );
  }

  // Raf etiketi içeriği önizlemesi
  Widget _buildShelfLabelPreview() {
    // Raf etiketi için içerik boyutlarını ayarla
    final contentWidth = _paperWidth * _scaleFactor - 16;
    final contentHeight = _paperHeight * _scaleFactor - 16;
    
    return SizedBox(
      width: contentWidth,
      height: contentHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Süt 1L',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
                        ),
          const SizedBox(height: 2),
          Text(
            '15,00 TL/L',
            style: const TextStyle(fontSize: 8),
          ),
          Text(
            '30,00 TL',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
          const SizedBox(height: 2),
                    Text(
            'SKU12345',
            style: const TextStyle(fontSize: 8),
                    ),
          const SizedBox(height: 2),
          Container(
            height: 15,
            color: Colors.grey.shade200,
            child: const Center(
              child: Text('8690123456789', style: TextStyle(fontSize: 8)),
            ),
          ),
        ],
      ),
    );
  }

  // Ürün etiketi içeriği önizlemesi
  Widget _buildProductLabelPreview() {
    // Ürün etiketi için içerik boyutlarını ayarla
    final contentWidth = _paperWidth * _scaleFactor - 16;
    final contentHeight = _paperHeight * _scaleFactor - 16;
    
    return SizedBox(
      width: contentWidth,
      height: contentHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tarih
          Align(
            alignment: Alignment.topRight,
            child: Text(
              '01.02.2023',
              style: const TextStyle(fontSize: 8),
            ),
          ),
          const SizedBox(height: 5),
          // Ürün adı
          Text(
            'Ürününüzün adı',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          // Ürün açıklaması
          Text(
            'Ürününüzün açıklaması',
            style: const TextStyle(fontSize: 10),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // Fiyat
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₺299',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
              Text(
                '95',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.start,
              ),
            ],
          ),
          // Birim fiyat
          Text(
            '100 g = 200',
            style: const TextStyle(fontSize: 8),
          ),
          const SizedBox(height: 5),
          // Ürün kodu
          Text(
            'Kod: 1234567890',
            style: const TextStyle(fontSize: 8),
          ),
          const SizedBox(height: 5),
          // Barkod
          Container(
            height: 25,
            width: contentWidth * 0.8,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
            child: const Center(
              child: Text('||||| ||| ||| |||||||| || |||', style: TextStyle(fontSize: 10, fontFamily: 'monospace')),
            ),
          ),
          // Barkod numarası
          Text(
            '1234567890',
            style: const TextStyle(fontSize: 8),
          ),
          const SizedBox(height: 5),
          // Ülke ve şirket
          Align(
            alignment: Alignment.bottomRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'İngiltere',
                  style: const TextStyle(fontSize: 8),
                ),
                Text(
                  'Şirketinizin adı',
                  style: const TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sipariş etiketi içeriği önizlemesi
  Widget _buildOrderLabelPreview() {
    // Sipariş etiketi için içerik boyutlarını ayarla
    final contentWidth = _paperWidth * _scaleFactor - 16;
    final contentHeight = _paperHeight * _scaleFactor - 16;
    
    return SizedBox(
      width: contentWidth,
      height: contentHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'No: ORD123',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '01.01.24',
                style: const TextStyle(fontSize: 8),
              ),
            ],
          ),
          Text(
            'Ahmet Yılmaz',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '0555 123 45 67',
            style: const TextStyle(fontSize: 8),
          ),
          const Divider(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Süt 1L x2',
                  style: const TextStyle(fontSize: 8),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '30,00 TL',
                style: const TextStyle(fontSize: 8),
                textAlign: TextAlign.right,
                      ),
            ],
          ),
          const Divider(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Toplam:',
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
              ),
              Text(
                '30,00 TL',
                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: Container(
              height: 20,
              width: contentWidth * 0.8,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                border: Border.all(color: Colors.grey.shade400, width: 1),
              ),
              child: const Center(
                child: Text('QR KOD', style: TextStyle(fontSize: 8)),
              ),
                ),
              ),
            ],
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrinterId = _getSelectedPrinterId();
    final selectedPrinterName = _getSelectedPrinterName();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiş ve Etiket Tasarımı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: () => _printPreview(),
            tooltip: 'Önizlemeyi Yazdır',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Etiket türü seçimi
              DropdownButtonFormField<String>(
                value: _designType,
                decoration: const InputDecoration(
                  labelText: 'Etiket Türü',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'receipt', child: Text('Fiş')),
                  DropdownMenuItem(value: 'product_label', child: Text('Ürün Etiketi')),
                  DropdownMenuItem(value: 'shelf_label', child: Text('Raf Etiketi')),
                  DropdownMenuItem(value: 'order_label', child: Text('Sipariş Etiketi')),
                ],
                onChanged: _onDesignTypeChanged,
                ),
              const SizedBox(height: 24),
              
              // Etiket türüne göre yazıcı seçimi
              const Text(
                'Yazıcı Seçimi',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
            ),
              ),
              const SizedBox(height: 16),
              
              // Yazıcı seçim kartı (aktif etiket türüne göre)
              Card(
                elevation: 2,
                      child: Column(
              children: [
                    // Başlık ve expand/collapse butonu
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isPrinterSelectorExpanded = !_isPrinterSelectorExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Text(
                              _getPrinterTypeTitle(),
                              style: const TextStyle(
                                fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                            const Spacer(),
                          Text(
                              selectedPrinterName.isEmpty
                                  ? 'Seçilmedi'
                                  : selectedPrinterName,
                            style: TextStyle(
                                color: selectedPrinterId.isEmpty
                                    ? Colors.grey
                                    : Colors.blue,
                            ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isPrinterSelectorExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: Colors.grey,
                      ),
                        ],
                      ),
                    ),
                    ),
                    
                    // Yazıcı listesi (genişlediğinde gösterilir)
                    if (_isPrinterSelectorExpanded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade300, width: 1),
                          ),
                        ),
                        child: _availablePrinters.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Hiç yazıcı bulunamadı. Önce aygıtlar bölümünden yazıcı ekleyin.'),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _availablePrinters.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final printer = _availablePrinters[index];
                                  final isSelected = printer['id'] == selectedPrinterId;
                                  
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    leading: Icon(
                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                      color: isSelected ? Colors.blue : Colors.grey,
                                    ),
                                    title: Text(printer['name'] as String),
                                    subtitle: Text(
                                      '${printer['model'] ?? 'Model bilgisi yok'} - ${printer['connection'] ?? 'Bağlantı bilgisi yok'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    selected: isSelected,
                                    onTap: () => _assignPrinter(_designType, printer['id'] as String),
                                  );
                                },
                              ),
                      ),
                      
                    // Seçilen yazıcı bilgisi (seçim yapıldıysa ve menü kapalıysa gösterilir)
                    if (!_isPrinterSelectorExpanded && selectedPrinterId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                        child: _buildPrinterInfo(selectedPrinterId),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Kağıt boyutu ayarları
              if (_designType != 'receipt') ...[
                TextFormField(
                  initialValue: _paperWidth.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Kağıt Genişliği (mm)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: _onPaperWidthChanged,
                      ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _paperHeight.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Kağıt Yüksekliği (mm)',
                    border: OutlineInputBorder(),
                      ),
                  keyboardType: TextInputType.number,
                  onChanged: _onPaperHeightChanged,
                ),
              ],
              const SizedBox(height: 24),

              // Kağıt boyutu önizlemesi
              Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(
                      children: [
                        const Text(
                          'İçerik Önizlemesi',
                          style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                        const Spacer(),
                        Text(
                          '${_paperWidth.toStringAsFixed(0)} x ${_designType == 'receipt' ? 'Otomatik' : _paperHeight.toStringAsFixed(0)} mm',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        width: _paperWidth * _scaleFactor,
                        height: _designType == 'receipt' 
                            ? null 
                            : _paperHeight * _scaleFactor,
                        constraints: BoxConstraints(
                          minHeight: 100,
                          maxHeight: _designType == 'receipt' ? 400 : double.infinity,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha((0.1 * 255).toInt()),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(8.0),
                        child: _getPreviewForType(_designType),
                      ),
                    ),
                    if (_designType != 'receipt') ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Gerçek boyut: ${_paperWidth.toStringAsFixed(0)} x ${_paperHeight.toStringAsFixed(0)} mm',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                  ],
            ),
          ),
              const SizedBox(height: 24),
              
              // Test yazdırma butonu
                ElevatedButton.icon(
                onPressed: () => _printPreview(),
                icon: const Icon(Icons.print),
                label: const Text('Önizlemeyi Yazdır'),
                  style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }
  
  // Önizleme içeriğini yazdır
  Future<void> _printPreview() async {
    final selectedPrinterId = _getSelectedPrinterId();
    final selectedPrinterName = _getSelectedPrinterName();
    final String printerType = _getPrinterTypeTitle();
    
    // Yazıcı seçilmemişse uyarı göster
    if (selectedPrinterId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lütfen önce bir $printerType seçin'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
    try {
      // Yazdırma işlemi başladı bildirimi
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$selectedPrinterName ile yazdırma işlemi başlatılıyor...'),
          duration: const Duration(seconds: 1),
        ),
      );
      
      // Yazıcı bağlantı kontrolünü burada atla, doğrudan yazdırma dene
      
      // Yazıcı yardımcı sınıfını al
      final printerHelper = PrinterHelper();
      
      // Etiket türüne göre yazdırma işlemi
      bool success = false;
      
      switch (_designType) {
        case 'receipt':
          // Fiş örnek verileri
          success = await printerHelper.printReceipt(
            printerId: selectedPrinterId,
            paperWidth: _paperWidth.toInt(),
            title: 'MARKET AŞ',
            subtitle: 'Atatürk Cad. No:123',
            items: [
              {'name': 'Süt 1L', 'quantity': 2, 'price': 30.00},
              {'name': 'Ekmek', 'quantity': 1, 'price': 7.50},
            ],
            total: 37.50,
            paymentMethod: 'Nakit',
          );
          break;
          
        case 'product_label':
          // Ürün etiketi örnek verileri
          success = await printerHelper.printProductLabel(
            printerId: selectedPrinterId,
            paperWidth: _paperWidth.toInt(),
            paperHeight: _paperHeight.toInt(),
            productName: 'Ürününüzün adı',
            productDescription: 'Ürününüzün açıklaması',
            price: 299.95,
            expiryDate: '01.02.2023',
            barcode: '1234567890',
            code: '1234567890',
            unitPrice: '200',
            company: 'Şirketinizin adı',
            country: 'İngiltere',
          );
          break;
          
        case 'shelf_label':
          // Raf etiketi örnek verileri
          success = await printerHelper.printShelfLabel(
            printerId: selectedPrinterId,
            paperWidth: _paperWidth.toInt(),
            paperHeight: _paperHeight.toInt(),
            productName: 'Süt 1L',
            price: 30.00,
            unitPrice: '15,00 TL/L',
            barcode: '8690123456789',
          );
          break;
          
        case 'order_label':
          // Sipariş etiketi örnek verileri
          success = await printerHelper.printOrderLabel(
            printerId: selectedPrinterId,
            paperWidth: _paperWidth.toInt(),
            paperHeight: _paperHeight.toInt(),
            orderNo: 'ORD123',
            customerName: 'Ahmet Yılmaz',
            customerPhone: '0555 123 45 67',
            items: [
              {'name': 'Süt 1L', 'quantity': 2, 'price': 30.00},
            ],
            total: 30.00,
          );
          break;
      }
      
      // Başarı durumuna göre bildirim göster
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Önizleme başarıyla yazdırıldı. (${_getPrinterTypeTitle()})'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('Yazdırma işlemi başarısız oldu');
      }
    } catch (e) {
      // Hata durumunda bildirim göster
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yazdırma hatası: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  // Yazıcı bilgisi widget'ı
  Widget _buildPrinterInfo(String printerId) {
    final printer = _availablePrinters.firstWhere(
      (p) => p['id'] == printerId,
      orElse: () => <String, dynamic>{},
    );
    
    if (printer.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text('Model: ${printer['model'] ?? 'Bilinmiyor'}',
          style: const TextStyle(fontSize: 12),
        ),
        if (printer['connection'] != null)
          Text('Bağlantı: ${printer['connection']}',
            style: const TextStyle(fontSize: 12),
          ),
        if (printer['paperWidth'] != null)
          Text('Kağıt Genişliği: ${printer['paperWidth']} mm',
            style: const TextStyle(fontSize: 12),
          ),
      ],
    );
  }

  // Etiket türüne göre önizleme widget'ı döndürür
  Widget _getPreviewForType(String type) {
    switch (type) {
      case 'receipt':
        return _buildReceiptPreview();
      case 'product_label':
        return _buildProductLabelPreview();
      case 'shelf_label':
        return _buildShelfLabelPreview();
      case 'order_label':
        return _buildOrderLabelPreview();
      default:
        return _buildReceiptPreview();
    }
  }

  // Seçili yazıcı bilgisini al
  String _getSelectedPrinterId() {
    switch (_designType) {
      case 'receipt':
        return _selectedReceiptPrinterId;
      case 'product_label':
        return _selectedProductLabelPrinterId;
      case 'shelf_label':
        return _selectedShelfLabelPrinterId;
      case 'order_label':
        return _selectedOrderLabelPrinterId;
      default:
        return '';
    }
  }
  
  // Seçili yazıcı adını al
  String _getSelectedPrinterName() {
    switch (_designType) {
      case 'receipt':
        return _selectedReceiptPrinterName;
      case 'product_label':
        return _selectedProductLabelPrinterName;
      case 'shelf_label':
        return _selectedShelfLabelPrinterName;
      case 'order_label':
        return _selectedOrderLabelPrinterName;
      default:
        return '';
    }
  }
  
  // Etiket türüne göre başlık metni al
  String _getPrinterTypeTitle() {
    switch (_designType) {
      case 'receipt':
        return 'Fiş Yazıcısı';
      case 'product_label':
        return 'Ürün Etiketi Yazıcısı';
      case 'shelf_label':
        return 'Raf Etiketi Yazıcısı';
      case 'order_label':
        return 'Sipariş Etiketi Yazıcısı';
      default:
        return 'Yazıcı Seçimi';
    }
  }
} 