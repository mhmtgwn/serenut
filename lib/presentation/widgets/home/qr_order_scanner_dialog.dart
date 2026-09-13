// lib/presentation/widgets/home/qr_order_scanner_dialog.dart
// Serenut OS — Hızlı QR & Barkod Operasyon Merkezi
// Desteklenen: Kamera (Mobil & PC Webcam), El tipi USB/HID Barkod Okuyucu, Klavye Girişi

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:serenutos/config/theme.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/presentation/pages/order_details_page.dart';
import 'package:serenutos/presentation/pages/sale_details_page.dart';
import 'package:serenutos/presentation/pages/sales_page.dart';
import 'package:serenutos/providers/repository_providers.dart';

class QrOrderScannerDialog extends ConsumerStatefulWidget {
  const QrOrderScannerDialog({super.key});

  /// Diyaloğu açar
  static Future<void> show(BuildContext context) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QR & Barkod Tara',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      pageBuilder: (context, _, __) => const QrOrderScannerDialog(),
    );
  }

  @override
  ConsumerState<QrOrderScannerDialog> createState() =>
      _QrOrderScannerDialogState();
}

class _QrOrderScannerDialogState extends ConsumerState<QrOrderScannerDialog> {
  late final MobileScannerController _scannerController;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _isCameraSupported = true;
  bool _isCameraActive = true;
  bool _isTorchOn = false;
  bool _isResolving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Masaüstünde varsayılan kamera olmayabilir veya kullanıcı USB okuyucu kullanabilir
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      _isCameraSupported = true; // Web cam varsa açılır, yoksa hata vermez
    }
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    // Otomatik odaklan (PC barkod okuyucu klavye gibi hemen buraya yazar)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _toggleTorch() {
    setState(() => _isTorchOn = !_isTorchOn);
    _scannerController.toggleTorch();
  }

  void _toggleCamera() {
    setState(() {
      _isCameraActive = !_isCameraActive;
      if (_isCameraActive) {
        _scannerController.start();
      } else {
        _scannerController.stop();
      }
    });
  }

  Future<void> _handleBarcodeDetected(String rawCode) async {
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty || _isResolving) return;

    // Haptic feedback (titreşim)
    HapticFeedback.mediumImpact();

    await _resolveAndNavigate(cleanCode);
  }

  Future<void> _resolveAndNavigate(String query) async {
    setState(() {
      _isResolving = true;
      _errorMessage = null;
    });

    try {
      String clean = query.trim();

      // ── 1. Fiş QR Formatı Kontrolü (order|<id> veya sale|<id>|<total>) ──
      if (clean.startsWith('order|')) {
        final parts = clean.split('|');
        if (parts.length >= 2) {
          final orderId = parts[1].trim();
          final order = await _findOrderById(orderId);
          if (order != null) {
            _openOrder(order.id);
            return;
          }
        }
      } else if (clean.startsWith('sale|')) {
        final parts = clean.split('|');
        if (parts.length >= 2) {
          final saleId = parts[1].trim();
          final sale = await _findSaleById(saleId);
          if (sale != null) {
            _openSale(sale.id);
            return;
          }
        }
      }

      // ── 2. Doğrudan Sipariş Arama (ID veya Sipariş No / Prefix) ──
      final order = await _findOrderByIdOrQuery(clean);
      if (order != null) {
        _openOrder(order.id);
        return;
      }

      // ── 3. Doğrudan Satış Arama (ID veya Fiş No) ──
      final sale = await _findSaleById(clean);
      if (sale != null) {
        _openSale(sale.id);
        return;
      }

      // ── 4. Ürün Barkodu Kontrolü (Satış ekranına yönlendirme) ──
      final productRepo = await ref.read(productRepositoryProvider.future);
      final products = await productRepo.findFiltered(searchQuery: clean, limit: 1);
      if (products.isNotEmpty) {
        final product = products.first;
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Ürün bulundu: ${product.name} (${product.price.toStringAsFixed(2)} ₺)',
            ),
            action: SnackBarAction(
              label: 'Satışa Git',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesPage()),
                );
              },
            ),
          ),
        );
        return;
      }

      // Bulunamadı uyarısı
      if (mounted) {
        setState(() {
          _errorMessage = '"$clean" koduna ait sipariş veya satış bulunamadı.';
          _isResolving = false;
        });
        _inputFocusNode.requestFocus();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Arama sırasında hata oluştu: $e';
          _isResolving = false;
        });
        _inputFocusNode.requestFocus();
      }
    }
  }

  Future<OrderEntity?> _findOrderById(String id) async {
    try {
      final orderRepo = await ref.read(orderRepositoryProvider.future);
      return await orderRepo.findById(id);
    } catch (_) {
      return null;
    }
  }

  Future<OrderEntity?> _findOrderByIdOrQuery(String query) async {
    try {
      final orderRepo = await ref.read(orderRepositoryProvider.future);
      // 1. Doğrudan ID ile ara
      final direct = await orderRepo.findById(query);
      if (direct != null) return direct;

      // 2. Filtreli ara (Sipariş no veya ID kısmi eşleşmesi)
      final filtered = await orderRepo.findFiltered(searchQuery: query, limit: 1);
      if (filtered.isNotEmpty) return filtered.first;
    } catch (_) {}
    return null;
  }

  Future<SaleEntity?> _findSaleById(String id) async {
    try {
      final saleRepo = await ref.read(saleRepositoryProvider.future);
      return await saleRepo.findById(id);
    } catch (_) {
      return null;
    }
  }

  void _openOrder(String orderId) {
    if (!mounted) return;
    Navigator.pop(context); // Scanner dialog'u kapat
    // Sipariş detayını aç (Doğrudan durum değiştirme ve teslimat sayfası)
    OrderDetailsPage.show(context, orderId: orderId);
  }

  void _openSale(String saleId) {
    if (!mounted) return;
    Navigator.pop(context); // Scanner dialog'u kapat
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleDetailsPage(saleId: saleId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 720;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: isDesktop ? 540 : size.width * 0.92,
          constraints: BoxConstraints(maxHeight: isDesktop ? 680 : size.height * 0.88),
          decoration: BoxDecoration(
            color: POSColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: POSColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Başlık Barı ──
              _buildHeader(context),

              // ── 2. Kamera / Vizör Alanı ──
              if (_isCameraActive && _isCameraSupported)
                _buildCameraSection(isDesktop)
              else
                _buildCameraOffPlaceholder(isDesktop),

              // ── 3. Manuel Giriş / PC Barkod Okuyucu Girişi ──
              _buildManualInputSection(context),

              // ── 4. Bilgi ve Hızlı İpuçları ──
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: POSColors.surface,
        border: Border(bottom: BorderSide(color: POSColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: POSColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.qr_code_scanner_rounded,
              color: POSColors.greenDark,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sipariş & Satış QR Okuyucu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: POSColors.text,
                  ),
                ),
                Text(
                  'Fiş QR kodunu veya barkodunu okutun',
                  style: TextStyle(
                    fontSize: 12,
                    color: POSColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kapat',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: POSColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSection(bool isDesktop) {
    final cameraHeight = isDesktop ? 260.0 : 220.0;

    return Container(
      height: cameraHeight,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Canlı Kamera Akışı
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (capture.barcodes.isNotEmpty) {
                final code = capture.barcodes.first.rawValue;
                if (code != null && code.isNotEmpty) {
                  _handleBarcodeDetected(code);
                }
              }
            },
          ),

          // Vizör Çerçevesi (Hedefleme Karesi)
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: POSColors.green, width: 2.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 140,
                    height: 2,
                    color: POSColors.green.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),

          // Kamera Kontrol Butonları (Fener + Kapat)
          Positioned(
            top: 10,
            right: 10,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                  ),
                  tooltip: _isTorchOn ? 'Feneri Kapat' : 'Feneri Aç',
                  onPressed: _toggleTorch,
                  icon: Icon(
                    _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _isTorchOn ? Colors.amber : Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                  ),
                  tooltip: 'Kamerayı Gizle',
                  onPressed: _toggleCamera,
                  icon: const Icon(
                    Icons.videocam_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),

          // Yükleniyor / Çözümleniyor Overlay
          if (_isResolving)
            Container(
              color: Colors.black.withValues(alpha: 0.75),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: POSColors.green),
                    SizedBox(height: 12),
                    Text(
                      'Sipariş aranıyor…',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraOffPlaceholder(bool isDesktop) {
    return Container(
      height: 130,
      width: double.infinity,
      color: POSColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.barcode_reader, size: 36, color: POSColors.green.withValues(alpha: 0.8)),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El Tipi Barkod Okuyucu Modu',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: POSColors.text,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'USB barkod tabancasıyla fişi okutun veya kodu elle yazın.',
                  style: TextStyle(
                    fontSize: 12,
                    color: POSColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: _toggleCamera,
            icon: const Icon(Icons.videocam_rounded, size: 16),
            label: const Text('Kamerayı Aç', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildManualInputSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hata Mesajı Varsa Göster
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: POSColors.redLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: POSColors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: POSColors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Giriş Alanı (USB Okuyucu veya Klavye)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  enabled: !_isResolving,
                  decoration: InputDecoration(
                    hintText: 'Sipariş No, Fiş No veya Barkod…',
                    hintStyle: const TextStyle(fontSize: 13, color: POSColors.textSecondary),
                    prefixIcon: const Icon(Icons.keyboard_alt_outlined, size: 20),
                    suffixIcon: _inputController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _inputController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: POSColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: POSColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: POSColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: POSColors.green, width: 1.5),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _resolveAndNavigate(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: POSColors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isResolving || _inputController.text.trim().isEmpty
                    ? null
                    : () => _resolveAndNavigate(_inputController.text),
                child: _isResolving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Bul & Aç',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: POSColors.surface,
        border: Border(top: BorderSide(color: POSColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 15, color: POSColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Okutulan sipariş anında açılarak durum güncelleme ve teslimat paneline yönlendirilir.',
              style: TextStyle(
                fontSize: 11,
                color: POSColors.textSecondary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
