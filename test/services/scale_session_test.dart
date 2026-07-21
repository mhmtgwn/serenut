import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/hardware/hardware_status.dart';
import 'package:serenutos/domain/hardware/scale_service.dart';

void main() {
  ScaleReading reading(int sequence, int grams,
          {bool stable = true, DateTime? measuredAt}) =>
      ScaleReading(
        deviceId: 'test-scale',
        sequence: sequence,
        grossGrams: grams,
        stable: stable,
        measuredAt: measuredAt ?? DateTime.now(),
      );

  test('accepts only repeated stable readings inside tolerance', () {
    final session = ScaleSession(requiredStableSamples: 3);
    session.start(productId: 'tomato');

    session.addReading(reading(1, 1245));
    session.addReading(reading(2, 1247));
    expect(session.state, ScaleSessionState.measuring);

    session.addReading(reading(3, 1246));
    expect(session.state, ScaleSessionState.stable);
    expect(session.accept().netGrams, 1246);
    expect(session.state, ScaleSessionState.accepted);
  });

  test('does not accept moving or device-unstable weight', () {
    final session = ScaleSession(requiredStableSamples: 3);
    session.start(productId: 'tomato');
    session.addReading(reading(1, 1000));
    session.addReading(reading(2, 1030));
    session.addReading(reading(3, 1010, stable: false));

    expect(session.state, ScaleSessionState.measuring);
    expect(() => session.accept(), throwsA(isA<HardwareFailure>()));
  });

  test('requires scale to return to zero before next product', () {
    final session = ScaleSession(requiredStableSamples: 1);
    session.start(productId: 'tomato');
    session.addReading(reading(1, 500));
    session.accept();

    session.start(productId: 'pepper');
    expect(session.state, ScaleSessionState.waitingForZero);
    session.addReading(reading(2, 510));
    expect(session.state, ScaleSessionState.waitingForZero);

    session.addReading(reading(3, 0));
    session.addReading(reading(4, 300));
    expect(session.state, ScaleSessionState.stable);
  });

  test('ignores stale readings', () {
    final now = DateTime.now();
    final session = ScaleSession(requiredStableSamples: 1);
    session.start(productId: 'tomato');
    session.addReading(
      reading(1, 500, measuredAt: now.subtract(const Duration(seconds: 5))),
      now: now,
    );
    expect(session.state, ScaleSessionState.waitingForWeight);
  });
}
