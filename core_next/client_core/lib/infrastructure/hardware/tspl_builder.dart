// core_next/client_core/lib/infrastructure/hardware/tspl_builder.dart
import 'dart:convert';
import 'dart:typed_data';
import 'hardware_commands.dart';

/// Saf Dart TSPL Barkod Etiket Komut Üreteci.
/// 
/// Xprinter, Argox, Bixolon, TSC vb. tüm TSPL/TSPL2 uyumlu etiket yazıcıları için
/// milimetrik koordinatlı etiket komutları üretir.
class TsplBuilder {
  Uint8List buildLabel(PrintLabelCommand cmd) {
    final sb = StringBuffer();

    // 1. Etiket boyut ve boşluk kalibrasyonu
    sb.writeln('SIZE ${cmd.widthMm} mm, ${cmd.heightMm} mm');
    sb.writeln('GAP 3 mm, 0 mm');
    sb.writeln('DIRECTION 1');
    sb.writeln('CLS');

    // 2. Ürün Adı (Üst Başlık)
    final normalizedName = _normalizeTurkish(cmd.productName);
    sb.writeln('TEXT 20,20,"3",0,1,1,"$normalizedName"');

    // 3. Fiyat (Büyük Font)
    final priceStr = _formatTL(cmd.priceCents);
    sb.writeln('TEXT 20,60,"4",0,1,1,"$priceStr"');

    // 4. Barkod (EAN13 veya Code128)
    final barcodeType = cmd.barcode.length == 13 ? 'EAN13' : '128';
    sb.writeln('BARCODE 20,110,"$barcodeType",60,1,0,2,2,"${cmd.barcode}"');

    // 5. Baskı komutu
    sb.writeln('PRINT ${cmd.copies}');

    return Uint8List.fromList(latin1.encode(sb.toString()));
  }

  String _normalizeTurkish(String text) {
    const turkishChars = 'çÇğĞıİöÖşŞüÜ';
    const asciiChars   = 'cCgGiIoOsSuU';
    
    var normalized = text;
    for (var i = 0; i < turkishChars.length; i++) {
      normalized = normalized.replaceAll(turkishChars[i], asciiChars[i]);
    }
    return normalized;
  }

  String _formatTL(int cents) {
    final lira = cents ~/ 100;
    final kurus = (cents % 100).abs().toString().padLeft(2, '0');
    return '$lira,$kurus TL';
  }
}
