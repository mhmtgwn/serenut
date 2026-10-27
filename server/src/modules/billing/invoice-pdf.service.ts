import fs from 'fs';
import path from 'path';
import PDFDocument from 'pdfkit';
import { pgPool } from '../../config/database';
import { BillingDomainService } from './billing-domain.service';

const FONT_CANDIDATES = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  'C:/Windows/Fonts/arial.ttf',
  'C:/Windows/Fonts/segoeui.ttf',
];

function resolveUnicodeFont(): string | null {
  for (const candidate of FONT_CANDIDATES) {
    try {
      if (fs.existsSync(candidate)) return candidate;
    } catch (_) {}
  }
  return null;
}

function safePdfText(value: unknown, hasUnicodeFont: boolean): string {
  const str = String(value ?? '');
  if (hasUnicodeFont) return str;
  return str
    .replace(/ğ/g, 'g')
    .replace(/Ğ/g, 'G')
    .replace(/ü/g, 'u')
    .replace(/Ü/g, 'U')
    .replace(/ş/g, 's')
    .replace(/Ş/g, 'S')
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'I')
    .replace(/ö/g, 'o')
    .replace(/Ö/g, 'O')
    .replace(/ç/g, 'c')
    .replace(/Ç/g, 'C')
    .replace(/₺/g, 'TL ');
}

export class InvoicePdfService {
  static getInvoicesDir(): string {
    return path.resolve(process.env.INVOICES_DIR || path.join(__dirname, '../../../../invoices'));
  }

  static async ensureInvoicePdf(
    invoiceId: string,
    companyId: string,
    bypassRls = false,
  ): Promise<{ pdfPath: string; invoiceNumber: string } | null> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      if (bypassRls) {
        await client.query("SELECT set_config('app.bypass_rls', 'true', true)");
      } else {
        await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      }

      const invRes = await client.query(
        `SELECT i.*, c.name AS company_name, c.tax_number, c.tax_office, c.address AS company_address,
                c.email AS company_email, c.phone AS company_phone, p.name AS plan_name
         FROM invoices i
         JOIN companies c ON c.id = i.company_id
         LEFT JOIN subscriptions s ON s.id = i.subscription_id
         LEFT JOIN plans p ON p.id = COALESCE(i.billing_details->>'planId', s.plan_id)
         WHERE i.id = $1 AND ($2::boolean = TRUE OR i.company_id = $3)
         LIMIT 1`,
        [invoiceId, bypassRls, companyId],
      );

      if (invRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return null;
      }

      const row = invRes.rows[0];
      const invoiceNumber =
        row.invoice_number ||
        `SRN-${new Date(row.created_at || Date.now()).getFullYear()}-${String(row.id).replace(/[^a-zA-Z0-9]/g, '').slice(-8).toUpperCase()}`;

      const invoicesDir = this.getInvoicesDir();
      fs.mkdirSync(invoicesDir, { recursive: true });

      if (row.pdf_path && fs.existsSync(row.pdf_path)) {
        const resolvedExisting = path.resolve(row.pdf_path);
        if (resolvedExisting.startsWith(invoicesDir) || resolvedExisting.startsWith('/var/invoices')) {
          await client.query('COMMIT');
          return { pdfPath: resolvedExisting, invoiceNumber };
        }
      }

      const fileName = `${invoiceNumber.replace(/[^a-zA-Z0-9_-]/g, '_')}.pdf`;
      const targetPath = path.join(invoicesDir, fileName);

      await this.renderPdfFile(row, invoiceNumber, targetPath);

      await client.query(
        `UPDATE invoices
         SET pdf_path = $1,
             invoice_number = COALESCE(invoice_number, $2),
             updated_at = NOW()
         WHERE id = $3`,
        [targetPath, invoiceNumber, row.id],
      );

      await client.query('COMMIT');
      return { pdfPath: targetPath, invoiceNumber };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  private static renderPdfFile(row: any, invoiceNumber: string, targetPath: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const doc = new PDFDocument({ size: 'A4', margin: 50 });
      const stream = fs.createWriteStream(targetPath);
      doc.pipe(stream);

      const unicodeFont = resolveUnicodeFont();
      const hasUnicode = Boolean(unicodeFont);
      if (unicodeFont) {
        doc.font(unicodeFont);
      }
      const txt = (v: unknown) => safePdfText(v, hasUnicode);

      const details = BillingDomainService.invoiceDetails(row);
      const totalAmount = Number(row.amount || 0);
      const netAmount = +(totalAmount / 1.2).toFixed(2);
      const vatAmount = +(totalAmount - netAmount).toFixed(2);
      const currency = String(details.currency || 'TRY');
      const periodLabel = details.billingPeriod === 'yearly' ? 'Yıllık Abonelik' : 'Aylık Abonelik';
      const statusLabel =
        row.status === 'paid'
          ? 'ÖDENDİ'
          : row.status === 'pending' || row.status === 'verification_pending'
            ? 'ÖDEME BEKLİYOR'
            : String(row.status || '').toUpperCase();

      // Header
      doc.fontSize(20).fillColor('#0b714d').text(txt('SERENUT OS'), 50, 50);
      doc.fontSize(10).fillColor('#475569').text(txt('Ticari Abonelik ve Lisans Hizmet Belgesi / Fatura Özeti'), 50, 76);

      doc.fontSize(12).fillColor('#0f172a').text(txt(`Belge No: ${invoiceNumber}`), 350, 50, { align: 'right' });
      doc.fontSize(10).fillColor('#475569')
        .text(txt(`Düzenlenme: ${new Date(row.created_at || Date.now()).toLocaleDateString('tr-TR')}`), 350, 68, { align: 'right' })
        .text(txt(`Son Ödeme: ${row.due_at ? new Date(row.due_at).toLocaleDateString('tr-TR') : '-'}`), 350, 83, { align: 'right' })
        .text(txt(`Durum: ${statusLabel}`), 350, 98, { align: 'right' });

      doc.moveTo(50, 125).lineTo(545, 125).strokeColor('#cbd5e1').stroke();

      // Customer Details
      doc.fontSize(11).fillColor('#0f172a').text(txt('MÜŞTERİ / FİRMA BİLGİLERİ'), 50, 145);
      doc.fontSize(10).fillColor('#334155')
        .text(txt(`Ünvan: ${row.company_name || details.companyName || '-'}`), 50, 165)
        .text(txt(`TC / VKN: ${row.tax_number || details.taxId || '-'}`), 50, 180)
        .text(txt(`Vergi Dairesi: ${row.tax_office || details.taxOffice || '-'}`), 50, 195)
        .text(txt(`Adres: ${row.company_address || details.address || '-'}`), 50, 210)
        .text(txt(`İletişim: ${row.company_email || details.email || '-'} ${row.company_phone ? `/ ${row.company_phone}` : ''}`), 50, 225);

      // Line Items Table Header
      const tableTop = 270;
      doc.rect(50, tableTop, 495, 24).fill('#f1f5f9');
      doc.fillColor('#0f172a').fontSize(10)
        .text(txt('Hizmet / Paket Açıklaması'), 60, tableTop + 7)
        .text(txt('Dönem'), 310, tableTop + 7)
        .text(txt('Tutar'), 440, tableTop + 7, { width: 95, align: 'right' });

      const itemTop = tableTop + 34;
      const planLabel = row.plan_name || details.planId || 'Serenut OS Abonelik Paketi';
      doc.fillColor('#1e293b').fontSize(10)
        .text(txt(`Serenut OS — ${planLabel}`), 60, itemTop)
        .text(txt(periodLabel), 310, itemTop)
        .text(txt(`${netAmount.toFixed(2)} ${currency}`), 440, itemTop, { width: 95, align: 'right' });

      doc.moveTo(50, itemTop + 25).lineTo(545, itemTop + 25).strokeColor('#e2e8f0').stroke();

      // Totals
      const totalsTop = itemTop + 40;
      doc.fontSize(10).fillColor('#475569')
        .text(txt('Ara Toplam (KDV Hariç):'), 320, totalsTop)
        .text(txt(`${netAmount.toFixed(2)} ${currency}`), 440, totalsTop, { width: 95, align: 'right' })
        .text(txt('KDV (%20):'), 320, totalsTop + 18)
        .text(txt(`${vatAmount.toFixed(2)} ${currency}`), 440, totalsTop + 18, { width: 95, align: 'right' });

      doc.fontSize(12).fillColor('#0f172a')
        .text(txt('Genel Toplam:'), 320, totalsTop + 40)
        .text(txt(`${totalAmount.toFixed(2)} ${currency}`), 440, totalsTop + 40, { width: 95, align: 'right' });

      if (row.paid_at) {
        doc.fontSize(9).fillColor('#0b714d')
          .text(txt(`Ödeme Tarihi: ${new Date(row.paid_at).toLocaleString('tr-TR')}`), 50, totalsTop + 40);
      }
      if (row.payment_gateway_reference || details.transferReference) {
        doc.fontSize(9).fillColor('#64748b')
          .text(txt(`Ödeme Referansı: ${row.payment_gateway_reference || details.transferReference}`), 50, totalsTop + 56);
      }

      doc.fontSize(8).fillColor('#94a3b8')
        .text(txt('Bu belge Serenut OS Faturalama Merkezi tarafından elektronik olarak üretilmiştir.'), 50, 760, {
          align: 'center',
          width: 495,
        });

      doc.end();
      stream.on('finish', () => resolve());
      stream.on('error', (err) => reject(err));
    });
  }
}

