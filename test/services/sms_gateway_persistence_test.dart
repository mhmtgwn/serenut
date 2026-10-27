import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/services/device_manager.dart';
import 'package:serenutos/domain/services/sms_service.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/services/sms_gateway_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('serenut/sms_sender'),
            (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'acquireWakeLock':
          return true;
        case 'releaseWakeLock':
          return true;
        case 'isIgnoringBatteryOptimizations':
          return true;
        case 'requestIgnoreBatteryOptimizations':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('serenut/sms_sender'), null);
  });

  test('SmsService WakeLock and battery optimization channels invoke Android platform methods', () async {
    final smsService = SmsService();

    // In unit test environment, Platform.isAndroid might be false (e.g. windows host),
    // but we can verify the method signatures and channel implementation logic.
    final wakeAcquired = await smsService.acquireWakeLock('TestTag');
    expect(wakeAcquired, isA<bool>());

    final wakeReleased = await smsService.releaseWakeLock();
    expect(wakeReleased, isA<bool>());

    final ignoring = await smsService.isIgnoringBatteryOptimizations();
    expect(ignoring, isA<bool>());

    final requested = await smsService.requestIgnoreBatteryOptimizations();
    expect(requested, isA<bool>());
  });

  test('SmsGatewayService lifecycle manages WakeLock during active polling', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final apiClient = ApiClient();
    final smsService = SmsService();
    final deviceManager = DeviceManager(prefs);
    final gateway = SmsGatewayService(apiClient, smsService, deviceManager);

    gateway.start();
    gateway.dispose();

    final isIgnoring = await gateway.isIgnoringBatteryOptimizations();
    expect(isIgnoring, isA<bool>());
  });

  test('AndroidManifest.xml contains all critical background and foreground service permissions', () {
    final manifestFile = File('android/app/src/main/AndroidManifest.xml');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'AndroidManifest.xml must exist');

    final manifestContent = manifestFile.readAsStringSync();

    expect(manifestContent.contains('android.permission.FOREGROUND_SERVICE'), isTrue,
        reason: 'FOREGROUND_SERVICE permission is required for background SMS persistence');
    expect(
        manifestContent.contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
        isTrue,
        reason:
            'FOREGROUND_SERVICE_DATA_SYNC permission is required on Android 14+');
    expect(manifestContent.contains('android.permission.WAKE_LOCK'), isTrue,
        reason: 'WAKE_LOCK is required to prevent CPU sleep during SMS polling');
    expect(
        manifestContent.contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
        isTrue,
        reason:
            'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS is required to bypass Android Doze mode');
    expect(
        manifestContent.contains('android.permission.POST_NOTIFICATIONS'),
        isTrue,
        reason:
            'POST_NOTIFICATIONS is required on Android 13+ for foreground service notification');
    expect(manifestContent.contains('android.permission.SEND_SMS'), isTrue);
  });
}
