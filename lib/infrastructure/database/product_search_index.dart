import 'package:sqflite/sqflite.dart';

/// Optional FTS5 trigram index for contains-style catalog search.
/// Older Android SQLite builds may not ship FTS5; callers retain their LIKE fallback.
class ProductSearchIndex {
  static String _fold(String column) =>
      "LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE($column,''), 'İ', 'i'), 'I', 'i'), 'ı', 'i'), 'Ş', 's'), 'ş', 's'), 'Ç', 'c'), 'ç', 'c'), 'Ğ', 'g'), 'ğ', 'g'), 'Ü', 'u'), 'ü', 'u'), 'Ö', 'o'), 'ö', 'o'))";

  static Future<bool> ensure(DatabaseExecutor db,
      {bool rebuild = false}) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS product_search_fts USING fts5(
          id, name, description, brand, shelf_code, sku,
          tokenize='trigram'
        )
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS products_search_fts_ai AFTER INSERT ON products BEGIN
          DELETE FROM product_search_fts WHERE id=new.id;
          INSERT INTO product_search_fts(rowid,id,name,description,brand,shelf_code,sku)
          VALUES (new.rowid,new.id,${_fold('new.name')},${_fold('new.description')},${_fold('new.brand')},${_fold('new.shelf_code')},${_fold('new.sku')});
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS products_search_fts_ad AFTER DELETE ON products BEGIN
          DELETE FROM product_search_fts WHERE rowid=old.rowid;
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS products_search_fts_au AFTER UPDATE OF id,name,description,brand,shelf_code,sku ON products BEGIN
          DELETE FROM product_search_fts WHERE rowid=old.rowid;
          DELETE FROM product_search_fts WHERE id=new.id;
          INSERT INTO product_search_fts(rowid,id,name,description,brand,shelf_code,sku)
          VALUES (new.rowid,new.id,${_fold('new.name')},${_fold('new.description')},${_fold('new.brand')},${_fold('new.shelf_code')},${_fold('new.sku')});
        END
      ''');
      if (rebuild) {
        await db.execute('DELETE FROM product_search_fts');
        await db.execute('''
          INSERT INTO product_search_fts(rowid,id,name,description,brand,shelf_code,sku)
          SELECT rowid,id,${_fold('name')},${_fold('description')},${_fold('brand')},${_fold('shelf_code')},${_fold('sku')}
          FROM products
        ''');
      }
      return true;
    } catch (_) {
      // FTS5 trigram tokenizer is unavailable on some bundled/system SQLite builds.
      // Search remains correct through the repository's LIKE fallback.
      for (final trigger in const [
        'products_search_fts_ai',
        'products_search_fts_ad',
        'products_search_fts_au',
      ]) {
        try {
          await db.execute('DROP TRIGGER IF EXISTS $trigger');
        } catch (_) {}
      }
      try {
        await db.execute('DROP TABLE IF EXISTS product_search_fts');
      } catch (_) {}
      return false;
    }
  }
}
