import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/license_model.dart';
import 'package:serenutos/domain/services/license_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/infrastructure/realtime/websocket_manager.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/rsa_test_keys.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Sprint D license recovery and multi-device realtime acceptance',
      () async {
    DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
    final databaseManager = DatabaseManager();
    addTearDown(() async {
      await databaseManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final keys = RsaTestKeys.generate();
    final service = LicenseService(prefs, rsaModulus: keys.modulus);
    final manager = LicenseManager(service);
    expect(manager.isLockedDown, isTrue);

    final expiry = DateTime.now().add(const Duration(days: 30)).toUtc();
    final payload = jsonEncode({
      'allowed_devices': [service.getDeviceUuid()],
      'expiry_date': expiry.toIso8601String(),
      'features': ['realtime'],
      'merchant_id': 'sprint-d-company',
      'tier': 'pro',
    });
    final token = base64Encode(utf8.encode(jsonEncode(LicenseInfo(
      merchantId: 'sprint-d-company',
      allowedDevices: [service.getDeviceUuid()],
      expiryDate: expiry,
      tier: LicenseTier.pro,
      features: const ['realtime'],
      signature: base64Encode(keys.sign(utf8.encode(payload))),
    ).toJson())));
    expect(await manager.recoverLicense(token), isTrue);
    expect(manager.isLockedDown, isFalse);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final serverSubscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((message) {
        for (final peer in List<WebSocket>.from(sockets)) {
          peer.add(message);
        }
      });
    });
    addTearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    final first = WebSocketManager();
    final second = WebSocketManager();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final firstReady = first.connectionEvents
        .firstWhere((event) => event.type == 'handshake_succeeded');
    final secondReady = second.connectionEvents
        .firstWhere((event) => event.type == 'handshake_succeeded');
    final stopwatch = Stopwatch()..start();
    final url = 'ws://${server.address.address}:${server.port}';
    first.connect(url);
    second.connect(url);
    await Future.wait([firstReady, secondReady])
        .timeout(const Duration(seconds: 3));
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));

    final received = second.messages.first;
    first.send('{"type":"inventory.updated","device":"first"}');
    expect(await received.timeout(const Duration(seconds: 2)),
        contains('inventory.updated'));
  });
}
