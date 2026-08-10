// lib/presentation/pages/product_form_page.dart
// Serenut OS — Ürün Ekleme / Düzenleme (Tam Ekran, Çok Bölümlü Form)
// UX Redesign v3: Full-screen form, Shopify admin style, no dialogs

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/presentation/widgets/product_image.dart';
import 'package:serenutos/presentation/widgets/sales/barcode_scanner_dialog.dart';
import 'package:serenutos/presentation/pages/settings/catalog_settings_page.dart';

const _kGreen = POSColors.green;
const _kGreenDark = POSColors.greenDark;
const _kAmber = POSColors.amber;
const _kRed = POSColors.red;
const _kSurface = POSColors.surface;
const _kText = POSColors.text;
const _kTextSecondary = POSColors.textSecondary;
const _kBorder = POSColors.border;

class ProductFormPage extends ConsumerStatefulWidget {
  final bool isEditing;
  final ProductEntity? existingProduct;

  const ProductFormPage({
    super.key,
    required this.isEditing,
    this.existingProduct,
  });

  @override
  ConsumerState<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends ConsumerState<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _minStockCtrl;
  late final TextEditingController _vatCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _shelfCodeCtrl;
  String _unit = 'adet';
  String? _imageUrl;

  String? _selectedCategory;
  bool _isSaving = false;
  late String _saleType;
  late final TextEditingController _minimumWeightCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.price.toStringAsFixed(2) : '');
    _purchasePriceCtrl = TextEditingController(
        text: p != null && p.purchasePrice > 0
            ? p.purchasePrice.toStringAsFixed(2)
            : '');
    _qtyCtrl =
        TextEditingController(text: p != null ? p.quantity.toString() : '');
    _minStockCtrl = TextEditingController(text: p?.minStock.toString() ?? '5');
    _vatCtrl = TextEditingController(text: p?.vat?.toString() ?? '18');
    final barcodeText = p != null
        ? (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                .hasMatch(p.id)
            ? ''
            : p.id)
        : '';
    _barcodeCtrl = TextEditingController(text: barcodeText);
    _brandCtrl = TextEditingController(text: p?.brand ?? '');
    _shelfCodeCtrl = TextEditingController(text: p?.shelfCode ?? '');
    _unit = p?.unit ?? (p?.isWeighed == true ? 'kg' : 'adet');
    _saleType = p?.saleType ?? 'piece';
    _minimumWeightCtrl =
        TextEditingController(text: (p?.minimumWeightGrams ?? 20).toString());
    _selectedCategory = p?.category;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _qtyCtrl.dispose();
    _minStockCtrl.dispose();
    _vatCtrl.dispose();
    _barcodeCtrl.dispose();
    _brandCtrl.dispose();
    _shelfCodeCtrl.dispose();
    _minimumWeightCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen bir kategori seçiniz.'),
          backgroundColor: _kRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final oldId = widget.isEditing ? widget.existingProduct!.id : null;
      final id = widget.isEditing
          ? (_barcodeCtrl.text.trim().isNotEmpty
              ? _barcodeCtrl.text.trim()
              : widget.existingProduct!.id)
          : (_barcodeCtrl.text.trim().isNotEmpty
              ? _barcodeCtrl.text.trim()
              : const Uuid().v4());

      final product = ProductEntity(
        id: id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        price: double.parse(_priceCtrl.text.trim().replaceAll(',', '.')),
        purchasePrice: double.tryParse(
                _purchasePriceCtrl.text.trim().replaceAll(',', '.')) ??
            0,
        quantity: int.parse(_qtyCtrl.text.trim()),
        minStock: int.tryParse(_minStockCtrl.text.trim()) ?? 5,
        brand: _brandCtrl.text.trim(),
        unit: _saleType == 'weighed' ? 'kg' : _unit,
        shelfCode: _shelfCodeCtrl.text.trim(),
        category: _selectedCategory!,
        vat: int.tryParse(_vatCtrl.text.trim()) ?? 18,
        saleType: _saleType,
        minimumWeightGrams: int.tryParse(_minimumWeightCtrl.text.trim()) ?? 20,
        imageUrl: _imageUrl,
      );
      final notifier = ref.read(productsControllerProvider.notifier);
      if (widget.isEditing) {
        await notifier.updateProduct(product, oldId: oldId);
      } else {
        await notifier.addProduct(product);
      }

      // Auto-sync category VAT mapping to Settings
      try {
        final settings = ref.read(settingsNotifierProvider).value;
        if (settings != null) {
          List<Map<String, dynamic>> vatList = [];
          if (settings.vatCategories.isNotEmpty) {
            final decoded = jsonDecode(settings.vatCategories);
            if (decoded is List) {
              vatList = decoded
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
          }

          final categoryName = _selectedCategory!.trim();
          final currentVat = product.vat;

          final index = vatList.indexWhere((e) =>
              e['name']?.toString().toLowerCase().trim() ==
              categoryName.toLowerCase());
          bool needUpdate = false;
          if (index == -1) {
            vatList.add({'name': categoryName, 'rate': currentVat});
            needUpdate = true;
          } else if (vatList[index]['rate'] != currentVat) {
            vatList[index]['rate'] = currentVat;
            needUpdate = true;
          }

          if (needUpdate) {
            final updatedSettings = settings.copyWith(
              vatCategories: jsonEncode(vatList),
            );
            await ref
                .read(settingsNotifierProvider.notifier)
                .updateSettings(updatedSettings);
          }
        }
      } catch (_) {
        // Silent catch: do not block product save if settings sync fails
      }

      ref.invalidate(dashboardProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing
                ? '${product.name} güncellendi.'
                : '${product.name} eklendi.'),
            backgroundColor: _kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Bir hata oluştu: $e'),
              backgroundColor: _kRed,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsyncValue = ref.watch(settingsNotifierProvider);
    final settings = settingsAsyncValue.value;
    final List<Map<String, dynamic>> parsedVatCategories = [];
    if (settings != null) {
      try {
        final decoded = jsonDecode(settings.vatCategories);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              parsedVatCategories.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {}
    }

    final allCategories = ref.watch(categoryPoolProvider);

    return Scaffold(
      backgroundColor: _kSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: _kText),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.isEditing ? 'Ürün Düzenle' : 'Yeni Ürün',
          style: const TextStyle(
              fontWeight: FontWeight.bold, color: _kText, fontSize: 17),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const Center(
                    child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(_kGreen)),
                  ))
                : TextButton(
                    onPressed: _save,
                    style: TextButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: Text(widget.isEditing ? 'Kaydet' : 'Ekle',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection(children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ProductImage(
                      imageUrl: _imageUrl,
                      barcode: _barcodeCtrl.text.trim(),
                      size: 82,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _chooseProductImageSource,
                          icon: const Icon(Icons.add_a_photo_rounded),
                          label: Text(_imageUrl == null
                              ? 'Ürün fotoğrafı ekle'
                              : 'Fotoğrafı değiştir'),
                        ),
                        if (_imageUrl != null)
                          TextButton(
                            onPressed: () => setState(() => _imageUrl = null),
                            child: const Text('Fotoğrafı kaldır'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),
            // ── Bölüm 1: Temel Bilgiler ────────────────────────────────────
            _buildSectionHeader(
                icon: Icons.inventory_2_rounded,
                label: 'Ürün Bilgileri',
                color: _kGreen),
            const SizedBox(height: 10),
            _buildSection(children: [
              _buildField(
                controller: _nameCtrl,
                label: 'Ürün Adı *',
                icon: Icons.shopping_bag_rounded,
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Lütfen ürün adı giriniz.'
                    : null,
              ),

              const SizedBox(height: 12),
              // ── Kategori ───────────────────────────────────────────────────
              _buildCategoryField(allCategories, parsedVatCategories),
            ]),
            const SizedBox(height: 16),

            // ── Bölüm 2: Fiyat & Stok ─────────────────────────────────────
            _buildSectionHeader(
                icon: Icons.attach_money_rounded,
                label: 'Fiyat & Stok',
                color: _kGreenDark),
            const SizedBox(height: 10),
            _buildSection(children: [
              DropdownButtonFormField<String>(
                value: _saleType,
                decoration: InputDecoration(
                  labelText: 'Satış Şekli',
                  prefixIcon: Icon(
                    _saleType == 'weighed'
                        ? Icons.monitor_weight_rounded
                        : Icons.numbers_rounded,
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'piece', child: Text('Adet')),
                  DropdownMenuItem(value: 'weighed', child: Text('Ağırlık')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _saleType = value);
                },
              ),
              if (_saleType == 'weighed') ...[
                const SizedBox(height: 12),
                _buildField(
                  controller: _minimumWeightCtrl,
                  label: 'Minimum Tartım (gram)',
                  icon: Icons.scale_rounded,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (_saleType != 'weighed') return null;
                    final grams = int.tryParse(value?.trim() ?? '');
                    if (grams == null || grams <= 0) {
                      return 'Geçerli bir minimum gram değeri giriniz.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Satış fiyatı kilogram fiyatı olarak kullanılır.',
                  style: TextStyle(fontSize: 12, color: _kTextSecondary),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _priceCtrl,
                      label: 'Satış Fiyatı *',
                      icon: Icons.sell_rounded,
                      prefix: '₺',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]'))
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Lütfen bir satış fiyatı giriniz.';
                        }
                        if (double.tryParse(v.trim().replaceAll(',', '.')) ==
                            null) {
                          return 'Lütfen geçerli bir satış fiyatı giriniz.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _purchasePriceCtrl,
                      label: 'Alış Fiyatı',
                      icon: Icons.store_rounded,
                      prefix: '₺',
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]'))
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _qtyCtrl,
                      label: 'Stok Miktarı *',
                      icon: Icons.inventory_rounded,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Lütfen stok miktarı giriniz.';
                        }
                        if (int.tryParse(v.trim()) == null) {
                          return 'Lütfen geçerli bir tam sayı giriniz.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _minStockCtrl,
                      label: 'Min. Stok Uyarısı',
                      icon: Icons.warning_amber_rounded,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),

            // ── Bölüm 3: Vergi & Barkod ────────────────────────────────────
            _buildSectionHeader(
                icon: Icons.receipt_long_rounded,
                label: 'Vergi & Barkod',
                color: _kAmber),
            const SizedBox(height: 10),
            _buildSection(children: [
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _vatCtrl,
                      label: 'KDV Oranı (%) *',
                      icon: Icons.percent_rounded,
                      prefix: '%',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Lütfen KDV oranı giriniz.';
                        }
                        if (int.tryParse(v.trim()) == null) {
                          return 'Lütfen geçerli bir tam sayı giriniz.';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Barkod',
                        suffixIcon: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: IconButton(
                            tooltip: 'Kamerayla barkod okut',
                            onPressed: _scanBarcode,
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                color: _kGreen),
                          ),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 28),

            // ── Kaydet Butonu ─────────────────────────────────────────────
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(widget.isEditing
                        ? Icons.save_rounded
                        : Icons.add_box_rounded),
                label: Text(
                  widget.isEditing ? 'Değişiklikleri Kaydet' : 'Ürün Ekle',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProductImage(
      [ImageSource source = ImageSource.gallery]) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final documents = await getApplicationDocumentsDirectory();
    final images = Directory(path.join(documents.path, 'product_images'));
    await images.create(recursive: true);
    final extension = path.extension(picked.path).isEmpty
        ? '.jpg'
        : path.extension(picked.path);
    final target = path.join(
      images.path,
      '${widget.existingProduct?.id ?? const Uuid().v4()}$extension',
    );
    await File(picked.path).copy(target);
    ProductImage.clearCache();
    if (mounted) setState(() => _imageUrl = target);
  }

  Future<void> _chooseProductImageSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (Platform.isAndroid || Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Kamerayla çek'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galeriden veya dosyadan seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickProductImage(source);
  }

  Future<void> _scanBarcode() async {
    await BarcodeScannerDialog.show(
      context,
      onBarcodeScanned: (barcode) {
        if (mounted) setState(() => _barcodeCtrl.text = barcode.trim());
      },
    );
  }

  // ── Yardımcı Widget'lar ────────────────────────────────────────────────────

  Widget _buildSectionHeader(
      {required IconData icon, required String label, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  Widget _buildSection({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildCategoryField(List<String> allCategories,
      List<Map<String, dynamic>> parsedVatCategories) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: allCategories.contains(_selectedCategory)
              ? _selectedCategory
              : null,
          hint: const Text('Kategori Seç *',
              style: TextStyle(color: _kTextSecondary)),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.category_rounded,
                size: 20, color: _kTextSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _kGreen, width: 2),
            ),
            filled: true,
            fillColor: _kSurface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          items: [
            ...allCategories.map((cat) => DropdownMenuItem(
                  value: cat,
                  child: Text(cat),
                )),
            const DropdownMenuItem(
              value: '__new__',
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 16, color: _kGreen),
                  SizedBox(width: 6),
                  Text('+ Yeni Kategori',
                      style: TextStyle(
                          color: _kGreen, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
          onChanged: (val) async {
            if (val == '__new__') {
              final newCat = await _showNewCategorySheet();
              if (newCat != null && newCat.isNotEmpty) {
                final canonical = _canonicalName(newCat);
                final vatText = _vatCtrl.text.trim();
                final rate = vatText.isEmpty ? null : int.tryParse(vatText);
                await _addNewCategoryToSettings(canonical, rate: rate);
                setState(() {
                  _selectedCategory = canonical;
                });
              }
            } else {
              setState(() {
                _selectedCategory = val;
                if (val != null) {
                  final match = parsedVatCategories.firstWhere(
                    (item) =>
                        item['name']?.toString().toLowerCase() ==
                        val.toLowerCase(),
                    orElse: () => <String, dynamic>{},
                  );
                  if (match.isNotEmpty && match['rate'] != null) {
                    _vatCtrl.text = match['rate'].toString();
                  }
                }
              });
            }
          },
          validator: (_) =>
              _selectedCategory == null ? 'Lütfen bir kategori seçiniz.' : null,
        ),
      ],
    );
  }

  static String _canonicalName(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  Future<void> _addNewCategoryToSettings(String categoryName, {int? rate}) async {
    try {
      final settings = ref.read(settingsNotifierProvider).value;
      if (settings != null) {
        List<Map<String, dynamic>> vatList = [];
        if (settings.vatCategories.isNotEmpty) {
          final decoded = jsonDecode(settings.vatCategories);
          if (decoded is List) {
            vatList = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        }

        final index = vatList.indexWhere((e) =>
            e['name']?.toString().toLowerCase().trim() ==
            categoryName.toLowerCase());
        if (index == -1) {
          vatList.add({'name': categoryName, 'rate': rate});
          await ref.read(settingsNotifierProvider.notifier).updateSettings(
                settings.copyWith(vatCategories: jsonEncode(vatList)),
              );
        }
      }
    } catch (_) {}
    ref.invalidate(productCategoriesProvider);
    ref.invalidate(productCategoriesStateProvider);
  }

  Future<String?> _showNewCategorySheet() async {
    final nameCtrl = TextEditingController();
    final vatCtrl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Yeni Kategori',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17, color: _kText)),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  tooltip: 'Tüm kategorileri yönet',
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const CatalogSettingsPage()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Kategori adı *',
                hintText: 'Örn: İçecekler',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kGreen, width: 2)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vatCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Varsayılan KDV (%) (İsteğe bağlı)',
                hintText: 'Örn: 20',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kGreen, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final catName = nameCtrl.text.trim();
                  if (catName.isEmpty) return;
                  final vatText = vatCtrl.text.trim();
                  final rate = vatText.isEmpty ? null : int.tryParse(vatText);
                  if (vatText.isNotEmpty && (rate == null || rate < 0 || rate > 100)) {
                    return;
                  }
                  if (rate != null) {
                    _vatCtrl.text = rate.toString();
                  }
                  Navigator.pop(ctx, catName);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Kategori Ekle',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefix,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: _kTextSecondary),
        prefixText: prefix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kRed),
        ),
        filled: true,
        fillColor: _kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
