// lib/infrastructure/database/sqlcipher_stub.dart
// Stub implementation of SQLCipher and Sqlite FFI check for web build compatibility.

import 'package:sqflite_sqlcipher/sqflite.dart';

void initWindowsSqlCipherSync() {}

bool isSqlCipherAvailableOnWindows() => true;

void initSqfliteFfiForTest() {}

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
  throw UnsupportedError('FFI database is not supported on web.');
}

Future<String> getFfiDatabasesPath() {
  throw UnsupportedError('FFI database is not supported on web.');
}
