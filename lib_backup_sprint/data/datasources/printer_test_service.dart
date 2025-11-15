import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:bluetooth_print_plus/bluetooth_print_plus.dart';
import '../../shared/utils/debug_config.dart';
import 'bluetooth_service.dart';

/// Harici yazıcı (Bluetooth) test servisi - ESC/POS, TSC, CPCL, ZPL
class PrinterTestService {
  static final PrinterTestService instance = PrinterTestService._init();
  final BluetoothService _bluetoothService = BluetoothService.instance;

  PrinterTestService._init();

  /// Test sayfası yazdır - Harici yazıcılar için (Bluetooth)
  Future<bool> printTestPage({
    required String printerName,
    String? address,
    required BluetoothDevice bluetoothDevice,
    String protocol = 'esc_pos',
    String encoding = 'UTF-8',
    int paperWidth = 58,
    int paperHeight = 0,
    double gap = 0.0,
  }) async {
    try {
      DebugConfig.logDebug('Harici yazıcı test sayfası: $printerName');
      DebugConfig.logDebug(
          'Protokol: $protocol, Encoding: $encoding, Kağıt: ${paperWidth}mm, Yükseklik: ${paperHeight}mm, GAP: ${gap}mm');

      // Protokole göre komutları oluştur
      final Uint8List commands = await _createTestPageByProtocol(
        printerName: printerName,
        address: address ?? 'N/A',
        protocol: protocol,
        encoding: encoding,
        paperWidth: paperWidth,
        paperHeight: paperHeight,
        gap: gap,
      );

      // Bluetooth üzerinden yazdır
      return await _printViaBluetooth(commands, bluetoothDevice, printerName);
    } catch (e) {
      DebugConfig.logError('Harici yazıcı test hatası', e);
      return false;
    }
  }

  /// Bluetooth üzerinden yazdır (bluetooth_print_plus paketi)
  Future<bool> _printViaBluetooth(Uint8List data,
      BluetoothDevice bluetoothDevice, String printerName) async {
    try {
      // Bağlı değilse otomatik bağlan
      if (!_bluetoothService.isConnected) {
        DebugConfig.logDebug(
            'Bluetooth bağlantısı yok, $printerName\'e bağlanılıyor...');

        final connected = await _bluetoothService.connect(bluetoothDevice);

        if (!connected) {
          DebugConfig.logError('$printerName\'e bağlanılamadı', null);
          return false;
        }

        DebugConfig.logSuccess('$printerName\'e bağlantı başarılı');
      }

      DebugConfig.logDebug(
          'Bluetooth üzerinden ${data.length} byte gönderiliyor...');

      final success = await _bluetoothService.sendData(data);

      if (success) {
        DebugConfig.logSuccess('Test sayfası başarıyla gönderildi');
      } else {
        DebugConfig.logError('Test sayfası gönderilemedi', null);
      }

      return success;
    } catch (e) {
      DebugConfig.logError('Bluetooth yazdırma hatası', e);
      return false;
    }
  }

  /// Protokole göre test sayfası komutlarını oluştur
  Future<Uint8List> _createTestPageByProtocol({
    required String printerName,
    required String address,
    required String protocol,
    required String encoding,
    required int paperWidth,
    required int paperHeight,
    required double gap,
  }) async {
    switch (protocol.toLowerCase()) {
      case 'esc_pos':
        return await _createEscPosTestPage(
            printerName, address, paperWidth, paperHeight, gap);
      case 'tsc':
      case 'tspl':
        return await _createTscTestPage(
            printerName, address, paperWidth, paperHeight, gap);
      case 'cpcl':
        return await _createCpclTestPage(
            printerName, address, paperWidth, paperHeight, gap);
      case 'zpl':
        return await _createZplTestPage(
            printerName, address, paperWidth, paperHeight, gap);
      default:
        DebugConfig.logWarning(
            'Bilinmeyen protokol: $protocol, ESC/POS kullanılıyor');
        return await _createEscPosTestPage(
            printerName, address, paperWidth, paperHeight, gap);
    }
  }

  /// Logo yükle ve işle (tüm protokoller için ortak)
  Future<img.Image?> _loadAndProcessLogo(int maxWidth) async {
    try {
      final ByteData data = await rootBundle.load('assets/logo.png');
      final Uint8List imageBytes = data.buffer.asUint8List();
      img.Image? image = img.decodeImage(imageBytes);

      if (image == null) return null;

      // Minimum genişlik kontrolü
      if (maxWidth < 100) maxWidth = 150;

      // Ölçeklendir - Aspect ratio koru
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

      // Şeffaflık kontrolü - Şeffaf pikselleri beyaz yap
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final alpha = pixel.a.toInt();
          if (alpha < 128) {
            image.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
      }

      // Grayscale
      image = img.grayscale(image);

      // Kontrast ve parlaklık ayarı - Logo netliği için
      image = img.adjustColor(image, contrast: 1.3, brightness: 1.1);

      // Threshold (siyah-beyaz) - 150 threshold daha iyi sonuç verir
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

      // Minimum boyut kontrolü - çok küçük logolar yazdırılmaz
      if (image != null && image.width >= 50 && image.height >= 20) {
        bytes.addAll([27, 97, 1]); // Ortala

        // GS v 0 - Raster bit image
        int widthBytes = (image.width + 7) ~/ 8;
        bytes.addAll([29, 118, 48, 0]);
        bytes.addAll([widthBytes % 256, widthBytes ~/ 256]);
        bytes.addAll([image.height % 256, image.height ~/ 256]);

        // Image data
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
        // Text logo - Logo yüklenemezse veya çok küçükse
        bytes.addAll([27, 97, 1, 27, 69, 1, 29, 33, 17]);
        bytes.addAll('SHAMAN POS\n'.codeUnits);
        bytes.addAll([29, 33, 0, 27, 69, 0]);
      }
    } catch (e) {
      DebugConfig.logError('ESC/POS logo hatası', e);
      // Hata durumunda text logo
      bytes.addAll([27, 97, 1, 27, 69, 1, 29, 33, 17]);
      bytes.addAll('SHAMAN POS\n'.codeUnits);
      bytes.addAll([29, 33, 0, 27, 69, 0]);
    }
    return bytes;
  }

  /// Logo yazdır - TSC
  Future<String> _printLogoTsc(int paperWidth, int yPos) async {
    try {
      int maxWidth = (paperWidth * 8) - 32;
      final image = await _loadAndProcessLogo(maxWidth);

      // Minimum boyut kontrolü - çok küçük logolar yazdırılmaz
      if (image != null && image.width >= 50 && image.height >= 20) {
        String cmd = '';
        int xPos = ((paperWidth * 8) - image.width) ~/ 2;
        int widthBytes = (image.width + 7) ~/ 8;

        // TSC BITMAP komutu: BITMAP x,y,width_bytes,height,mode,data
        cmd += 'BITMAP $xPos,$yPos,$widthBytes,${image.height},1,';

        // Image data - hex formatında (TSC: MSB first)
        StringBuffer hexData = StringBuffer();
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < widthBytes; x++) {
            int byte = 0;
            for (int bit = 0; bit < 8; bit++) {
              int px = x * 8 + bit;
              if (px < image.width) {
                final pixel = image.getPixel(px, y);
                // Siyah piksel = 1 (TSC: bit 7 = sol, bit 0 = sağ)
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

        DebugConfig.logDebug(
            'TSC BITMAP oluşturuldu: ${image.width}x${image.height}, ${hexData.length} hex chars');
        return cmd;
      }
    } catch (e) {
      DebugConfig.logError('TSC logo hatası', e);
    }
    // Text logo - Logo yüklenemezse veya çok küçükse
    return 'TEXT 150,30,"4",0,1,1,"SHAMAN POS"\n';
  }

  /// Logo yazdır - CPCL (EG komutu)
  Future<String> _printLogoCpcl(int paperWidth, int yPos) async {
    try {
      int maxWidth = (paperWidth * 8) - 32;
      final image = await _loadAndProcessLogo(maxWidth);

      // Minimum boyut kontrolü
      if (image != null && image.width >= 50 && image.height >= 20) {
        String cmd = '';
        int xPos = ((paperWidth * 8) - image.width) ~/ 2;
        int widthBytes = (image.width + 7) ~/ 8;

        // CPCL EG (Expanded Graphics) komutu
        cmd += 'EG $widthBytes ${image.height} $xPos $yPos ';

        // Image data - hex formatında
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

        DebugConfig.logDebug(
            'CPCL EG oluşturuldu: ${image.width}x${image.height}');
        return cmd;
      }
    } catch (e) {
      DebugConfig.logError('CPCL logo hatası', e);
    }
    // Text logo - Logo yüklenemezse veya çok küçükse
    return 'CENTER\nTEXT 4 0 0 $yPos SHAMAN POS\n';
  }

  /// Logo yazdır - ZPL (^GF komutu)
  Future<String> _printLogoZpl(int paperWidth, int yPos) async {
    try {
      int maxWidth = (paperWidth * 8) - 32;
      final image = await _loadAndProcessLogo(maxWidth);

      // Minimum boyut kontrolü - çok küçük logolar yazdırılmaz
      if (image != null && image.width >= 50 && image.height >= 20) {
        String cmd = '';
        int xPos = ((paperWidth * 8) - image.width) ~/ 2;
        int widthBytes = (image.width + 7) ~/ 8;
        int totalBytes = (widthBytes * image.height).toInt();

        // ZPL ^GF (Graphic Field) komutu: ^GFA,total,total,width_bytes,data
        cmd += '^FO$xPos,$yPos\n';
        cmd += '^GFA,$totalBytes,$totalBytes,$widthBytes,';

        // Image data - hex formatında (ZPL: MSB first, siyah = 1)
        // ZPL hex compression kullanabilir ama basit hex daha güvenli
        StringBuffer hexData = StringBuffer();
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < widthBytes; x++) {
            int byte = 0;
            for (int bit = 0; bit < 8; bit++) {
              int px = x * 8 + bit;
              if (px < image.width) {
                final pixel = image.getPixel(px, y);
                // ZPL: Siyah piksel = 1 (MSB first: bit 7 = sol, bit 0 = sağ)
                if (pixel.r.toInt() < 128) {
                  byte |= (1 << (7 - bit));
                }
              }
            }
            hexData.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
          }
        }

        // ZPL hex data'yı satırlara böl (her satır max 80 karakter)
        String fullHex = hexData.toString();
        for (int i = 0; i < fullHex.length; i += 80) {
          int end = (i + 80 < fullHex.length) ? i + 80 : fullHex.length;
          cmd += fullHex.substring(i, end);
          if (end < fullHex.length) cmd += '\n';
        }

        cmd += '^FS\n';

        DebugConfig.logDebug(
            'ZPL ^GF oluşturuldu: ${image.width}x${image.height}, ${fullHex.length} hex chars');
        return cmd;
      }
    } catch (e) {
      DebugConfig.logError('ZPL logo hatası', e);
    }
    // Text logo - Logo yüklenemezse veya çok küçükse
    return '^FO200,30^A0N,60,60^FDSHAMAN POS^FS\n';
  }

  /// ESC/POS test sayfası komutlarını oluştur - Logo, Barkod, QR, Text
  Future<Uint8List> _createEscPosTestPage(
    String printerName,
    String address,
    int paperWidth,
    int paperHeight,
    double gap,
  ) async {
    List<int> bytes = [];

    try {
      // ESC @ - Yazıcıyı sıfırla
      bytes.addAll([27, 64]);

      // ==================== LOGO ====================
      bytes.addAll(await _printLogoEscPos(paperWidth));
      bytes.addAll('Test Sayfasi\n\n'.codeUnits);

      // ==================== YAZICI BİLGİLERİ ====================
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll('--------------------------------\n'.codeUnits);
      bytes.addAll('Yazici: $printerName\n'.codeUnits);
      bytes.addAll('Adres: $address\n'.codeUnits);

      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      bytes.addAll('Tarih: $dateStr\n'.codeUnits);
      bytes.addAll('Saat: $timeStr\n'.codeUnits);
      bytes.addAll('--------------------------------\n\n'.codeUnits);

      // ==================== METIN TESTLERİ ====================
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('METIN TESTLERI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]); // Kalın kapat
      bytes.addAll('\n'.codeUnits);

      // Normal metin
      bytes.addAll('Normal metin\n'.codeUnits);

      // Kalın metin
      bytes.addAll([27, 69, 1]);
      bytes.addAll('Kalin metin\n'.codeUnits);
      bytes.addAll([27, 69, 0]);

      // Altı çizili
      bytes.addAll([27, 45, 1]); // Altı çizili aç
      bytes.addAll('Alti cizili metin\n'.codeUnits);
      bytes.addAll([27, 45, 0]); // Altı çizili kapat

      // Büyük metin
      bytes.addAll([29, 33, 17]); // 2x boyut
      bytes.addAll('Buyuk metin\n'.codeUnits);
      bytes.addAll([29, 33, 0]); // Normal boyut

      bytes.addAll('\n'.codeUnits);

      // Hizalama testleri
      bytes.addAll([27, 97, 0]); // Sol
      bytes.addAll('Sol hizali\n'.codeUnits);

      bytes.addAll([27, 97, 1]); // Orta
      bytes.addAll('Orta hizali\n'.codeUnits);

      bytes.addAll([27, 97, 2]); // Sağ
      bytes.addAll('Sag hizali\n\n'.codeUnits);

      // Türkçe karakterler
      bytes.addAll([27, 97, 0]); // Sol hizala
      bytes.addAll('Turkce: cCgGiIsSOoUu\n\n'.codeUnits);

      // ==================== BARKOD ====================
      bytes.addAll([27, 97, 1]); // Ortala
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('BARKOD TESTI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]); // Kalın kapat
      bytes.addAll('\n'.codeUnits);

      // Barkod yazdır - CODE128
      // GS k m d1...dk NUL
      bytes.addAll([29, 107, 73]); // GS k 73 (CODE128)
      bytes.addAll([12]); // Uzunluk
      bytes.addAll('{B'.codeUnits); // CODE128 B
      bytes.addAll('1234567890'.codeUnits); // Barkod verisi

      bytes.addAll('\n\n'.codeUnits);
      bytes.addAll('1234567890\n\n'.codeUnits); // Barkod metni

      // ==================== QR KOD ====================
      bytes.addAll([27, 97, 1]); // Ortala
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll('QR KOD TESTI:\n'.codeUnits);
      bytes.addAll([27, 69, 0]); // Kalın kapat
      bytes.addAll('\n'.codeUnits);

      // QR Kod yazdır
      final qrData = 'https://shaman.pos';
      final qrDataBytes = qrData.codeUnits;

      // QR kod model ayarla
      bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]); // Model 2

      // QR kod boyutu ayarla (3-8 arası, 6 orta boy)
      bytes.addAll([29, 40, 107, 3, 0, 49, 67, 6]); // Size 6

      // QR kod hata düzeltme seviyesi (L=48, M=49, Q=50, H=51)
      bytes.addAll([29, 40, 107, 3, 0, 49, 69, 49]); // Level M

      // QR kod verisi
      final qrLen = qrDataBytes.length + 3;
      bytes.addAll(
          [29, 40, 107, qrLen % 256, qrLen ~/ 256, 49, 80, 48]); // Store data
      bytes.addAll(qrDataBytes);

      // QR kodu yazdır
      bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]); // Print QR

      bytes.addAll('\n\n'.codeUnits);
      bytes.addAll('$qrData\n\n'.codeUnits);

      // ==================== SONUÇ ====================
      bytes.addAll([27, 97, 1]); // Ortala
      bytes.addAll('--------------------------------\n'.codeUnits);
      bytes.addAll([27, 69, 1]); // Kalın
      bytes.addAll([29, 33, 17]); // 2x boyut
      bytes.addAll('TEST BASARILI!\n'.codeUnits);
      bytes.addAll([29, 33, 0]); // Normal boyut
      bytes.addAll([27, 69, 0]); // Kalın kapat
      bytes.addAll('--------------------------------\n'.codeUnits);

      // KAĞIT BESLEME YOK - Sadece yazdır ve dur
      // ESC/POS: Hiçbir kağıt besleme komutu yok

      DebugConfig.logDebug(
          'ESC/POS test sayfası oluşturuldu: ${bytes.length} byte (Kağıt besleme: YOK)');

      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('ESC/POS komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// TSC/TSPL test sayfası (Etiket yazıcıları için) - Profesyonel
  Future<Uint8List> _createTscTestPage(
    String printerName,
    String address,
    int paperWidth,
    int paperHeight,
    double gap,
  ) async {
    List<int> bytes = [];

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      String cmd = '';

      // GAP ve paperHeight'a göre FİŞ mi ETİKET mi belirle
      // GAP > 0 veya paperHeight > 0 ise ETİKET, yoksa FİŞ
      bool isLabel = (gap > 0 || paperHeight > 0);

      if (!isLabel) {
        // FİŞ YAZICI (GAP=0, paperHeight=0)
        int height = 150; // Varsayılan fiş yüksekliği
        cmd += 'SIZE $paperWidth mm,$height mm\n';
        cmd += 'BLINE 0 mm,0 mm\n'; // FİŞ: BLINE kullan (GAP değil)
        cmd += 'DIRECTION 0\n';
        cmd += 'CLS\n';

        // Logo ekle
        cmd += await _printLogoTsc(paperWidth, 20);
        cmd += 'TEXT 160,70,"2",0,1,1,"Test Sayfasi"\n';
        cmd += 'TEXT 20,120,"1",0,1,1,"Yazici: $printerName"\n';
        cmd += 'TEXT 20,145,"1",0,1,1,"Tarih: $dateStr $timeStr"\n';
        cmd += 'TEXT 20,190,"2",0,1,1,"METIN TESTLERI:"\n';
        cmd += 'TEXT 20,220,"1",0,1,1,"Normal metin"\n';
        cmd += 'TEXT 20,245,"2",0,1,1,"Kalin metin"\n';
        cmd += 'TEXT 20,275,"3",0,1,1,"Buyuk metin"\n';
        cmd += 'TEXT 150,330,"2",0,1,1,"BARKOD TESTI:"\n';
        cmd += 'BARCODE 150,365,"128",60,1,0,2,2,"1234567890"\n';
        cmd += 'TEXT 160,435,"1",0,1,1,"1234567890"\n';
        cmd += 'TEXT 150,480,"2",0,1,1,"QR KOD TESTI:"\n';
        cmd += 'QRCODE 160,515,H,4,A,0,"https://shaman.pos"\n';
        cmd += 'TEXT 140,655,"1",0,1,1,"https://shaman.pos"\n';
        cmd += 'TEXT 130,710,"3",0,1,1,"TEST BASARILI!"\n';
        cmd += 'PRINT 1,1\n'; // 1 kopya, 1 set
        // FİŞ: END komutu YOK, sadece PRINT yeterli
      } else {
        // ETİKET YAZICI (GAP > 0 veya paperHeight > 0)
        int height = paperHeight > 0 ? paperHeight : 100; // Varsayılan 100mm
        double gapValue = gap > 0 ? gap : 2.0; // Varsayılan 2mm
        cmd += 'SIZE $paperWidth mm,$height mm\n';
        cmd += 'GAP $gapValue mm,0 mm\n';
        cmd += 'DIRECTION 0\n';
        cmd += 'CLS\n';
        int centerX = (paperWidth * 8) ~/ 2;
        int leftMargin = 30;

        // Logo ekle
        cmd += await _printLogoTsc(paperWidth, 15);
        cmd += 'TEXT $centerX,60,"2",0,1,1,"Test Sayfasi"\n';
        cmd += 'TEXT $leftMargin,110,"2",0,1,1,"Yazici: $printerName"\n';
        cmd += 'TEXT $leftMargin,140,"2",0,1,1,"Tarih: $dateStr"\n';
        cmd += 'TEXT $leftMargin,190,"2",0,1,1,"METIN TESTLERI:"\n';
        cmd += 'TEXT $leftMargin,220,"1",0,1,1,"Normal"\n';
        cmd += 'TEXT ${leftMargin + 120},220,"2",0,1,1,"Kalin"\n';
        cmd += 'TEXT ${leftMargin + 220},220,"3",0,1,1,"Buyuk"\n';
        cmd += 'TEXT $centerX,270,"2",0,1,1,"BARKOD TESTI:"\n';
        cmd += 'BARCODE $centerX,300,"128",50,1,0,2,2,"1234567890"\n';
        cmd += 'TEXT $centerX,360,"1",0,1,1,"1234567890"\n';
        cmd += 'TEXT $centerX,400,"2",0,1,1,"QR KOD TESTI:"\n';
        cmd += 'QRCODE $centerX,430,H,3,A,0,"https://shaman.pos"\n';
        cmd += 'TEXT $centerX,540,"1",0,1,1,"https://shaman.pos"\n';
        cmd += 'TEXT $centerX,590,"3",0,1,1,"TEST BASARILI!"\n';
        cmd += 'PRINT 1,1\n'; // 1 kopya, 1 set
        // ETİKET: END komutu YOK, sadece PRINT yeterli
      }

      bytes.addAll(cmd.codeUnits);

      DebugConfig.logDebug(
          'TSC test sayfası oluşturuldu: ${bytes.length} byte (${isLabel ? "ETİKET" : "FİŞ"} modu)');
      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('TSC komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// CPCL test sayfası (Zebra mobil yazıcılar için) - Profesyonel
  Future<Uint8List> _createCpclTestPage(
    String printerName,
    String address,
    int paperWidth,
    int paperHeight,
    double gap,
  ) async {
    List<int> bytes = [];

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // FİŞ mi ETİKET mi
      bool isLabel = (gap > 0 || paperHeight > 0);

      String cmd = '';
      // FİŞ: Kompakt sayfa
      int pageHeight = isLabel ? 800 : 600;
      cmd += '! 0 200 200 $pageHeight 1\n';

      // Logo ekle
      cmd += await _printLogoCpcl(paperWidth, 10);
      cmd += 'CENTER\n';
      cmd += 'TEXT 2 0 0 50 Test Sayfasi\n';
      cmd += 'LINE 0 75 400 75 1\n';

      // Bilgiler - Kompakt
      cmd += 'LEFT\n';
      cmd += 'TEXT 2 0 10 85 Yazici: $printerName\n';
      cmd += 'TEXT 2 0 10 105 Tarih: $dateStr $timeStr\n';

      // Metin testleri - Küçük fontlar
      cmd += 'TEXT 2 0 10 130 METIN TESTLERI:\n';
      cmd += 'TEXT 1 0 10 150 Normal metin\n';
      cmd += 'TEXT 2 0 10 170 Kalin metin\n';
      cmd += 'TEXT 3 0 10 195 Buyuk metin\n';

      // Barkod - Kompakt
      cmd += 'CENTER\n';
      cmd += 'TEXT 2 0 0 230 BARKOD TESTI:\n';
      cmd += 'BARCODE 128 1 1 40 80 260 1234567890\n';
      cmd += 'TEXT 2 0 0 350 1234567890\n';

      // QR Kod - Küçük
      cmd += 'TEXT 2 0 0 380 QR KOD TESTI:\n';
      cmd += 'BARCODE QR 80 400 M 2 U 4\n';
      cmd += 'MA,https://shaman.pos\n';
      cmd += 'ENDQR\n';
      cmd += 'TEXT 1 0 0 510 https://shaman.pos\n';

      // Sonuç
      cmd += 'TEXT 3 0 0 540 TEST BASARILI!\n';

      cmd += 'FORM\n';
      cmd += 'PRINT\n';

      bytes.addAll(cmd.codeUnits);

      DebugConfig.logDebug(
          'CPCL profesyonel test sayfası oluşturuldu: ${bytes.length} byte');
      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('CPCL komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// ZPL test sayfası (Zebra etiket yazıcıları için) - Profesyonel
  Future<Uint8List> _createZplTestPage(
    String printerName,
    String address,
    int paperWidth,
    int paperHeight,
    double gap,
  ) async {
    List<int> bytes = [];

    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // FİŞ mi ETİKET mi
      bool isLabel = (gap > 0 || paperHeight > 0);

      String cmd = '';
      cmd += '^XA\n';

      // FİŞ: Kısa etiket modu - Kompakt
      if (!isLabel) {
        cmd += '^LL700\n'; // Etiket uzunluğu 700 dots (kısa)
        cmd += '^PW400\n'; // Etiket genişliği
        cmd += '^MNN\n'; // Media tracking: continuous (fiş)
      }

      // Logo ekle
      cmd += await _printLogoZpl(paperWidth, 20);
      cmd += '^FO200,100^A0N,30,30^FDTest Sayfasi^FS\n';
      cmd += '^FO50,140^GB500,3,3^FS\n';

      // Bilgiler
      cmd += '^FO50,160^A0N,25,25^FDYazici: $printerName^FS\n';
      cmd += '^FO50,195^A0N,25,25^FDAdres: $address^FS\n';
      cmd += '^FO50,230^A0N,25,25^FDTarih: $dateStr $timeStr^FS\n';
      cmd += '^FO50,265^GB500,3,3^FS\n';

      // Metin testleri
      cmd += '^FO50,285^A0N,25,25^FDMETIN TESTLERI:^FS\n';
      cmd += '^FO50,320^A0N,20,20^FDNormal metin^FS\n';
      cmd += '^FO50,350^A0N,30,30^FDKalin metin^FS\n';
      cmd += '^FO50,390^A0N,40,40^FDBuyuk metin^FS\n';

      // Barkod
      cmd += '^FO200,450^A0N,25,25^FDBARKOD TESTI:^FS\n';
      cmd += '^FO150,485^BY2^BCN,60,Y,N,N^FD1234567890^FS\n';
      cmd += '^FO230,555^A0N,20,20^FD1234567890^FS\n';

      // QR Kod
      cmd += '^FO200,620^A0N,25,25^FDQR KOD TESTI:^FS\n';
      cmd += '^FO220,660^BQN,2,5^FDQA,https://shaman.pos^FS\n';
      cmd += '^FO180,800^A0N,20,20^FDhttps://shaman.pos^FS\n';

      // Sonuç - Fiş modunda daha yukarıda
      if (!isLabel) {
        cmd += '^FO180,650^A0N,30,30^FDTEST BASARILI!^FS\n';
        // FİŞ: ^PQ komutu YOK
      } else {
        cmd += '^FO50,810^GB500,3,3^FS\n';
        cmd += '^FO180,830^A0N,40,40^FDTEST BASARILI!^FS\n';
        cmd += '^FO50,880^GB500,3,3^FS\n';
      }

      cmd += '^XZ\n';

      bytes.addAll(cmd.codeUnits);

      DebugConfig.logDebug(
          'ZPL profesyonel test sayfası oluşturuldu: ${bytes.length} byte');
      return Uint8List.fromList(bytes);
    } catch (e) {
      DebugConfig.logError('ZPL komutları oluşturma hatası', e);
      rethrow;
    }
  }

  /// Basit test yazdırma (sadece metin)
  Future<bool> printSimpleTest(String text) async {
    try {
      if (!_bluetoothService.isConnected) {
        DebugConfig.logError('Bluetooth bağlantısı yok', null);
        return false;
      }

      List<int> bytes = [];

      // ESC @ - Yazıcıyı sıfırla
      bytes.addAll([27, 64]);

      // Metni yazdır
      bytes.addAll(text.codeUnits);
      bytes.addAll('\n\n\n'.codeUnits);

      // Kağıt kes
      bytes.addAll([29, 86, 65, 0]);

      final Uint8List commands = Uint8List.fromList(bytes);
      return await _bluetoothService.sendData(commands);
    } catch (e) {
      DebugConfig.logError('Basit test yazdırma hatası', e);
      return false;
    }
  }

  /// QR kod yazdır (test için)
  Future<bool> printQRCode(String content) async {
    try {
      if (!_bluetoothService.isConnected) {
        DebugConfig.logError('Bluetooth bağlantısı yok', null);
        return false;
      }

      List<int> bytes = [];

      // ESC @ - Yazıcıyı sıfırla
      bytes.addAll([27, 64]);

      // QR kod model seç
      bytes.addAll([29, 40, 107, 4, 0, 49, 65, 50, 0]);

      // QR kod boyut ayarla (6)
      bytes.addAll([29, 40, 107, 3, 0, 49, 67, 6]);

      // QR kod hata düzeltme seviyesi (0)
      bytes.addAll([29, 40, 107, 3, 0, 49, 69, 0]);

      // QR kod veri gönder
      int contentLength = content.length + 3;
      int pL = contentLength % 256;
      int pH = contentLength ~/ 256;
      bytes.addAll([29, 40, 107, pL, pH, 49, 80, 48]);
      bytes.addAll(content.codeUnits);

      // QR kodu yazdır
      bytes.addAll([29, 40, 107, 3, 0, 49, 81, 48]);

      // Kağıt besle
      bytes.addAll([27, 100, 3]);

      final Uint8List commands = Uint8List.fromList(bytes);
      return await _bluetoothService.sendData(commands);
    } catch (e) {
      DebugConfig.logError('QR kod yazdırma hatası', e);
      return false;
    }
  }
}
