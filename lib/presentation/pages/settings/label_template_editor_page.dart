// lib/presentation/pages/settings/label_template_editor_page.dart
// Serenut OS — Etiket Tasarımı, Şablonlar & Donanım Ayarları (Canlı Önizlemeli)

import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/printing_providers.dart';

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
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadFromProfiles(
    PrintDesignProfile product,
    PrintDesignProfile order,
    PrinterDeviceProfile? device,
  ) {
    if (_initialized) return;
    _initialized = true;
    final p = product.definition;
    final o = order.definition;
    _productShowBusinessName = p['showBusinessName'] != false;
    _productShowBrand = p['showBrand'] != false;
    _productShowBarcode = p['showBarcode'] != false;
    _productShowPrice = p['showPrice'] != false;
    _productShowVat = p['showVat'] != false;
    _productFontSize = p['fontSize']?.toString() ?? 'Orta';
    _orderShowBusinessName = o['showBusinessName'] != false;
    _orderShowCustomerName = o['showCustomerName'] != false;
    _orderShowOrderNo = o['showOrderNo'] != false;
    _orderShowDate = o['showDate'] != false;
    _orderShowTotalAmount = o['showTotalAmount'] != false;
    _orderShowItemsCount = o['showItemsCount'] != false;
    _orderFontSize = o['fontSize']?.toString() ?? 'Orta';
    _labelWidthMm =
        (device?.capabilities['mediaWidthMm'] as num?)?.toInt() ?? 50;
    _labelHeightMm =
        (device?.capabilities['mediaHeightMm'] as num?)?.toInt() ?? 30;
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final repository = ref.read(printingRepositoryProvider);
      final product =
          (await repository.getDesignProfiles(PrintDocumentKind.productLabel))
              .firstWhere((profile) => profile.isDefault);
      final order =
          (await repository.getDesignProfiles(PrintDocumentKind.orderLabel))
              .firstWhere((profile) => profile.isDefault);
      final now = DateTime.now();
      await repository.saveDesignProfile(PrintDesignProfile(
        id: product.id,
        name: product.name,
        kind: product.kind,
        schemaVersion: product.schemaVersion,
        rendererVersion: product.rendererVersion,
        definition: {
          'showBusinessName': _productShowBusinessName,
          'showBrand': _productShowBrand,
          'showBarcode': _productShowBarcode,
          'showPrice': _productShowPrice,
          'showVat': _productShowVat,
          'fontSize': _productFontSize,
        },
        isDefault: true,
        createdAt: product.createdAt,
        updatedAt: now,
      ));
      await repository.saveDesignProfile(PrintDesignProfile(
        id: order.id,
        name: order.name,
        kind: order.kind,
        schemaVersion: order.schemaVersion,
        rendererVersion: order.rendererVersion,
        definition: {
          'showBusinessName': _orderShowBusinessName,
          'showCustomerName': _orderShowCustomerName,
          'showOrderNo': _orderShowOrderNo,
          'showDate': _orderShowDate,
          'showTotalAmount': _orderShowTotalAmount,
          'showItemsCount': _orderShowItemsCount,
          'fontSize': _orderFontSize,
        },
        isDefault: true,
        createdAt: order.createdAt,
        updatedAt: now,
      ));
      ref.invalidate(
          printDesignProfilesProvider(PrintDocumentKind.productLabel));
      ref.invalidate(printDesignProfilesProvider(PrintDocumentKind.orderLabel));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Etiket tasarımları başarıyla kaydedildi.'),
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider).value;
    final productProfiles =
        ref.watch(printDesignProfilesProvider(PrintDocumentKind.productLabel));
    final orderProfiles =
        ref.watch(printDesignProfilesProvider(PrintDocumentKind.orderLabel));
    final activeDevice =
        ref.watch(activePrinterDeviceProvider(PrintDocumentKind.productLabel));
    if (!_initialized &&
        productProfiles.hasValue &&
        orderProfiles.hasValue &&
        activeDevice.hasValue) {
      _loadFromProfiles(
        productProfiles.requireValue.firstWhere((item) => item.isDefault),
        orderProfiles.requireValue.firstWhere((item) => item.isDefault),
        activeDevice.value,
      );
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
            Tab(
                icon: Icon(Icons.receipt_long_rounded),
                text: 'Sipariş Etiketi'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProductLabelTab(settings),
          _buildOrderLabelTab(settings),
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

  // ── İşletme Bilgisi Banner ──────────────────────────────────────────────
  Widget _buildBusinessInfoBanner(Settings? settings) {
    final hasLogo = settings?.businessLogo != null &&
        settings!.businessLogo!.trim().isNotEmpty;

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
                    child: _logoImage(
                      settings.businessLogo!,
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
    final dimScale = math.min(_labelWidthMm / 50.0, _labelHeightMm / 30.0);
    final scale = (switch (_productFontSize) {
          'Küçük' => 0.85,
          'Büyük' => 1.15,
          _ => 1.0,
        }) *
        dimScale;

    final hasLogo = logoPath != null && logoPath.trim().isNotEmpty;
    final aspect = _labelWidthMm / _labelHeightMm;
    final previewWidth = 260.0;
    final previewHeight = (previewWidth / aspect).clamp(110.0, 340.0);

    return Center(
      child: Container(
        width: previewWidth,
        height: previewHeight,
        padding: EdgeInsets.all(12 * scale),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_productShowBusinessName) ...[
                  if (hasLogo)
                    _logoImage(
                      logoPath,
                      height: (24 * scale).clamp(10.0, 40.0),
                      fit: BoxFit.contain,
                    )
                  else
                    Text(
                      bizName.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: (10 * scale).clamp(8.0, 16.0),
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                        letterSpacing: 0.5,
                      ),
                    ),
                  const Divider(height: 8, thickness: 0.5),
                ],
                if (_productShowBrand)
                  Text(
                    'SERENUT ORGANİK',
                    style: GoogleFonts.inter(
                      fontSize: (10 * scale).clamp(7.0, 14.0),
                      color: Colors.grey[600],
                    ),
                  ),
                Text(
                  'Taze Çifte Kavrulmuş Fındık 500g',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: (13 * scale).clamp(9.0, 18.0),
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_productShowBarcode) ...[
                  Container(
                    height: (30 * scale).clamp(14.0, 44.0),
                    width: (160 * scale).clamp(80.0, 220.0),
                    color: Colors.grey[200],
                    child: Center(
                      child: Text(
                        '||||| ||||||| ||||||| |||||',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: (13 * scale).clamp(9.0, 18.0),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '8690000123456',
                    style: GoogleFonts.inter(
                      fontSize: (9 * scale).clamp(7.0, 12.0),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
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
                          fontSize: (20 * scale).clamp(12.0, 28.0),
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      if (_productShowVat) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(KDV Dahil)',
                          style: GoogleFonts.inter(
                            fontSize: (8 * scale).clamp(6.0, 12.0),
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderLabelPreview(String bizName, String? logoPath) {
    final dimScale = math.min(_labelWidthMm / 50.0, _labelHeightMm / 30.0);
    final scale = (switch (_orderFontSize) {
          'Küçük' => 0.85,
          'Büyük' => 1.15,
          _ => 1.0,
        }) *
        dimScale;

    final aspect = _labelWidthMm / _labelHeightMm;
    final previewWidth = 260.0;
    final previewHeight = (previewWidth / aspect).clamp(130.0, 380.0);

    return Center(
      child: Container(
        width: previewWidth,
        height: previewHeight,
        padding: EdgeInsets.all(12 * scale),
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
            // Sipariş etiketinde logo gösterilmez, sadece firma ismi metni
            if (_orderShowBusinessName) ...[
              Center(
                child: Text(
                  bizName.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: (11 * scale).clamp(8.0, 16.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Divider(height: 8, thickness: 0.5),
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
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Eski borç:',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    '₺150,00',
                    style: GoogleFonts.inter(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[700],
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
                'SİPARİŞ İÇERİĞİ (2 Çeşit):',
                style: GoogleFonts.inter(
                  fontSize: 10 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Taze Çifte Kavrulmuş Fındık 500g',
                    style: GoogleFonts.inter(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '  2x 200,00 TL',
                        style: GoogleFonts.inter(
                          fontSize: 10 * scale,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        '400,00 TL',
                        style: GoogleFonts.inter(
                          fontSize: 10 * scale,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Anamur Muz 1kg',
                    style: GoogleFonts.inter(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '  1x 20,00 TL',
                        style: GoogleFonts.inter(
                          fontSize: 10 * scale,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        '20,00 TL',
                        style: GoogleFonts.inter(
                          fontSize: 10 * scale,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            const Divider(height: 10, thickness: 0.5),
            if (_orderShowTotalAmount) ...[
              const SizedBox(height: 4),
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

  Widget _logoImage(
    String source, {
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    Widget fallback(BuildContext _, Object __, StackTrace? ___) =>
        const Icon(Icons.storefront_rounded, color: POSColors.green);
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0) {
        return const Icon(Icons.storefront_rounded, color: POSColors.green);
      }
      return Image.memory(
        base64Decode(source.substring(comma + 1)),
        height: height,
        fit: fit,
        errorBuilder: fallback,
      );
    }
    if (source.startsWith('https://') || source.startsWith('http://')) {
      return Image.network(
        source,
        height: height,
        fit: fit,
        errorBuilder: fallback,
      );
    }
    return Image.file(
      File(source),
      height: height,
      fit: fit,
      errorBuilder: fallback,
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
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
            const SizedBox(width: 16),
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
      ),
    );
  }
}
