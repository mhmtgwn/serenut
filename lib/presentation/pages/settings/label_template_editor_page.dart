// lib/presentation/pages/settings/label_template_editor_page.dart
// Serenut OS — Etiket Tasarımı, Şablonlar & Donanım Ayarları (Canlı Önizlemeli)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/service_providers.dart';

class LabelTemplateEditorPage extends ConsumerStatefulWidget {
  const LabelTemplateEditorPage({super.key});

  @override
  ConsumerState<LabelTemplateEditorPage> createState() =>
      _LabelTemplateEditorPageState();
}

class _LabelTemplateEditorPageState
    extends ConsumerState<LabelTemplateEditorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Logo Ayarı
  String? _businessLogoPath;

  // Ürün Etiketi Ayarları
  bool _productShowBusinessName = true;
  bool _productShowBrand = true;
  bool _productShowBarcode = true;
  bool _productShowPrice = true;
  bool _productShowVat = true;
  String _productFontSize = 'Orta'; // Küçük, Orta, Büyük

  // Sipariş Etiketi Ayarları
  bool _orderShowBusinessName = true;
  bool _orderShowCustomerName = true;
  bool _orderShowOrderNo = true;
  bool _orderShowDate = true;
  bool _orderShowTotalAmount = true;
  bool _orderShowItemsCount = true;
  String _orderFontSize = 'Orta';

  // Donanım & Fiziki Boyut Ayarları
  int _labelWidthMm = 50;
  int _labelHeightMm = 30;
  int _labelGapMm = 2;
  int _labelDpi = 203;
  String _labelPrinterLanguage = 'tspl';
  int _labelPrinterCopies = 1;

  bool _initialized = false;
  bool _isSaving = false;
  bool _isTestingPrinter = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadFromSettings(Settings settings) {
    if (_initialized) return;
    _initialized = true;

    _businessLogoPath = settings.businessLogo;

    _productShowBusinessName = settings.printLogo;
    _productShowBrand = settings.labelShowBrand;
    _productShowBarcode = settings.printBarcode;
    _productShowPrice = settings.printProductDetails;
    _productShowVat = settings.labelShowVat;
    _productFontSize = settings.labelFontSize;

    _orderShowBusinessName = settings.labelOrderShowBusinessName;
    _orderShowCustomerName = settings.labelOrderShowCustomerName;
    _orderShowOrderNo = settings.labelOrderShowOrderNo;
    _orderShowDate = settings.labelOrderShowDate;
    _orderShowTotalAmount = settings.labelOrderShowTotalAmount;
    _orderShowItemsCount = settings.labelOrderShowItemsCount;
    _orderFontSize = settings.labelOrderFontSize;

    _labelWidthMm = settings.labelWidthMm.clamp(20, 100);
    _labelHeightMm = settings.labelHeightMm.clamp(15, 100);
    _labelGapMm = settings.labelGapMm.clamp(0, 10);
    _labelDpi = settings.labelDpi;
    _labelPrinterLanguage = settings.labelPrinterLanguage;
    _labelPrinterCopies = settings.labelPrinterCopies.clamp(1, 20);
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
      );
      if (picked != null) {
        setState(() => _businessLogoPath = picked.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logo seçimi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _saveSettings() async {
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;

    setState(() => _isSaving = true);
    try {
      final updated = settings.copyWith(
        businessLogo: _businessLogoPath,
        printLogo: _productShowBusinessName,
        printBarcode: _productShowBarcode,
        printProductDetails: _productShowPrice,
        labelShowBrand: _productShowBrand,
        labelShowVat: _productShowVat,
        labelFontSize: _productFontSize,
        labelOrderShowBusinessName: _orderShowBusinessName,
        labelOrderShowCustomerName: _orderShowCustomerName,
        labelOrderShowOrderNo: _orderShowOrderNo,
        labelOrderShowDate: _orderShowDate,
        labelOrderShowTotalAmount: _orderShowTotalAmount,
        labelOrderShowItemsCount: _orderShowItemsCount,
        labelOrderFontSize: _orderFontSize,
        labelWidthMm: _labelWidthMm,
        labelHeightMm: _labelHeightMm,
        labelGapMm: _labelGapMm,
        labelDpi: _labelDpi,
        labelPrinterLanguage: _labelPrinterLanguage,
        labelPrinterCopies: _labelPrinterCopies,
      );
      await ref.read(settingsNotifierProvider.notifier).updateSettings(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Etiket tasarımı ve ayarları başarıyla kaydedildi.'),
            backgroundColor: POSColors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kaydetme hatası: $e'),
            backgroundColor: POSColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testLabelPrinter() async {
    final settings = ref.read(settingsNotifierProvider).value;
    if (settings == null) return;

    final candidate = settings.copyWith(
      businessLogo: _businessLogoPath,
      printLogo: _productShowBusinessName,
      printBarcode: _productShowBarcode,
      printProductDetails: _productShowPrice,
      labelShowBrand: _productShowBrand,
      labelShowVat: _productShowVat,
      labelFontSize: _productFontSize,
      labelWidthMm: _labelWidthMm,
      labelHeightMm: _labelHeightMm,
      labelGapMm: _labelGapMm,
      labelDpi: _labelDpi,
      labelPrinterLanguage: _labelPrinterLanguage,
      labelPrinterCopies: _labelPrinterCopies,
    );

    setState(() => _isTestingPrinter = true);
    try {
      await ref
          .read(printerServiceProvider)
          .testLabelPrinterConnection(candidate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Etiket yazıcısı testi başarılı! Çıktı gönderildi.'),
            backgroundColor: POSColors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Yazıcı testi başarısız: $e'),
            backgroundColor: POSColors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTestingPrinter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider).value;
    if (settings != null) {
      _loadFromSettings(settings);
    }

    return Scaffold(
      backgroundColor: POSColors.surface,
      appBar: AppBar(
        backgroundColor: POSColors.card,
        elevation: 0,
        title: Text(
          'Etiket Tasarımı',
          style: GoogleFonts.inter(
            color: POSColors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Kaydet'),
              style: FilledButton.styleFrom(
                backgroundColor: POSColors.green,
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: POSColors.green,
          unselectedLabelColor: POSColors.textSecondary,
          indicatorColor: POSColors.green,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2_rounded), text: 'Ürün Etiketi'),
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'Sipariş Etiketi'),
            Tab(icon: Icon(Icons.aspect_ratio_rounded), text: 'Boyut & Donanım'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductLabelTab(settings),
          _buildOrderLabelTab(settings),
          _buildHardwareTab(settings),
        ],
      ),
    );
  }

  // ── Ürün Etiketi Sekmesi ──────────────────────────────────────────────────
  Widget _buildProductLabelTab(Settings? settings) {
    final bizName = settings?.businessName.isNotEmpty == true
        ? settings!.businessName
        : 'SERENUT OS MARKET';

    final logoPath = settings?.businessLogo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Canlı Önizleme (${_labelWidthMm}x$_labelHeightMm mm)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
          const SizedBox(height: 10),
          _buildProductLabelPreview(bizName, logoPath),
          const SizedBox(height: 20),
          _buildBusinessInfoBanner(settings),
          const SizedBox(height: 16),
          Text(
            'Etiket İçerik Ayarları',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildToggleTile(
            title: 'Firma Adı / Logosu Göster',
            subtitle: 'Etiketin en üstünde firma logosunu veya adını basar',
            value: _productShowBusinessName,
            onChanged: (v) => setState(() => _productShowBusinessName = v),
          ),
          _buildToggleTile(
            title: 'Marka Göster',
            subtitle: 'Ürünün markasını adının üstünde basar',
            value: _productShowBrand,
            onChanged: (v) => setState(() => _productShowBrand = v),
          ),
          _buildToggleTile(
            title: 'Barkod Göster',
            subtitle: 'Çizgi barkod ve barkod numarasını basar',
            value: _productShowBarcode,
            onChanged: (v) => setState(() => _productShowBarcode = v),
          ),
          _buildToggleTile(
            title: 'Fiyat Göster',
            subtitle: 'Büyük punto ile ürün satış fiyatını basar',
            value: _productShowPrice,
            onChanged: (v) => setState(() => _productShowPrice = v),
          ),
          _buildToggleTile(
            title: 'KDV Bilgisi Göster',
            subtitle: 'Fiyatın yanında "KDV Dahil" metnini ekler',
            value: _productShowVat,
            onChanged: (v) => setState(() => _productShowVat = v),
          ),
          const SizedBox(height: 16),
          _buildFontSizeSelector(
            current: _productFontSize,
            onSelect: (v) => setState(() => _productFontSize = v),
          ),
        ],
      ),
    );
  }

  // ── Sipariş Etiketi Sekmesi ────────────────────────────────────────────────
  Widget _buildOrderLabelTab(Settings? settings) {
    final bizName = settings?.businessName.isNotEmpty == true
        ? settings!.businessName
        : 'SERENUT OS MARKET';
    final logoPath = settings?.businessLogo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Canlı Önizleme (${_labelWidthMm}x$_labelHeightMm mm)',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
          const SizedBox(height: 10),
          _buildOrderLabelPreview(bizName, logoPath),
          const SizedBox(height: 20),
          _buildBusinessInfoBanner(settings),
          const SizedBox(height: 16),
          Text(
            'Sipariş Etiketi Ayarları',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
          const SizedBox(height: 12),
          _buildToggleTile(
            title: 'Firma Adı Göster',
            subtitle: 'Sipariş etiketinin başında işletme adını yazar',
            value: _orderShowBusinessName,
            onChanged: (v) => setState(() => _orderShowBusinessName = v),
          ),
          _buildToggleTile(
            title: 'Müşteri Adı Göster',
            subtitle: 'Sipariş sahibinin ad soyadını basar',
            value: _orderShowCustomerName,
            onChanged: (v) => setState(() => _orderShowCustomerName = v),
          ),
          _buildToggleTile(
            title: 'Sipariş No / Kodu Göster',
            subtitle: 'Örn: #ORD-2026-0042',
            value: _orderShowOrderNo,
            onChanged: (v) => setState(() => _orderShowOrderNo = v),
          ),
          _buildToggleTile(
            title: 'Tarih & Saat Göster',
            subtitle: 'Sipariş alma tarih saatini basar',
            value: _orderShowDate,
            onChanged: (v) => setState(() => _orderShowDate = v),
          ),
          _buildToggleTile(
            title: 'Toplam Tutar Göster',
            subtitle: 'Sipariş toplam tutarını belirgin basar',
            value: _orderShowTotalAmount,
            onChanged: (v) => setState(() => _orderShowTotalAmount = v),
          ),
          _buildToggleTile(
            title: 'Ürün Adedi Göster',
            subtitle: 'Paketteki toplam parça sayısını basar',
            value: _orderShowItemsCount,
            onChanged: (v) => setState(() => _orderShowItemsCount = v),
          ),
          const SizedBox(height: 16),
          _buildFontSizeSelector(
            current: _orderFontSize,
            onSelect: (v) => setState(() => _orderFontSize = v),
          ),
        ],
      ),
    );
  }

  // ── Donanım & Fiziki Boyut Sekmesi ──────────────────────────────────────────
  Widget _buildHardwareTab(Settings? settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fiziki Etiket & Yazıcı Ayarları',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: POSColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: POSColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: POSColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Genişlik (mm): $_labelWidthMm mm',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    Slider(
                      value: _labelWidthMm.toDouble(),
                      min: 20,
                      max: 100,
                      divisions: 80,
                      activeColor: POSColors.green,
                      label: '$_labelWidthMm mm',
                      onChanged: (val) =>
                          setState(() => _labelWidthMm = val.round()),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Text('Yükseklik (mm): $_labelHeightMm mm',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    Slider(
                      value: _labelHeightMm.toDouble(),
                      min: 15,
                      max: 100,
                      divisions: 85,
                      activeColor: POSColors.green,
                      label: '$_labelHeightMm mm',
                      onChanged: (val) =>
                          setState(() => _labelHeightMm = val.round()),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Text('Boşluk (Gap): $_labelGapMm mm',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    Slider(
                      value: _labelGapMm.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      activeColor: POSColors.green,
                      label: '$_labelGapMm mm',
                      onChanged: (val) =>
                          setState(() => _labelGapMm = val.round()),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Text('Çözünürlük (DPI)',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 203, label: Text('203 DPI')),
                        ButtonSegment(value: 300, label: Text('300 DPI')),
                      ],
                      selected: {_labelDpi},
                      onSelectionChanged: (set) {
                        if (set.isNotEmpty) {
                          setState(() => _labelDpi = set.first);
                        }
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: POSColors.greenLight,
                        selectedForegroundColor: POSColors.greenDark,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Text('Yazıcı Dili',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'tspl', label: Text('TSPL')),
                        ButtonSegment(value: 'escpos', label: Text('ESC/POS')),
                      ],
                      selected: {_labelPrinterLanguage},
                      onSelectionChanged: (set) {
                        if (set.isNotEmpty) {
                          setState(() => _labelPrinterLanguage = set.first);
                        }
                      },
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: POSColors.greenLight,
                        selectedForegroundColor: POSColors.greenDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isTestingPrinter ? null : _testLabelPrinter,
              icon: _isTestingPrinter
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_rounded),
              label: const Text('Etiket Yazıcısını Test Et'),
              style: OutlinedButton.styleFrom(
                foregroundColor: POSColors.green,
                side: const BorderSide(color: POSColors.green),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── İşletme Bilgisi Banner ──────────────────────────────────────────────
  Widget _buildBusinessInfoBanner(Settings? settings) {
    final hasLogo = settings?.businessLogo != null &&
        settings!.businessLogo!.trim().isNotEmpty &&
        File(settings.businessLogo!).existsSync();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: POSColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: POSColors.border),
            ),
            child: hasLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.file(
                      File(settings.businessLogo!),
                      fit: BoxFit.contain,
                    ),
                  )
                : const Icon(
                    Icons.storefront_rounded,
                    color: POSColors.green,
                    size: 24,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İşletme Adı & Logosu',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: POSColors.text,
                  ),
                ),
                Text(
                  hasLogo
                      ? 'Etiket başlığında İşletme Bilgileri logosu kullanılır.'
                      : 'Logoyu değiştirmek için İşletme Bilgileri ekranını kullanabilirsiniz.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: POSColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Önizleme Widget'ları ──────────────────────────────────────────────────
  Widget _buildProductLabelPreview(String bizName, String? logoPath) {
    double scale = switch (_productFontSize) {
      'Küçük' => 0.85,
      'Büyük' => 1.15,
      _ => 1.0,
    };

    final hasLogo = logoPath != null &&
        logoPath.trim().isNotEmpty &&
        File(logoPath).existsSync();

    return Center(
      child: Container(
        width: 280,
        padding: EdgeInsets.all(14 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black38, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_productShowBusinessName) ...[
              if (hasLogo) ...[
                Image.file(
                  File(logoPath),
                  height: 24 * scale,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 2),
              ],
              Text(
                bizName.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                  letterSpacing: 0.5,
                ),
              ),
              const Divider(height: 10, thickness: 0.5),
            ],
            if (_productShowBrand)
              Text(
                'SERENUT ORGANİK',
                style: GoogleFonts.inter(
                  fontSize: 10 * scale,
                  color: Colors.grey[600],
                ),
              ),
            Text(
              'Taze Çifte Kavrulmuş Fındık 500g',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14 * scale,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            if (_productShowBarcode) ...[
              Container(
                height: 36 * scale,
                width: 180,
                color: Colors.grey[200],
                child: Center(
                  child: Text(
                    '||||| ||||||| ||||||| |||||',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '8690000123456',
                style: GoogleFonts.inter(
                  fontSize: 10 * scale,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (_productShowPrice)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '₺185,00',
                    style: GoogleFonts.inter(
                      fontSize: 22 * scale,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  if (_productShowVat) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(KDV Dahil)',
                      style: GoogleFonts.inter(
                        fontSize: 9 * scale,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderLabelPreview(String bizName, String? logoPath) {
    double scale = switch (_orderFontSize) {
      'Küçük' => 0.85,
      'Büyük' => 1.15,
      _ => 1.0,
    };

    final hasLogo = logoPath != null &&
        logoPath.trim().isNotEmpty &&
        File(logoPath).existsSync();

    return Center(
      child: Container(
        width: 280,
        padding: EdgeInsets.all(14 * scale),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black38, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_orderShowBusinessName) ...[
              Center(
                child: Column(
                  children: [
                    if (hasLogo) ...[
                      Image.file(
                        File(logoPath),
                        height: 24 * scale,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      bizName.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11 * scale,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 10, thickness: 0.5),
            ],
            if (_orderShowOrderNo)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SİPARİŞ NO:',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '#ORD-2026-0042',
                    style: GoogleFonts.inter(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            if (_orderShowCustomerName) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'MÜŞTERİ:',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    'Ahmet Yılmaz',
                    style: GoogleFonts.inter(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
            if (_orderShowDate) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TARİH:',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '31.07.2026 14:30',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 12, thickness: 0.5),
            if (_orderShowItemsCount) ...[
              Text(
                'ÜRÜN İÇERİĞİ (3 Parça):',
                style: GoogleFonts.inter(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '• 2x Taze Çifte Kavrulmuş Fındık 500g\n• 1x Anamur Muz 1kg',
                style: GoogleFonts.inter(
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (_orderShowTotalAmount) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOPLAM:',
                    style: GoogleFonts.inter(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '₺420,00',
                    style: GoogleFonts.inter(
                      fontSize: 16 * scale,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Yardımcı UI ───────────────────────────────────────────────────────────
  Widget _buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: POSColors.border),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: POSColors.text,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: POSColors.textSecondary,
          ),
        ),
        activeColor: POSColors.green,
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFontSizeSelector({
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          Text(
            'Yazı Boyutu',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: POSColors.text,
            ),
          ),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Küçük', label: Text('Küçük')),
              ButtonSegment(value: 'Orta', label: Text('Orta')),
              ButtonSegment(value: 'Büyük', label: Text('Büyük')),
            ],
            selected: {current},
            onSelectionChanged: (set) {
              if (set.isNotEmpty) onSelect(set.first);
            },
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: POSColors.greenLight,
              selectedForegroundColor: POSColors.greenDark,
            ),
          ),
        ],
      ),
    );
  }
}
