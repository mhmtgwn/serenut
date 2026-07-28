import 'dart:async';
import 'dart:convert';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_executor.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

class SqliteSettingsRepository implements ISettingsRepository {
  final DbGateway _gateway;

  SqliteSettingsRepository(this._gateway);

  DbExecutor get _executor => _gateway;

  @override
  Future<Settings> getSettings() async {
    final rows = await _executor.query('settings', limit: 1);
    if (rows.isEmpty) {
      final defaultSettings = Settings(
        businessName: 'Serenut OS',
        businessPhone: '+90-555-xxx-xxxx',
        businessAddress: 'Istanbul, Turkiye',
        currency: '₺',
        printerPort: 9100,
        paperWidth: 80,
        printReceipt: true,
        printQRCode: false,
        printProductDetails: true,
        printBarcode: false,
        printCopies: 1,
        vatCategories: '[]',
        smsEnabled: false,
        qrEnabled: false,
        qrFormat: 'type|id|timestamp|customerId|amount|hash',
        debugMode: false,
        createdAt: DateTime.now(),
      );
      final id = await _executor.insert('settings', defaultSettings.toMap());
      return defaultSettings.copyWith(id: id);
    }
    return Settings.fromMap(rows.first);
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    final rows = await _executor.query('settings', limit: 1);
    if (rows.isEmpty) {
      await _executor.insert('settings', settings.toMap());
    } else {
      final existingId = rows.first['id'] as int;
      await _executor.update(
        'settings',
        {
          ...settings.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
    }
  }
}

class SharedPreferencesSettingsRepository implements ISettingsRepository {
  final dynamic _prefs;
  static const _key = 'serenut_web_settings_json';

  SharedPreferencesSettingsRepository(this._prefs);

  @override
  Future<Settings> getSettings() async {
    final raw = _prefs.getString(_key) as String?;
    if (raw != null) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        return Settings.fromMap(map);
      } catch (_) {}
    }
    return Settings(
      businessName: 'Serenut OS',
      businessPhone: '+90-555-xxx-xxxx',
      businessAddress: 'Istanbul, Turkiye',
      currency: '₺',
      printerPort: 9100,
      paperWidth: 80,
      printReceipt: true,
      printQRCode: false,
      printProductDetails: true,
      printBarcode: false,
      printCopies: 1,
      vatCategories: '[]',
      smsEnabled: false,
      qrEnabled: false,
      qrFormat: 'type|id|timestamp|customerId|amount|hash',
      debugMode: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    await _prefs.setString(_key, jsonEncode(settings.toMap()));
  }
}
