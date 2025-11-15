import 'package:sunmi_printer_plus/core/styles/sunmi_text_style.dart';
import 'package:sunmi_printer_plus/core/types/sunmi_text.dart';
import 'package:sunmi_printer_plus/core/types/sunmi_column.dart';
import 'package:sunmi_printer_plus/core/enums/enums.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrinterController {
  final dynamic printer;

  PrinterController({required this.printer});

  // Metin yazdırma
  Future<void> printText(String text, {SunmiTextStyle? style}) async {
    await printer.printText(text: text, style: style);
  }

  // Barkod yazdırma
  Future<void> printBarcode(String data, {SunmiBarcodeType type = SunmiBarcodeType.CODE128, int width = 2, int height = 100, SunmiPrintAlign align = SunmiPrintAlign.CENTER}) async {
    await printer.printBarCode(
      data: data,
      type: type,
      width: width,
      height: height,
      align: align,
    );
  }

  // QR kod yazdırma
  Future<void> printQRCode(String data, {int size = 8, SunmiPrintAlign align = SunmiPrintAlign.CENTER}) async {
    await printer.printQRCode(
      data: data,
      size: size,
      align: align,
    );
  }

  // Çizgi çekme
  Future<void> printLine({
    int lineWidth = 1,
    SunmiPrintAlign align = SunmiPrintAlign.CENTER,
  }) async {
    await printer.lineWrap(times: lineWidth);
  }

  // Kesikli çizgi çekme
  Future<void> printDashedLine({
    int lineWidth = 1,
    int dashLength = 4,
    SunmiPrintAlign align = SunmiPrintAlign.CENTER,
  }) async {
    String dash = '';
    for (int i = 0; i < dashLength; i++) {
      dash += '-';
    }
    await printer.printText(text: dash);
  }

  // Çizgi yazdırma
  Future<void> line({SunmiPrintLine? style}) async {
    await printer.line();
  }

  // Satır atlama
  Future<void> lineWrap(int n) async {
    await printer.lineWrap(times: n);
  }

  // Kağıt kesme
  Future<void> cutPaper() async {
    await printer.cutPaper();
  }
  
  // Özel metin yazdırma
  Future<void> printCustomText({required SunmiText sunmiText}) async {
    await printer.printText(
      text: sunmiText.text,
      style: sunmiText.style,
    );
  }
  
  // Birden fazla metin yazdırma
  Future<void> addText({required List<SunmiText> sunmiTexts}) async {
    for (var text in sunmiTexts) {
      await printCustomText(sunmiText: text);
    }
  }
  
  // Satır yazdırma
  Future<void> printRow({required List<SunmiColumn> cols}) async {
    String rowText = '';
    for (var col in cols) {
      int spaces = col.width;
      String text = col.text;
      if (text.length > spaces) {
        text = text.substring(0, spaces);
      } else {
        text = text.padRight(spaces);
      }
      rowText += text;
    }
    await printer.printText(text: rowText);
  }
  
  // Resim yazdırma
  Future<void> printImage({required Uint8List image, SunmiPrintAlign align = SunmiPrintAlign.CENTER}) async {
    await printer.printImage(image, align: align);
  }
  
  // ESC/POS komut yazdırma
  Future<List<int>> customEscPos() async {
    return [27, 64]; // ESC @: Initialize printer
  }
  
  // ESC/POS yazdırma
  Future<void> printEscPos({required List<int> data}) async {
    await printer.printText(text: "[ESC/POS Data]");
  }
  
  // TSPL yazdırma (etiket yazıcılar için)
  Future<void> printTSPL({required String data}) async {
    await printer.printText(text: "[TSPL Data]");
  }

  /// Test sayfası yazdırma metodu
  Future<bool> printTestPage() async {
    try {
      debugPrint('Test sayfası yazdırılıyor...');
      
      // Başlık yazdır
      await printCustomText(
        sunmiText: SunmiText(
          text: 'SUNMI TEST SAYFASI',
          style: SunmiTextStyle(
            bold: true,
            align: SunmiPrintAlign.CENTER,
          ),
        ),
      );
      
      // Alt başlık yazdır
      await printCustomText(
        sunmiText: SunmiText(
          text: 'Yazıcı Test Çıktısı',
          style: SunmiTextStyle(
            align: SunmiPrintAlign.CENTER,
          ),
        ),
      );
      
      // Tarih yazdır
      final now = DateTime.now();
      final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}';
      await printCustomText(
        sunmiText: SunmiText(
          text: dateStr,
          style: SunmiTextStyle(
            align: SunmiPrintAlign.CENTER,
          ),
        ),
      );
      
      // Çizgi yazdır
      await line();
      
      // Test içeriği yazdır
      await printer.printText(text: 'Bu bir test çıktısıdır. Yazıcı düzgün çalışıyor.');
      
      // Logo yazdır
      try {
        final logoBytes = await rootBundle.load('assets/logo.png');
        await printImage(image: logoBytes.buffer.asUint8List());
      } catch (e) {
        debugPrint('Logo yazdırma hatası: $e');
      }
      
      // QR kod yazdır
      await printer.printQRCode(
        data: 'https://shaman.com.tr',
        size: 8,
        align: SunmiPrintAlign.CENTER,
      );
      
      // Alt bilgi yazdır
      await printCustomText(
        sunmiText: SunmiText(
          text: 'Test başarılı!',
          style: SunmiTextStyle(
            align: SunmiPrintAlign.CENTER,
          ),
        ),
      );
      
      await printCustomText(
        sunmiText: SunmiText(
          text: 'Teşekkürler',
          style: SunmiTextStyle(
            align: SunmiPrintAlign.CENTER,
          ),
        ),
      );
      
      // Boşluk bırak ve kes
      await lineWrap(3);
      await cutPaper();
      
      debugPrint('Test sayfası yazdırma başarılı');
      return true;
    } catch (e) {
      debugPrint('Test sayfası yazdırma hatası: $e');
      return false;
    }
  }
} 