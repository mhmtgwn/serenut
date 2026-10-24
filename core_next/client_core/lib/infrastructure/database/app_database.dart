// core_next/client_core/lib/infrastructure/database/app_database.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'schema_definitions.dart';

class CoreAppDatabase {
  final Database db;

  const CoreAppDatabase(this.db);

  static Future<int> _readUserVersion(String path) async {
    final file = File(path);
    if (!await file.exists()) return 0;
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        if (await raf.length() >= 64) {
          await raf.setPosition(60);
          final bytes = await raf.read(4);
          if (bytes.length == 4) {
            return ByteData.sublistView(bytes).getUint32(0, Endian.big);
          }
        }
      } finally {
        await raf.close();
      }
    } catch (_) {}
    return 0;
  }

  /// Yeni nesil temiz veritabanını başlatır.
  /// 
  /// Standart, şifresiz sqflite motoru üzerinde WAL modu ve yabancı anahtar (FK)
  /// koruması tam açık olarak ayağa kalkar.
  static Future<CoreAppDatabase> open({
    String dbName = 'serenut_core_v2.db',
    String? inMemoryOrCustomPath,
  }) async {
    final String path;
    if (inMemoryOrCustomPath != null) {
      path = inMemoryOrCustomPath;
    } else {
      final databasesPath = await getDatabasesPath();
      path = p.join(databasesPath, dbName);
    }

    // Şema sınırı koruması: Legacy veritabanı dosyalarının Core Next olarak açılmasını engelle
    if (path != inMemoryDatabasePath) {
      final file = File(path);
      if (await file.exists() && await file.length() >= 64) {
        final userVersion = await _readUserVersion(path);
        if (userVersion > CoreSchemaDefinitions.schemaVersion) {
          throw IncompatibleDatabaseSchemaException(
            'CoreAppDatabase şema sınırı ihlali: "$path" dosyasının legacy şemaya ait olduğu tespit edildi (user_version: $userVersion > ${CoreSchemaDefinitions.schemaVersion}). '
            'CoreAppDatabase legacy veritabanlarını açamaz; bu dosya DatabaseManager ile açılmalıdır.',
          );
        }
      }
    }

    final database = await openDatabase(
      path,
      version: CoreSchemaDefinitions.schemaVersion,
      onConfigure: (db) async {
        // Yabancı anahtar (Foreign Key) bütünlüğünü zorunlu kıl
        await db.execute('PRAGMA foreign_keys = ON;');
        // Eşzamanlı yazma/okuma kilitlemelerini önlemek için WAL modu
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL;');
          await db.execute('PRAGMA synchronous = NORMAL;');
          await db.execute('PRAGMA busy_timeout = 30000;');
        } catch (_) {
          // Bellek içi veya özel platform fallback
        }
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final query in CoreSchemaDefinitions.createTablesQueries) {
          batch.execute(query);
        }
        for (final query in CoreSchemaDefinitions.createIndexesQueries) {
          batch.execute(query);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await CoreSchemaDefinitions.migrate(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        final legacyTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('financial_transactions', 'sms_logs')",
        );
        if (legacyTables.isNotEmpty) {
          throw IncompatibleDatabaseSchemaException(
            'CoreAppDatabase şema sınırı ihlali: Veritabanında legacy tablolar (${legacyTables.map((r) => r['name']).join(', ')}) tespit edildi.',
          );
        }
      },
    );

    return CoreAppDatabase(database);
  }

  /// Tüm işlemleri tek bir ACID transaction içinde çalıştırır.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) {
    return db.transaction(action);
  }

  /// Veritabanı okuma sorgusu delegasyonu
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  /// Veritabanını güvenle kapatır.
  Future<void> close() => db.close();
}
