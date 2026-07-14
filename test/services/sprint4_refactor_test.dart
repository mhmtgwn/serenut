// test/services/sprint4_refactor_test.dart
// Sprint 4 Verification Tests: Single-Source-of-Truth Settings & Audit Logs
// Covers: DB migration v22, settings CRUD, AuditLogger SQLite writes, notifier reactivity

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';

import 'dart:io';

/// Helper: creates a fresh in-memory DatabaseManager for each test.
Future<DatabaseManager> _createInMemoryDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = Directory.systemTemp.createTempSync();
  final dbPath =
      '${tempDir.path}/test_db_${DateTime.now().microsecondsSinceEpoch}.db';
  final mgr = DatabaseManager();
  await mgr
      .close(); // Crucial: clear cached connection in the DatabaseManager singleton
  DatabaseManager.overrideDatabasePath = dbPath;
  await mgr.getDatabase(); // triggers onCreate
  return mgr;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() {
    DatabaseManager.overrideDatabasePath = null;
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1: Database Migration v22 — new columns exist
  // ──────────────────────────────────────────────────────────────────────────
  group('DB Migration v22 — new columns in settings table', () {
    test('Fresh install: settings row has all 9 new Sprint 4 columns',
        () async {
      final mgr = await _createInMemoryDb();
      final db = await mgr.getDatabase();
      final rows = await db.query('settings');
      expect(rows, isNotEmpty, reason: 'Default settings row should be seeded');
      final row = rows.first;

      expect(row.containsKey('sound_notification_enabled'), isTrue);
      expect(row.containsKey('sms_auto_debt_reminder_enabled'), isTrue);
      expect(row.containsKey('sms_auto_debt_reminder_days'), isTrue);
      expect(row.containsKey('sms_auto_debt_reminder_min_amount'), isTrue);
      expect(row.containsKey('label_printer_enabled'), isTrue);
      expect(row.containsKey('label_printer_ip'), isTrue);
      expect(row.containsKey('label_printer_port'), isTrue);
      expect(row.containsKey('label_printer_copies'), isTrue);
      expect(row.containsKey('admin_pin_code'), isTrue);
    });

    test('Fresh install: default values for new columns are correct', () async {
      final mgr = await _createInMemoryDb();
      final db = await mgr.getDatabase();
      final row = (await db.query('settings')).first;

      expect(row['sound_notification_enabled'], equals(0));
      expect(row['sms_auto_debt_reminder_enabled'], equals(0));
      expect(row['sms_auto_debt_reminder_days'], equals(15));
      expect(row['sms_auto_debt_reminder_min_amount'], closeTo(100.0, 0.001));
      expect(row['label_printer_enabled'], equals(0));
      expect(row['label_printer_port'], equals(9100));
      expect(row['label_printer_copies'], equals(1));
      expect(row['admin_pin_code'], isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2: Settings CRUD — round-trip through repository
  // ──────────────────────────────────────────────────────────────────────────
  group('Settings Repository CRUD with new Sprint 4 fields', () {
    test('getSettings() returns defaults for new fields', () async {
      final mgr = await _createInMemoryDb();
      final gateway = DbGatewayImpl(mgr);
      final repo = SqliteSettingsRepository(gateway);
      final settings = await repo.getSettings();

      expect(settings.soundNotificationEnabled, isFalse);
      expect(settings.smsAutoDebtReminderEnabled, isFalse);
      expect(settings.smsAutoDebtReminderDays, equals(15));
      expect(settings.smsAutoDebtReminderMinAmount, closeTo(100.0, 0.001));
      expect(settings.labelPrinterEnabled, isFalse);
      expect(settings.labelPrinterPort, equals(9100));
      expect(settings.labelPrinterCopies, equals(1));
      expect(settings.adminPinCode, isNull);
    });

    test('updateSettings() persists new Sprint 4 fields to SQLite', () async {
      final mgr = await _createInMemoryDb();
      final gateway = DbGatewayImpl(mgr);
      final repo = SqliteSettingsRepository(gateway);

      final original = await repo.getSettings();
      final updated = original.copyWith(
        soundNotificationEnabled: true,
        smsAutoDebtReminderEnabled: true,
        smsAutoDebtReminderDays: 30,
        smsAutoDebtReminderMinAmount: 250.0,
        labelPrinterEnabled: true,
        labelPrinterIp: '192.168.1.99',
        labelPrinterPort: 9200,
        labelPrinterCopies: 3,
        adminPinCode: 'hashed_pin_value',
      );
      await repo.updateSettings(updated);

      final reloaded = await repo.getSettings();
      expect(reloaded.soundNotificationEnabled, isTrue);
      expect(reloaded.smsAutoDebtReminderEnabled, isTrue);
      expect(reloaded.smsAutoDebtReminderDays, equals(30));
      expect(reloaded.smsAutoDebtReminderMinAmount, closeTo(250.0, 0.001));
      expect(reloaded.labelPrinterEnabled, isTrue);
      expect(reloaded.labelPrinterIp, equals('192.168.1.99'));
      expect(reloaded.labelPrinterPort, equals(9200));
      expect(reloaded.labelPrinterCopies, equals(3));
      expect(reloaded.adminPinCode, equals('hashed_pin_value'));
    });

    test('copyWith(adminPinCode: null) clears the PIN', () async {
      final mgr = await _createInMemoryDb();
      final gateway = DbGatewayImpl(mgr);
      final repo = SqliteSettingsRepository(gateway);

      final withPin =
          (await repo.getSettings()).copyWith(adminPinCode: 'some_hash');
      await repo.updateSettings(withPin);

      // Verify PIN is stored
      final loaded = await repo.getSettings();
      expect(loaded.adminPinCode, equals('some_hash'));

      // Now clear it
      final withoutPin = loaded.copyWith(adminPinCode: null);
      await repo.updateSettings(withoutPin);

      final cleared = await repo.getSettings();
      expect(cleared.adminPinCode, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3: AuditLogger — writes to SQLite audit_logs table
  // ──────────────────────────────────────────────────────────────────────────
  group('AuditLogger — SQLite audit_logs table', () {
    test('logAction() inserts a row into audit_logs', () async {
      final mgr = await _createInMemoryDb();
      final logger = AuditLogger(mgr);

      await logger.logAction(
        action: 'test_action',
        beforeState: '{"amount": 0}',
        afterState: '{"amount": 100}',
        metadata: {'user': 'admin'},
      );

      final logs = await logger.getLogs();
      expect(logs, hasLength(1));
      expect(logs.first['action'], equals('test_action'));
      expect(logs.first['beforeState'], contains('amount'));
    });

    test('getLogs() returns entries in reverse chronological order', () async {
      final mgr = await _createInMemoryDb();
      final logger = AuditLogger(mgr);

      for (int i = 1; i <= 3; i++) {
        await logger.logAction(
          action: 'action_$i',
          beforeState: '',
          afterState: '',
        );
        // Small delay to get distinct timestamps
        await Future.delayed(const Duration(milliseconds: 5));
      }

      final logs = await logger.getLogs();
      expect(logs.length, greaterThanOrEqualTo(3));
      // Most recent first
      expect(logs.first['action'], equals('action_3'));
      expect(logs.last['action'], equals('action_1'));
    });

    test('logAction() is non-fatal on closed database', () async {
      final mgr = await _createInMemoryDb();
      final logger = AuditLogger(mgr);
      await mgr.close();

      // Should not throw
      await expectLater(
        logger.logAction(action: 'test', beforeState: '', afterState: ''),
        completes,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4: Settings model — copyWith sentinel correctness
  // ──────────────────────────────────────────────────────────────────────────
  group('Settings.copyWith — sentinel null handling', () {
    test('copyWith without adminPinCode preserves existing value', () {
      final s = Settings(
        businessName: 'Test',
        businessPhone: '123',
        businessAddress: 'Address',
        adminPinCode: 'existing_hash',
      );
      final updated = s.copyWith(soundNotificationEnabled: true);
      expect(updated.adminPinCode, equals('existing_hash'));
    });

    test('copyWith(adminPinCode: null) explicitly clears the PIN', () {
      final s = Settings(
        businessName: 'Test',
        businessPhone: '123',
        businessAddress: 'Address',
        adminPinCode: 'existing_hash',
      );
      final cleared = s.copyWith(adminPinCode: null);
      expect(cleared.adminPinCode, isNull);
    });

    test('Settings.fromMap correctly parses all 9 new fields', () {
      final map = {
        'id': 1,
        'business_name': 'Test',
        'business_phone': '',
        'business_address': '',
        'owner_name': '',
        'business_email': '',
        'business_city': '',
        'business_district': '',
        'business_type': '',
        'currency': '₺',
        'printer_port': 9100,
        'paper_width': 80,
        'print_receipt': 1,
        'print_qr_code': 0,
        'print_product_details': 1,
        'print_barcode': 0,
        'print_copies': 1,
        'vat_categories': '[]',
        'sms_enabled': 0,
        'qr_enabled': 0,
        'qr_format': '',
        'debug_mode': 0,
        'created_at': DateTime.now().toIso8601String(),
        'sound_notification_enabled': 1,
        'sms_auto_debt_reminder_enabled': 1,
        'sms_auto_debt_reminder_days': 7,
        'sms_auto_debt_reminder_min_amount': 50.5,
        'label_printer_enabled': 1,
        'label_printer_ip': '10.0.0.1',
        'label_printer_port': 9200,
        'label_printer_copies': 2,
        'admin_pin_code': 'test_hash',
      };
      final s = Settings.fromMap(map);
      expect(s.soundNotificationEnabled, isTrue);
      expect(s.smsAutoDebtReminderEnabled, isTrue);
      expect(s.smsAutoDebtReminderDays, equals(7));
      expect(s.smsAutoDebtReminderMinAmount, closeTo(50.5, 0.001));
      expect(s.labelPrinterEnabled, isTrue);
      expect(s.labelPrinterIp, equals('10.0.0.1'));
      expect(s.labelPrinterPort, equals(9200));
      expect(s.labelPrinterCopies, equals(2));
      expect(s.adminPinCode, equals('test_hash'));
    });
  });
}
