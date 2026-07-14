// test/services/settings_repository_test.dart
// Phase 2.5 — SQLite Settings Repository Integration Tests
// Generated: 21 Jun 2026

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SqliteSettingsRepository Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late SqliteSettingsRepository settingsRepo;

    setUp(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_settings_test.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();
      final gateway = DbGatewayImpl(databaseManager);
      settingsRepo = SqliteSettingsRepository(gateway);

      // Clean start: clear settings table
      await db.delete('settings');
    });

    tearDown(() async {
      await databaseManager.close();
    });

    test('getSettings - Should return default settings if table is empty',
        () async {
      final settings = await settingsRepo.getSettings();

      expect(settings, isNotNull);
      expect(settings.businessName, equals('Serenut POS'));
      expect(settings.printerPort, equals(9100));
      expect(settings.paperWidth, equals(80));
      expect(settings.printReceipt, isTrue);
      expect(settings.smsEnabled, isFalse);
    });

    test('updateSettings - Should persist changes and load updated settings',
        () async {
      // 1. Fetch initial settings (which inserts default row)
      final initial = await settingsRepo.getSettings();
      expect(initial.businessName, equals('Serenut POS'));

      // 2. Modify properties
      final modified = initial.copyWith(
        businessName: 'Super ERP Market',
        businessPhone: '+90-555-999-8877',
        businessAddress: 'Kadikoy, Istanbul',
        printerName: 'Epson TM-T20',
        printerIp: '192.168.1.150',
        paperWidth: 58,
        printCopies: 2,
        smsEnabled: true,
      );

      // 3. Save modifications
      await settingsRepo.updateSettings(modified);

      // 4. Fetch settings again and check values
      final updated = await settingsRepo.getSettings();
      expect(updated.businessName, equals('Super ERP Market'));
      expect(updated.businessPhone, equals('+90-555-999-8877'));
      expect(updated.businessAddress, equals('Kadikoy, Istanbul'));
      expect(updated.printerName, equals('Epson TM-T20'));
      expect(updated.printerIp, equals('192.168.1.150'));
      expect(updated.paperWidth, equals(58));
      expect(updated.printCopies, equals(2));
      expect(updated.smsEnabled, isTrue);
    });
  });
}
