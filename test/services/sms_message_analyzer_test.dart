import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/sms_message_analyzer.dart';

void main() {
  const analyzer = SmsMessageAnalyzer();

  test('calculates GSM single and multipart segments', () {
    expect(analyzer.analyze('a' * 160).segments, 1);
    expect(analyzer.analyze('a' * 161).segments, 2);
  });

  test('uses UCS-2 limits for Turkish characters outside GSM alphabet', () {
    final result = analyzer.analyze('ş' * 71);
    expect(result.unicode, isTrue);
    expect(result.segments, 2);
  });

  test('counts GSM extension characters as two septets', () {
    final result = analyzer.analyze('€' * 81);
    expect(result.unicode, isFalse);
    expect(result.segments, 2);
  });
}
