import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../../shared/utils/debug_config.dart';

/// Dahili yazıcı (Sunmi) test servisi - ESC/POS ve TSPL
class InternalPrinterTestService {
  static final InternalPrinterTestService instance =
      InternalPrinterTestService._init();
  static const MethodChannel _printerChannel =
      MethodChannel('com.sunmi.printer');

  InternalPrinterTestService._init();

  /// Test sayfası yazdır - Dahili yazıcı için
  Future<bool> printTestPage({
    required String printerName,
    String protocol = 'esc_pos',
    int paperWidth = 58,
    int paperHeight = 0,
    double gap = 0.0,
  }) async {
    try {
      DebugConfig.logDebug(
          'Dahili yazıcı test sayfası yazdırılıyor: $printerName');
      DebugConfig.logDebug('Protokol: $protocol, Kağıt: ${paperWidth}mm');

      // Protokole göre komutları oluştur
      final bool isTspl = protocol.toLowerCase() == 'tspl';
      final Uint8List commands = isTspl
          ? await _createTsplTestPage(
              printerName: printerName,
              paperWidth: paperWidth,
              paperHeight: paperHeight,
              gap: gap,
            )
          : await _createEscPosTestPage(
              printerName: printerName,
              paperWidth: paperWidth,
            );

      return await _printViaInternal(commands, isTspl: isTspl);
    } catch (e) {
      DebugConfig.logError('Dahili yazıcı test hatası', e);
      return false;
    }
  }

  /// Dahili yazıcı üzerinden yazdır (Sunmi platform channel)
  Future<bool> _printViaInternal(Uint8List data, {bool isTspl = false}) async {
    try {
      DebugConfig.logDebug(
          'Dahili yazıcı üzerinden ${data.length} byte gönderiliyor... (TSPL: $isTspl)');

      final Map<String, dynamic> params = {
        'data': data,
      };

      // TSPL için sendRAWData kullan, ESC/POS için printRawData
      final String method = isTspl ? 'sendRAWData' : 'printRawData';

      final bool result = await _printerChannel.invokeMethod(method, params);

      if (result) {
        DebugConfig.logSuccess('Dahili yazıcıya test sayfası gönderildi');
      } else {
        DebugConfig.logError('Dahili yazıcı yazdırma başarısız', null);
      }

      return result;
    } catch (e) {
      DebugConfig.logError('Dahili yazıcı hatası', e);
      return false;
    }
  }

  /// Logo yükle ve işle
  Future<img.Image?> _loadAndProcessLogo(int maxWidth) async {
    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      final Uint8List imageBytes = data.buffer.asUint8List();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) return null;

      if (maxWidth < 100) maxWidth = 150;

      if (image.width > maxWidth) {
        final aspectRatio = image.height / image.width;
        final newHeight = (maxWidth * aspectRatio).round();
        image = img.copyResize(
          image,
          width: maxWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
      }

      // Şeffaflık kontrolü
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final alpha = pixel.a.toInt();
          if (alpha < 128) {
            image.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
      }

      image = img.grayscale(image);
      image = img.adjustColor(image, contrast: 1.3, brightness: 1.1);

      // Threshold
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final gray = pixel.r.toInt();
          final newColor = gray < 150 ? 0 : 255;
          image.setPixelRgba(x, y, newColor, newColor, newColor, 255);
        }
      }

      return image;
    } catch (e) {
      DebugConfig.logError('Logo yükleme hatası', e);
      return null;
    }
  }

  /// Logo yazdır - ESC/POS
  Future<List<int>> _printLogoEscPos(int paperWidth) async {
    List<int> bytes = [];

    try {
      int maxWidth = (paperWidth * 8) - 16; // 8 dots/mm
      final image = await _loadAndProcessLogo(maxWidth);

      if (image != null && image.width >= 50 && image.height >= 20) {
        bytes.addAll([27, 97, 1]); // Ortala

        int widthBytes = (image.width + 7) ~/ 8;
        bytes.addAll([29, 118, 48, 0]);
        bytes.addAll([widthBytes % 256, widthBytes ~/ 256]);
        bytes.addAll([image.height % 256, image.height ~/ 256]);

        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < widthBytes; x++) {
            int byte = 0;
            for (int bit = 0; bit < 8; bit++) {
              int px = x * 8 + bit;
              if (px < image.width) {
                final pixel = image.getPixel(px, y);
                if (pixel.r.toInt() < 128) {
                  byte |= (1 << (7 - bit));
                }
              }
            }
            bytes.add(byte);
          }
        }
        bytes.addAll('\n'.codeUnits);
      } else {
        // Text logo
        bytes.addAll([27, 97, 1, 27, 69, 1, 29, 33, 17]);
        bytes.addAll('SHAMAN POS\n'.codeUnits);
        bytes.addAll([29, 33, 0, 27, 69, 0]);
      }
    } catch (e) {
      DebugConfig.logError('ESC/POS logo hatası', e);
      bytes.addAll([27, 97, 1, 27, 69, 1, 29, 33, 17]);
      bytes.addAll('SHAMAN POS\n'.codeUnits);
      bytes.addAll([29, 33, 0, 27, 69, 0]);
    }
    return bytes;
  }

  /// ESC/POS test sayfası - Dahili yazıcı için
  Future<Uint8List> _createEscPosTestPage({
    required String printerName,
    required int paperWidth,
  }) async {
    List<int> bytes = [];

    try {
      // ESC @ - Yazıcıyı sıfırla
      bytes.addAll([27, 64]);

      // Logo
      bytes.addAll(await _printLogoEscPos(paperWidth));
      bytes.addAll('Test Sayfasi\n\n'.codeUnits);

      // Yazıcı bilgileri
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll('--------------------------------\n'.codeUnits);
      bytes.addAll('Yazici: $printerName\n'.codeUnits);
      bytes.addAll('Tip: Dahili (Sunmi)\n'.codeUnits);

      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      bytes.addAll('Tarih: $dateStr\n'.codeUnits);
      bytes.addAll('Saat: $timeStr\n'.codeUnits);
      bytes.addAll('--------------------------------\n\n'.codeUnits);

      // Metin testleri
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('METIN TESTLERI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]);
      bytes.addAll('\n'.codeUnits);

      bytes.addAll('Normal metin\n'.codeUnits);

      bytes.addAll([27, 69, 1]);
      bytes.addAll('Kalin metin\n'.codeUnits);
      bytes.addAll([27, 69, 0]);

      bytes.addAll([27, 45, 1]);
      bytes.addAll('Alti cizili metin\n'.codeUnits);
      bytes.addAll([27, 45, 0]);

      bytes.addAll([29, 33, 17]);
      bytes.addAll('Buyuk metin\n'.codeUnits);
      bytes.addAll([29, 33, 0]);

      bytes.addAll('\n'.codeUnits);

      // Hizalama testleri
      bytes.addAll([27, 97, 0]);
      bytes.addAll('Sol hizali\n'.codeUnits);

      bytes.addAll([27, 97, 1]);
      bytes.addAll('Orta hizali\n'.codeUnits);

      bytes.addAll([27, 97, 2]);
      bytes.addAll('Sag hizali\n\n'.codeUnits);

      bytes.addAll([27, 97, 0]);
      bytes.addAll('Turkce: cCgGiIsSOoUu\n\n'.codeUnits);

      // Barkod
      bytes.addAll([27, 97, 1]);
      bytes.addAll([27, 69, 1]);
      bytes.addAll('BARKOD TESTI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]);
      bytes.addAll('\n'.codeUnits);

      bytes.addAll([29, 107, 73]);
      bytes.addAll([12]);
      bytes.addAll('{B'.codeUnits);
      bytes.addAll('1234567890'.codeUnits);

      bytes.addAll('\n\n'.codeUnits);
      bytes.addAll('1234567890\n\n'.codeUnits);

      // QR Kod
      bytes.addAll([27, 97, 1]);
      bytes.addAll([27, 69, 1]);
      bytes.addAll('QR KOD TESTI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]);
      bytes.addAll('\n'.codeUnits);

      final qrData = 'https://shaman.pos';
      final qrDataBytes = qrData.codeUnits;

      bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]);
      bytes.addAll([29, 40, 107, 3, 0, 49, 67, 6]);
      bytes.addAll([29, 40, 107, 3, 0, 49, 69, 49]);

      final qrLen = qrDataBytes.length + 3;
      bytes.addAll([29, 40, 107, qrLen % 256, qrLen ~/ 256, 49, 80, 48]);
      bytes.addAll(qrDataBytes);

      bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);

      bytes.addAll('\n\n'.codeUnits);
      bytes.addAll('$qrData\n\n'.codeUnits);

      // Sonuç
      bytes.addAll([27, 97, 1]);
      bytes.addAll('--------------------------------\n'.codeUnits);
      bytes.addAll([27, 69, 1]);
      bytes.addAll([29, 33, 17]);
      bytes.addAll('TEST BASARILI!\n'.codeUnits);
      bytes.addAll([29, 33, 0]);
      bytes.addAll([27, 69, 0]);
      bytes.addAll('--------------------------------\n'.codeUnits);

      bytes.addAll('\n\n\n'.codeUnits);

      DebugConfig.logDebug(
          'Dahili yazıcı ESC/POS test sayfası: ${bytes.length} byte');

      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('ESC/POS komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// TSPL test sayfası - Dahili yazıcı için etiket modu
  Future<Uint8List> _createTsplTestPage({
    required String printerName,
    required int paperWidth,
    required int paperHeight,
    required double gap,
  }) async {
    List<int> bytes = [];

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

      String cmd = '';

      // Etiket boyutları
      int height = paperHeight > 0 ? paperHeight : 100;
      double gapValue = gap > 0 ? gap : 2.0;

      cmd += 'SIZE $paperWidth mm,$height mm\n';
      cmd += 'GAP $gapValue mm,0 mm\n';
      cmd += 'DIRECTION 0\n';
      cmd += 'CLS\n';

      int centerX = (paperWidth * 8) ~/ 2;
      int leftMargin = 30;

      // Logo
      int maxWidth = (paperWidth * 8) - 32;
      final image = await _loadAndProcessLogo(maxWidth);

      if (image != null && image.width >= 50 && image.height >= 20) {
        int xPos = ((paperWidth * 8) - image.width) ~/ 2;
        int widthBytes = (image.width + 7) ~/ 8;

        cmd += 'BITMAP $xPos,15,$widthBytes,${image.height},1,';

        StringBuffer hexData = StringBuffer();
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < widthBytes; x++) {
            int byte = 0;
            for (int bit = 0; bit < 8; bit++) {
              int px = x * 8 + bit;
              if (px < image.width) {
                final pixel = image.getPixel(px, y);
                if (pixel.r.toInt() < 128) {
                  byte |= (1 << (7 - bit));
                }
              }
            }
            hexData.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
          }
        }
        cmd += hexData.toString();
        cmd += '\n';
      } else {
        cmd += 'TEXT $centerX,15,"4",0,1,1,"SHAMAN POS"\n';
      }

      cmd += 'TEXT $centerX,60,"2",0,1,1,"Test Sayfasi"\n';
      cmd += 'TEXT $leftMargin,110,"2",0,1,1,"Yazici: $printerName"\n';
      cmd += 'TEXT $leftMargin,140,"2",0,1,1,"Tip: Dahili (TSPL)"\n';
      cmd += 'TEXT $leftMargin,170,"2",0,1,1,"Tarih: $dateStr"\n';
      cmd += 'TEXT $leftMargin,220,"2",0,1,1,"METIN TESTLERI:"\n';
      cmd += 'TEXT $leftMargin,250,"1",0,1,1,"Normal"\n';
      cmd += 'TEXT ${leftMargin + 120},250,"2",0,1,1,"Kalin"\n';
      cmd += 'TEXT ${leftMargin + 220},250,"3",0,1,1,"Buyuk"\n';
      cmd += 'TEXT $centerX,300,"2",0,1,1,"BARKOD TESTI:"\n';
      cmd += 'BARCODE $centerX,330,"128",50,1,0,2,2,"1234567890"\n';
      cmd += 'TEXT $centerX,390,"1",0,1,1,"1234567890"\n';
      cmd += 'TEXT $centerX,430,"2",0,1,1,"QR KOD TESTI:"\n';
      cmd += 'QRCODE $centerX,460,H,3,A,0,"https://shaman.pos"\n';
      cmd += 'TEXT $centerX,570,"1",0,1,1,"https://shaman.pos"\n';
      cmd += 'TEXT $centerX,620,"3",0,1,1,"TEST BASARILI!"\n';
      cmd += 'PRINT 1,1\n';

      bytes.addAll(cmd.codeUnits);

      DebugConfig.logDebug(
          'Dahili yazıcı TSPL test sayfası: ${bytes.length} byte');
      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('TSPL komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// Basit test yazdırma
  Future<bool> printSimpleTest(String text) async {
    try {
      List<int> bytes = [];

      bytes.addAll([27, 64]);
      bytes.addAll(text.codeUnits);
      bytes.addAll('\n\n\n'.codeUnits);

      final Uint8List commands = Uint8List.fromList(bytes);
      return await _printViaInternal(commands);
    } catch (e) {
      DebugConfig.logError('Basit test yazdırma hatası', e);
      return false;
    }
  }
}
