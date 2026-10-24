// core_next/client_core/lib/infrastructure/hardware/esc_pos_builder.dart
import 'dart:convert';
import 'dart:typed_data';
import 'hardware_commands.dart';

/// Saf Dart ESC/POS Termal Fiş Bayt Üreteci.
/// 
/// 58mm ve 80mm standart fiş yazıcıları için yüksek performanslı bayt dizisi üretir.
/// Türkçe karakterleri CP857/ASCII standardına göre normalize eder.
class EscPosBuilder {
  final BytesBuilder _buffer = BytesBuilder();

  // ESC/POS Komut Sabitleri
  static const List<int> cmdInit = [0x1B, 0x40]; // ESC @
  static const List<int> cmdAlignLeft = [0x1B, 0x61, 0x00]; // ESC a 0
  static const List<int> cmdAlignCenter = [0x1B, 0x61, 0x01]; // ESC a 1
  static const List<int> cmdAlignRight = [0x1B, 0x61, 0x02]; // ESC a 2
  static const List<int> cmdBoldOn = [0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> cmdBoldOff = [0x1B, 0x45, 0x00]; // ESC E 0
  static const List<int> cmdDoubleHeight = [0x1B, 0x21, 0x10]; // ESC ! 16
  static const List<int> cmdNormalText = [0x1B, 0x21, 0x00]; // ESC ! 0
  static const List<int> cmdCutPaper = [0x1D, 0x56, 0x42, 0x00]; // GS V B 0
  static const List<int> cmdOpenDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA]; // ESC p 0 25 250

  Uint8List buildReceipt(PrintReceiptCommand cmd, {int paperWidthChars = 32}) {
    _buffer.clear();
    _buffer.add(cmdInit);

    // Kasa çekmecesi aç komutu
    if (cmd.openCashDrawer) {
      _buffer.add(cmdOpenDrawer);
    }

    // ── BAŞLIK BÖLÜMÜ (CENTER) ──────────────────────────────────────────────
    _buffer.add(cmdAlignCenter);
    _buffer.add(cmdBoldOn);
    _buffer.add(cmdDoubleHeight);
    _addNormalizedText('${cmd.title}\n');
    _buffer.add(cmdNormalText);
    _buffer.add(cmdBoldOff);

    if (cmd.address != null && cmd.address!.isNotEmpty) {
      _addNormalizedText('${cmd.address}\n');
    }
    if (cmd.phone != null && cmd.phone!.isNotEmpty) {
      _addNormalizedText('Tel: ${cmd.phone}\n');
    }
    _addNormalizedText('Fiş No: ${cmd.receiptNo}\n');
    _addNormalizedText('Tarih: ${_formatDate(cmd.timestamp)}\n');
    if (cmd.customerName != null) {
      _addNormalizedText('Müşteri: ${cmd.customerName}\n');
    }

    // Çizgi
    _addSeparator(paperWidthChars);

    // ── KALEMLER LİSTESİ ────────────────────────────────────────────────────
    _buffer.add(cmdAlignLeft);
    for (final item in cmd.items) {
      // Satır 1: Ürün Adı
      _addNormalizedText('${item.name}\n');
      
      // Satır 2: "2 x 45,00 TL              90,00 TL"
      final qtyPrice = '${item.quantity} x ${_formatTL(item.unitPriceCents)}';
      final total = _formatTL(item.totalCents);
      _addTwoColumnLine(qtyPrice, total, paperWidthChars);
    }

    // Çizgi
    _addSeparator(paperWidthChars);

    // ── TOPLAMLAR ───────────────────────────────────────────────────────────
    if (cmd.discountCents > 0) {
      _addTwoColumnLine('Ara Toplam:', _formatTL(cmd.subtotalCents), paperWidthChars);
      _addTwoColumnLine('İskonto:', '-${_formatTL(cmd.discountCents)}', paperWidthChars);
    }

    _buffer.add(cmdBoldOn);
    _addTwoColumnLine('GENEL TOPLAM:', _formatTL(cmd.totalCents), paperWidthChars);
    _buffer.add(cmdBoldOff);

    _addTwoColumnLine('Ödeme (${cmd.paymentType}):', _formatTL(cmd.paidCents), paperWidthChars);

    if (cmd.debtCents > 0) {
      _buffer.add(cmdBoldOn);
      _addTwoColumnLine('Kalan Borç:', _formatTL(cmd.debtCents), paperWidthChars);
      _buffer.add(cmdBoldOff);
    }

    // Alt bilgi
    _buffer.add(cmdAlignCenter);
    _addNormalizedText('\nBizi Tercih Ettiğiniz İçin Teşekkür Ederiz\n\n\n');

    // Kağıt kes
    if (cmd.cutPaper) {
      _buffer.add(cmdCutPaper);
    }

    return _buffer.toBytes();
  }

  void _addSeparator(int width) {
    _buffer.add(utf8.encode('${'-' * width}\n'));
  }

  void _addTwoColumnLine(String left, String right, int width) {
    final availableSpace = width - left.length - right.length;
    final padding = availableSpace > 0 ? ' ' * availableSpace : ' ';
    _addNormalizedText('$left$padding$right\n');
  }

  void _addNormalizedText(String text) {
    // Termal yazıcılarda bozuk çıkmaması için Türkçe karakter normalizasyonu
    const turkishChars = 'çÇğĞıİöÖşŞüÜ';
    const asciiChars   = 'cCgGiIoOsSuU';
    
    var normalized = text;
    for (var i = 0; i < turkishChars.length; i++) {
      normalized = normalized.replaceAll(turkishChars[i], asciiChars[i]);
    }
    _buffer.add(utf8.encode(normalized));
  }

  String _formatTL(int cents) {
    final lira = cents ~/ 100;
    final kurus = (cents % 100).abs().toString().padLeft(2, '0');
    return '$lira,$kurus TL';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
