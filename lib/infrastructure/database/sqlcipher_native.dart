// lib/infrastructure/database/sqlcipher_native.dart
// Native VM-specific implementation of SQLCipher & FFI.

import 'dart:ffi';
import 'dart:io' show Platform, File;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as ffi_sqlite;
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart';

bool _sqlCipherTested = false;
bool _isSqlCipherAvailable = false;

bool isSqlCipherAvailableOnWindows() {
  if (!Platform.isWindows) return true;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
  return _isSqlCipherAvailable;
}

void initSqfliteFfiForTest() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    ffi.sqfliteFfiInit();
  }
}

void initWindowsSqlCipherSync() {
  if (!Platform.isWindows || _sqlCipherTested) return;
  try {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final sqlCipherDll = File(join(appDir, 'sqlcipher.dll'));
    if (sqlCipherDll.existsSync()) {
      open.overrideFor(OperatingSystem.windows, () {
        return DynamicLibrary.open(sqlCipherDll.path);
      });
    }
    
    final testDb = ffi_sqlite.sqlite3.openInMemory();
    final result = testDb.select('PRAGMA cipher_version');
    testDb.dispose();
    
    if (result.isNotEmpty && result.first.values.first != null) {
      final version = result.first.values.first.toString();
      if (version.isNotEmpty) {
        _isSqlCipherAvailable = true;
        debugPrint('SQLCipher detected on Windows: Version $version');
      }
    }
  } catch (_) {
    // Fallback silently to standard sqlite3
  } finally {
    _sqlCipherTested = true;
  }
}

Future<Database> openFfiDb(
  String path, {
  String? password,
  int? version,
  OnDatabaseConfigureFn? onConfigure,
  OnDatabaseCreateFn? onCreate,
  OnDatabaseVersionChangeFn? onUpgrade,
  bool readOnly = false,
  bool singleInstance = true,
}) {
  return ffi.databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (db) async {
        if (password != null && password.isNotEmpty) {
          final escaped = password.replaceAll("'", "''");
          await db.execute("PRAGMA key = '$escaped'");
        }
        if (onConfigure != null) {
          await onConfigure(db);
        }
      },
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      readOnly: readOnly,
      singleInstance: singleInstance,
    ),
  );
}

Future<String> getFfiDatabasesPath() {
  return ffi.databaseFactoryFfi.getDatabasesPath();
}
