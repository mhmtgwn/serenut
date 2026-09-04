import 'dart:convert';
import 'dart:typed_data';

import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/services/tspl_canvas_label_engine.dart';
import 'package:serenutos/domain/services/tspl_label_layout_engine.dart';

class LegacyRawPrintRenderer implements PrintRenderer {
  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) =>
      rendererVersion == 'legacy-raw-v1';

  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async {
    final values = job.payloadJson
        .split(',')
        .where((value) => value.trim().isNotEmpty)
        .map((value) => int.parse(value.trim()))
        .toList(growable: false);
    if (values.any((value) => value < 0 || value > 255)) {
      throw const FormatException('Legacy raw print byte is out of range.');
    }
    return RenderedPrintDocument(
      bytes: Uint8List.fromList(values),
      mimeType: job.kind == PrintDocumentKind.receipt
          ? 'application/vnd.escpos'
          : 'application/vnd.tspl',
    );
  }
}

class EscPosReceiptRenderer implements PrintRenderer {
  static const _init = [0x1B, 0x40];
  static const _alignLeft = [0x1B, 0x61, 0x00];
  static const _alignCenter = [0x1B, 0x61, 0x01];
  static const _alignRight = [0x1B, 0x61, 0x02];
  static const _boldOn = [0x1B, 0x45, 0x01];
  static const _boldOff = [0x1B, 0x45, 0x00];
  static const _cut = [0x1D, 0x56, 0x41, 0x08];
  static const _drawer = [0x1B, 0x70, 0x00, 0x19, 0xFA];

  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) =>
      kind == PrintDocumentKind.receipt && rendererVersion == 'escpos-v1';

  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async {
    final payload = _map(job.payloadJson);
    final design = _map(job.designSnapshotJson);
    final capabilities = _map(job.capabilitySnapshotJson);
    final paperWidth = _integer(capabilities['paperWidthMm'], 58);
    final width = paperWidth <= 58 ? 32 : 48;
    final business = Map<String, Object?>.from(
      payload['business'] as Map? ?? const {},
    );
    final document = Map<String, Object?>.from(
      payload['document'] as Map? ?? const {},
    );
    final turkishMode = design['turkishMode']?.toString() ?? 'universal';
    final List<int> bytes;
    if (turkishMode == 'cp857') {
      bytes = <int>[
        ..._init,
        0x1C, 0x2E,
        0x1B, 0x74, 0x0D, // ESC t 13 (Epson CP857)
        0x1B, 0x74, 0x18, // ESC t 24 (Xprinter CP857)
      ];
    } else if (turkishMode == 'cp1254') {
      bytes = <int>[
        ..._init,
        0x1C, 0x2E,
        0x1B, 0x74, 0x46, // ESC t 70 (Windows-1254)
      ];
    } else {
      bytes = <int>[
        ..._init,
        0x1C, 0x2E,
      ];
    }

    if (document['openDrawer'] == true && design['openCashDrawer'] == true) {
      bytes.addAll(_drawer);
    }
    final logo = payload['logoEscPosBase64'] as String?;
    if (design['showLogo'] == true && logo != null && logo.isNotEmpty) {
      bytes
        ..addAll(_alignCenter)
        ..addAll(base64Decode(logo))
        ..add(0x0A);
    }
    bytes.addAll(_alignCenter);
    final businessName = business['name']?.toString().trim() ?? '';
    if ((logo == null || logo.isEmpty) && businessName.isNotEmpty) {
      _line(bytes, businessName, bold: true, mode: turkishMode);
    }
    final subtitle = business['subtitle']?.toString().trim() ?? '';
    if (subtitle.isNotEmpty) {
      _line(bytes, '— $subtitle —', mode: turkishMode);
    }
    _line(bytes, '[ SİPARİŞ FİŞİ ]', bold: true, mode: turkishMode);

    // Address rendering: Respects manual newlines and uses word-wrapping
    final addressRaw = business['address']?.toString().trim() ?? '';
    if (addressRaw.isNotEmpty) {
      for (final rawLine in addressRaw.split('\n')) {
        final lineTrimmed = rawLine.trim();
        if (lineTrimmed.isNotEmpty) {
          for (final wrapped in _wrap(lineTrimmed, width)) {
            _line(bytes, wrapped, mode: turkishMode);
          }
        }
      }
    }
    final phone = business['phone']?.toString().trim() ?? '';
    if (phone.isNotEmpty) {
      _line(bytes, 'Tel: $phone', mode: turkishMode);
    }
    final taxId = business['taxId']?.toString().trim() ?? '';
    if (taxId.isNotEmpty) {
      _line(bytes, 'Vergi No: $taxId', mode: turkishMode);
    }
    _line(bytes, _dashed(width), mode: turkishMode);

    bytes.addAll(_alignLeft);
    final docNumber = document['number']?.toString().trim() ?? '';
    final dateRaw = document['date']?.toString().trim() ?? '';
    final customerName = document['customerName']?.toString().trim() ?? '';
    final cashier = document['cashier']?.toString().trim() ?? '';
    final payment = document['payment']?.toString().trim() ?? '';

    String datePart = dateRaw;
    String timePart = '';
    if (dateRaw.contains(' ')) {
      final parts = dateRaw.split(' ');
      datePart = parts[0];
      timePart = parts.sublist(1).join(' ');
    }

    if (width >= 48) {
      if (docNumber.isNotEmpty || datePart.isNotEmpty) {
        final left = docNumber.isNotEmpty ? 'Sipariş No: #$docNumber' : '';
        final right = datePart.isNotEmpty ? 'Tarih: $datePart' : '';
        _line(bytes, _columns(left, right, width), mode: turkishMode);
      }
      if (customerName.isNotEmpty || timePart.isNotEmpty) {
        final left = customerName.isNotEmpty ? 'Müşteri: $customerName' : '';
        final right = timePart.isNotEmpty ? 'Saat: $timePart' : '';
        _line(bytes, _columns(left, right, width), mode: turkishMode);
      }
      if (payment.isNotEmpty) {
        _line(bytes, 'Ödeme Türü: $payment', mode: turkishMode);
      }
      if (cashier.isNotEmpty) {
        _line(bytes, 'Kasiyer: $cashier', mode: turkishMode);
      }
    } else {
      if (docNumber.isNotEmpty || datePart.isNotEmpty) {
        final left = docNumber.isNotEmpty ? 'Sip: #$docNumber' : '';
        _line(bytes, _columns(left, datePart, width), mode: turkishMode);
      }
      if (customerName.isNotEmpty) {
        _line(bytes, _fit('Müşteri: $customerName', width), mode: turkishMode);
      }
      if (timePart.isNotEmpty || payment.isNotEmpty) {
        final left = timePart.isNotEmpty ? 'Saat: $timePart' : '';
        final right = payment.isNotEmpty ? 'Ödeme: $payment' : '';
        _line(bytes, _columns(left, right, width), mode: turkishMode);
      }
      if (cashier.isNotEmpty) {
        _line(bytes, 'Kasiyer: $cashier', mode: turkishMode);
      }
    }

    final currency = payload['currency']?.toString() ?? 'TL';

    if (design['showCustomerBalance'] != false &&
        document['customerBalance'] != null) {
      final balance = _decimal(document['customerBalance']);
      _line(
          bytes,
          balance < 0
              ? 'Geçmiş Borç: ${balance.abs().toStringAsFixed(2)} $currency'
              : 'Bakiye: ${balance.toStringAsFixed(2)} $currency',
          mode: turkishMode);
    }
    if (document['notes']?.toString().trim().isNotEmpty == true) {
      for (final line in _wrap('Not: ${document['notes']}', width)) {
        _line(bytes, line, mode: turkishMode);
      }
    }
    _line(bytes, '=' * width, mode: turkishMode);

    if (design['showProductDetails'] != false) {
      final items = payload['items'] as List? ?? const [];
      final int wQty = width >= 48 ? 4 : 3;
      final int wPrice = width >= 48 ? 9 : 7;
      final int wTotal = width >= 48 ? 11 : 9;
      final int wName = width - wQty - wPrice - wTotal;

      _line(
        bytes,
        _columns4('AD.', 'ÜRÜN ADI', 'BİRİM', 'TUTAR', wQty, wName, wPrice, wTotal),
        bold: true,
        mode: turkishMode,
      );
      _line(bytes, '-' * width, mode: turkishMode);

      for (final raw in items) {
        final item = Map<String, Object?>.from(raw as Map);
        final name = item['name']?.toString().trim() ?? 'Ürün';
        final quantity = _decimal(item['quantity']);
        final unitPrice = _decimal(item['unitPrice']);
        final total = item['total'] == null
            ? quantity * unitPrice
            : _decimal(item['total']);
        final qtyStr = _quantity(quantity);
        final priceStr = unitPrice.toStringAsFixed(2);
        final totStr = total.toStringAsFixed(2);

        if (name.length <= wName - 1) {
          _line(
            bytes,
            _columns4(qtyStr, name, priceStr, totStr, wQty, wName, wPrice, wTotal),
            mode: turkishMode,
          );
        } else {
          final nameLines = _wrap(name, wName - 1);
          _line(
            bytes,
            _columns4(qtyStr, nameLines[0], '', '', wQty, wName, wPrice, wTotal),
            mode: turkishMode,
          );
          for (var i = 1; i < nameLines.length - 1; i++) {
            _line(
              bytes,
              _columns4('', nameLines[i], '', '', wQty, wName, wPrice, wTotal),
              mode: turkishMode,
            );
          }
          final lastLine = nameLines.length > 1 ? nameLines.last : '';
          _line(
            bytes,
            _columns4('', lastLine, priceStr, totStr, wQty, wName, wPrice, wTotal),
            mode: turkishMode,
          );
        }
      }
      _line(bytes, '-' * width, mode: turkishMode);
    }

    bytes.addAll(_alignRight);
    final total = _decimal(document['total']);
    final subtotal = payload['subtotal'] != null
        ? _decimal(payload['subtotal'])
        : total;
    final discount = _decimal(payload['discount']);
    final vat = payload['vat'] != null
        ? _decimal(payload['vat'])
        : (total * 0.10 / 1.10);

    _line(bytes, _columns('Ara Toplam:', '${subtotal.toStringAsFixed(2)} $currency', width), mode: turkishMode);
    if (vat > 0.009) {
      _line(bytes, _columns('KDV (%10 Dahil):', '${vat.toStringAsFixed(2)} $currency', width), mode: turkishMode);
    }
    if (discount > 0.009) {
      _line(bytes, _columns('İndirim / Kupon:', '-${discount.toStringAsFixed(2)} $currency', width), mode: turkishMode);
    }

    _line(bytes, '=' * width, mode: turkishMode);
    _line(bytes, _columns('GENEL TOPLAM', '${total.toStringAsFixed(2)} $currency', width), bold: true, mode: turkishMode);
    _line(bytes, '=' * width, mode: turkishMode);

    if (document['paid'] != null) {
      final paid = _decimal(document['paid']);
      _line(bytes, _columns('Ödenen:', '${paid.toStringAsFixed(2)} $currency', width), mode: turkishMode);
      if (paid < total - 0.01) {
        _line(bytes, _columns('Kalan:', '${(total - paid).toStringAsFixed(2)} $currency', width), bold: true, mode: turkishMode);
      }
    }

    bytes.addAll(_alignCenter);
    _line(bytes, _dashed(width), mode: turkishMode);

    final barcode = document['barcode']?.toString().trim() ?? document['number']?.toString().trim() ?? '';
    if (barcode.isNotEmpty) {
      final safe = barcode.codeUnits.where((value) => value <= 127).toList();
      bytes
        ..addAll(_alignCenter)
        ..addAll([0x1D, 0x48, 0x00, 0x1D, 0x68, 0x40, 0x1D, 0x77, 0x02])
        ..addAll([0x1D, 0x6B, 0x49, safe.length])
        ..addAll(safe)
        ..add(0x0A);
      final bizShort = (business['name']?.toString().trim() ?? 'SERENUT').toUpperCase();
      final humanBarcode = '* $barcode - ${DateTime.now().year} - $bizShort *';
      _line(bytes, humanBarcode, mode: turkishMode);
    }

    final qrData = document['qrData']?.toString() ?? '';
    if (design['showQrCode'] == true && qrData.isNotEmpty) {
      bytes
        ..addAll(_qr(qrData))
        ..add(0x0A);
    }

    final footer = business['receiptFooterText']?.toString().trim() ??
        design['footerText']?.toString().trim() ??
        'Afiyet Olsun! Bizi tercih ettiğiniz için teşekkür ederiz.';
    if (footer.isNotEmpty) {
      for (final line in _wrap(footer, width)) {
        _line(bytes, line, mode: turkishMode);
      }
    }

    final website = business['website']?.toString().trim() ?? business['email']?.toString().trim() ?? '';
    if (website.isNotEmpty) {
      _line(bytes, website, mode: turkishMode);
    }

    for (var i = 0; i < _integer(design['feedLines'], 2).clamp(0, 8); i++) {
      bytes.add(0x0A);
    }
    if (design['autoCut'] != false) bytes.addAll(_cut);
    return RenderedPrintDocument(
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/vnd.escpos',
    );
  }

  static String _dashed(int width) =>
      List.generate((width / 2).floor(), (_) => '- ').join().padRight(width).substring(0, width);

  static String _columns4(
    String col1,
    String col2,
    String col3,
    String col4,
    int w1,
    int w2,
    int w3,
    int w4,
  ) {
    final c1 = col1.padRight(w1);
    final c2 = (col2.length > w2 ? col2.substring(0, w2) : col2).padRight(w2);
    final c3 = col3.padLeft(w3);
    final c4 = col4.padLeft(w4);
    return '$c1$c2$c3$c4';
  }

  static void _line(List<int> bytes, String value,
      {bool bold = false, String mode = 'universal'}) {
    if (bold) bytes.addAll(_boldOn);
    bytes
      ..addAll(_encodeText(value, mode))
      ..add(0x0A);
    if (bold) bytes.addAll(_boldOff);
  }

  static Map<String, Object?> _map(String value) =>
      Map<String, Object?>.from(jsonDecode(value) as Map);
  static int _integer(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  static double _decimal(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
  static String _fit(String value, int width) =>
      value.length <= width ? value : '${value.substring(0, width - 3)}...';
  static String _columns(String left, String right, int width) {
    final safeLeft = _fit(left, (width - right.length - 1).clamp(1, width));
    return '$safeLeft${' ' * (width - safeLeft.length - right.length)}$right';
  }

  static List<String> _wrap(String value, int width) {
    final lines = <String>[];
    var current = '';
    for (final word in value.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        if (word.length <= width) {
          current = word;
        } else {
          for (var i = 0; i < word.length; i += width) {
            final end = (i + width < word.length) ? i + width : word.length;
            lines.add(word.substring(i, end));
          }
        }
      } else if (current.length + word.length + 1 <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        if (word.length <= width) {
          current = word;
        } else {
          for (var i = 0; i < word.length; i += width) {
            final end = (i + width < word.length) ? i + width : word.length;
            lines.add(word.substring(i, end));
          }
          current = '';
        }
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  static List<int> _encodeText(String text, String mode) {
    if (mode == 'cp857') {
      return _cp857(text);
    } else if (mode == 'cp1254') {
      return _cp1254(text);
    } else {
      return _universalTurkish(text);
    }
  }

  static List<int> _universalTurkish(String text) {
    const substitutions = {
      'ğ': 'g',
      'Ğ': 'G',
      'ş': 's',
      'Ş': 'S',
      'ı': 'i',
      'İ': 'I',
      'ç': 'c',
      'Ç': 'C',
      'ö': 'o',
      'Ö': 'O',
      'ü': 'u',
      'Ü': 'U',
      '₺': 'TL',
    };
    final bytes = <int>[];
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final replacement = substitutions[character];
      if (replacement != null) {
        bytes.addAll(replacement.codeUnits);
      } else if (rune <= 127) {
        bytes.add(rune);
      } else {
        bytes.add(0x20);
      }
    }
    return bytes;
  }

  static List<int> _cp857(String text) {
    const substitutions = {
      'ğ': 0xA7,
      'Ğ': 0xA6,
      'ş': 0x9F,
      'Ş': 0x9E,
      'ı': 0x8D,
      'İ': 0x98,
      'ç': 0x87,
      'Ç': 0x80,
      'ö': 0x94,
      'Ö': 0x99,
      'ü': 0x81,
      'Ü': 0x9A,
    };
    final bytes = <int>[];
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final replacement = substitutions[character];
      if (replacement != null) {
        bytes.add(replacement);
      } else if (character == '₺') {
        bytes.addAll('TL'.codeUnits);
      } else {
        bytes.add(rune <= 127 ? rune : 0x3F);
      }
    }
    return bytes;
  }

  static List<int> _cp1254(String text) {
    const substitutions = {
      'ğ': 0xF0,
      'Ğ': 0xD0,
      'ş': 0xFE,
      'Ş': 0xDE,
      'ı': 0xFD,
      'İ': 0xDD,
      'ç': 0xE7,
      'Ç': 0xC7,
      'ö': 0xF6,
      'Ö': 0xD6,
      'ü': 0xFC,
      'Ü': 0xDC,
    };
    final bytes = <int>[];
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      final replacement = substitutions[character];
      if (replacement != null) {
        bytes.add(replacement);
      } else if (character == '₺') {
        bytes.addAll('TL'.codeUnits);
      } else {
        bytes.add(rune <= 127 ? rune : 0x3F);
      }
    }
    return bytes;
  }

  static List<int> _qr(String value) {
    final data = value.codeUnits.where((byte) => byte <= 127).toList();
    final length = data.length + 3;
    return [
      0x1D,
      0x28,
      0x6B,
      0x03,
      0,
      0x31,
      0x43,
      0x04,
      0x1D,
      0x28,
      0x6B,
      0x03,
      0,
      0x31,
      0x45,
      0x30,
      0x1D,
      0x28,
      0x6B,
      length & 0xFF,
      (length >> 8) & 0xFF,
      0x31,
      0x50,
      0x30,
      ...data,
      0x1D,
      0x28,
      0x6B,
      0x03,
      0,
      0x31,
      0x51,
      0x30,
    ];
  }
}

class TsplProductLabelRenderer implements PrintRenderer {
  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) =>
      kind == PrintDocumentKind.productLabel &&
      rendererVersion.startsWith('tspl-product');

  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async {
    final payload = _map(job.payloadJson);
    final design = _map(job.designSnapshotJson);
    final capabilities = _map(job.capabilitySnapshotJson);
    final logo = payload['logoBytesBase64'] as String?;
    final widthMm = _integer(
      payload['labelWidthMm'] ??
          payload['widthMm'] ??
          capabilities['mediaWidthMm'] ??
          capabilities['labelWidthMm'] ??
          capabilities['paperWidthMm'] ??
          design['widthMm'],
      50,
    );
    final heightMm = _integer(
      payload['labelHeightMm'] ??
          payload['heightMm'] ??
          capabilities['mediaHeightMm'] ??
          capabilities['labelHeightMm'] ??
          design['heightMm'],
      30,
    );
    final gapMm = _integer(
      payload['labelGapMm'] ??
          payload['gapMm'] ??
          capabilities['gapMm'] ??
          capabilities['labelGapMm'] ??
          design['gapMm'],
      2,
    );
    final dpi = _integer(
      payload['labelDpi'] ??
          payload['dpi'] ??
          capabilities['dpi'] ??
          design['dpi'],
      203,
    );
    final autoDetectGap = payload['autoDetectGap'] == true ||
        capabilities['autoDetectGap'] == true ||
        design['autoDetectGap'] == true;
    final printableWidthDots = (payload['printableWidthDots'] ??
        capabilities['printableWidthDots']) as int?;

    final bytes = <int>[];
    var isFirstLabel = true;
    for (final raw in payload['labels'] as List? ?? const []) {
      bytes.addAll(TsplLabelLayoutEngine.generateLabelBytes(
        LabelModel.fromMap(Map<String, dynamic>.from(raw as Map)),
        widthMm: widthMm,
        heightMm: heightMm,
        gapMm: gapMm,
        autoDetectGap: isFirstLabel && autoDetectGap,
        dpi: dpi,
        printableWidthDots: printableWidthDots,
        direction: _integer(capabilities['direction'], 0),
        copies: 1,
        showBusinessName: design['showBusinessName'] != false,
        showBrand: design['showBrand'] == true,
        showBarcode: design['showBarcode'] != false,
        showPrice: design['showPrice'] != false,
        showVat: design['showVat'] == true,
        fontSize: design['fontSize']?.toString() ?? 'Orta',
        logoBytes: logo == null ? null : base64Decode(logo),
      ));
      isFirstLabel = false;
    }
    return RenderedPrintDocument(
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/vnd.tspl',
    );
  }
}

class TsplOrderLabelRenderer implements PrintRenderer {
  @override
  bool supports(PrintDocumentKind kind, String rendererVersion) =>
      kind == PrintDocumentKind.orderLabel &&
      rendererVersion.startsWith('tspl-order');

  @override
  Future<RenderedPrintDocument> render(PrintJobRecord job) async {
    final payload = _map(job.payloadJson);
    final design = _map(job.designSnapshotJson);
    final capabilities = _map(job.capabilitySnapshotJson);
    final useCanvas = design['useCanvas'] != false && design['engine'] != 'legacy';

    final widthMm = _integer(
      payload['labelWidthMm'] ??
          payload['widthMm'] ??
          capabilities['mediaWidthMm'] ??
          capabilities['labelWidthMm'] ??
          capabilities['paperWidthMm'] ??
          design['widthMm'],
      50,
    );
    final heightMm = _integer(
      payload['labelHeightMm'] ??
          payload['heightMm'] ??
          capabilities['mediaHeightMm'] ??
          capabilities['labelHeightMm'] ??
          design['heightMm'],
      30,
    );
    final gapMm = _integer(
      payload['labelGapMm'] ??
          payload['gapMm'] ??
          capabilities['gapMm'] ??
          capabilities['labelGapMm'] ??
          design['gapMm'],
      2,
    );
    final dpi = _integer(
      payload['labelDpi'] ??
          payload['dpi'] ??
          capabilities['dpi'] ??
          design['dpi'],
      203,
    );
    final autoDetectGap = payload['autoDetectGap'] == true ||
        capabilities['autoDetectGap'] == true ||
        design['autoDetectGap'] == true;
    final printableWidthDots = (payload['printableWidthDots'] ??
        capabilities['printableWidthDots']) as int?;

    final List<int> bytes;
    if (useCanvas) {
      bytes = await TsplCanvasLabelEngine.generateOrderLabelBytes(
        orderIdShort: payload['orderNo']?.toString() ?? '',
        customerName: payload['customerName']?.toString() ?? '',
        customerPhone: payload['customerPhone']?.toString(),
        customerNo: payload['customerNo']?.toString(),
        previousDebt: _decimal(payload['previousDebt'], 0),
        paymentStatus: payload['paymentStatus']?.toString() ?? 'Bilinmiyor',
        productName: payload['productName']?.toString() ?? '',
        quantity: _decimal(payload['quantity'], 1),
        items: (payload['items'] as List?)
            ?.map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
        note: payload['note'] as String?,
        timestamp: payload['timestamp'] == null
            ? null
            : DateTime.parse(payload['timestamp']! as String),
        totalAmount: payload['totalAmount'] == null
            ? null
            : _decimal(payload['totalAmount'], 0),
        itemsCount: payload['itemsCount'] as int?,
        widthMm: widthMm,
        heightMm: heightMm,
        gapMm: gapMm,
        autoDetectGap: autoDetectGap,
        dpi: dpi,
        direction: _integer(capabilities['direction'], 0),
        copies: 1,
        printableWidthDots: printableWidthDots,
        showBusinessName: design['showBusinessName'] != false,
        showCustomerName: design['showCustomerName'] != false,
        showOrderNo: design['showOrderNo'] != false,
        showDate: design['showDate'] != false,
        showTotalAmount: design['showTotalAmount'] != false,
        showItemsCount: design['showItemsCount'] != false,
        fontSize: design['fontSize']?.toString() ?? 'Orta',
        paginateOnOverflow: design['paginateOnOverflow'] != false,
        businessName: payload['businessName'] as String?,
        logoBytes: null, // Order labels do not print a logo
      );
    } else {
      bytes = TsplLabelLayoutEngine.generateOrderLabelBytes(
        orderIdShort: payload['orderNo']?.toString() ?? '',
        customerName: payload['customerName']?.toString() ?? '',
        customerPhone: payload['customerPhone']?.toString(),
        customerNo: payload['customerNo']?.toString(),
        previousDebt: _decimal(payload['previousDebt'], 0),
        paymentStatus: payload['paymentStatus']?.toString() ?? 'Bilinmiyor',
        productName: payload['productName']?.toString() ?? '',
        quantity: _decimal(payload['quantity'], 1),
        items: (payload['items'] as List?)
            ?.map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
        note: payload['note'] as String?,
        timestamp: payload['timestamp'] == null
            ? null
            : DateTime.parse(payload['timestamp']! as String),
        totalAmount: payload['totalAmount'] == null
            ? null
            : _decimal(payload['totalAmount'], 0),
        itemsCount: payload['itemsCount'] as int?,
        widthMm: widthMm,
        heightMm: heightMm,
        gapMm: gapMm,
        autoDetectGap: autoDetectGap,
        dpi: dpi,
        printableWidthDots: printableWidthDots,
        direction: _integer(capabilities['direction'], 0),
        copies: 1,
        showBusinessName: design['showBusinessName'] != false,
        showCustomerName: design['showCustomerName'] != false,
        showOrderNo: design['showOrderNo'] != false,
        showDate: design['showDate'] != false,
        showTotalAmount: design['showTotalAmount'] != false,
        showItemsCount: design['showItemsCount'] != false,
        fontSize: design['fontSize']?.toString() ?? 'Orta',
        paginateOnOverflow: design['paginateOnOverflow'] != false,
        businessName: payload['businessName'] as String?,
        logoBytes: null, // Order labels do not print a logo
      );
    }
    return RenderedPrintDocument(
      bytes: Uint8List.fromList(bytes),
      mimeType: 'application/vnd.tspl',
    );
  }
}

Map<String, Object?> _map(String value) =>
    Map<String, Object?>.from(jsonDecode(value) as Map);
int _integer(Object? value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
double _decimal(Object? value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
