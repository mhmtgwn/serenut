import 'dart:convert';
import 'dart:typed_data';

import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/printing/printing_engine.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
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
    final bytes = <int>[..._init, 0x1C, 0x2E, 0x1B, 0x74, 0x0D];

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
      _line(bytes, businessName, bold: true);
    }
    for (final value in [
      business['address'],
      business['phone'],
      business['taxId']
    ]) {
      if (value?.toString().trim().isNotEmpty == true) {
        _line(bytes, value.toString());
      }
    }
    _line(bytes, '_' * width);

    bytes.addAll(_alignLeft);
    for (final entry in <String, Object?>{
      'Fiş No': document['number'],
      'Tarih': document['date'],
      'Ödeme': document['payment'],
      'Kasiyer': document['cashier'],
      'Müşteri': document['customerName'],
    }.entries) {
      if (entry.value?.toString().trim().isNotEmpty == true) {
        _line(bytes, '${entry.key}: ${entry.value}');
      }
    }
    if (design['showCustomerBalance'] != false &&
        document['customerBalance'] != null) {
      final balance = _decimal(document['customerBalance']);
      _line(
          bytes,
          balance < 0
              ? 'Geçmiş Borç: ${balance.abs().toStringAsFixed(2)}'
              : 'Bakiye: ${balance.toStringAsFixed(2)}');
    }
    if (document['notes']?.toString().trim().isNotEmpty == true) {
      for (final line in _wrap('Not: ${document['notes']}', width)) {
        _line(bytes, line);
      }
    }
    _line(bytes, '_' * width);

    if (design['showProductDetails'] != false) {
      final items = payload['items'] as List? ?? const [];
      for (final raw in items) {
        final item = Map<String, Object?>.from(raw as Map);
        final name = item['name']?.toString() ?? 'Ürün';
        final quantity = _decimal(item['quantity']);
        final unitPrice = _decimal(item['unitPrice']);
        final total = item['total'] == null
            ? quantity * unitPrice
            : _decimal(item['total']);
        final currency = payload['currency']?.toString() ?? 'TL';
        final right = '${total.toStringAsFixed(2)} $currency';
        final detail = '$name (${_quantity(quantity)} x '
            '${unitPrice.toStringAsFixed(2)})';
        if (detail.length + right.length + 1 <= width) {
          _line(bytes, _columns(detail, right, width));
        } else {
          _line(bytes, _fit(name, width));
          _line(
              bytes,
              _columns(
                '  ${_quantity(quantity)} x ${unitPrice.toStringAsFixed(2)}',
                right,
                width,
              ));
        }
      }
      _line(bytes, '_' * width);
    }

    bytes.addAll(_alignRight);
    final currency = payload['currency']?.toString() ?? 'TL';
    _line(bytes,
        'TOPLAM: ${_decimal(document['total']).toStringAsFixed(2)} $currency',
        bold: true);
    if (document['paid'] != null) {
      _line(bytes,
          'Ödenen: ${_decimal(document['paid']).toStringAsFixed(2)} $currency');
    }
    bytes.addAll(_alignCenter);
    _line(bytes, '_' * width);
    final footer = business['receiptFooterText']?.toString().trim() ??
        design['footerText']?.toString().trim() ??
        '';
    if (footer.isNotEmpty) {
      for (final line in _wrap(footer, width)) {
        _line(bytes, line);
      }
    }
    final barcode = document['barcode']?.toString().trim() ?? '';
    if (barcode.isNotEmpty) {
      final safe = barcode.codeUnits.where((value) => value <= 127).toList();
      bytes
        ..addAll(_alignCenter)
        ..addAll([0x1D, 0x48, 0x02, 0x1D, 0x68, 0x40, 0x1D, 0x77, 0x02])
        ..addAll([0x1D, 0x6B, 0x49, safe.length])
        ..addAll(safe)
        ..add(0x0A);
    }
    final qrData = document['qrData']?.toString() ?? '';
    if (design['showQrCode'] == true && qrData.isNotEmpty) {
      bytes
        ..addAll(_qr(qrData))
        ..add(0x0A);
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

  static void _line(List<int> bytes, String value, {bool bold = false}) {
    if (bold) bytes.addAll(_boldOn);
    bytes
      ..addAll(_cp857(value))
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
      if (current.isEmpty) {
        current = word;
      } else if (current.length + word.length + 1 <= width) {
        current = '$current $word';
      } else {
        lines.add(_fit(current, width));
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(_fit(current, width));
    return lines;
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
    final bytes = <int>[];
    var isFirstLabel = true;
    for (final raw in payload['labels'] as List? ?? const []) {
      bytes.addAll(TsplLabelLayoutEngine.generateLabelBytes(
        LabelModel.fromMap(Map<String, dynamic>.from(raw as Map)),
        widthMm: _integer(capabilities['mediaWidthMm'], 50),
        heightMm: _integer(capabilities['mediaHeightMm'], 30),
        gapMm: _integer(capabilities['gapMm'], 2),
        autoDetectGap: isFirstLabel && capabilities['autoDetectGap'] == true,
        dpi: _integer(capabilities['dpi'], 203),
        printableWidthDots: capabilities['printableWidthDots'] as int?,
        direction: _integer(capabilities['direction'], 0),
        copies: 1,
        showBusinessName: design['showBusinessName'] != false,
        showBrand: false,
        showBarcode: design['showBarcode'] != false,
        showPrice: design['showPrice'] != false,
        // The compact shelf label deliberately omits the redundant VAT line.
        showVat: false,
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
    final logo = payload['logoBytesBase64'] as String?;
    final bytes = TsplLabelLayoutEngine.generateOrderLabelBytes(
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
      widthMm: _integer(capabilities['mediaWidthMm'], 50),
      heightMm: _integer(capabilities['mediaHeightMm'], 30),
      gapMm: _integer(capabilities['gapMm'], 2),
      autoDetectGap: capabilities['autoDetectGap'] == true,
      dpi: _integer(capabilities['dpi'], 203),
      printableWidthDots: capabilities['printableWidthDots'] as int?,
      direction: _integer(capabilities['direction'], 0),
      copies: 1,
      showBusinessName: design['showBusinessName'] != false,
      showCustomerName: design['showCustomerName'] != false,
      showOrderNo: design['showOrderNo'] != false,
      showDate: design['showDate'] != false,
      showTotalAmount: design['showTotalAmount'] != false,
      showItemsCount: design['showItemsCount'] != false,
      fontSize: design['fontSize']?.toString() ?? 'Orta',
      businessName: payload['businessName'] as String?,
      logoBytes: null,
    );
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
