/// Yazıcı metin boyutu
enum PrintSize {
  small,
  normal,
  medium,
  large
}

/// Yazıcı metin hizalaması
enum PrintAlign {
  left,
  center,
  right
}

/// SunmiPrinter için gerekli enum değerleri
enum SunmiPrintAlign {
  left, center, right
}

enum SunmiFontSize {
  xs, sm, md, lg, xl
}

enum SunmiBarcodeType {
  upca, upce, jan13, jan8, code39, itf, codabar, code93, code128
}

enum SunmiBarcodeTextPos {
  noText, textAbove, textUnder, both
}

enum SunmiQrcodeStyle {
  sunmiQrcode1, sunmiQrcode2
}

/// Yazdırma protokolü türleri
class PrinterProtocols {
  static const String escPos = 'esc_pos';
  static const String tsc = 'tsc';
  static const String cpcl = 'cpcl';
  static const String tspl = 'tspl';
  static const String zpl = 'zpl';
  
  /// Protokollerin dahili/harici kullanılabilirliği
  static bool isProtocolSupportedForInternal(String protocol) {
    switch (protocol.toLowerCase()) {
      case escPos:
      case tspl:
        return true;
      default:
        return false;
    }
  }
  
  static bool isProtocolSupportedForExternal(String protocol) {
    switch (protocol.toLowerCase()) {
      case escPos:
      case tsc:
      case cpcl:
        return true;
      default:
        return false;
    }
  }
}
