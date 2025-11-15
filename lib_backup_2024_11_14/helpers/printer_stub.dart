import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:sunmi_printer_plus/core/enums/enums.dart';
import 'package:sunmi_printer_plus/core/styles/sunmi_text_style.dart';

/// SunmiPrinterPlus sınıfının stub versiyonu
class SunmiPrinterPlusStub {
  Future<void> printText({
    required String text,
    SunmiTextStyle? style,
  }) async {
    debugPrint('STUB: printText - $text');
  }
  
  Future<void> line() async {
    debugPrint('STUB: line');
  }
  
  Future<void> lineWrap({required int times}) async {
    debugPrint('STUB: lineWrap - $times');
  }
  
  Future<void> cutPaper() async {
    debugPrint('STUB: cutPaper');
  }
  
  Future<void> printImage(Uint8List image, {SunmiPrintAlign? align}) async {
    debugPrint('STUB: printImage - ${image.length} bytes');
  }
}

/// EscCommand sınıfının stub versiyonu
class EscCommandStub {
  Future<void> cleanCommand() async {
    debugPrint('STUB: cleanCommand');
  }
  
  Future<void> text({required String content}) async {
    debugPrint('STUB: text - $content');
  }
  
  Future<void> cutPaper() async {
    debugPrint('STUB: cutPaper');
  }
  
  Future<Uint8List?> getCommand() async {
    return Uint8List.fromList([0, 0, 0]);
  }
}

/// Yazıcı yardımcı sınıfları
extension PrinterHelperExtensions on dynamic {
  Future<void> printTest() async {
    debugPrint('STUB: printTest');
  }
} 