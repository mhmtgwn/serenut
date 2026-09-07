// test/services/telemetry_provider_observer_test.dart
// Unit tests for TelemetryProviderObserver verifying automatic capture of Riverpod errors.

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/presentation/observers/telemetry_provider_observer.dart';

final failingFutureProvider = FutureProvider<String>((ref) async {
  throw Exception('Async failure inside FutureProvider');
});

class FailingStateNotifier extends StateNotifier<AsyncValue<int>> {
  FailingStateNotifier() : super(const AsyncValue.data(0));

  Future<void> triggerFailure() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      throw const FormatException('Guarded mutation failed');
    });
  }
}

final failingNotifierProvider =
    StateNotifierProvider<FailingStateNotifier, AsyncValue<int>>((ref) {
  return FailingStateNotifier();
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late TelemetryService telemetryService;

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('telemetry_obs_test');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    telemetryService = TelemetryService();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await telemetryService.clearLogs();
    telemetryService.onOperationalEvent = null;
  });

  test('captures unhandled provider failure via providerDidFail', () async {
    final forwarded = <TelemetryEvent>[];
    final completer = Completer<TelemetryEvent>();
    telemetryService.onOperationalEvent = (event) async {
      forwarded.add(event);
      if (!completer.isCompleted) completer.complete(event);
    };

    final container = ProviderContainer(
      observers: [TelemetryProviderObserver(telemetry: telemetryService)],
    );

    // Read failing future provider
    expect(
      () => container.read(failingFutureProvider.future),
      throwsA(isA<Exception>()),
    );

    await completer.future.timeout(const Duration(seconds: 3));

    expect(forwarded, isNotEmpty);
    expect(
      forwarded.any((e) =>
          e.metadata['error_message']?.toString().contains('Async failure') ==
          true),
      isTrue,
    );
    container.dispose();
  });

  test('captures AsyncError state changes via didUpdateProvider', () async {
    final forwarded = <TelemetryEvent>[];
    final completer = Completer<TelemetryEvent>();
    telemetryService.onOperationalEvent = (event) async {
      forwarded.add(event);
      if (!completer.isCompleted) completer.complete(event);
    };

    final container = ProviderContainer(
      observers: [TelemetryProviderObserver(telemetry: telemetryService)],
    );

    final notifier = container.read(failingNotifierProvider.notifier);
    await notifier.triggerFailure();

    await completer.future.timeout(const Duration(seconds: 3));

    expect(container.read(failingNotifierProvider).hasError, isTrue);
    expect(forwarded, isNotEmpty);
    expect(
      forwarded.any((e) =>
          e.metadata['error_message']?.toString().contains('Guarded mutation') ==
          true),
      isTrue,
    );
    container.dispose();
  });
}
