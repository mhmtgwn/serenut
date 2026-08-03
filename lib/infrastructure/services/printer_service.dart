// lib/domain/services/printer_service.dart
// Phase 4 — ESC/POS Thermal Printer Service
// Updated: 24 Jun 2026 — Failover chain + persistent queue + platform guards

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:image/image.dart' as img;
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/infrastructure/services/native_printer_bridge.dart';
import 'package:serenutos/infrastructure/services/persistent_print_queue.dart';
import 'package:serenutos/domain/services/i_printer_service.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/services/label_layout_engine.dart';
import 'package:serenutos/domain/services/tspl_label_layout_engine.dart';

/// Platform-aware printer backend.
enum PrinterBackend { sunmi, network, bluetooth, usb, none }

/// Low-level ESC/POS codes for thermal printers
class EscPosCommands {
  static const List<int> init = [0x1B, 0x40];
  static const List<int> alignLeft = [0x1B, 0x61, 0x00];
  static const List<int> alignCenter = [0x1B, 0x61, 0x01];
  static const List<int> alignRight = [0x1B, 0x61, 0x02];
  static const List<int> boldOn = [0x1B, 0x45, 0x01];
  static const List<int> boldOff = [0x1B, 0x45, 0x00];
  static const List<int> fontA = [0x1B, 0x4D, 0x00];
  static const List<int> fontB = [0x1B, 0x4D, 0x01];
  static const List<int> sizeNormal = [0x1D, 0x21, 0x00];
  static const List<int> sizeMedium = [
    0x1D,
    0x21,
    0x01
  ]; // Double height, normal width
  static const List<int> sizeLarge = [
    0x1D,
    0x21,
    0x11
  ]; // Double width & height
  static const List<int> lf = [0x0A];
  static const List<int> cut = [0x1D, 0x56, 0x41, 0x08]; // Feed & Cut
  static const List<int> beep = [0x1B, 0x42, 0x04, 0x02]; // Sound buzzer
  static const List<int> openDrawer = [
    0x1B,
    0x70,
    0x00,
    0x19,
    0xFA
  ]; // RJ11 drawer open
}

/// Service to handle connection, receipt formatting, and binary transmission
class PrinterService with ChangeNotifier implements IPrinterService {
  // Socket connector abstraction for mock tests
  final Future<Socket> Function(String, int, {Duration? timeout})?
      _socketConnector;
  final PersistentPrintQueue? _persistentQueue;

  final List<PrintJob> _queue = [];
  bool _isProcessing = false;

  PrinterService([this._socketConnector, this._persistentQueue]);

  @override
  List<PrintJob> get queue => List.unmodifiable(_queue);
  @override
  bool get isProcessing => _isProcessing;

  /// Enqueues a task and processes the queue asynchronously
  @override
  void enqueue(String title, Future<void> Function() printFn) {
    final job = PrintJob(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      printFn: printFn,
      createdAt: DateTime.now(),
    );
    _queue.add(job);
    notifyListeners();
    _processQueue();
  }

  /// Retries a failed job
  @override
  void retryJob(String id) {
    final idx = _queue.indexWhere((job) => job.id == id);
    if (idx != -1) {
      _queue[idx].status = 'pending';
      _queue[idx].error = null;
      notifyListeners();
      _processQueue();
    }
  }

  /// Clears completed/failed jobs from queue
  @override
  void clearQueue() {
    _queue.removeWhere(
        (job) => job.status == 'success' || job.status == 'failed');
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (true) {
      PrintJob? nextJob;
      for (final job in _queue) {
        if (job.status == 'pending') {
          nextJob = job;
          break;
        }
      }

      if (nextJob == null) break;

      nextJob.status = 'printing';
      notifyListeners();

      try {
        await nextJob.printFn();
        nextJob.status = 'success';
      } catch (e) {
        nextJob.status = 'failed';
        nextJob.error = e.toString();
        notifyListeners();
      }
      notifyListeners();
    }

    _isProcessing = false;
    notifyListeners();
  }

  /// Detect best available printer backend for current platform and settings.
  Future<PrinterBackend> _detectBackend(Settings settings) async {
    if (kIsWeb) return PrinterBackend.none;

    final printerName = settings.printerName?.trim();
    final ip = settings.printerIp?.trim();

    // Windows & iOS. An explicit IP always means raw TCP; otherwise a Windows
    // spooler printer name is used. This is especially important for the label
    // route, whose synthetic printerName is "network".
    if (Platform.isWindows || Platform.isIOS) {
      if (ip != null && ip.isNotEmpty) {
        return PrinterBackend.network;
      }
      if (Platform.isWindows &&
          printerName != null &&
          printerName.isNotEmpty &&
          printerName != 'network') {
        return PrinterBackend.usb;
      }
      return PrinterBackend.none;
    }

    // Android: Sunmi first, then USB, then network, then Bluetooth
    if (printerName == 'sunmi') {
      final hasSunmi = await NativePrinterBridge.hasSunmiPrinter();
      if (hasSunmi) return PrinterBackend.sunmi;
    }
    if (printerName != null && printerName.startsWith('usb:')) {
      return PrinterBackend.usb;
    }
    if (ip != null && ip.isNotEmpty) return PrinterBackend.network;
    if (printerName != null && printerName.contains(':')) {
      return PrinterBackend.bluetooth;
    }
    return PrinterBackend.none;
  }

  /// Settings helper based on purpose
  Settings _getSettingsForPurpose(Settings settings, PrinterPurpose purpose) {
    if (purpose == PrinterPurpose.label) {
      final labelIp = settings.labelPrinterIp ?? '';
      final labelPort = settings.labelPrinterPort;
      return settings.copyWith(
        printerName:
            labelIp.isNotEmpty ? 'network' : (settings.labelPrinterName ?? ''),
        printerIp: labelIp,
        printerPort: labelPort,
      );
    }
    return settings;
  }

  /// Helper to send bytes with Sunmi → Network → Bluetooth → PersistentQueue failover.
  Future<void> _sendBytes(List<int> bytes, Settings settings,
      {PrinterPurpose purpose = PrinterPurpose.receipt}) async {
    final targetSettings = _getSettingsForPurpose(settings, purpose);

    if (_socketConnector != null && _persistentQueue == null) {
      // Test mode — use mock socket directly
      await _sendViaTcp(bytes, targetSettings.printerIp ?? '127.0.0.1',
          targetSettings.printerPort);
      return;
    }

    // Failover chain: Sunmi → Network → Bluetooth → PersistentQueue
    final backends = await _buildFailoverChain(targetSettings, purpose: purpose);

    final failures = <String>[];
    for (final backend in backends) {
      try {
        await _sendViaBackend(bytes, backend, targetSettings);
        return; // Success
      } catch (error) {
        failures.add('${backend.name}: $error');
        // Try next backend
        continue;
      }
    }

    // All backends failed — enqueue persistently for retry
    final queue = _persistentQueue;
    if (queue != null) {
      await queue.enqueue(
        title: purpose == PrinterPurpose.label
            ? 'Etiket (failover)'
            : 'Fis (failover)',
        receiptJson: bytes.join(','), // Compact byte list
      );
    }
    final jobName = purpose == PrinterPurpose.label ? 'Etiket' : 'Fiş';
    final queueMessage =
        queue == null ? 'Kuyruğa alınamadı.' : 'Kuyruğa alındı.';
    throw Exception(
      '$jobName yazdırılamadı. $queueMessage ${failures.join(' | ')}',
    );
  }

  /// Build ordered failover chain for current platform and settings.
  Future<List<PrinterBackend>> _buildFailoverChain(Settings settings, {PrinterPurpose purpose = PrinterPurpose.receipt}) async {
    final chain = <PrinterBackend>[];

    if (kIsWeb) return [PrinterBackend.none];

    final printerName = settings.printerName?.trim();
    final ip = settings.printerIp?.trim();

    if (Platform.isIOS || Platform.isWindows) {
      if (ip != null && ip.isNotEmpty) {
        chain.add(PrinterBackend.network);
      }
      if (Platform.isWindows &&
          printerName != null &&
          printerName.isNotEmpty &&
          printerName != 'network') {
        chain.add(PrinterBackend.usb);
      }
      if (chain.isEmpty) chain.add(PrinterBackend.none);
      return chain;
    }

    // Android: preferred backend first, then fallbacks
    final isLabel = purpose == PrinterPurpose.label;

    if (printerName == 'sunmi') {
      chain.add(PrinterBackend.sunmi);
      if (ip != null && ip.isNotEmpty) chain.add(PrinterBackend.network);
    } else if (printerName != null && printerName.startsWith('usb:')) {
      chain.add(PrinterBackend.usb);
      if (!isLabel) chain.add(PrinterBackend.sunmi);
    } else if (ip != null && ip.isNotEmpty) {
      chain.add(PrinterBackend.network);
      if (!isLabel) chain.add(PrinterBackend.sunmi); // Sunmi as last-resort on Sunmi devices
    } else if (printerName != null && printerName.contains(':')) {
      chain.add(PrinterBackend.bluetooth);
      if (!isLabel) chain.add(PrinterBackend.sunmi);
    } else {
      chain.add(PrinterBackend.sunmi);
    }

    return chain;
  }

  Future<void> _sendViaBackend(
    List<int> bytes,
    PrinterBackend backend,
    Settings settings,
  ) async {
    switch (backend) {
      case PrinterBackend.sunmi:
        final ok = await NativePrinterBridge.printSunmiRaw(bytes);
        if (!ok) throw Exception('Sunmi print failed');
      case PrinterBackend.usb:
        final name = settings.printerName?.trim() ?? 'POS-58';
        final cleanName = name.startsWith('usb:') ? name.substring(4) : name;
        final ok = await NativePrinterBridge.printUsbRaw(cleanName, bytes);
        if (!ok) throw Exception('USB print failed');
      case PrinterBackend.network:
        final ip = settings.printerIp?.trim();
        if (ip == null || ip.isEmpty) {
          throw Exception('No printer IP configured');
        }
        await _sendViaTcp(bytes, ip, settings.printerPort);
      case PrinterBackend.bluetooth:
        final mac = settings.printerName?.trim() ?? '';
        final connected = await NativePrinterBridge.connectBluetoothDevice(mac);
        if (!connected) throw Exception('BT connect failed');
        final ok = await NativePrinterBridge.printBluetoothRaw(bytes);
        if (!ok) throw Exception('BT print failed');
      case PrinterBackend.none:
        throw Exception('No printer available');
    }
  }

  Future<void> _sendViaTcp(List<int> bytes, String ip, int port) async {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) {
      throw Exception('Yazıcı IP adresi belirtilmemiş.');
    }

    const maxAttempts = 2;
    const retryDelay = Duration(milliseconds: 400);

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final socket = _socketConnector != null
            ? await _socketConnector!(cleanIp, port,
                timeout: const Duration(seconds: 4))
            : await Socket.connect(cleanIp, port,
                timeout: const Duration(seconds: 4));
        try {
          socket.add(bytes);
          await socket.flush();
        } finally {
          await socket.close();
        }
        return; // success
      } on SocketException catch (e) {
        if (attempt >= maxAttempts) {
          throw Exception(
              'Yazıcıya ulaşılamadı ($cleanIp:$port). Lütfen yazıcının açık ve aynı ağa bağlı olduğunu kontrol edin. (Detay: ${e.message})');
        }
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          throw Exception(
              'Yazıcı yanıt vermedi ($cleanIp:$port). Zaman aşımı oluştu.');
        }
      } catch (e) {
        if (attempt >= maxAttempts) {
          throw Exception('Yazıcı bağlantı hatası ($cleanIp:$port): $e');
        }
      }
      await Future.delayed(retryDelay);
    }
  }

  bool _hasPrinter(Settings settings) {
    return (settings.printerIp != null && settings.printerIp!.isNotEmpty) ||
        (settings.printerName != null && settings.printerName!.isNotEmpty);
  }

  /// Backward-compatible TCP test (used by printer_service_test.dart).
  /// Sends a minimal test page directly via TCP — bypasses failover chain.
  @override
  Future<void> testConnection(String ip, int port) async {
    final List<int> bytes = [];
    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(EscPosCommands.beep);
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeLarge);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('SERENUT OS\n'));
    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes('Yazıcı Bağlantı Testi\n'));
    bytes.addAll(
        _textToBytes('Tarih: ${DateTime.now().toString().substring(0, 19)}\n'));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes('Durum: BAĞLANTI BAŞARILI! :)\n'));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.cut);

    await _sendViaTcp(bytes, ip, port);
  }

  /// Sends a realistic sample receipt page based on the new fixed layout
  @override
  Future<void> testPrinterConnection(Settings settings) async {
    // Generate a dummy order to test the actual receipt layout
    final order = OrderEntity(
      id: 'TEST-1001',
      customerId: '0',
      status: 'completed',
      createdAt: DateTime.now(),
      items: [
        {
          'product_name': 'Test Ürünü (Örnek)',
          'quantity': 2,
          'unit_price': 150.0,
          'barcode': '12345678',
        },
        {
          'product_name': 'Kurulum Hizmeti',
          'quantity': 1,
          'unit_price': 50.0,
        },
      ],
    );

    // We reuse printOrderReceipt to ensure the test exactly matches production layout
    await printOrderReceipt(
      order,
      order.items,
      null, // No customer info
      settings,
      paidAmount: 350.0,
      notes: 'Bu bir yazıcı test fişidir. Başarıyla yazdırıldı!',
    );
  }

  @override
  Future<void> testLabelPrinterConnection(Settings settings) async {
    final model = LabelModel(
      productName: 'Çifte Kavrulmuş Fındık 500g',
      brand: 'SERENUT ORGANİK',
      unit: 'Adet',
      shelfCode: 'A-01',
      businessName: settings.businessName.isNotEmpty
          ? settings.businessName
          : 'Serenut OS',
      weight: 1,
      price: 249.90,
      barcode: '8690123456789',
      qrData: 'product|8690123456789',
      timestamp: DateTime.now(),
    );
    final escPosLogo = settings.labelPrinterLanguage != 'tspl' && settings.printLogo
        ? await _getLogoBytes(settings.businessLogo, maxWidth: 320, maxHeight: 45)
        : const <int>[];

    final bytes = settings.labelPrinterLanguage == 'tspl'
        ? TsplLabelLayoutEngine.generateLabelBytes(
            model,
            widthMm: settings.labelWidthMm,
            heightMm: settings.labelHeightMm,
            gapMm: settings.labelGapMm,
            dpi: settings.labelDpi,
            showLogo: settings.printLogo,
            showBusinessName: true,
            showBarcode: true,
            showPrice: true,
            logoPath: settings.businessLogo,
          )
        : LabelLayoutEngine.generateLabelBytes(model, width: 32, logoBytes: escPosLogo);
    await _sendBytes(bytes, settings, purpose: PrinterPurpose.label);
  }

  /// Prints a sale receipt (Fiş)
  @override
  Future<void> printSaleReceipt(
    SaleEntity sale,
    List<Map<String, dynamic>> items,
    CustomerEntity? customer,
    Settings settings,
  ) async {
    if (!_hasPrinter(settings)) return;

    final width = _receiptWidth(settings);
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);

    // Trigger physical cash drawer open for cash transactions
    if (sale.paymentMethod == 'cash' && settings.openCashDrawer) {
      bytes.addAll(EscPosCommands.openDrawer);
    }

    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson
    bytes.addAll(_receiptTypography(settings));

    // 0. Logo (Centred)
    final logoWidth = settings.paperWidth <= 58 ? 320 : 448;
    final logo = settings.printLogo
        ? await _getLogoBytes(settings.businessLogo, maxWidth: logoWidth)
        : const <int>[];
    if (logo.isNotEmpty) {
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(logo);
      // Logodan sonraki boşluğu azalttık
    }

    final currency = settings.currency == '₺' ? 'TL' : settings.currency;

    // 1. Header (Centred)
    bytes.addAll(EscPosCommands.alignCenter);
    if (settings.businessName.trim().isNotEmpty) {
      bytes.addAll(EscPosCommands.sizeMedium);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll([0x1D, 0x42, 0x01]); // Invert ON (Siyah Arkaplan)
      bytes.addAll(_textToBytes(' ${settings.businessName} \n'));
      bytes.addAll([0x1D, 0x42, 0x00]); // Invert OFF
      bytes.addAll(EscPosCommands.sizeNormal);
      bytes.addAll(EscPosCommands.boldOff);
      bytes.addAll(EscPosCommands.lf);
    } else {
      bytes.addAll(EscPosCommands.sizeNormal);
    }
    
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('*** SATIŞ FİŞİ ***\n\n'));
    bytes.addAll(EscPosCommands.boldOff);
    if (settings.ownerName.trim().isNotEmpty) {
      bytes.addAll(_textToBytes('Yetkili: ${settings.ownerName}\n'));
    }

    final fullAddress = [
      settings.businessCity,
      settings.businessDistrict,
      settings.businessAddress
    ].where((e) => e.trim().isNotEmpty).join(', ');

    if (fullAddress.isNotEmpty) {
      bytes.addAll(_textToBytes('${_wrapText(fullAddress, width)}\n'));
    }

    if (settings.businessPhone.trim().isNotEmpty) {
      bytes.addAll(_textToBytes('Tel: ${settings.businessPhone}\n'));
    }
    if (settings.businessTaxId != null && settings.businessTaxId!.isNotEmpty) {
      bytes.addAll(_textToBytes('VKN/TC: ${settings.businessTaxId}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 2. Info (Left aligned)
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(_textToBytes('Fiş No: #${sale.id.toShortId}\n'));
    bytes.addAll(
        _textToBytes('Tarih: ${sale.createdAt.toString().substring(0, 16)}\n'));
    bytes.addAll(
        _textToBytes('Ödeme: ${_getPaymentLabel(sale.paymentMethod)}\n'));
    if (sale.createdBy != null && sale.createdBy!.isNotEmpty) {
      bytes.addAll(_textToBytes('Kasiyer: ${sale.createdBy}\n'));
    }
    if (customer != null) {
      bytes.addAll(_textToBytes('Müşteri: ${customer.name}\n'));
      if (settings.printCustomerBalance) {
        final absBal = customer.balance.abs().toStringAsFixed(2);
        if (customer.balance < 0) {
          bytes.addAll(_textToBytes('Geçmiş Borç: $absBal $currency\n'));
        } else if (customer.balance > 0) {
          bytes.addAll(_textToBytes('Alacak: $absBal $currency\n'));
        } else {
          bytes.addAll(_textToBytes('Borç Durumu: Yok\n'));
        }
      }
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 3. Items (Tabular)
    for (final item in settings.printProductDetails
        ? items
        : const <Map<String, dynamic>>[]) {
      final name = item['product_name']?.toString().trim().isNotEmpty == true
          ? item['product_name'].toString()
          : item['product_id']?.toString() ?? 'Ürün';
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final subtotal = qty * price;

      final details = '(${_formatQty(qty)} x ${price.toStringAsFixed(2)})';
      final left = '$name $details'.replaceAll('₺', 'TL');
      final right = '${subtotal.toStringAsFixed(2)} $currency';

      if (settings.receiptItemLayout == 'single') {
        bytes.addAll(_textToBytes('${_formatLine(left, right, width)}\n'));
      } else if (settings.receiptItemLayout == 'auto' &&
          left.length + right.length + 1 <= width) {
        bytes.addAll(_textToBytes('${_formatLine(left, right, width)}\n'));
      } else {
        // Truncate name if it overflows width, preventing messy wrapping
        final displayName =
            name.length > width ? '${name.substring(0, width - 3)}...' : name;
        bytes.addAll(_textToBytes('${displayName.replaceAll('₺', 'TL')}\n'));
        final subLeft = '  ${_formatQty(qty)} x ${price.toStringAsFixed(2)}';
        bytes.addAll(_textToBytes('${_formatLine(subLeft, right, width)}\n'));
      }
      if (settings.printBarcode) {
        final barcode =
            item['barcode']?.toString() ?? item['product_id']?.toString() ?? '';
        final barcodeBytes = _generateCode128Bytes(barcode);
        if (barcodeBytes.isNotEmpty) {
          bytes.addAll(EscPosCommands.alignCenter);
          bytes.addAll(barcodeBytes);
          bytes.addAll(EscPosCommands.lf);
          bytes.addAll(EscPosCommands.alignLeft);
        }
      }
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 4. Totals (Right aligned)
    bytes.addAll(EscPosCommands.alignRight);
    bytes.addAll(EscPosCommands.sizeMedium); // Make total pop!
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes(
        'TOPLAM: ${sale.totalAmount.toStringAsFixed(2)} $currency\n'));
    bytes.addAll(EscPosCommands.sizeNormal); // Revert size
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes(
        'Ödenen: ${sale.paidAmount.toStringAsFixed(2)} $currency\n'));
    final debt = sale.totalAmount - sale.paidAmount;
    if (debt > 0) {
      bytes.addAll(
          _textToBytes('Kalan Borç: ${debt.toStringAsFixed(2)} $currency\n'));
    }
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 5. QR Code
    if (settings.printQRCode) {
      final qrData = sale.id;
      bytes.addAll(_generateQrCodeBytes(qrData));
      bytes.addAll(EscPosCommands.lf);
    }

    bytes.addAll(_textToBytes(
        '${_wrapText(settings.receiptFooterText.trim(), width)}\n'));
    for (var i = 0; i < settings.receiptFeedLines.clamp(0, 8); i++) {
      bytes.addAll(EscPosCommands.lf);
    }
    if (settings.autoCutReceipt) bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  /// Prints a detailed order receipt (Sipariş Fişi)
  @override
  Future<void> printOrderReceipt(
    OrderEntity order,
    List<Map<String, dynamic>> items,
    CustomerEntity? customer,
    Settings settings, {
    double? paidAmount,
    String? notes,
  }) async {
    if (!_hasPrinter(settings)) return;

    final width = _receiptWidth(settings);
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson
    bytes.addAll(_receiptTypography(settings));

    // 0. Logo (Centred)
    final logoWidth = settings.paperWidth <= 58 ? 320 : 448;
    final logo = settings.printLogo
        ? await _getLogoBytes(settings.businessLogo, maxWidth: logoWidth)
        : const <int>[];
    if (logo.isNotEmpty) {
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(logo);
      // Logodan sonraki boşluğu azalttık
    }

    final currency = settings.currency == '₺' ? 'TL' : settings.currency;

    // 1. Header (Centred)
    bytes.addAll(EscPosCommands.alignCenter);
    if (settings.businessName.trim().isNotEmpty) {
      bytes.addAll(EscPosCommands.sizeMedium);
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll([0x1D, 0x42, 0x01]); // Invert ON (Siyah Arkaplan)
      bytes.addAll(_textToBytes(' ${settings.businessName} \n'));
      bytes.addAll([0x1D, 0x42, 0x00]); // Invert OFF
      bytes.addAll(EscPosCommands.sizeNormal);
      bytes.addAll(EscPosCommands.boldOff);
      bytes.addAll(EscPosCommands.lf);
    } else {
      bytes.addAll(EscPosCommands.sizeNormal);
    }
    
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('*** SİPARİŞ FİŞİ ***\n\n'));
    bytes.addAll(EscPosCommands.boldOff);
    if (settings.ownerName.trim().isNotEmpty) {
      bytes.addAll(_textToBytes('Yetkili: ${settings.ownerName}\n'));
    }

    final fullAddress = [
      settings.businessCity,
      settings.businessDistrict,
      settings.businessAddress
    ].where((e) => e.trim().isNotEmpty).join(', ');

    if (fullAddress.isNotEmpty) {
      bytes.addAll(_textToBytes('${_wrapText(fullAddress, width)}\n'));
    }

    if (settings.businessPhone.trim().isNotEmpty) {
      bytes.addAll(_textToBytes('Tel: ${settings.businessPhone}\n'));
    }
    if (settings.businessTaxId != null && settings.businessTaxId!.isNotEmpty) {
      bytes.addAll(_textToBytes('VKN/TC: ${settings.businessTaxId}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 2. Info (Left aligned)
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('*** SİPARİŞ FİŞİ ***\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes('Sipariş No: #${order.id.toShortId}\n'));
    bytes.addAll(_textToBytes(
        'Tarih: ${order.createdAt.toString().substring(0, 16)}\n'));
    if (order.expectedDeliveryDate != null) {
      bytes.addAll(_textToBytes(
          'Teslim Tarihi: ${order.expectedDeliveryDate!.toString().substring(0, 10)}\n'));
    }
    if (customer != null) {
      bytes.addAll(_textToBytes('Müşteri: ${customer.name}\n'));
      if (customer.phone.isNotEmpty) {
        bytes.addAll(_textToBytes('Tel: ${customer.phone}\n'));
      }
      if (settings.printCustomerBalance) {
        final absBal = customer.balance.abs().toStringAsFixed(2);
        if (customer.balance < 0) {
          bytes.addAll(_textToBytes('Geçmiş Borç: $absBal $currency\n'));
        } else if (customer.balance > 0) {
          bytes.addAll(_textToBytes('Alacak: $absBal $currency\n'));
        } else {
          bytes.addAll(_textToBytes('Borç Durumu: Yok\n'));
        }
      }
    }
    if (notes != null && notes.isNotEmpty) {
      bytes.addAll(_textToBytes('Not: $notes\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 3. Items (Tabular)
    double totalAmount = 0.0;
    for (final item in settings.printProductDetails
        ? items
        : const <Map<String, dynamic>>[]) {
      final name = item['product_name']?.toString().trim().isNotEmpty == true
          ? item['product_name'].toString()
          : item['product_id']?.toString() ?? 'Ürün';
      final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final subtotal = qty * price;
      totalAmount += subtotal;

      final details = '(${_formatQty(qty)} x ${price.toStringAsFixed(2)})';
      final left = '$name $details'.replaceAll('₺', 'TL');
      final right = '${subtotal.toStringAsFixed(2)} $currency';

      final displayName = name.length > width ? '${name.substring(0, width - 3)}...' : name;
      bytes.addAll(_textToBytes('${displayName.replaceAll('₺', 'TL')}\n'));
      
      final subLeft = '  ${_formatQty(qty)} x ${price.toStringAsFixed(2)}';
      bytes.addAll(_textToBytes('${_formatLine(subLeft, right, width)}\n'));
      if (settings.printBarcode) {
        final barcode =
            item['barcode']?.toString() ?? item['product_id']?.toString() ?? '';
        final barcodeBytes = _generateCode128Bytes(barcode);
        if (barcodeBytes.isNotEmpty) {
          bytes.addAll(EscPosCommands.alignCenter);
          bytes.addAll(barcodeBytes);
          bytes.addAll(EscPosCommands.lf);
          bytes.addAll(EscPosCommands.alignLeft);
        }
      }
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 4. Totals (Right aligned)
    bytes.addAll(EscPosCommands.alignRight);
    bytes.addAll(EscPosCommands.sizeMedium); // Make total pop!
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(
        _textToBytes('TOPLAM: ${totalAmount.toStringAsFixed(2)} $currency\n'));
    bytes.addAll(EscPosCommands.sizeNormal); // Revert size
    bytes.addAll(EscPosCommands.boldOff);

    if (paidAmount != null) {
      bytes.addAll(
          _textToBytes('Ödenen: ${paidAmount.toStringAsFixed(2)} $currency\n'));
      final debt = totalAmount - paidAmount;
      if (debt > 0) {
        bytes.addAll(
            _textToBytes('Kalan Borç: ${debt.toStringAsFixed(2)} $currency\n'));
      }
    }
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    if (settings.printQRCode) {
      final qrData = order.id;
      bytes.addAll(_generateQrCodeBytes(qrData));
      bytes.addAll(EscPosCommands.lf);
    }

    bytes.addAll(_textToBytes(
        '${_wrapText(settings.receiptFooterText.trim(), width)}\n'));
    for (var i = 0; i < settings.receiptFeedLines.clamp(0, 8); i++) {
      bytes.addAll(EscPosCommands.lf);
    }
    if (settings.autoCutReceipt) bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  /// Prints a collection receipt (Tahsilat Fişi)
  @override
  Future<void> printCollectionReceipt(
    CustomerEntity customer,
    double amount,
    String paymentMethod,
    String? notes,
    Settings settings,
  ) async {
    if (!_hasPrinter(settings)) return;

    final width = settings.paperWidth <= 58 ? 32 : 48;
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson

    // 0. Logo (Centred)
    final logoWidth = settings.paperWidth <= 58 ? 320 : 448;
    final logo = settings.printLogo
        ? await _getLogoBytes(settings.businessLogo, maxWidth: logoWidth)
        : const <int>[];
    if (logo.isNotEmpty) {
      bytes.addAll(EscPosCommands.alignCenter);
      bytes.addAll(logo);
      bytes.addAll(EscPosCommands.lf);
    }

    final currency = settings.currency == '₺' ? 'TL' : settings.currency;

    // 1. Header (Centred)
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeNormal);
    if (logo.isEmpty && settings.businessName.trim().isNotEmpty) {
      bytes.addAll(EscPosCommands.boldOn);
      bytes.addAll(_textToBytes('${settings.businessName}\n'));
      bytes.addAll(EscPosCommands.boldOff);
    }
    bytes.addAll(_textToBytes('${settings.businessAddress}\n'));
    bytes.addAll(_textToBytes('Tel: ${settings.businessPhone}\n'));
    if (settings.businessTaxId != null && settings.businessTaxId!.isNotEmpty) {
      bytes.addAll(_textToBytes('Vergi No: ${settings.businessTaxId}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 2. Title (Centred, Bold, Large)
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeLarge);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('TAHSİLAT MAKBUZU\n'));
    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 3. Info (Left aligned)
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(
        _textToBytes('Tarih: ${DateTime.now().toString().substring(0, 16)}\n'));
    bytes.addAll(_textToBytes('Müşteri: ${customer.name}\n'));
    bytes.addAll(
        _textToBytes('Ödeme Yöntemi: ${_getPaymentLabel(paymentMethod)}\n'));
    if (notes != null && notes.trim().isNotEmpty) {
      bytes.addAll(_textToBytes('Not: ${notes.trim()}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // 4. Details
    const leftText = 'Tahsil Edilen Tutar:';
    final rightText = '${amount.toStringAsFixed(2)} $currency';
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('${_formatLine(leftText, rightText, width)}\n'));
    bytes.addAll(EscPosCommands.boldOff);

    // Dynamic customer balance breakdown
    final absBal = customer.balance.abs().toStringAsFixed(2);
    String balText = '';
    if (customer.balance < 0) {
      balText = 'Kalan Borç: $absBal $currency';
    } else if (customer.balance > 0) {
      balText = 'Alacak: $absBal $currency';
    } else {
      balText = 'Bakiye: 0.00 $currency';
    }
    bytes.addAll(
        _textToBytes('${_formatLine("Güncel Bakiye:", balText, width)}\n'));
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('Tahsilat başarıyla kaydedildi.\n'));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  /// Prints an X-Report (Gün İçi Rapor)
  @override
  Future<void> printXReport(
    ReportSummary summary,
    List<CategoryRevenue> categories,
    Settings settings,
  ) async {
    if (!_hasPrinter(settings)) return;

    final width = settings.paperWidth <= 58 ? 32 : 48;
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('GÜN İÇİ X RAPORU\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes('İşletme: ${settings.businessName}\n'));
    bytes.addAll(
        _textToBytes('Tarih: ${DateTime.now().toString().substring(0, 16)}\n'));
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    final currency = settings.currency == '₺' ? 'TL' : settings.currency;

    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(_textToBytes(_formatLine('Toplam Ciro:',
        '${summary.totalRevenue.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(
        _formatLine('Satış Sayısı:', '${summary.totalSales}', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(_formatLine('Toplam Tahsilat:',
        '${summary.totalCollected.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(_formatLine('Vadeli Borç:',
        '${summary.totalDebt.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(_formatLine('Ort. Sepet:',
        '${summary.avgBasket.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(
        _formatLine('Yeni Müşteri:', '${summary.newCustomers}', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('KATEGORİ KIRILIMLARI\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(EscPosCommands.alignLeft);
    for (final cat in categories) {
      final left = '${cat.categoryName} (${cat.percentage.toStringAsFixed(0)}%)'
          .replaceAll('₺', 'TL');
      final right = '${cat.totalAmount.toStringAsFixed(2)} $currency';
      bytes.addAll(_textToBytes('${_formatLine(left, right, width)}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('*** RAPOR SONU ***\n'));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  /// Prints a Z-Report (Gün Sonu Raporu)
  @override
  Future<void> printZReport(
    ReportSummary summary,
    List<CategoryRevenue> categories,
    Settings settings,
  ) async {
    if (!_hasPrinter(settings)) return;

    final width = settings.paperWidth <= 58 ? 32 : 48;
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('GÜN SONU Z RAPORU\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(_textToBytes('İşletme: ${settings.businessName}\n'));
    bytes.addAll(_textToBytes(
        'Z No: #${DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '')}\n'));
    bytes.addAll(
        _textToBytes('Tarih: ${DateTime.now().toString().substring(0, 16)}\n'));
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    final currency = settings.currency == '₺' ? 'TL' : settings.currency;

    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(_textToBytes(_formatLine('TOPLAM CIRO:',
        '${summary.totalRevenue.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(
        _formatLine('TOPLAM SATIŞ:', '${summary.totalSales}', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(_formatLine('TOPLAM TAHSILAT:',
        '${summary.totalCollected.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes(_formatLine('TOPLAM VADELİ ALACAK:',
        '${summary.totalDebt.toStringAsFixed(2)} $currency', width)));
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('KATEGORİ SATIŞLARI\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(EscPosCommands.alignLeft);
    for (final cat in categories) {
      final left = cat.categoryName.replaceAll('₺', 'TL');
      final right = '${cat.totalAmount.toStringAsFixed(2)} $currency';
      bytes.addAll(_textToBytes('${_formatLine(left, right, width)}\n'));
    }
    bytes.addAll(_textToBytes('${"_" * width}\n'));
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('GÜN SONU KAPANMIŞTIR\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  // Helper to format left/right alignment
  String _formatLine(String left, String right, int width) {
    final int spaces = width - left.length - right.length;
    if (spaces <= 0) {
      final int maxL = width - right.length - 1;
      if (maxL > 0 && left.length >= maxL) {
        return '${left.substring(0, maxL)} $right';
      }
      return '$left $right';
    }
    return left + (' ' * spaces) + right;
  }

  int _receiptWidth(Settings settings) {
    var width = settings.paperWidth <= 58
        ? (settings.receiptFont == 'b' ? 42 : 32)
        : (settings.receiptFont == 'b' ? 64 : 48);
    if (settings.receiptTextSize == 'large') width ~/= 2;
    return width;
  }

  List<int> _receiptTypography(Settings settings) => [
        ...(settings.receiptFont == 'b'
            ? EscPosCommands.fontB
            : EscPosCommands.fontA),
        ...(settings.receiptTextSize == 'large'
            ? EscPosCommands.sizeLarge
            : EscPosCommands.sizeNormal),
      ];

  String _wrapText(String text, int width) {
    if (text.isEmpty) return '';
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (final word in paragraph.split(RegExp(r'\s+'))) {
        if (line.isEmpty) {
          line = word;
        } else if (line.length + word.length + 1 <= width) {
          line = '$line $word';
        } else {
          lines.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) lines.add(line);
    }
    return lines.join('\n');
  }

  // Converts text to CP857 (Turkish) bytes safely for native printing
  List<int> _textToBytes(String text) {
    final List<int> bytes = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      switch (char) {
        case 'ğ':
          bytes.add(0xA7);
          break;
        case 'Ğ':
          bytes.add(0xA6);
          break;
        case 'ş':
          bytes.add(0x9F);
          break;
        case 'Ş':
          bytes.add(0x9E);
          break;
        case 'ı':
          bytes.add(0x8D);
          break;
        case 'İ':
          bytes.add(0x98);
          break;
        case 'ç':
          bytes.add(0x87);
          break;
        case 'Ç':
          bytes.add(0x80);
          break;
        case 'ö':
          bytes.add(0x94);
          break;
        case 'Ö':
          bytes.add(0x99);
          break;
        case 'ü':
          bytes.add(0x81);
          break;
        case 'Ü':
          bytes.add(0x9A);
          break;
        case '₺':
          bytes.addAll('TL'.codeUnits);
          break;
        default:
          final code = char.codeUnitAt(0);
          if (code <= 127) {
            bytes.add(code);
          } else {
            bytes.add(0x3F); // '?'
          }
      }
    }
    return bytes;
  }

  // Load and dither logo from settings or fallback asset
  Future<List<int>> _getLogoBytes(String? logoPath,
      {int maxWidth = 320, int? maxHeight}) async {
    if (_socketConnector != null) {
      // Test mode - bypass loading from assets/files to avoid errors
      return [];
    }
    try {
      Uint8List list;
      if (logoPath != null && logoPath.startsWith('data:image/')) {
        final comma = logoPath.indexOf(',');
        if (comma < 0) return [];
        list = base64Decode(logoPath.substring(comma + 1));
      } else if (!kIsWeb &&
          logoPath != null &&
          (logoPath.startsWith('https://') || logoPath.startsWith('http://'))) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await client.getUrl(Uri.parse(logoPath));
          final response = await request.close();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException('Logo HTTP ${response.statusCode}');
          }
          list = Uint8List.fromList(await response
              .fold<List<int>>([], (all, part) => all..addAll(part)));
        } finally {
          client.close(force: true);
        }
      } else if (!kIsWeb &&
          logoPath != null &&
          logoPath.isNotEmpty &&
          File(logoPath).existsSync()) {
        list = await File(logoPath).readAsBytes();
      } else {
        final ByteData data = await rootBundle.load('assets/logo.png');
        list = data.buffer.asUint8List();
      }
      final img.Image? decoded = img.decodeImage(list);
      if (decoded != null) {
        // Enforce logo width to be an exact multiple of 8 bytes for ESC/POS GS v 0
        int rawTargetWidth = decoded.width > maxWidth ? maxWidth : decoded.width;
        int targetWidth = (rawTargetWidth ~/ 8) * 8;
        if (targetWidth < 8) targetWidth = 8;

        if (maxHeight != null) {
          double ratio = targetWidth / decoded.width;
          int projectedHeight = (decoded.height * ratio).toInt();
          if (projectedHeight > maxHeight) {
            double heightRatio = maxHeight / decoded.height;
            targetWidth = ((decoded.width * heightRatio) ~/ 8) * 8;
            if (targetWidth < 8) targetWidth = 8;
          }
        }

        final img.Image resized = img.copyResize(
          decoded,
          width: targetWidth,
          interpolation: img.Interpolation.cubic,
        );
        return _convertImageToEscPos(resized);
      }
    } catch (e) {
      debugPrint('Logo yukleme hatasi: $e');
    }
    return [];
  }

  // Converts an Image into ESC/POS GS v 0 raster bit image bytes
  List<int> _convertImageToEscPos(img.Image image) {
    final int width = image.width;
    final int height = image.height;
    final int widthBytes = (width + 7) ~/ 8;
    final List<int> bytes = [];

    // GS v 0 m xL xH yL yH
    final int xL = widthBytes & 0xFF;
    final int xH = (widthBytes >> 8) & 0xFF;
    final int yL = height & 0xFF;
    final int yH = (height >> 8) & 0xFF;

    bytes.addAll([0x1D, 0x76, 0x30, 0, xL, xH, yL, yH]);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < widthBytes * 8; x += 8) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final int px = x + bit;
          if (px < width) {
            final pixel = image.getPixel(px, y);
            // Handle transparent background pixels cleanly (treat alpha < 128 as white)
            if (pixel.a >= 128) {
              final double luminance =
                  0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
              if (luminance < 128) {
                byte |= (1 << (7 - bit));
              }
            }
          }
        }
        bytes.add(byte);
      }
    }
    return bytes;
  }

  // Generate Epson ESC/POS QR bytes
  List<int> _generateQrCodeBytes(String qrText) {
    final textBytes = qrText.codeUnits;
    final len = textBytes.length + 3;
    final lenL = len & 0xFF;
    final lenH = (len >> 8) & 0xFF;

    return [
      // 1. Module size (0x04)
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x04],
      // 2. Error correction Level L (0x30)
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30],
      // 3. Store text data in buffer
      ...[0x1D, 0x28, 0x6B, lenL, lenH, 0x31, 0x50, 0x30],
      ...textBytes,
      // 4. Print stored QR code
      ...[0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30],
    ];
  }

  /// Common Epson-compatible CODE128 subset B command. Non-ASCII identifiers
  /// are skipped because silently replacing barcode data would make it scan to
  /// the wrong product.
  List<int> _generateCode128Bytes(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 120 ||
        normalized.codeUnits.any((unit) => unit < 0x20 || unit > 0x7E)) {
      return const [];
    }
    final data = <int>[0x7B, 0x42, ...normalized.codeUnits]; // {B + data
    return [
      0x1D, 0x48, 0x00, // Human-readable text disabled (No text under barcode)
      0x1D, 0x68, 0x50, // Height: 80 dots
      0x1D, 0x77, 0x02, // Module width
      0x1D, 0x6B, 0x49, data.length,
      ...data,
    ];
  }

  String _getPaymentLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
      case 'nakit':
        return 'Nakit';
      case 'card':
      case 'kart':
        return 'Kart';
      case 'debt':
      case 'vadeli':
        return 'Vadeli';
      default:
        return method;
    }
  }

  @override
  Future<void> printOrderLabels(
    OrderEntity order,
    List<Map<String, dynamic>> items,
    Settings settings, {
    CustomerEntity? customer,
  }) async {
    final targetSettings =
        _getSettingsForPurpose(settings, PrinterPurpose.label);
    if (!_hasPrinter(targetSettings)) return;

    final List<int> allBytes = [];
    final isTspl = settings.labelPrinterLanguage == 'tspl';
    final custName = customer?.name ?? order.customerId;

    if (!isTspl) {
      // ESC/POS - Tek bir uzun sipariş etiketi basılır (Tüm ürünler içinde)
      final escPosLogo = settings.printLogo 
          ? await _getLogoBytes(settings.businessLogo, maxWidth: targetSettings.paperWidth <= 58 ? 240 : 360, maxHeight: 45) 
          : const <int>[];
          
      final labelBytes = LabelLayoutEngine.generateOrderLabelBytes(
        order: order,
        items: items,
        customer: customer,
        settings: settings,
        width: targetSettings.paperWidth <= 58 ? 32 : 48,
        logoBytes: escPosLogo,
      );
      allBytes.addAll(labelBytes);
    } else {
      // TSPL - Fiş gibi tüm ürünler tek bir uzun etikette basılır
      double orderTotal = 0.0;
      for (final item in items) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        orderTotal += qty * price;
      }
      
      final labelBytes = TsplLabelLayoutEngine.generateOrderLabelBytes(
        orderIdShort: order.id.length > 8 ? order.id.substring(0, 8) : order.id,
        customerName: custName,
        customerPhone: customer?.phone,
        items: items,
        orderNotes: order.notes,
        totalAmount: orderTotal,
        timestamp: order.createdAt,
        widthMm: settings.labelWidthMm,
        heightMm: settings.labelHeightMm,
        gapMm: settings.labelGapMm,
        dpi: settings.labelDpi,
        copies: settings.labelPrinterCopies,
      );
      allBytes.addAll(labelBytes);
    }

    await _sendBytes(allBytes, settings, purpose: PrinterPurpose.label);
  }

  @override
  Future<void> printShelfLabels(
    List<ProductEntity> products,
    Settings settings, {
    int copies = 1,
  }) async {
    if (products.isEmpty) return;
    final targetSettings =
        _getSettingsForPurpose(settings, PrinterPurpose.label);
    if (!_hasPrinter(targetSettings)) {
      throw StateError('Etiket yazıcısı tanımlı değil.');
    }
    final isTspl = settings.labelPrinterLanguage == 'tspl';
    final width = targetSettings.paperWidth <= 58 ? 32 : 48;
    final logo = !isTspl && settings.printLogo
        ? await _getLogoBytes(settings.businessLogo,
            maxWidth: targetSettings.paperWidth <= 58 ? 240 : 360,
            maxHeight: 45)
        : <int>[];
    final bytes = <int>[];
    final effectiveCopies = copies == 1
        ? settings.labelPrinterCopies.clamp(1, 20)
        : copies.clamp(1, 20);
    for (final product in products) {
      final model = LabelModel(
        productName: product.name,
        brand: product.brand,
        unit: product.unit,
        shelfCode: product.shelfCode,
        businessName: settings.businessName,
        weight: 1,
        price: product.price,
        barcode: product.id,
        qrData: 'product|${product.id}',
        timestamp: DateTime.now(),
      );
      if (isTspl) {
        bytes.addAll(TsplLabelLayoutEngine.generateLabelBytes(
          model,
          widthMm: settings.labelWidthMm,
          heightMm: settings.labelHeightMm,
          gapMm: settings.labelGapMm,
          dpi: settings.labelDpi,
          showLogo: settings.printLogo,
          showBusinessName: true,
          showBarcode: settings.printBarcode,
          showPrice: true,
          logoPath: settings.businessLogo,
        ));
      } else {
        for (var copy = 0; copy < effectiveCopies; copy++) {
          bytes.addAll(LabelLayoutEngine.generateLabelBytes(
            model,
            width: width,
            logoBytes: logo,
          ));
        }
      }
    }
    await _sendBytes(bytes, settings, purpose: PrinterPurpose.label);
  }

  String _formatQty(double qty) {
    if (qty == qty.toInt()) {
      return qty.toInt().toString();
    }
    return qty.toString();
  }

  @override
  Future<void> printDiagnosticsTest(Settings settings, int paperWidth) async {
    if (!_hasPrinter(settings)) return;

    final backend = await _detectBackend(settings);
    final width = paperWidth == 58 ? 32 : 48;
    final List<int> bytes = [];

    bytes.addAll(EscPosCommands.init);
    bytes.addAll([0x1C, 0x2E]); // Cancel Chinese character mode
    bytes.addAll(
        [0x1B, 0x74, 0x0D]); // Select Code Page CP857 (Turkish) on Sunmi/Epson

    // Sound buzzer
    bytes.addAll(EscPosCommands.beep);

    // Title centered and large
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(EscPosCommands.sizeLarge);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('SERENUT OS\n'));
    bytes.addAll(EscPosCommands.boldOff);

    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(_textToBytes('DONANIM TEŞHİS FİŞİ\n'));
    bytes.addAll(
        _textToBytes('Tarih: ${DateTime.now().toString().substring(0, 19)}\n'));
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Alignments test
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(_textToBytes('Sola Hizalı Test\n'));
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('Ortaya Hizalı Test\n'));
    bytes.addAll(EscPosCommands.alignRight);
    bytes.addAll(_textToBytes('Sağa Hizalı Test\n'));

    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Turkish characters test
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('Türkçe Karakter Testi:\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(
        _textToBytes('ııı İİİ şşş ŞŞŞ ğğğ ĞĞĞ\nüüü ÜÜÜ ççç ÇÇÇ ööö ÖÖÖ\n'));
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Device / width parameters
    bytes.addAll(EscPosCommands.alignLeft);
    bytes.addAll(
        _textToBytes('Kağıt Genişliği: $paperWidth mm ($width karakter)\n'));
    bytes.addAll(_textToBytes(
        'Printer Modeli: ${settings.printerName ?? 'Belirtilmedi'}\n'));
    bytes.addAll(
        _textToBytes('Yazıcı IP: ${settings.printerIp ?? 'Belirtilmedi'}\n'));
    bytes.addAll(
        _textToBytes('Bağlantı Türü: ${backend.toString().split('.').last}\n'));
    bytes.addAll(EscPosCommands.alignCenter);
    bytes.addAll(_textToBytes('${"_" * width}\n'));

    // Beep and cut
    bytes.addAll(EscPosCommands.sizeLarge);
    bytes.addAll(EscPosCommands.boldOn);
    bytes.addAll(_textToBytes('TEST BAŞARILI!\n'));
    bytes.addAll(EscPosCommands.boldOff);
    bytes.addAll(EscPosCommands.sizeNormal);
    bytes.addAll(EscPosCommands.lf);
    bytes.addAll(EscPosCommands.cut);

    await _sendBytes(bytes, settings);
  }

  @override
  Future<void> retryPersistedJob(dynamic job, Settings settings) async {
    final persistedJob = job as PersistedPrintJob;
    final bytes = persistedJob.receiptJson
        .split(',')
        .map((s) => int.parse(s.trim()))
        .toList();

    final isLabel = persistedJob.title.toLowerCase().contains('etiket');
    final targetSettings = isLabel
        ? _getSettingsForPurpose(settings, PrinterPurpose.label)
        : settings;

    final queue = _persistentQueue;
    if (queue != null) {
      await queue.markPrinting(persistedJob.id);
    }
    try {
      if (_socketConnector != null) {
        // Test mode — use mock socket directly
        await _sendViaTcp(
            bytes, targetSettings.printerIp ?? '127.0.0.1', targetSettings.printerPort);
      } else {
        final purpose = isLabel ? PrinterPurpose.label : PrinterPurpose.receipt;
        final backends = await _buildFailoverChain(targetSettings, purpose: purpose);
        bool sent = false;
        for (final backend in backends) {
          try {
            await _sendViaBackend(bytes, backend, targetSettings);
            sent = true;
            break;
          } catch (_) {
            continue;
          }
        }
        if (!sent) {
          throw Exception('Bütün fiziksel yazıcı yolları başarısız oldu.');
        }
      }
      if (queue != null) {
        await queue.markDone(persistedJob.id);
      }
    } catch (e) {
      if (queue != null) {
        await queue.markFailed(persistedJob.id, error: e.toString());
      }
      rethrow;
    }
  }

  @override
  Future<void> processPendingQueue(Settings settings) async {
    final queue = _persistentQueue;
    if (queue == null) return;

    final pendingJobs = await queue.loadPending();
    if (pendingJobs.isEmpty) return;

    for (final job in pendingJobs) {
      try {
        await retryPersistedJob(job, settings);
      } catch (_) {
        // Continue processing others
      }
    }
  }
}
