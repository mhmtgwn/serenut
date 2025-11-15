import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io';
import '../services/product_service.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';

class EditProductForm extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function onProductUpdated;

  const EditProductForm({
    super.key,
    required this.product,
    required this.onProductUpdated,
  });

  @override
  State<EditProductForm> createState() => _EditProductFormState();
}

class _EditProductFormState extends State<EditProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcodeController;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _taxController;
  late final TextEditingController _discountController;
  late final TextEditingController _stockController;
  late final TextEditingController _criticalStockController;
  late final TextEditingController _unitController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;
  late final TextEditingController _brandController;
  late String _selectedUnit;
  File? _imageFile;
  bool _isSaving = false;
  bool _isScanning = false;
  
  // Kar marjı ve vergi hesaplamaları için değişkenler
  double _profitMargin = 0.0;
  double _profitAmount = 0.0;
  double _finalPrice = 0.0;
  double _taxAmount = 0.0;
  bool productStatus = true;

  final List<String> _units = [
    'adet',
    'kg',
    'g',
    'lt',
    'ml',
    'm',
    'cm',
    'm²',
    'paket',
    'kutu',
    'düzine',
    'koli',
    'metre',
  ];

  @override
  void initState() {
    super.initState();
    
    _nameController = TextEditingController(text: widget.product['name'] ?? '');
    _descriptionController = TextEditingController(text: widget.product['description'] ?? '');
    _priceController = TextEditingController(text: (widget.product['price'] ?? 0.0).toString());
    _purchasePriceController = TextEditingController(text: (widget.product['purchasePrice'] ?? 0.0).toString());
    _stockController = TextEditingController(text: (widget.product['stock'] ?? 0.0).toString());
    _criticalStockController = TextEditingController(text: (widget.product['criticalStock'] ?? 0.0).toString());
    _barcodeController = TextEditingController(text: widget.product['barcode'] ?? '');
    _discountController = TextEditingController(text: (widget.product['discount'] ?? 0.0).toString());
    _taxController = TextEditingController(text: (widget.product['taxRate'] ?? 18.0).toString());
    _brandController = TextEditingController(text: widget.product['brand'] ?? '');
    _selectedUnit = widget.product['unit'] ?? 'adet';
    _categoryController = TextEditingController(text: widget.product['category'] ?? '');
    _unitController = TextEditingController(text: widget.product['unit'] ?? 'adet');

    if (widget.product['imagePath'] != null) {
      final imagePath = widget.product['imagePath'] as String;
      final file = File(imagePath);
      if (file.existsSync()) {
        _imageFile = file;
      }
    }
    
    _loadCategories();
    _loadTaxRates();
    _loadUnits();
    
    _priceController.addListener(_calculateProfitAndTax);
    _purchasePriceController.addListener(_calculateProfitAndTax);
    _taxController.addListener(_calculateProfitAndTax);
    _discountController.addListener(_calculateProfitAndTax);
    
    // İlk hesaplamayı yap
    _calculateProfitAndTax();
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
                  final XFile? imageFile = await picker.pickImage(source: ImageSource.camera);
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context, imageFile);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  final XFile? imageFile = await picker.pickImage(source: ImageSource.gallery);
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context, imageFile);
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

  void _showBarcodeScanner() {
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

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Hesaplamaları tekrar yap (son değerleri almak için)
      _calculateProfitAndTax();
      
      final updatedProduct = {
        'id': widget.product['id'],
        'name': _nameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'price': double.parse(_priceController.text),
        'purchasePrice': _purchasePriceController.text.isNotEmpty 
            ? double.parse(_purchasePriceController.text) 
            : 0.0,
        'tax': _taxController.text.isNotEmpty 
            ? double.parse(_taxController.text) 
            : 0.0,
        'discount': _discountController.text.isNotEmpty 
            ? double.parse(_discountController.text) 
            : 0.0,
        'stock': double.parse(_stockController.text),
        'criticalStock': _criticalStockController.text.isNotEmpty 
            ? double.parse(_criticalStockController.text) 
            : 0.0,
        'unit': _selectedUnit,
        'description': _descriptionController.text.trim(),
        'category': _categoryController.text.trim(),
        'brand': _brandController.text.trim(),
        'imagePath': _imageFile?.path,
        'profitMargin': _profitMargin,
        'finalPrice': _finalPrice,
        'status': productStatus,
      };
      
      await ProductService.instance.updateProduct(updatedProduct);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ürün başarıyla güncellendi'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Callback'i çağır
      widget.onProductUpdated();
      
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Ürün güncellenirken hata: $e');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Text('Ürün güncellenirken hata oluştu: ${e.toString()}'),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
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
          title: const Text('Barkod Tara'),
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
        title: const Text('Ürünü Düzenle'),
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
              onPressed: _updateProduct,
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
                        child: _imageFile != null || widget.product['imagePath'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _imageFile != null
                                    ? Image.file(
                                        _imageFile!,
                                        fit: BoxFit.cover,
                                      )
                                    : widget.product['imagePath'] != null
                                        ? Image.file(
                                            File(widget.product['imagePath']),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
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
                          style: TextStyle(color: textColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor),
                        onPressed: _showBarcodeScanner,
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
                    style: TextStyle(color: textColor),
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
                          decoration: const InputDecoration(
                            labelText: 'Satış Fiyatı (KDV Dahil) *',
                            prefixIcon: Icon(Icons.attach_money),
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'KDV (%)',
                            prefixIcon: Icon(Icons.receipt_long_outlined),
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'Alış Fiyatı',
                            prefixIcon: Icon(Icons.shopping_cart_outlined),
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'İndirim (%)',
                            prefixIcon: Icon(Icons.discount_outlined),
                            border: OutlineInputBorder(),
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
                          decoration: const InputDecoration(
                            labelText: 'Stock *',
                            prefixIcon: Icon(Icons.warehouse_outlined),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter stock amount';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Please enter a valid number';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _criticalStockController,
                          decoration: const InputDecoration(
                            labelText: 'Critical Stock *',
                            prefixIcon: Icon(Icons.warning_amber_outlined),
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter critical stock amount';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Please enter a valid number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'Birim',
                            border: OutlineInputBorder(),
                          ),
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
                                _unitController.text = newValue;
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
                          controller: _categoryController,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.category),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _brandController,
                          decoration: const InputDecoration(
                            labelText: 'Brand',
                            prefixIcon: Icon(Icons.branding_watermark),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _updateProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Değişiklikleri Kaydet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<bool>(
                    title: const Text('Aktif'),
                    value: true,
                    groupValue: productStatus,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          productStatus = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.removeListener(_calculateProfitAndTax);
    _purchasePriceController.removeListener(_calculateProfitAndTax);
    _taxController.removeListener(_calculateProfitAndTax);
    _discountController.removeListener(_calculateProfitAndTax);
    _priceController.dispose();
    _purchasePriceController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    _stockController.dispose();
    _criticalStockController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      // Kategori verilerini ürün servisinden alma (basitleştirilmiş)
      // Not: ProductService'de getCategories metodu olmadığı için basit bir yaklaşım kullanıyoruz
      
      if (mounted) {
        setState(() {
          // Eğer kategori controller boşsa ve widget.product'ta kategori varsa doldur
          if (_categoryController.text.isEmpty && widget.product['category'] != null) {
            _categoryController.text = widget.product['category'];
          }
        });
      }
    } catch (e) {
      debugPrint('Kategorileri yüklerken hata: $e');
    }
  }
  
  Future<void> _loadTaxRates() async {
    try {
      // Vergi oranları zaten varsayılan değerler olarak tanımlı
      
      // Vergi oranı controller'ı boşsa ve widget.product'ta vergi oranı varsa doldur
      if (_taxController.text.isEmpty && widget.product['taxRate'] != null) {
        setState(() {
          _taxController.text = widget.product['taxRate'].toString();
        });
      }
    } catch (e) {
      debugPrint('Vergi oranlarını yüklerken hata: $e');
    }
  }
  
  Future<void> _loadUnits() async {
    try {
      // Birimler zaten sınıf değişkeni olarak tanımlandı (_units)
      // Birim kontrolcüsü boşsa ve widget.product'ta birim varsa doldur
      if (_unitController.text.isEmpty && widget.product['unit'] != null) {
        setState(() {
          _unitController.text = widget.product['unit'];
          _selectedUnit = widget.product['unit'];
        });
      }
    } catch (e) {
      debugPrint('Birimleri yüklerken hata: $e');
    }
  }
} 
