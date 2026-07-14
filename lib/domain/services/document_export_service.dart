import 'dart:io';
import 'package:excel/excel.dart' as ex;
import 'package:flutter/foundation.dart'; // compute
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

// ─── Background Isolate Helpers ──────────────────────────────────────────────
// These are top-level static functions so Flutter's compute() can spawn them
// in a background isolate. They only use plain Dart types (no Platform channels).

Future<List<int>> _buildCustomerStatementPdf(Map<String, dynamic> args) async {
  final customerName = args['customerName'] as String;
  final customerPhone = args['customerPhone'] as String;
  final customerEmail = args['customerEmail'] as String;
  final customerBalance = args['customerBalance'] as double;
  final currency = args['currency'] as String;
  final txList = (args['transactions'] as List).cast<Map<String, dynamic>>();

  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('CARI HESAP EKSTRESI',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Musteri Bilgileri:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Ad Soyad: $customerName'),
              pw.Text(
                  'Telefon: ${customerPhone.isNotEmpty ? customerPhone : '-'}'),
              pw.Text(
                  'E-posta: ${customerEmail.isNotEmpty ? customerEmail : '-'}'),
              pw.Text(
                'Mevcut Bakiye: ${customerBalance.abs().toStringAsFixed(2)} $currency (${customerBalance < 0 ? 'Borclu' : 'Alacakli'})',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color:
                        customerBalance < 0 ? PdfColors.red : PdfColors.green),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Islem Gecmisi:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Tarih', 'Islem Tipi', 'Tutar', 'Odenen', 'Kalan Borc'],
          data: txList.map((t) {
            final isCredit =
                t['type'] == 'collection' || t['type'] == 'payment';
            return [
              DateFormat('dd.MM.yyyy HH:mm')
                  .format(DateTime.parse(t['date'] as String)),
              t['type'] == 'sale'
                  ? 'Satis'
                  : t['type'] == 'collection'
                      ? 'Tahsilat'
                      : t['type'] == 'payment'
                          ? 'Odeme'
                          : t['type'],
              '${isCredit ? '' : '-'}${(t['amount'] as num).toStringAsFixed(2)} $currency',
              '${(t['paidAmount'] as num).toStringAsFixed(2)} $currency',
              '${(t['debtAmount'] as num).toStringAsFixed(2)} $currency',
            ];
          }).toList(),
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
        ),
      ],
    ),
  );
  return (await pdf.save()).toList();
}

Future<List<int>> _buildCustomerStatementExcel(
    Map<String, dynamic> args) async {
  final customerName = args['customerName'] as String;
  final customerPhone = args['customerPhone'] as String;
  final customerBalance = args['customerBalance'] as double;
  final currency = args['currency'] as String;
  final txList = (args['transactions'] as List).cast<Map<String, dynamic>>();

  final excel = ex.Excel.createExcel();
  final sheet = excel['Cari Ekstre'];
  excel.delete('Sheet1');
  sheet.appendRow([ex.TextCellValue('CARI HESAP EKSTRESI')]);
  sheet.appendRow([ex.TextCellValue('Musteri: $customerName')]);
  sheet.appendRow([ex.TextCellValue('Telefon: $customerPhone')]);
  sheet.appendRow([
    ex.TextCellValue(
        'Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')
  ]);
  sheet.appendRow([
    ex.TextCellValue('Bakiye: ${customerBalance.toStringAsFixed(2)} $currency')
  ]);
  sheet.appendRow([]);
  sheet.appendRow([
    ex.TextCellValue('Tarih'),
    ex.TextCellValue('Islem Tipi'),
    ex.TextCellValue('Tutar ($currency)'),
    ex.TextCellValue('Odenen ($currency)'),
    ex.TextCellValue('Kalan Borc ($currency)'),
  ]);
  for (final t in txList) {
    final isCredit = t['type'] == 'collection' || t['type'] == 'payment';
    sheet.appendRow([
      ex.TextCellValue(DateFormat('dd.MM.yyyy HH:mm')
          .format(DateTime.parse(t['date'] as String))),
      ex.TextCellValue(t['type'] as String),
      ex.DoubleCellValue(double.parse(
          '${isCredit ? '' : '-'}${(t['amount'] as num).toStringAsFixed(2)}')),
      ex.DoubleCellValue((t['paidAmount'] as num).toDouble()),
      ex.DoubleCellValue((t['debtAmount'] as num).toDouble()),
    ]);
  }
  return excel.save()?.toList() ?? [];
}

Future<List<int>> _buildSalesReportExcel(Map<String, dynamic> args) async {
  final dateRangeLabel = args['dateRangeLabel'] as String;
  final currency = args['currency'] as String;
  final salesList = (args['sales'] as List).cast<Map<String, dynamic>>();

  final excel = ex.Excel.createExcel();
  final sheet = excel['Satis Raporu'];
  excel.delete('Sheet1');
  sheet.appendRow([ex.TextCellValue('SATIS RAPORU')]);
  sheet.appendRow([ex.TextCellValue('Donem: $dateRangeLabel')]);
  sheet.appendRow([
    ex.TextCellValue(
        'Rapor Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')
  ]);
  sheet.appendRow([]);
  sheet.appendRow([
    ex.TextCellValue('Satis ID'),
    ex.TextCellValue('Tarih'),
    ex.TextCellValue('Musteri ID'),
    ex.TextCellValue('Odeme Tipi'),
    ex.TextCellValue('Toplam Tutar ($currency)'),
    ex.TextCellValue('Odenen ($currency)'),
    ex.TextCellValue('Kalan Borc ($currency)'),
    ex.TextCellValue('Durum'),
  ]);
  for (final s in salesList) {
    final total = (s['totalAmount'] as num).toDouble();
    final paid = (s['paidAmount'] as num).toDouble();
    sheet.appendRow([
      ex.TextCellValue(s['id'] as String),
      ex.TextCellValue(DateFormat('dd.MM.yyyy HH:mm')
          .format(DateTime.parse(s['createdAt'] as String))),
      ex.TextCellValue(s['customerId'] as String),
      ex.TextCellValue(s['paymentMethod'] as String),
      ex.DoubleCellValue(total),
      ex.DoubleCellValue(paid),
      ex.DoubleCellValue(total - paid),
      ex.TextCellValue(s['status'] as String),
    ]);
  }
  return excel.save()?.toList() ?? [];
}

// ─── DocumentExportService ────────────────────────────────────────────────────
class DocumentExportService {
  /// Helper to get temporary file path
  Future<String> _getTempFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return join(tempDir.path, fileName);
  }

  /// ── 1. CARI HESAP EKSTRESI ──

  /// Exports customer statement to PDF (generation runs in background isolate)
  Future<String> exportCustomerStatementPdf(
    CustomerEntity customer,
    List<FinancialTransactionEntity> transactions,
    String currency,
  ) async {
    final bytes = await compute(
      _buildCustomerStatementPdf,
      {
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'customerEmail': customer.email,
        'customerBalance': customer.balance,
        'currency': currency,
        'transactions': transactions
            .map((t) => {
                  'date': t.date.toIso8601String(),
                  'type': t.type,
                  'amount': t.amount,
                  'paidAmount': t.paidAmount,
                  'debtAmount': t.debtAmount,
                })
            .toList(),
      },
    );
    final String fileName =
        'serenut_ekstre_${customer.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final String filePath = await _getTempFilePath(fileName);
    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// Exports customer statement to Excel (generation runs in background isolate)
  Future<String> exportCustomerStatementExcel(
    CustomerEntity customer,
    List<FinancialTransactionEntity> transactions,
    String currency,
  ) async {
    final bytes = await compute(
      _buildCustomerStatementExcel,
      {
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'customerBalance': customer.balance,
        'currency': currency,
        'transactions': transactions
            .map((t) => {
                  'date': t.date.toIso8601String(),
                  'type': t.type,
                  'amount': t.amount,
                  'paidAmount': t.paidAmount,
                  'debtAmount': t.debtAmount,
                })
            .toList(),
      },
    );
    final String fileName =
        'serenut_ekstre_${customer.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    if (bytes.isNotEmpty) await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// ── 2. SATIS RAPORU ──

  /// Exports sales report to Excel (generation runs in background isolate)
  Future<String> exportSalesReportExcel(
    List<SaleEntity> sales,
    String dateRangeLabel,
    String currency,
  ) async {
    final bytes = await compute(
      _buildSalesReportExcel,
      {
        'dateRangeLabel': dateRangeLabel,
        'currency': currency,
        'sales': sales
            .map((s) => {
                  'id': s.id,
                  'createdAt': s.createdAt.toIso8601String(),
                  'customerId': s.customerId,
                  'paymentMethod': s.paymentMethod,
                  'totalAmount': s.totalAmount,
                  'paidAmount': s.paidAmount,
                  'status': s.status,
                })
            .toList(),
      },
    );
    final String fileName =
        'serenut_satis_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    if (bytes.isNotEmpty) await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  /// ── 3. STOK ENVANTER RAPORU ──

  /// Exports stock list to Excel and triggers native share
  Future<String> exportStockReportExcel(
    List<ProductEntity> products,
  ) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Stok Envanteri'];
    excel.delete('Sheet1');

    sheet.appendRow([ex.TextCellValue('STOK VE ENVANTER RAPORU')]);
    sheet.appendRow([
      ex.TextCellValue(
          'Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')
    ]);
    sheet.appendRow([]);

    sheet.appendRow([
      ex.TextCellValue('Urun ID'),
      ex.TextCellValue('Urun Adi'),
      ex.TextCellValue('Kategori'),
      ex.TextCellValue('KDV (%)'),
      ex.TextCellValue('Fiyat (TL)'),
      ex.TextCellValue('Mevcut Stok')
    ]);

    for (final p in products) {
      sheet.appendRow([
        ex.TextCellValue(p.id),
        ex.TextCellValue(p.name),
        ex.TextCellValue(p.category),
        ex.IntCellValue(p.vat ?? 0),
        ex.DoubleCellValue(p.price),
        ex.IntCellValue(p.quantity)
      ]);
    }

    final String fileName =
        'serenut_stok_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    }
    return filePath;
  }

  /// ── 4. GUN SONU RAPORU ──
  Future<String> exportEndOfDayReportExcel({
    required DateTime date,
    required double totalRevenue,
    required double totalCollected,
    required double totalDebt,
    required int salesCount,
    required List<SaleEntity> sales,
    required String currency,
  }) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Gun Sonu Raporu'];
    excel.delete('Sheet1');

    sheet.appendRow([ex.TextCellValue('GÜN SONU (Z) RAPORU')]);
    sheet.appendRow(
        [ex.TextCellValue('Tarih: ${DateFormat('dd.MM.yyyy').format(date)}')]);
    sheet.appendRow([
      ex.TextCellValue(
          'Oluşturma Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')
    ]);
    sheet.appendRow([]);

    // Summary Card Details
    sheet.appendRow([ex.TextCellValue('ÖZET BİLGİLER')]);
    sheet.appendRow([
      ex.TextCellValue('Toplam Ciro:'),
      ex.DoubleCellValue(totalRevenue),
      ex.TextCellValue(currency)
    ]);
    sheet.appendRow([
      ex.TextCellValue('Toplam Tahsilat:'),
      ex.DoubleCellValue(totalCollected),
      ex.TextCellValue(currency)
    ]);
    sheet.appendRow([
      ex.TextCellValue('Toplam Veresiye Borç:'),
      ex.DoubleCellValue(totalDebt),
      ex.TextCellValue(currency)
    ]);
    sheet.appendRow(
        [ex.TextCellValue('Toplam Satış Adedi:'), ex.IntCellValue(salesCount)]);
    sheet.appendRow([]);

    // Detailed Sales Today
    sheet.appendRow([ex.TextCellValue('DETAYLI GÜNLÜK SATIŞ LİSTESİ')]);
    sheet.appendRow([
      ex.TextCellValue('Satış ID'),
      ex.TextCellValue('Saat'),
      ex.TextCellValue('Ödeme Yöntemi'),
      ex.TextCellValue('Toplam Tutar ($currency)'),
      ex.TextCellValue('Ödenen Miktar ($currency)'),
      ex.TextCellValue('Durum')
    ]);

    for (final s in sales) {
      sheet.appendRow([
        ex.TextCellValue(s.id),
        ex.TextCellValue(DateFormat('HH:mm').format(s.createdAt)),
        ex.TextCellValue(s.paymentMethod),
        ex.DoubleCellValue(s.totalAmount),
        ex.DoubleCellValue(s.paidAmount),
        ex.TextCellValue(s.status)
      ]);
    }

    final String fileName =
        'serenut_gun_sonu_${DateFormat('yyyyMMdd').format(date)}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    }
    return filePath;
  }

  /// ── 5. KDV RAPORU ──
  Future<String> exportVatReportExcel({
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> vatSummaryRows,
    required String currency,
  }) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['KDV Raporu'];
    excel.delete('Sheet1');

    sheet.appendRow([ex.TextCellValue('KDV MATRAH RAPORU')]);
    sheet.appendRow([
      ex.TextCellValue(
          'Dönem: ${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}')
    ]);
    sheet.appendRow([
      ex.TextCellValue(
          'Oluşturma Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')
    ]);
    sheet.appendRow([]);

    sheet.appendRow([
      ex.TextCellValue('KDV Oranı (%)'),
      ex.TextCellValue('Vergisiz Tutar (Matrah) ($currency)'),
      ex.TextCellValue('Hesaplanan KDV ($currency)'),
      ex.TextCellValue('Toplam Tutar ($currency)')
    ]);

    double totalMatrah = 0;
    double totalVat = 0;
    double totalAmount = 0;

    for (final row in vatSummaryRows) {
      final int vatRate = (row['vat_rate'] as num?)?.toInt() ?? 0;
      final double matrah = (row['taxable_amount'] as num?)?.toDouble() ?? 0.0;
      final double vatAmount = (row['vat_amount'] as num?)?.toDouble() ?? 0.0;
      final double sumAmount = matrah + vatAmount;

      totalMatrah += matrah;
      totalVat += vatAmount;
      totalAmount += sumAmount;

      sheet.appendRow([
        ex.IntCellValue(vatRate),
        ex.DoubleCellValue(matrah),
        ex.DoubleCellValue(vatAmount),
        ex.DoubleCellValue(sumAmount)
      ]);
    }

    sheet.appendRow([]);
    sheet.appendRow([
      ex.TextCellValue('GENEL TOPLAM'),
      ex.DoubleCellValue(totalMatrah),
      ex.DoubleCellValue(totalVat),
      ex.DoubleCellValue(totalAmount)
    ]);

    final String fileName =
        'serenut_kdv_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    }
    return filePath;
  }

  /// Share document natively
  Future<void> shareFile(String filePath, String subject) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Paylasilacak dosya bulunamadı.');
    }
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: subject,
    );
  }
}
