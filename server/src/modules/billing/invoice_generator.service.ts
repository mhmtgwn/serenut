// server/src/modules/billing/invoice_generator.service.ts
// Serenut Platform — PDF Invoice Generator Service (Sprint 8)
// Creates professional PDF invoices on VPS storage using pdfkit.
// Created: 04 Jul 2026

import PDFDocument from 'pdfkit';
import fs from 'fs';
import path from 'path';

export interface InvoiceItem {
  description: string;
  quantity: number;
  unitPrice: number;
  taxRate: number; // e.g. 20 for 20%
}

export interface InvoiceMetadata {
  invoiceNumber: string;
  date: Date;
  dueDate: Date;
  companyName: string;
  companyAddress: string;
  taxOffice?: string;
  taxNumber: string;
  items: InvoiceItem[];
  currency: string;
}

export class InvoiceGeneratorService {
  private static INVOICES_BASE_DIR = process.env.INVOICES_DIR || '/var/www/serenut-api/invoices';

  /**
   * Generates a professional PDF invoice and saves it to VPS storage.
   * Returns the absolute path of the created PDF.
   */
  public static async generateInvoicePdf(companyId: string, meta: InvoiceMetadata): Promise<string> {
    const tenantDir = path.join(this.INVOICES_BASE_DIR, companyId);
    fs.mkdirSync(tenantDir, { recursive: true });

    const filePath = path.join(tenantDir, `${meta.invoiceNumber}.pdf`);
    
    return new Promise((resolve, reject) => {
      const doc = new PDFDocument({ margin: 50, size: 'A4' });
      const writeStream = fs.createWriteStream(filePath);

      doc.pipe(writeStream);

      // ── 1. HEADER (Logo & Serenut Identity) ─────────────────────────────────
      doc.fillColor('#16A34A')
         .fontSize(22)
         .text('SERENUT CLOUD', 50, 45, { bold: true } as any)
         .fontSize(9)
         .fillColor('#64748B')
         .text('SaaS POS Orchestration & Billing Platform', 50, 70);

      // Invoice info block (Top-right)
      doc.fillColor('#0F172A')
         .fontSize(14)
         .text('E-ARŞİV FATURA', 400, 45, { align: 'right' })
         .fontSize(9)
         .fillColor('#334155')
         .text(`Fatura No: ${meta.invoiceNumber}`, 400, 65, { align: 'right' })
         .text(`Tarih: ${meta.date.toLocaleDateString('tr-TR')}`, 400, 80, { align: 'right' })
         .text(`Vade: ${meta.dueDate.toLocaleDateString('tr-TR')}`, 400, 95, { align: 'right' });

      doc.moveDown(2);

      // Horizontal separator rule
      doc.strokeColor('#E2E8F0').lineWidth(1).moveTo(50, 115).lineTo(550, 115).stroke();

      // ── 2. CLIENT & BILLING DETAILS ──────────────────────────────────────────
      doc.fillColor('#0F172A')
         .fontSize(10)
         .text('Kime Faturalandı:', 50, 130, { underline: true })
         .fontSize(11)
         .text(meta.companyName, 50, 145, { bold: true } as any)
         .fontSize(9)
         .fillColor('#475569')
         .text(meta.companyAddress, 50, 160, { width: 220 })
         .text(`V.Dairesi: ${meta.taxOffice || 'Belirtilmedi'}`, 50, 205)
         .text(`Vergi No: ${meta.taxNumber}`, 50, 220);

      // Sender Info (Platform details)
      doc.fillColor('#0F172A')
         .fontSize(10)
         .text('Gönderici:', 350, 130, { underline: true })
         .fontSize(10)
         .text('Serenut Teknoloji A.Ş.', 350, 145, { bold: true } as any)
         .fontSize(9)
         .fillColor('#475569')
         .text('Maslak Mh. Büyükdere Cd. No:239', 350, 160)
         .text('Sarıyer / İstanbul', 350, 175)
         .text('Vergi Dairesi: Maslak', 350, 190)
         .text('VKN: 7690184423', 350, 205)
         .text('destek@serenut.com', 350, 220);

      doc.moveDown(3);

      // ── 3. TABLE OF ITEMS ───────────────────────────────────────────────────
      let yOffset = 250;
      doc.strokeColor('#CBD5E1').lineWidth(1).moveTo(50, yOffset).lineTo(550, yOffset).stroke();
      
      // Header row
      yOffset += 10;
      doc.fillColor('#475569').fontSize(9)
         .text('Açıklama / Plan', 60, yOffset)
         .text('Miktar', 280, yOffset, { width: 50, align: 'center' })
         .text('Birim Fiyat', 340, yOffset, { width: 70, align: 'right' })
         .text('KDV', 420, yOffset, { width: 50, align: 'center' })
         .text('Tutar', 480, yOffset, { width: 70, align: 'right' });

      yOffset += 15;
      doc.strokeColor('#CBD5E1').lineWidth(1).moveTo(50, yOffset).lineTo(550, yOffset).stroke();

      // Seed/render items
      let subtotal = 0;
      let totalVat = 0;

      for (const item of meta.items) {
        yOffset += 15;
        
        const lineTotal = item.quantity * item.unitPrice;
        const vatAmount = lineTotal - (lineTotal / (1.0 + (item.taxRate / 100.0)));
        
        subtotal += (lineTotal - vatAmount);
        totalVat += vatAmount;

        doc.fillColor('#0F172A').fontSize(10)
           .text(item.description, 60, yOffset)
           .text(item.quantity.toString(), 280, yOffset, { width: 50, align: 'center' })
           .text(`${item.unitPrice.toFixed(2)} ${meta.currency}`, 340, yOffset, { width: 70, align: 'right' })
           .text(`%${item.taxRate}`, 420, yOffset, { width: 50, align: 'center' })
           .text(`${lineTotal.toFixed(2)} ${meta.currency}`, 480, yOffset, { width: 70, align: 'right' });
      }

      yOffset += 25;
      doc.strokeColor('#CBD5E1').lineWidth(1).moveTo(50, yOffset).lineTo(550, yOffset).stroke();

      // ── 4. SUMMARY TOTALS ───────────────────────────────────────────────────
      yOffset += 15;
      doc.fillColor('#475569').fontSize(9)
         .text('KDV Matrahı (Ara Toplam):', 340, yOffset, { align: 'right', width: 120 })
         .fillColor('#0F172A')
         .text(`${subtotal.toFixed(2)} ${meta.currency}`, 470, yOffset, { align: 'right', width: 80 });

      yOffset += 15;
      doc.fillColor('#475569')
         .text('Toplam KDV:', 340, yOffset, { align: 'right', width: 120 })
         .fillColor('#0F172A')
         .text(`${totalVat.toFixed(2)} ${meta.currency}`, 470, yOffset, { align: 'right', width: 80 });

      yOffset += 18;
      doc.strokeColor('#E2E8F0').lineWidth(1).moveTo(340, yOffset).lineTo(550, yOffset).stroke();

      yOffset += 10;
      doc.fillColor('#16A34A').fontSize(12).text('GENEL TOPLAM:', 300, yOffset, { align: 'right', width: 150 })
         .fontSize(13)
         .text(`${(subtotal + totalVat).toFixed(2)} ${meta.currency}`, 460, yOffset, { align: 'right', width: 90, bold: true } as any);

      // ── 5. FOOTER (Legalese & Signature block) ──────────────────────────────
      doc.fillColor('#64748B')
         .fontSize(8)
         .text('Bu fatura elektronik imza kanununa göre dijital olarak üretilmiştir. e-Fatura / e-Arşiv e-posta adresinize iletilmiştir.', 50, 720, { align: 'center' })
         .text('Serenut OS platformunu tercih ettiğiniz için teşekkür ederiz.', 50, 735, { align: 'center' });

      doc.end();

      writeStream.on('finish', () => resolve(filePath));
      writeStream.on('error', (err) => reject(err));
    });
  }
}
