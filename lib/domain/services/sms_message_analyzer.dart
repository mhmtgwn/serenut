class SmsMessageAnalysis {
  final int characters;
  final int segments;
  final bool unicode;
  final int remainingInSegment;

  const SmsMessageAnalysis({
    required this.characters,
    required this.segments,
    required this.unicode,
    required this.remainingInSegment,
  });
}

class SmsMessageAnalyzer {
  const SmsMessageAnalyzer();

  // GSM 03.38 basic and extension tables. Extension characters consume two
  // septets; anything else switches the entire message to UCS-2.
  static const _basic =
      '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
  static const _extended = '^{}\\[~]|€';

  SmsMessageAnalysis analyze(String message) {
    var septets = 0;
    var unicode = false;
    for (final rune in message.runes) {
      final character = String.fromCharCode(rune);
      if (_basic.contains(character)) {
        septets++;
      } else if (_extended.contains(character)) {
        septets += 2;
      } else {
        unicode = true;
        break;
      }
    }

    final units = unicode ? message.runes.length : septets;
    final singleLimit = unicode ? 70 : 160;
    final multipartLimit = unicode ? 67 : 153;
    final segments = units == 0
        ? 1
        : units <= singleLimit
            ? 1
            : (units / multipartLimit).ceil();
    final limit = segments == 1 ? singleLimit : multipartLimit;
    return SmsMessageAnalysis(
      characters: message.runes.length,
      segments: segments,
      unicode: unicode,
      remainingInSegment: segments * limit - units,
    );
  }
}
