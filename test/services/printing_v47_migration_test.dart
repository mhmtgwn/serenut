import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/infrastructure/database/schema/db_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v47 migrates design profiles, devices and explicit routes', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    // The application currently upgrades through v48 in one pass. Keep the
    // legacy sales table present so the test exercises the real migration
    // chain instead of hiding expected v48 work behind "no such table" logs.
    await db.execute('''CREATE TABLE sales (
      id TEXT PRIMARY KEY,
      total_amount REAL NOT NULL DEFAULT 0
    )''');
    await db.execute('''CREATE TABLE settings (
      id INTEGER PRIMARY KEY,
      active_receipt_printer_id TEXT,
      active_label_printer_id TEXT,
      paper_width INTEGER,
      print_logo INTEGER,
      print_barcode INTEGER,
      print_product_details INTEGER,
      print_customer_balance INTEGER,
      receipt_font TEXT,
      receipt_text_size TEXT,
      receipt_item_layout TEXT,
      receipt_footer_text TEXT,
      receipt_feed_lines INTEGER,
      auto_cut_receipt INTEGER,
      open_cash_drawer INTEGER,
      label_show_business_name INTEGER,
      label_show_brand INTEGER,
      label_show_barcode INTEGER,
      label_show_price INTEGER,
      label_show_vat INTEGER,
      label_font_size TEXT,
      label_order_show_business_name INTEGER,
      label_order_show_customer_name INTEGER,
      label_order_show_order_no INTEGER,
      label_order_show_date INTEGER,
      label_order_show_total_amount INTEGER,
      label_order_show_items_count INTEGER,
      label_order_font_size TEXT,
      printer_name TEXT,
      printer_ip TEXT,
      printer_port INTEGER,
      label_printer_enabled INTEGER,
      label_printer_name TEXT,
      label_printer_ip TEXT,
      label_printer_port INTEGER,
      label_width_mm INTEGER,
      label_height_mm INTEGER,
      label_gap_mm INTEGER,
      label_dpi INTEGER
    )''');
    await db.insert('settings', {
      'id': 1,
      'active_receipt_printer_id': 'receipt-a',
      'active_label_printer_id': 'label-a',
      'paper_width': 58,
      'print_logo': 1,
      'print_barcode': 0,
      'print_product_details': 1,
      'label_show_business_name': 1,
      'label_show_barcode': 1,
      'label_show_price': 1,
      'label_printer_enabled': 1,
      'printer_name': '58 mm Kasa',
      'printer_ip': '192.168.1.10',
      'printer_port': 9100,
      'label_printer_name': 'TSPL',
      'label_printer_ip': '',
      'label_printer_port': 9100,
      'label_width_mm': 50,
      'label_height_mm': 30,
      'label_gap_mm': 2,
      'label_dpi': 203,
    });
    await db.execute('''CREATE TABLE print_queue (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      receipt_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      retry_count INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      purpose TEXT NOT NULL,
      device_id TEXT NOT NULL,
      last_error TEXT
    )''');
    await db.insert('print_queue', {
      'id': 'pending-label',
      'title': 'Etiket',
      'receipt_json': jsonEncode({'name': 'Ürün'}),
      'created_at': DateTime.utc(2026, 7, 1).toIso8601String(),
      'retry_count': 1,
      'status': 'printing',
      'purpose': 'productLabel',
      'device_id': 'label-a',
    });
    await db.insert('print_queue', {
      'id': 'completed-receipt',
      'title': 'Fiş',
      'receipt_json': jsonEncode({'sale': '1'}),
      'created_at': DateTime.utc(2026, 7, 1).toIso8601String(),
      'retry_count': 0,
      'status': 'success',
      'purpose': 'receipt',
      'device_id': 'receipt-a',
    });

    await DatabaseMigrations.onUpgrade(db, 46, 47);

    expect(await db.query('print_design_profiles'), hasLength(3));
    expect(await db.query('printer_devices'), hasLength(2));
    final routes = await db.query('printer_routes', orderBy: 'kind');
    expect(routes, hasLength(3));
    expect(
      routes.map((row) => '${row['kind']}:${row['device_id']}'),
      containsAll([
        'receipt:receipt-a',
        'productLabel:label-a',
        'orderLabel:label-a',
      ]),
    );
    final receipt = (await db.query(
      'printer_devices',
      where: 'id = ?',
      whereArgs: ['receipt-a'],
    ))
        .single;
    expect(jsonDecode(receipt['capabilities_json']! as String)['paperWidthMm'],
        58);
    final migratedJobs = await db.query('print_jobs', orderBy: 'id');
    expect(migratedJobs, hasLength(2));
    expect(
      migratedJobs
          .singleWhere((row) => row['id'] == 'legacy-pending-label')['state'],
      'queued',
    );
    expect(
      migratedJobs.singleWhere(
          (row) => row['id'] == 'legacy-completed-receipt')['state'],
      'delivered',
    );
    expect(
      migratedJobs.singleWhere(
          (row) => row['id'] == 'legacy-pending-label')['device_id'],
      'label-a',
    );
    expect(
      (await db.query(
        'print_queue',
        where: 'id = ?',
        whereArgs: ['pending-label'],
      ))
          .single['status'],
      'abandoned',
    );

    // The migration is idempotent and never duplicates imported work.
    await DatabaseMigrations.onUpgrade(db, 46, 47);
    expect(await db.query('print_jobs'), hasLength(2));
  });
}
