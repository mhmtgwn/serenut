// lib/presentation/pages/product_form_page.dart
// Serenut OS — Ürün Ekleme / Düzenleme (Tam Ekran, Çok Bölümlü Form)
// UX Redesign v3: Full-screen form, Shopify admin style, no dialogs

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/controllers/products_controller.dart';
import 'package:serenutos/presentation/controllers/dashboard_controller.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:uuid/uuid.dart';

const _kGreen = Color(0xFF16A34A);
const _kGreenDark = Color(0xFF15803D);
const _kAmber = Color(0xFFEAB308);
const _kRed = Color(0xFFDC2626);
const _kSurface = Color(0xFFF8FAFC);
const _kText = Color(0xFF0F172A);
const _kTextSecondary = Color(0xFF64748B);
const _kBorder = Color(0xFFE2E8F0);

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
  late final TextEditingController _supplierCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _notesCtrl;

  String? _selectedCategory;
  bool _isSaving = false;
  bool _showOptional = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.price.toStringAsFixed(2) : '');
    _purchasePriceCtrl = TextEditingController(text: '');
    _qtyCtrl =
        TextEditingController(text: p != null ? p.quantity.toString() : '');
    _minStockCtrl = TextEditingController(text: '');
    _vatCtrl = TextEditingController(text: p?.vat?.toString() ?? '18');
    final barcodeText = p != null
        ? (RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
                .hasMatch(p.id)
            ? ''
            : p.id)
        : '';
    _barcodeCtrl = TextEditingController(text: barcodeText);
    _supplierCtrl = TextEditingController(text: '');
    _unitCtrl = TextEditingController(text: 'Adet');
    _notesCtrl = TextEditingController(text: '');
    _selectedCategory = p?.category;
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
    _supplierCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
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
        quantity: int.parse(_qtyCtrl.text.trim()),
        category: _selectedCategory!,
        vat: int.tryParse(_vatCtrl.text.trim()) ?? 18,
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
              _buildField(
                controller: _descCtrl,
                label: 'Açıklama',
                icon: Icons.description_rounded,
                maxLines: 2,
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
                        if (v == null || v.trim().isEmpty)
                          return 'Lütfen bir satış fiyatı giriniz.';
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
                        if (v == null || v.trim().isEmpty)
                          return 'Lütfen stok miktarı giriniz.';
                        if (int.tryParse(v.trim()) == null)
                          return 'Lütfen geçerli bir tam sayı giriniz.';
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
                        if (v == null || v.trim().isEmpty)
                          return 'Lütfen KDV oranı giriniz.';
                        if (int.tryParse(v.trim()) == null)
                          return 'Lütfen geçerli bir tam sayı giriniz.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _barcodeCtrl,
                      label: 'Barkod',
                      icon: Icons.qr_code_rounded,
                      keyboardType: TextInputType.text,
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 16),

            // ── Bölüm 4: Opsiyonel Alanlar ────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _showOptional = !_showOptional),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded,
                        size: 16, color: _kTextSecondary),
                    const SizedBox(width: 8),
                    const Text(
                      'Gelişmiş Seçenekler',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _kTextSecondary),
                    ),
                    const Spacer(),
                    Icon(
                      _showOptional
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: _kTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_showOptional) ...[
              const SizedBox(height: 10),
              _buildSection(children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildField(
                        controller: _supplierCtrl,
                        label: 'Tedarikçi',
                        icon: Icons.local_shipping_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        controller: _unitCtrl,
                        label: 'Birim (Adet/Kg/Lt)',
                        icon: Icons.straighten_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _notesCtrl,
                  label: 'Notlar',
                  icon: Icons.sticky_note_2_rounded,
                  maxLines: 2,
                ),
              ]),
            ],
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
                setState(() {
                  _selectedCategory = newCat;
                  final match = parsedVatCategories.firstWhere(
                    (item) =>
                        item['name']?.toString().toLowerCase() ==
                        newCat.toLowerCase(),
                    orElse: () => <String, dynamic>{},
                  );
                  if (match.isNotEmpty && match['rate'] != null) {
                    _vatCtrl.text = match['rate'].toString();
                  }
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

  Future<String?> _showNewCategorySheet() async {
    final ctrl = TextEditingController();
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
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Yeni Kategori',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: _kText)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Kategori adı',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _kGreen, width: 2)),
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Ekle',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
