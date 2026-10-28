import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Schema Contract Verification — Single Source of Truth', () {
    late Database db;
    late Map<String, dynamic> contract;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      final manager = DatabaseManager();
      db = await manager.getDatabase();

      final contractFile = File('shared/schema_contract.json');
      expect(contractFile.existsSync(), isTrue,
          reason: 'shared/schema_contract.json must exist');
      contract = jsonDecode(contractFile.readAsStringSync()) as Map<String, dynamic>;
    });

    tearDown(() async {
      await db.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    test('SQLite tables conform to single-source-of-truth nullability invariants', () async {
      final entities = contract['entities'] as Map<String, dynamic>;

      for (final entry in entities.entries) {
        final entityName = entry.key;
        final entityDef = entry.value as Map<String, dynamic>;
        final tableName = entityDef['table_sqlite'] as String;
        final columns = entityDef['columns'] as Map<String, dynamic>;

        final pragmaRows = await db.rawQuery('PRAGMA table_info($tableName)');
        expect(pragmaRows.isNotEmpty, isTrue,
            reason: 'Table "$tableName" for entity "$entityName" must exist in SQLite.');

        final colMap = <String, Map<String, dynamic>>{};
        for (final row in pragmaRows) {
          colMap[row['name'].toString()] = row;
        }

        for (final colEntry in columns.entries) {
          final colName = colEntry.key;
          final colDef = colEntry.value as Map<String, dynamic>;
          final isNullableInContract = colDef['nullable'] == true;

          expect(colMap.containsKey(colName), isTrue,
              reason: 'Column "$colName" in entity "$entityName" must exist in SQLite table "$tableName".');

          final actualCol = colMap[colName]!;
          final isNotNullInSqlite = actualCol['notnull'] == 1;
          final hasDefaultInSqlite = actualCol['dflt_value'] != null;

          if (isNullableInContract) {
            expect(
              !isNotNullInSqlite || hasDefaultInSqlite,
              isTrue,
              reason: 'CONTRACT VIOLATION in "$tableName.$colName": '
                  'The contract specifies this column is nullable, but SQLite defines it as NOT NULL without a DEFAULT. '
                  'This would trigger a NOT NULL constraint violation during sync.',
            );
          }
        }
      }
    });

    test('sales table permits anonymous walk-in sales with null customer_id', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('sales', {
        'id': 'sale-walkin-test-1',
        'customer_id': null, // Must not violate NOT NULL constraint!
        'receipt_no': 'REC-001',
        'total_amount': 50.0,
        'paid_amount': 50.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': now,
        'updated_at': now,
      });

      final rows = await db.query('sales', where: 'id = ?', whereArgs: ['sale-walkin-test-1']);
      expect(rows.length, 1);
      expect(rows.first['customer_id'], isNull);
    });

    test('financial_transactions table permits expense/income without customer_id', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('financial_transactions', {
        'id': 'tx-expense-test-1',
        'type': 'expense',
        'customer_id': null, // General expenses do not have a customer!
        'amount': 120.0,
        'paid_amount': 120.0,
        'debt_amount': 0.0,
        'payment_method': 'cash',
        'created_at': now,
      });

      final rows = await db.query('financial_transactions', where: 'id = ?', whereArgs: ['tx-expense-test-1']);
      expect(rows.length, 1);
      expect(rows.first['customer_id'], isNull);
    });

    test('orders table permits walk-in orders with null customer_id', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('orders', {
        'id': 'order-walkin-test-1',
        'order_number': 'ORD-TEST-999',
        'customer_id': null,
        'status': 'created',
        'total_amount': 100.0,
        'created_at': now,
        'updated_at': now,
      });

      final rows = await db.query('orders', where: 'id = ?', whereArgs: ['order-walkin-test-1']);
      expect(rows.length, 1);
      expect(rows.first['customer_id'], isNull);
    });
  });
}
