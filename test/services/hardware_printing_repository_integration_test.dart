import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/hardware/hardware_device.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_printing_repository.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/providers/hardware_devices_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('application bootstrap imports legacy printer registry before runtime',
      () async {
    SharedPreferences.setMockInitialValues({
      'hardware_device_registry_v1': jsonEncode([
        {
          'id': 'legacy-receipt',
          'name': 'Eski 58 mm Yazıcı',
          'type': 'receiptPrinter',
          'connection_type': 'tcp',
          'configuration': {
            'host': '192.168.1.20',
            'port': 9100,
            'paperWidth': 58,
          },
          'enabled': true,
          'status': 'unverified',
        }
      ]),
    });
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final gateway = DbGatewayImpl.raw(db);
    final container = ProviderContainer(overrides: [
      dbGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);

    final devices = await container.read(hardwareDevicesProvider.future);
    final migrated =
        await SqlitePrintingRepository(gateway).getDevice('legacy-receipt');

    expect(devices.map((device) => device.id), contains('legacy-receipt'));
    expect(migrated, isNotNull);
    expect(migrated!.capabilities['paperWidthMm'], 58);
    expect(
      (await SqlitePrintingRepository(gateway)
              .getRoute(PrintDocumentKind.receipt))
          ?.deviceId,
      'legacy-receipt',
    );
  });

  test('hardware cards read printers and active routes from SQLite', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final gateway = DbGatewayImpl.raw(db);
    final printing = SqlitePrintingRepository(gateway);
    final now = DateTime.utc(2026);
    for (final id in const ['receipt-a', 'receipt-b']) {
      await printing.saveDevice(PrinterDeviceProfile(
        id: id,
        name: id,
        language: PrinterLanguage.escPos,
        transport: PrinterTransportKind.tcp,
        transportConfig: {'host': '192.168.1.${id == 'receipt-a' ? 10 : 11}'},
        capabilities: const {'paperWidthMm': 58},
        enabled: true,
        createdAt: now,
        updatedAt: now,
      ));
    }
    await printing.saveRoute(PrinterRoute(
      kind: PrintDocumentKind.receipt,
      deviceId: 'receipt-a',
      designProfileId: 'receipt-default-v1',
      updatedAt: now,
    ));
    final container = ProviderContainer(overrides: [
      dbGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);

    final initial = await container.read(hardwareDevicesProvider.future);
    expect(initial, hasLength(2));
    expect(
      initial
          .singleWhere((device) => device.id == 'receipt-a')
          .configuration['activeFor'],
      ['receipt'],
    );

    final second = initial.singleWhere((device) => device.id == 'receipt-b');
    await container.read(hardwareDevicesProvider.notifier).activate(second);
    final route = await printing.getRoute(PrintDocumentKind.receipt);
    expect(route!.deviceId, 'receipt-b');
    expect(
      container
          .read(hardwareDevicesProvider)
          .requireValue
          .singleWhere((device) => device.id == 'receipt-b')
          .configuration['activeFor'],
      ['receipt'],
    );
  });

  test('saving printer physical settings no longer mutates legacy settings',
      () async {
    SharedPreferences.setMockInitialValues({});
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await DatabaseSchema.createTables(db);
    final gateway = DbGatewayImpl.raw(db);
    final container = ProviderContainer(overrides: [
      dbGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);

    await container.read(hardwareDevicesProvider.future);
    final legacyBefore = (await db.query('settings')).single;
    await container.read(hardwareDevicesProvider.notifier).save(
          const HardwareDevice(
            id: 'label-a',
            name: 'Etiket',
            type: HardwareDeviceType.labelPrinter,
            connectionType: HardwareConnectionType.tcp,
            configuration: {
              'host': '192.168.1.50',
              'port': 9100,
              'labelWidthMm': 50,
              'labelHeightMm': 30,
              'labelGapMm': 2,
              'dpi': 203,
            },
          ),
        );

    final profile =
        await SqlitePrintingRepository(gateway).getDevice('label-a');
    expect(profile!.capabilities['mediaWidthMm'], 50);
    final legacyAfter = (await db.query('settings')).single;
    for (final key in [
      'label_printer_enabled',
      'label_printer_ip',
      'label_width_mm',
      'active_label_printer_id',
    ]) {
      expect(legacyAfter[key], legacyBefore[key], reason: key);
    }
  });
}
