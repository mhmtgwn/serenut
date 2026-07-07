import 'dart:io';
import 'package:excel/excel.dart' as ex;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class DocumentExportService {
  /// Helper to get temporary file path
  Future<String> _getTempFilePath(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return join(tempDir.path, fileName);
  }

  /// ── 1. CARI HESAP EKSTRESI ──

  /// Exports customer statement to PDF and triggers native share
  Future<String> exportCustomerStatementPdf(
    CustomerEntity customer,
    List<FinancialTransactionEntity> transactions,
    String currency,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          // Header
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('CARI HESAP EKSTRESI', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Customer Info
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Musteri Bilgileri:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Ad Soyad: ${customer.name}'),
                pw.Text('Telefon: ${customer.phone.isNotEmpty ? customer.phone : '-'}'),
                pw.Text('E-posta: ${customer.email.isNotEmpty ? customer.email : '-'}'),
                pw.Text(
                  'Mevcut Bakiye: ${customer.balance.abs().toStringAsFixed(2)} $currency (${customer.balance < 0 ? 'Borclu' : 'Alacakli'})',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: customer.balance < 0 ? PdfColors.red : PdfColors.green),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Transaction Table Header
          pw.Text('Islem Gecmisi:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 8),

          // Table
          pw.TableHelper.fromTextArray(
            headers: ['Tarih', 'Islem Tipi', 'Tutar', 'Odenen', 'Kalan Borc'],
            data: transactions.map((t) {
              final isCredit = t.type == 'collection' || t.type == 'payment';
              return [
                DateFormat('dd.MM.yyyy HH:mm').format(t.date),
                t.type == 'sale'
                    ? 'Vadeli Satis'
                    : t.type == 'collection' || t.type == 'payment'
                        ? 'Tahsilat'
                        : t.type == 'refund'
                            ? 'Iade'
                            : t.type == 'cancellation'
                                ? 'Iptal'
                                : t.type,
                '${isCredit ? '+' : '-'} ${t.amount.toStringAsFixed(2)} $currency',
                '${t.paidAmount.toStringAsFixed(2)} $currency',
                '${t.debtAmount.toStringAsFixed(2)} $currency',
              ];
            }).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey200, width: 0.5),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
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

    final String fileName = 'serenut_ekstre_${customer.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final String filePath = await _getTempFilePath(fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  /// Exports customer statement to Excel and triggers native share
  Future<String> exportCustomerStatementExcel(
    CustomerEntity customer,
    List<FinancialTransactionEntity> transactions,
    String currency,
  ) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Cari Ekstre'];
    excel.delete('Sheet1'); // Remove default sheet

    // Header info
    sheet.appendRow([ex.TextCellValue('CARI HESAP EKSTRESI')]);
    sheet.appendRow([ex.TextCellValue('Musteri: ${customer.name}')]);
    sheet.appendRow([ex.TextCellValue('Telefon: ${customer.phone}')]);
    sheet.appendRow([ex.TextCellValue('Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([ex.TextCellValue('Bakiye: ${customer.balance.toStringAsFixed(2)} $currency')]);
    sheet.appendRow([]); // Empty row

    // Table headers
    sheet.appendRow([
      ex.TextCellValue('Tarih'),
      ex.TextCellValue('Islem Tipi'),
      ex.TextCellValue('Tutar ($currency)'),
      ex.TextCellValue('Odenen ($currency)'),
      ex.TextCellValue('Kalan Borc ($currency)')
    ]);

    // Data rows
    for (final t in transactions) {
      final isCredit = t.type == 'collection' || t.type == 'payment';
      sheet.appendRow([
        ex.TextCellValue(DateFormat('dd.MM.yyyy HH:mm').format(t.date)),
        ex.TextCellValue(t.type),
        ex.DoubleCellValue(double.parse('${isCredit ? '' : '-'}${t.amount.toStringAsFixed(2)}')),
        ex.DoubleCellValue(t.paidAmount),
        ex.DoubleCellValue(t.debtAmount)
      ]);
    }

    final String fileName = 'serenut_ekstre_${customer.name.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    }
    return filePath;
  }

  /// ── 2. SATIS RAPORU ──

  /// Exports sales report to Excel and triggers native share
  Future<String> exportSalesReportExcel(
    List<SaleEntity> sales,
    String dateRangeLabel,
    String currency,
  ) async {
    final excel = ex.Excel.createExcel();
    final sheet = excel['Satis Raporu'];
    excel.delete('Sheet1');

    sheet.appendRow([ex.TextCellValue('SATIS RAPORU')]);
    sheet.appendRow([ex.TextCellValue('Donem: $dateRangeLabel')]);
    sheet.appendRow([ex.TextCellValue('Rapor Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      ex.TextCellValue('Satis ID'),
      ex.TextCellValue('Tarih'),
      ex.TextCellValue('Musteri ID'),
      ex.TextCellValue('Odeme Tipi'),
      ex.TextCellValue('Toplam Tutar ($currency)'),
      ex.TextCellValue('Odenen ($currency)'),
      ex.TextCellValue('Kalan Borc ($currency)'),
      ex.TextCellValue('Durum')
    ]);

    for (final s in sales) {
      final debt = s.totalAmount - s.paidAmount;
      sheet.appendRow([
        ex.TextCellValue(s.id),
        ex.TextCellValue(DateFormat('dd.MM.yyyy HH:mm').format(s.createdAt)),
        ex.TextCellValue(s.customerId),
        ex.TextCellValue(s.paymentMethod),
        ex.DoubleCellValue(s.totalAmount),
        ex.DoubleCellValue(s.paidAmount),
        ex.DoubleCellValue(debt),
        ex.TextCellValue(s.status)
      ]);
    }

    final String fileName = 'serenut_satis_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final String filePath = await _getTempFilePath(fileName);
    final bytes = excel.save();
    if (bytes != null) {
      final file = File(filePath);
      await file.writeAsBytes(bytes);
    }
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
    sheet.appendRow([ex.TextCellValue('Tarih: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')]);
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

    final String fileName = 'serenut_stok_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
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
    sheet.appendRow([ex.TextCellValue('Tarih: ${DateFormat('dd.MM.yyyy').format(date)}')]);
    sheet.appendRow([ex.TextCellValue('Oluşturma Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    // Summary Card Details
    sheet.appendRow([ex.TextCellValue('ÖZET BİLGİLER')]);
    sheet.appendRow([ex.TextCellValue('Toplam Ciro:'), ex.DoubleCellValue(totalRevenue), ex.TextCellValue(currency)]);
    sheet.appendRow([ex.TextCellValue('Toplam Tahsilat:'), ex.DoubleCellValue(totalCollected), ex.TextCellValue(currency)]);
    sheet.appendRow([ex.TextCellValue('Toplam Veresiye Borç:'), ex.DoubleCellValue(totalDebt), ex.TextCellValue(currency)]);
    sheet.appendRow([ex.TextCellValue('Toplam Satış Adedi:'), ex.IntCellValue(salesCount)]);
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

    final String fileName = 'serenut_gun_sonu_${DateFormat('yyyyMMdd').format(date)}.xlsx';
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
    sheet.appendRow([ex.TextCellValue('Dönem: ${DateFormat('dd.MM.yyyy').format(startDate)} - ${DateFormat('dd.MM.yyyy').format(endDate)}')]);
    sheet.appendRow([ex.TextCellValue('Oluşturma Tarihi: ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}')]);
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

    final String fileName = 'serenut_kdv_raporu_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
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
