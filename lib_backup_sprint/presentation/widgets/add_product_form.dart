import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import '../../data/datasources/product_service.dart';
import 'package:flutter/services.dart';
import '../../shared/constants/app_theme.dart';
import 'package:provider/provider.dart';
import '../../shared/constants/theme_provider.dart';

class AddProductForm extends StatefulWidget {
  final Function onProductAdded;

  const AddProductForm({
    super.key,
    required this.onProductAdded,
  });

  @override
  State<AddProductForm> createState() => _AddProductFormState();
}

class _AddProductFormState extends State<AddProductForm> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _taxController = TextEditingController();
  final _discountController = TextEditingController();
  final _stockController = TextEditingController();
  final _criticalStockController = TextEditingController();
  final _unitController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _brandController = TextEditingController();
  String _selectedUnit = 'adet';
  File? _imageFile;
  bool _isSaving = false;
  bool _isScanning = false;
  
  // Kar marjı ve vergi hesaplamaları için değişkenler
  double _profitMargin = 0.0;
  double _profitAmount = 0.0;
  double _finalPrice = 0.0;
  double _taxAmount = 0.0;

  final List<String> _units = [
    'adet',
    'kg',
    'g',
    'lt',
    'ml',
    'm',
    'cm',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadTaxRates();
    _loadUnits();
    
    _priceController.addListener(_calculateProfitAndTax);
    _purchasePriceController.addListener(_calculateProfitAndTax);
    _taxController.addListener(_calculateProfitAndTax);
    _discountController.addListener(_calculateProfitAndTax);
  }

  void _calculateProfitAndTax() {
    if (_priceController.text.isEmpty || _purchasePriceController.text.isEmpty) {
      setState(() {
        _profitMargin = 0.0;
        _profitAmount = 0.0;
        _finalPrice = 0.0;
        _taxAmount = 0.0;
      });
      return;
    }

    try {
      // Kullanıcının girdiği fiyat KDV hariç satış fiyatı olarak kabul edilir
      final double salePriceWithoutTax = double.parse(_priceController.text);
      final double purchasePrice = double.parse(_purchasePriceController.text);
      final double taxRate = _taxController.text.isNotEmpty 
          ? double.parse(_taxController.text) / 100 
          : 0.0;
      final double discountRate = _discountController.text.isNotEmpty 
          ? double.parse(_discountController.text) / 100 
          : 0.0;

      // İndirimli KDV hariç fiyat hesapla
      final double discountedPriceWithoutTax = salePriceWithoutTax * (1 - discountRate);
      
      // Kar miktarı hesapla (KDV hariç)
      final double profitAmount = discountedPriceWithoutTax - purchasePrice;
      
      // Kar marjı hesapla
      final double profitMargin = purchasePrice > 0 
          ? (profitAmount / purchasePrice) * 100
          : 0.0;
      
      // KDV'yi SADECE KAR TUTARI üzerinden hesapla
      final double taxAmount = profitAmount * taxRate;
      
      // Son fiyat (KDV dahil) = KDV hariç fiyat + KDV
      final double finalPrice = discountedPriceWithoutTax + taxAmount;

      setState(() {
        _profitMargin = profitMargin;
        _profitAmount = profitAmount;
        _finalPrice = finalPrice;
        _taxAmount = taxAmount;
      });
    } catch (e) {
      // Sayısal değer dönüştürme hatası
      setState(() {
        _profitMargin = 0.0;
        _profitAmount = 0.0;
        _finalPrice = 0.0;
        _taxAmount = 0.0;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await showDialog<XFile?>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a Photo'),
                onTap: () async {
                  final currentContext = context;
                  final result = await picker.pickImage(source: ImageSource.camera);
                  if (currentContext.mounted) {
                    Navigator.pop(currentContext, result);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  final currentContext = context;
                  final result = await picker.pickImage(source: ImageSource.gallery);
                  if (currentContext.mounted) {
                    Navigator.pop(currentContext, result);
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  void _showDialogBarcodeScanner() {
    setState(() {
      _isScanning = true;
    });
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      setState(() {
        _barcodeController.text = barcodes.first.rawValue ?? '';
        _isScanning = false;
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final newProduct = {
        'name': _nameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'price': double.parse(_priceController.text),
        'purchasePrice': _purchasePriceController.text.isNotEmpty 
            ? double.parse(_purchasePriceController.text) 
            : 0.0,
        'tax': _taxController.text.isNotEmpty 
            ? double.parse(_taxController.text) 
            : 18.0,
        'discount': _discountController.text.isNotEmpty 
            ? double.parse(_discountController.text) 
            : 0.0,
        'stock': _stockController.text.isNotEmpty 
            ? double.parse(_stockController.text) 
            : 0.0,
        'criticalStock': _criticalStockController.text.isNotEmpty 
            ? double.parse(_criticalStockController.text) 
            : 0.0,
        'unit': _selectedUnit,
        'description': _descriptionController.text.trim(),
        'category': _categoryController.text.trim(),
        'brand': _brandController.text.trim(),
        'imagePath': _imageFile?.path,
      };
      
      // ProductService kullanarak ürünü ekle
      final productId = await ProductService.instance.addProduct(newProduct);
      
      if (productId <= 0) {
        throw Exception('Ürün eklenemedi. Veritabanı hatası.');
      }

      widget.onProductAdded();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ürün başarıyla eklendi'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Ürün eklenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ürün eklenirken hata oluştu: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final textColor = isDarkMode ? AppTheme.darkPrimaryTextColor : Colors.black87;
    final iconColor = isDarkMode ? Colors.white70 : Colors.grey.shade600;
    
    if (_isScanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan Barcode'),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isScanning = false;
                });
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(
              onDetect: _onBarcodeDetect,
            ),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white,
                    width: 2.0,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                width: 200,
                height: 200,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Ürün Ekle'),
        backgroundColor: isDarkMode ? AppTheme.darkSurfaceColor : Colors.white,
        foregroundColor: isDarkMode ? Colors.white : Colors.black,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProduct,
            ),
        ],
      ),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Ürün resmi
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: isDarkMode ? AppTheme.darkCardColor : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: isDarkMode ? Colors.black.withAlpha(19635) : Colors.grey.withAlpha(19635),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _imageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _imageFile!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 40,
                                    color: iconColor,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Resim Ekle',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Barkod alanı
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: InputDecoration(
                            labelText: 'Barkod',
                            prefixIcon: Icon(Icons.qr_code, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor),
                        onPressed: _showDialogBarcodeScanner,
                        tooltip: 'Barkod Tara',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Ürün adı
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Ürün Adı *',
                      prefixIcon: Icon(Icons.inventory_2_outlined, color: iconColor),
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(color: textColor),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Lütfen ürün adı girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          onChanged: (value) => _calculateProfitAndTax(),
                          decoration: InputDecoration(
                            labelText: 'Satış Fiyatı (KDV Dahil) *',
                            prefixIcon: Icon(Icons.attach_money, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Lütfen fiyat girin';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _taxController,
                          decoration: InputDecoration(
                            labelText: 'KDV (%)',
                            prefixIcon: Icon(Icons.receipt_long_outlined, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          decoration: InputDecoration(
                            labelText: 'Alış Fiyatı',
                            prefixIcon: Icon(Icons.shopping_cart_outlined, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _discountController,
                          decoration: InputDecoration(
                            labelText: 'İndirim (%)',
                            prefixIcon: Icon(Icons.discount_outlined, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Kar marjı ve hesaplama bilgileri
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? AppTheme.darkCardColor : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDarkMode ? Colors.green.shade800 : Colors.green.shade200
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hesaplama Özeti',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Kar Marjı:',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              '${_profitMargin.toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _profitMargin >= 0 
                                  ? (isDarkMode ? Colors.green.shade300 : Colors.green) 
                                  : (isDarkMode ? Colors.red.shade300 : Colors.red),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Kar Miktarı (KDV Öncesi):',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              '${_profitAmount.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _profitAmount >= 0 
                                  ? (isDarkMode ? Colors.green.shade300 : Colors.green) 
                                  : (isDarkMode ? Colors.red.shade300 : Colors.red),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Kardan KDV (Sadece kar üzerinden):',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              '${_taxAmount.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KDV Hariç Fiyat:',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              _priceController.text.isEmpty ? '0.00 TL' : '${double.parse(_priceController.text).toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'KDV Dahil Son Fiyat:',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              '${_finalPrice.toStringAsFixed(2)} TL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDarkMode ? AppTheme.primaryColor : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stockController,
                          decoration: InputDecoration(
                            labelText: 'Stok Miktarı *',
                            prefixIcon: Icon(Icons.inventory_outlined, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Lütfen stok miktarı girin';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          decoration: InputDecoration(
                            labelText: 'Birim',
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          dropdownColor: isDarkMode ? AppTheme.darkCardColor : Colors.white,
                          style: TextStyle(color: textColor),
                          items: _units.map((String unit) {
                            return DropdownMenuItem<String>(
                              value: unit,
                              child: Text(unit),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedUnit = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _criticalStockController,
                          decoration: InputDecoration(
                            labelText: 'Kritik Stok Seviyesi',
                            prefixIcon: Icon(Icons.warning_amber_outlined, color: iconColor),
                            border: const OutlineInputBorder(),
                            labelStyle: TextStyle(color: textColor),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _categoryController,
                    decoration: InputDecoration(
                      labelText: 'Kategori',
                      prefixIcon: Icon(Icons.category, color: iconColor),
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(color: textColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _brandController,
                    decoration: InputDecoration(
                      labelText: 'Marka',
                      prefixIcon: Icon(Icons.business_outlined, color: iconColor),
                      border: const OutlineInputBorder(),
                      labelStyle: TextStyle(color: textColor),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Açıklama',
                      prefixIcon: Icon(Icons.description_outlined, color: iconColor),
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      labelStyle: TextStyle(color: textColor),
                    ),
                    style: TextStyle(color: textColor),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Ürünü Kaydet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _priceController.removeListener(_calculateProfitAndTax);
    _purchasePriceController.removeListener(_calculateProfitAndTax);
    _taxController.removeListener(_calculateProfitAndTax);
    _discountController.removeListener(_calculateProfitAndTax);
    
    _barcodeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _purchasePriceController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    _stockController.dispose();
    _criticalStockController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  // Kategorileri yükleyen metot
  Future<void> _loadCategories() async {
    try {
      // Kategori verilerini basit bir şekilde ele alıyoruz
      // Gerçek uygulamada veritabanından yüklenebilir
    } catch (e) {
      debugPrint('Kategorileri yüklerken hata: $e');
    }
  }
  
  // Vergi oranlarını yükleyen metot
  Future<void> _loadTaxRates() async {
    try {
      // Varsayılan vergi oranını ayarla
      if (_taxController.text.isEmpty) {
        _taxController.text = '18.0'; // Varsayılan KDV oranı
      }
    } catch (e) {
      debugPrint('Vergi oranlarını yüklerken hata: $e');
    }
  }
  
  // Birimleri yükleyen metot
  Future<void> _loadUnits() async {
    try {
      // Birimler zaten sınıfta tanımlı
      if (_selectedUnit.isEmpty) {
        _selectedUnit = 'adet'; // Varsayılan birim
      }
    } catch (e) {
      debugPrint('Birimleri yüklerken hata: $e');
    }
  }
} 
