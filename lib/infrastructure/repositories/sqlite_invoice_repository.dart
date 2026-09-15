// lib/infrastructure/repositories/sqlite_invoice_repository.dart
// Serenut OS — GİB e-Arşiv Fatura SQLite Veri Tabanı Deposu

import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/models/gib_invoice_models.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';

abstract class IGibInvoiceRepository {
  Future<void> saveInvoice(GibInvoiceRecord invoice);
  Future<GibInvoiceRecord?> findById(String id);
  Future<GibInvoiceRecord?> findByGibUuid(String gibUuid);
  Future<GibInvoiceRecord?> findBySaleId(String saleId);
  Future<List<GibInvoiceRecord>> getAllInvoices({int limit = 100});
  Future<List<GibInvoiceRecord>> getInvoicesByCustomerId(String customerId);
  Future<void> updateStatus({
    required String id,
    required GibInvoiceStatus status,
    String? invoiceNumber,
    String? htmlContent,
    DateTime? signedAt,
  });
  Future<void> deleteInvoice(String id);
}

class SqliteInvoiceRepository implements IGibInvoiceRepository {
  final DbGateway _gateway;
  bool _tableEnsured = false;

  SqliteInvoiceRepository(this._gateway);

  Future<void> _ensureTable() async {
    if (_tableEnsured) return;
    await _gateway.execute('''
      CREATE TABLE IF NOT EXISTS gib_invoices (
        id TEXT PRIMARY KEY,
        gib_uuid TEXT,
        invoice_number TEXT,
        sale_id TEXT,
        customer_id TEXT,
        recipient_json TEXT NOT NULL,
        items_json TEXT NOT NULL,
        total_without_vat REAL NOT NULL,
        total_vat REAL NOT NULL,
        total_amount REAL NOT NULL,
        invoice_type TEXT NOT NULL,
        status TEXT NOT NULL,
        note TEXT,
        html_content TEXT,
        created_at TEXT NOT NULL,
        signed_at TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_gib_invoices_sale_id ON gib_invoices (sale_id);
      CREATE INDEX IF NOT EXISTS idx_gib_invoices_customer_id ON gib_invoices (customer_id);
      CREATE INDEX IF NOT EXISTS idx_gib_invoices_created_at ON gib_invoices (created_at);
    ''');
    _tableEnsured = true;
  }

  @override
  Future<void> saveInvoice(GibInvoiceRecord invoice) async {
    await _ensureTable();
    await _gateway.insert(
      'gib_invoices',
      invoice.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<GibInvoiceRecord?> findById(String id) async {
    await _ensureTable();
    final rows = await _gateway.query(
      'gib_invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GibInvoiceRecord.fromMap(rows.first);
  }

  @override
  Future<GibInvoiceRecord?> findByGibUuid(String gibUuid) async {
    await _ensureTable();
    final rows = await _gateway.query(
      'gib_invoices',
      where: 'gib_uuid = ?',
      whereArgs: [gibUuid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GibInvoiceRecord.fromMap(rows.first);
  }

  @override
  Future<GibInvoiceRecord?> findBySaleId(String saleId) async {
    await _ensureTable();
    final rows = await _gateway.query(
      'gib_invoices',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GibInvoiceRecord.fromMap(rows.first);
  }

  @override
  Future<List<GibInvoiceRecord>> getAllInvoices({int limit = 100}) async {
    await _ensureTable();
    final rows = await _gateway.query(
      'gib_invoices',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((e) => GibInvoiceRecord.fromMap(e)).toList();
  }

  @override
  Future<List<GibInvoiceRecord>> getInvoicesByCustomerId(
      String customerId) async {
    await _ensureTable();
    final rows = await _gateway.query(
      'gib_invoices',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return rows.map((e) => GibInvoiceRecord.fromMap(e)).toList();
  }

  @override
  Future<void> updateStatus({
    required String id,
    required GibInvoiceStatus status,
    String? invoiceNumber,
    String? htmlContent,
    DateTime? signedAt,
  }) async {
    await _ensureTable();
    final values = <String, dynamic>{
      'status': status.code,
    };
    if (invoiceNumber != null) values['invoice_number'] = invoiceNumber;
    if (htmlContent != null) values['html_content'] = htmlContent;
    if (signedAt != null) values['signed_at'] = signedAt.toIso8601String();

    await _gateway.update(
      'gib_invoices',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteInvoice(String id) async {
    await _ensureTable();
    await _gateway.delete(
      'gib_invoices',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
