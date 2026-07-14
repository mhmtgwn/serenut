// lib/infrastructure/services/bootstrap_sync_service.dart
// Serenut OS — Initial Bootstrap Sync Service (Sprint 2)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../infrastructure/network/api_client.dart';
import '../../infrastructure/database/database_provider.dart';

class BootstrapSyncService {
  final SharedPreferences _prefs;
  final ApiClient _apiClient;

  static const String _bootstrapIndexKey = 'nutopiano_bootstrap_index';
  static const String _bootstrapCompletedKey = 'nutopiano_bootstrap_completed';

  final List<String> _modules = [
    'company',
    'stores',
    'users',
    'categories',
    'products',
    'customers',
    'payment-types',
    'tax-rates',
    'settings',
    'printer-config',
    'license-config',
  ];

  BootstrapSyncService(this._prefs, this._apiClient);

  bool isCompleted() {
    return _prefs.getBool(_bootstrapCompletedKey) ?? false;
  }

  int getProgressIndex() {
    return _prefs.getInt(_bootstrapIndexKey) ?? 0;
  }

  Future<void> resetBootstrap() async {
    await _prefs.remove(_bootstrapIndexKey);
    await _prefs.remove(_bootstrapCompletedKey);
  }

  /// Run bootstrap sync, updating state via [onProgress]
  Future<void> runBootstrap(
      Function(double progress, String statusText) onProgress) async {
    if (isCompleted()) {
      onProgress(100.0, 'Hazır');
      return;
    }

    final db = await DatabaseManager().getDatabase();

    if (_prefs.getBool('serenut_pending_company_patch') == true) {
      try {
        final settingsRows = await db.query('settings', limit: 1);
        if (settingsRows.isNotEmpty) {
          final row = settingsRows.first;
          final profileRows = await db.query('business_profile', limit: 1);
          int expectedVersion = 1;
          if (profileRows.isNotEmpty) {
            expectedVersion = profileRows.first['version'] as int? ?? 1;
          }

          final response = await _apiClient.send(
            'PATCH',
            '/api/v1/company',
            body: {
              'expected_version': expectedVersion,
              'name': row['business_name'],
              'phone': row['business_phone'],
              'address': row['business_address'],
              'owner_name': row['owner_name'],
              'type': row['business_type'],
              'city': row['business_city'],
              'district': row['business_district'],
              'currency': row['currency'],
              'logo_url': row['business_logo'],
            },
          );
          if (response.isSuccess) {
            final updatedMap = response.json as Map<String, dynamic>;
            final newVersion =
                updatedMap['version'] as int? ?? (expectedVersion + 1);
            await db.update(
              'business_profile',
              {
                'name': updatedMap['name'] ?? row['business_name'],
                'owner_name': updatedMap['owner_name'] ?? row['owner_name'],
                'type': updatedMap['type'] ?? row['business_type'],
                'phone': updatedMap['phone'] ?? row['business_phone'],
                'email': updatedMap['email'] ?? '',
                'tax_number': updatedMap['tax_number'] ?? '',
                'city': updatedMap['city'] ?? row['business_city'],
                'district': updatedMap['district'] ?? row['business_district'],
                'currency': updatedMap['currency'] ?? row['currency'],
                'version': newVersion,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [1],
            );
            await _prefs.setBool('serenut_pending_company_patch', false);
          }
        }
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          await _prefs.setBool('serenut_pending_company_patch', false);
          debugPrint(
              '[BootstrapSync] ⚠️ Settings patch version conflict: 409 returned.');
        }
      } catch (_) {}
    }

    int startIndex = getProgressIndex();

    for (int i = startIndex; i < _modules.length; i++) {
      final moduleName = _modules[i];
      final double progressPercentage = (i / _modules.length) * 100;

      onProgress(progressPercentage,
          '${_getFriendlyModuleName(moduleName)} yükleniyor...');

      final response = await _apiClient.get('/sync/bootstrap/$moduleName');
      if (!response.isSuccess) {
        throw Exception(
            'Bootstrap modülü yüklenemedi: $moduleName. HTTP ${response.statusCode}');
      }

      final resData = response.json;
      final payload = resData['data'];

      // Save module payloads to SQLite/SharedPreferences based on module type
      await _saveModuleData(db, moduleName, payload);

      // Save current step progress
      await _prefs.setInt(_bootstrapIndexKey, i + 1);
    }

    // Set as fully completed
    await _prefs.setBool(_bootstrapCompletedKey, true);
    onProgress(100.0, 'Tüm veriler başarıyla eşitlendi');
  }

  String _getFriendlyModuleName(String module) {
    switch (module) {
      case 'company':
        return 'Şirket Bilgileri';
      case 'stores':
        return 'Şube Bilgileri';
      case 'users':
        return 'Kullanıcılar';
      case 'categories':
        return 'Kategoriler';
      case 'products':
        return 'Ürün Katalogları';
      case 'customers':
        return 'Müşteri Kayıtları';
      case 'payment-types':
        return 'Ödeme Yöntemleri';
      case 'tax-rates':
        return 'KDV Tanımları';
      case 'settings':
        return 'Uygulama Ayarları';
      case 'printer-config':
        return 'Yazıcı Profilleri';
      case 'license-config':
        return 'Lisans Yetkileri';
      default:
        return 'Veriler';
    }
  }

  Future<void> _saveModuleData(
      Database db, String module, dynamic payload) async {
    await db.transaction((txn) async {
      if (module == 'company') {
        final map = payload as Map<String, dynamic>;
        final incomingName = map['name'] as String? ?? '';
        if (incomingName.trim().isEmpty) {
          debugPrint(
              '[BootstrapSync] ⚠️ Server returned empty company payload. Skipping local override.');
          return;
        }
        await txn.insert(
            'business_profile',
            {
              'id': 1,
              'name': map['name'] ?? '',
              'owner_name': map['owner_name'] ?? '',
              'type': map['type'] ?? '',
              'phone': map['phone'] ?? '',
              'email': map['email'] ?? '',
              'tax_number': map['tax_number'] ?? '',
              'city': map['city'] ?? '',
              'district': map['district'] ?? '',
              'currency': map['currency'] ?? '₺',
              'tax_included': 1,
              'version': map['version'] ?? 1,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        debugPrint('[Bootstrap] ✅ business_profile yazıldı: ${map['name']}');

        // Sync with settings table for settings screen
        try {
          await txn.execute('''
            UPDATE settings SET
              business_name = ?,
              business_phone = ?,
              business_address = ?,
              business_tax_id = ?,
              owner_name = ?,
              business_email = ?,
              business_city = ?,
              business_district = ?,
              business_type = ?,
              currency = ?
          ''', [
            map['name'] ?? '',
            map['phone'] ?? '',
            '${map['district'] ?? ''}, ${map['city'] ?? ''}',
            map['tax_number'] ?? '',
            map['owner_name'] ?? '',
            map['email'] ?? '',
            map['city'] ?? '',
            map['district'] ?? '',
            map['type'] ?? '',
            map['currency'] ?? '₺'
          ]);
          debugPrint(
              '[Bootstrap] ✅ settings.business_name güncellendi: ${map['name']}');
        } catch (e) {
          // Non-fatal: settings table sync after company bootstrap failed.
          // Business profile data is still saved to business_profile table above.
          debugPrint(
              '[BootstrapSync] ⚠️ Settings sync after company bootstrap failed: $e');
        }
      } else if (module == 'stores') {
        // Store details inside business_profile or local storage
        if (payload is List && payload.isNotEmpty) {
          final firstStore = payload.first as Map<String, dynamic>;
          await _prefs.setString(
              'nutopiano_store_name', firstStore['name'] ?? '');
          await _prefs.setString('nutopiano_store_id', firstStore['id'] ?? '');
        }
      } else if (module == 'users') {
        final list = payload as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final userId = map['id'] as String;

          final existing = await txn.query(
            'users',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [userId],
          );

          if (existing.isNotEmpty) {
            await txn.update(
              'users',
              {
                'name': map['name'],
                'email': map['email'],
                'password_hash':
                    map['password_hash'] ?? 'pbkdf2_sha256\$dummy_hash',
                'role': map['role'] ?? 'cashier',
                'is_active': map['is_active'] ? 1 : 0,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [userId],
            );
          } else {
            await txn.insert('users', {
              'id': userId,
              'name': map['name'],
              'email': map['email'],
              'password_hash':
                  map['password_hash'] ?? 'pbkdf2_sha256\$dummy_hash',
              'role': map['role'] ?? 'cashier',
              'is_active': map['is_active'] ? 1 : 0,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
              'username': null,
              'pin_hash': null,
              'business_code': null,
              'device_token_version': 1,
              'failed_pin_attempts': 0,
              'locked_until': null,
            });
          }
        }
      } else if (module == 'categories') {
        final list = payload as List<dynamic>;
        final categoriesStrList = list.map((e) => e.toString()).toList();
        await _prefs.setStringList('nutopiano_categories', categoriesStrList);
      } else if (module == 'products') {
        final list = payload as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          await txn.insert(
              'products',
              {
                'id': map['id'],
                'name': map['name'],
                'description': map['description'] ?? '',
                'price': (map['price'] as num?)?.toDouble() ?? 0.0,
                'quantity': (map['quantity'] as num?)?.toInt() ?? 0,
                'category': map['category'] ?? 'Genel',
                'sku': map['sku'] ?? map['id'],
                'vat': (map['vat'] as num?)?.toInt() ?? 18,
                'is_active': map['status'] == 'active' ? 1 : 0,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'image_url': map['image_path'] ?? '',
                'is_deleted': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else if (module == 'customers') {
        final list = payload as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          await txn.insert(
              'customers',
              {
                'id': map['id'],
                'name': map['name'],
                'email': map['email'] ?? '',
                'phone': map['phone'] ?? '',
                'balance': (map['balance'] as num?)?.toDouble() ?? 0.0,
                'credit_limit':
                    (map['credit_limit'] as num?)?.toDouble() ?? 0.0,
                'status': map['status'] ?? 'active',
                'is_active': 1,
                'created_at': DateTime.now().toIso8601String(),
                'updated_at': DateTime.now().toIso8601String(),
                'is_deleted': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else if (module == 'payment-types') {
        final list = payload as List<dynamic>;
        final paymentsStrList = list.map((e) => e.toString()).toList();
        await _prefs.setStringList('nutopiano_payment_types', paymentsStrList);
      } else if (module == 'tax-rates') {
        final list = payload as List<dynamic>;
        final taxRatesList = list.map((e) => e.toString()).toList();
        await _prefs.setStringList('nutopiano_tax_rates', taxRatesList);
      } else if (module == 'settings') {
        final map = payload as Map<String, dynamic>;
        final incomingName =
            (map['business_name'] ?? map['businessName']) as String? ?? '';
        if (incomingName.trim().isEmpty) {
          debugPrint(
              '[BootstrapSync] ⚠️ Server returned empty settings payload. Skipping local override.');
          return;
        }
        // Write directly to SQLite settings table (single source of truth)
        final existing = await txn.query('settings', limit: 1);
        if (existing.isEmpty) {
          await txn.insert('settings', {
            'business_name': map['business_name'] ?? map['businessName'] ?? '',
            'business_phone':
                map['business_phone'] ?? map['businessPhone'] ?? '',
            'business_address':
                map['business_address'] ?? map['businessAddress'] ?? '',
            'currency': map['currency'] ?? '₺',
            'vat_categories':
                map['vat_categories'] ?? map['vatCategories'] ?? '[]',
            'qr_format': map['qr_format'] ??
                map['qrFormat'] ??
                'type|id|timestamp|customerId|amount|hash',
            'debug_mode':
                ((map['debug_mode'] ?? map['debugMode']) == true) ? 1 : 0,
            'created_at': DateTime.now().toIso8601String(),
          });
        } else {
          final existingId = existing.first['id'];
          await txn.update(
              'settings',
              {
                'business_name': map['business_name'] ??
                    map['businessName'] ??
                    existing.first['business_name'],
                'currency': map['currency'] ?? existing.first['currency'],
                'vat_categories': map['vat_categories'] ??
                    map['vatCategories'] ??
                    existing.first['vat_categories'],
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [existingId]);
        }
      } else if (module == 'printer-config') {
        final map = payload as Map<String, dynamic>;
        // Write printer config fields into the SQLite settings table
        final existing = await txn.query('settings', limit: 1);
        if (existing.isNotEmpty) {
          final existingId = existing.first['id'];
          await txn.update(
              'settings',
              {
                'printer_name': map['printer_name'] ?? map['printerName'],
                'printer_ip': map['printer_ip'] ?? map['printerIp'],
                'printer_port':
                    (map['printer_port'] ?? map['printerPort'] as num?)
                            ?.toInt() ??
                        9100,
                'paper_width': (map['paper_width'] ?? map['paperWidth'] as num?)
                        ?.toInt() ??
                    80,
                'print_receipt':
                    ((map['print_receipt'] ?? map['printReceipt']) == true)
                        ? 1
                        : 0,
                'print_copies':
                    (map['print_copies'] ?? map['printCopies'] as num?)
                            ?.toInt() ??
                        1,
                'updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [existingId]);
        }
      } else if (module == 'license-config') {
        final map = payload as Map<String, dynamic>;
        if (map['license_key'] != null) {
          await _prefs.setString(
              'activated_license_key', map['license_key'] as String);
        }
        if (map['license_token'] != null) {
          await _prefs.setString(
              'license_token', map['license_token'] as String);
          try {
            await txn.rawUpdate(
              'UPDATE settings SET license_token = ? WHERE id = 1',
              [map['license_token'] as String],
            );
          } catch (_) {}
        }
        await _prefs.setString('nutopiano_license_config', json.encode(map));
      }
    });
  }
}
