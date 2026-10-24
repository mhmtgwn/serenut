// core_next/web_portal/src/types/portal.ts

export type MoneyCents = number;

export function formatTL(cents: MoneyCents): string {
  const lira = Math.floor(cents / 100);
  const kurus = Math.abs(cents % 100).toString().padStart(2, '0');
  return `${lira},${kurus} ₺`;
}

export interface ProductDto {
  id: string;
  barcode: string;
  name: string;
  categoryName?: string;
  priceCents: MoneyCents;
  costPriceCents?: MoneyCents;
  vatRate: number;
  stockQuantity: number;
  criticalThreshold: number;
  isActive: boolean;
}

export interface CustomerDto {
  id: string;
  name: string;
  phone?: string;
  balanceCents: MoneyCents; // Pozitif: Alacaklı, Negatif: Borçlu
  creditLimitCents: MoneyCents;
  isActive: boolean;
}

export interface SaleSummaryDto {
  id: string;
  receiptNo: string;
  customerName?: string;
  totalCents: MoneyCents;
  paidCents: MoneyCents;
  debtCents: MoneyCents;
  itemCount: number;
  createdAt: string;
}

export interface DashboardMetrics {
  todayRevenueCents: MoneyCents;
  todaySalesCount: number;
  totalCustomerDebtCents: MoneyCents;
  criticalStockCount: number;
  onlineDevicesCount: number;
}
