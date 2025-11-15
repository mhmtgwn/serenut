import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// TSC yazıcı fontları ve komutları

class TscCommand {
  List<int> _cmdBytes = [];

  Future<void> cleanCommand() async { _cmdBytes = []; }
  Future<void> size({required int width, required int height}) async {
    String cmd = 'SIZE $width mm, $height mm\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<void> cls() async { _cmdBytes.addAll('CLS\n'.codeUnits); }
  Future<void> text({required int x, required int y, required String content, String fontType = 'FONT_3'}) async {
    String cmd = 'TEXT $x,$y,"$fontType",0,1,1,"$content"\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<void> barcode({required int x, required int y, required String barcodeType, required int height, required int readable, required String rotation, required String content}) async {
    String cmd = 'BARCODE $x,$y,"$barcodeType",$height,0,$readable,2,"$content"\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<void> print(int copies) async { _cmdBytes.addAll('PRINT $copies\n'.codeUnits); }
  Future<Uint8List> getCommand() async => Uint8List.fromList(_cmdBytes);
}

class EscCommand {
  List<int> _cmdBytes = [];

  Future<void> cleanCommand() async { _cmdBytes = []; }
  Future<void> text({required String content}) async {
    // ESC/POS başlangıç komutu: ESC @ (27, 64)
    _cmdBytes.addAll([27, 64]); // Initialize printer
    
    // Metin yazdırma
    _cmdBytes.addAll(content.codeUnits);
    
    // Satır sonu: LF (10)
    _cmdBytes.add(10);
  }
  
  // Yazı tipini ayarla
  Future<void> setFont({required int fontType}) async {
    // ESC M n komutu (27, 77, n)
    _cmdBytes.addAll([27, 77, fontType]);
  }
  
  // Yazı boyutunu ayarla
  Future<void> setFontSize({required int width, required int height}) async {
    // GS ! n komutu (29, 33, n)
    int n = ((width - 1) << 4) | (height - 1);
    _cmdBytes.addAll([29, 33, n]);
  }
  
  // Kalın yazı
  Future<void> setBold({required bool enabled}) async {
    // ESC E n komutu (27, 69, n)
    _cmdBytes.addAll([27, 69, enabled ? 1 : 0]);
  }
  
  // Hizalama ayarla (0: sol, 1: orta, 2: sağ)
  Future<void> setAlignment({required int alignment}) async {
    // ESC a n komutu (27, 97, n)
    _cmdBytes.addAll([27, 97, alignment]);
  }
  
  Future<void> barcode({required int x, required int y, required dynamic barcodeType, required int height, required String content}) async {
    // Gerçek ESC/POS barkod komutları burada uygulanmalı
    // Örnek: CODE128 için
    _cmdBytes.addAll([29, 107, 73]); // GS k I
    _cmdBytes.add(content.length); // Barkod içerik uzunluğu
    _cmdBytes.addAll(content.codeUnits); // Barkod içeriği
  }
  
  Future<void> qrCode({required String content, int size = 6, int errorLevel = 0}) async {
    // QR kod model seç
    _cmdBytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]);
    
    // QR kod boyut ayarla
    _cmdBytes.addAll([29, 40, 107, 3, 0, 49, 67, size]);
    
    // QR kod hata düzeltme seviyesi
    _cmdBytes.addAll([29, 40, 107, 3, 0, 49, 69, errorLevel]);
    
    // QR kod veri gönder
    int contentLength = content.length + 3;
    int pL = contentLength % 256;
    int pH = contentLength ~/ 256;
    _cmdBytes.addAll([29, 40, 107, pL, pH, 49, 80, 48]);
    _cmdBytes.addAll(content.codeUnits);
    
    // QR kodu yazdır
    _cmdBytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);
  }
  
  Future<void> feedLine({int lines = 1}) async {
    // ESC d n komutu (27, 100, n)
    _cmdBytes.addAll([27, 100, lines]);
  }
  
  Future<void> cutPaper() async { 
    // ESC/POS kağıt kesme komutu: GS V (29, 86, 65)
    _cmdBytes.addAll([29, 86, 65, 0]); 
  }
  
  Future<Uint8List> getCommand() async => Uint8List.fromList(_cmdBytes);
}

class CpclCommand {
  List<int> _cmdBytes = [];

  Future<void> cleanCommand() async { _cmdBytes = []; }
  Future<void> size({required int width, required int height}) async {
    String cmd = '! 0 200 200 $height 1\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<void> text({required int x, required int y, required String content, dynamic fontType, int fontSize = 0}) async {
    String cmd = 'TEXT $fontType $fontSize $x $y $content\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<void> print() async { _cmdBytes.addAll('FORM\nPRINT\n'.codeUnits); }
  Future<void> line({required int x, required int y, required int width, required int height}) async {
    String cmd = 'LINE $x $y ${x+width} ${y+height} 1\n';
    _cmdBytes.addAll(cmd.codeUnits);
  }
  Future<Uint8List> getCommand() async => Uint8List.fromList(_cmdBytes);
}

// Etiket ve fiş yazdırma yardımcı sınıfı
class PrinterDocuments {
  // Test sayfası yazdırma - ESC/POS komutları kullanarak
  static Future<Uint8List> createTestPage({
    required String title,
    required String printerName,
    required String address,
  }) async {
    EscCommand cmd = EscCommand();
    await cmd.cleanCommand();
    
    try {
      debugPrint('Test sayfası oluşturuluyor: $title');
      
      // Yazıcıyı sıfırla
      cmd._cmdBytes.addAll([27, 64]); // ESC @
      
      // Başlık
      await cmd.setAlignment(alignment: 1); // Ortalama
      await cmd.setBold(enabled: true);
      await cmd.setFontSize(width: 2, height: 2);
      await cmd.text(content: title);
      await cmd.feedLine();
      
      await cmd.setBold(enabled: false);
      await cmd.setFontSize(width: 1, height: 1);
      await cmd.text(content: 'Yazıcı: $printerName');
      await cmd.feedLine();
      await cmd.text(content: 'Adres: $address');
      await cmd.feedLine(lines: 2);
      
      // Test içeriği
      await cmd.setAlignment(alignment: 0); // Sol hizalama
      await cmd.text(content: '--------------------------------');
      await cmd.feedLine();
      await cmd.text(content: 'TEST SAYFASI');
      await cmd.feedLine();
      await cmd.text(content: '--------------------------------');
      await cmd.feedLine();
      
      await cmd.text(content: 'Normal metin');
      await cmd.feedLine();
      
      await cmd.setBold(enabled: true);
      await cmd.text(content: 'Kalın metin');
      await cmd.setBold(enabled: false);
      await cmd.feedLine();
      
      await cmd.setAlignment(alignment: 0);
      await cmd.text(content: 'Sol hizalı metin');
      await cmd.feedLine();
      
      await cmd.setAlignment(alignment: 1);
      await cmd.text(content: 'Orta hizalı metin');
      await cmd.feedLine();
      
      await cmd.setAlignment(alignment: 2);
      await cmd.text(content: 'Sağ hizalı metin');
      await cmd.feedLine();
      
      await cmd.setAlignment(alignment: 1);
      await cmd.text(content: '--------------------------------');
      await cmd.feedLine();
      
      // Tarih ve saat
      final now = DateTime.now();
      final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      await cmd.text(content: 'Tarih: $dateStr');
      await cmd.feedLine();
      await cmd.text(content: 'Saat: $timeStr');
      await cmd.feedLine(lines: 2);
      
      // Basitleştirilmiş test - barkod ve QR kodu atla
      // Bazı yazıcılar bu komutları desteklemeyebilir
      
      // Alt bilgi
      await cmd.setAlignment(alignment: 1);
      await cmd.setBold(enabled: true);
      await cmd.text(content: 'Test Başarılı!');
      await cmd.setBold(enabled: false);
      await cmd.feedLine(lines: 3);
      
      // Kağıt kesme
      try {
        await cmd.cutPaper();
      } catch (e) {
        // Kağıt kesme desteklenmiyorsa atla
        debugPrint('Kağıt kesme desteklenmiyor: $e');
        // Birkaç satır boşluk ekle
        await cmd.feedLine(lines: 5);
      }
      
      final result = await cmd.getCommand();
      debugPrint('Test sayfası oluşturuldu (${result.length} byte)');
      return result;
    } catch (e) {
      debugPrint('Test sayfası oluşturma hatası: $e');
      
      // Hata durumunda basit bir test sayfası oluştur
      cmd = EscCommand();
      await cmd.cleanCommand();
      
      // Yazıcıyı sıfırla
      cmd._cmdBytes.addAll([27, 64]); // ESC @
      
      await cmd.setAlignment(alignment: 1);
      await cmd.text(content: 'TEST SAYFASI');
      await cmd.feedLine(lines: 2);
      await cmd.text(content: 'Yazıcı: $printerName');
      await cmd.feedLine();
      await cmd.text(content: 'Test Başarılı!');
      await cmd.feedLine(lines: 5);
      
      final result = await cmd.getCommand();
      debugPrint('Basit test sayfası oluşturuldu (${result.length} byte)');
      return result;
    }
  }

  // Etiket yazdırma - TSC komutları kullanarak
  static Future<Uint8List> createLabelDocument({
    required String title,
    required String barcode,
    required Map<String, String> data,
    int width = 50,
    int height = 30,
    int copies = 1,
  }) async {
    TscCommand cmd = TscCommand();
    await cmd.cleanCommand();
    await cmd.size(width: width, height: height);
    await cmd.cls();
    
    // Başlık
    await cmd.text(x: 10, y: 10, content: title, fontType: 'FONT_3');
    
    // Barkod
    if (barcode.isNotEmpty) {
      await cmd.barcode(
        x: 10, 
        y: 40, 
        barcodeType: '128', 
        height: 50, 
        readable: 1, 
        rotation: '0', 
        content: barcode
      );
    }
    
    // Diğer veriler
    int yPos = 100;
    data.forEach((key, value) {
      cmd.text(x: 10, y: yPos, content: '$key: $value');
      yPos += 30;
    });
    
    await cmd.print(copies);
    return await cmd.getCommand();
  }
  
  // Fiş yazdırma - ESC/POS komutları kullanarak
  static Future<Uint8List> createReceiptDocument({
    required String title,
    required String storeName,
    required String address,
    required String phone,
    required List<Map<String, dynamic>> items,
    required double total,
    required String footer,
    String? qrData,
  }) async {
    EscCommand cmd = EscCommand();
    await cmd.cleanCommand();
    
    // Başlık
    await cmd.setAlignment(alignment: 1); // Ortalama
    await cmd.setBold(enabled: true);
    await cmd.setFontSize(width: 2, height: 2);
    await cmd.text(content: storeName);
    await cmd.feedLine();
    
    await cmd.setBold(enabled: false);
    await cmd.setFontSize(width: 1, height: 1);
    await cmd.text(content: address);
    await cmd.feedLine();
    await cmd.text(content: phone);
    await cmd.feedLine(lines: 2);
    
    // Başlık
    await cmd.setBold(enabled: true);
    await cmd.text(content: title);
    await cmd.setBold(enabled: false);
    await cmd.feedLine(lines: 2);
    
    // Ürünler
    await cmd.setAlignment(alignment: 0); // Sola hizalama
    await cmd.text(content: '--------------------------------');
    await cmd.text(content: 'ÜRÜN           ADET     FİYAT');
    await cmd.text(content: '--------------------------------');
    
    for (var item in items) {
      String name = item['name'] as String;
      double quantity = (item['quantity'] is int) 
          ? (item['quantity'] as int).toDouble() 
          : item['quantity'] as double;
      double price = (item['price'] is int) 
          ? (item['price'] as int).toDouble() 
          : item['price'] as double;
      double itemTotal = quantity * price;
      
      // Ürün adı, miktarı ve fiyatı formatla
      String formattedLine = name.padRight(15).substring(0, 15);
      formattedLine += quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 1).padLeft(5);
      formattedLine += itemTotal.toStringAsFixed(2).padLeft(10);
      
      await cmd.text(content: formattedLine);
    }
    
    await cmd.text(content: '--------------------------------');
    
    // Toplam
    await cmd.setAlignment(alignment: 2); // Sağa hizalama
    await cmd.setBold(enabled: true);
    await cmd.text(content: 'TOPLAM: ${total.toStringAsFixed(2)} TL');
    await cmd.setBold(enabled: false);
    await cmd.feedLine();
    
    // Alt bilgi
    await cmd.setAlignment(alignment: 1); // Ortalama
    await cmd.feedLine();
    await cmd.text(content: footer);
    await cmd.feedLine(lines: 2);
    
    // QR kod (isteğe bağlı)
    if (qrData != null && qrData.isNotEmpty) {
      await cmd.qrCode(content: qrData, size: 6);
      await cmd.feedLine(lines: 2);
    }
    
    // Kağıt kesme
    await cmd.cutPaper();
    
    return await cmd.getCommand();
  }
} 