export function resolvePaidAmount(
  paymentMethod: unknown,
  paidAmount: number | null | undefined,
  total: number,
): number {
  if (paidAmount != null) return paidAmount;
  const normalized = String(paymentMethod || '').toLowerCase();
  return normalized === 'credit' || normalized === 'veresiye' ? 0 : total;
}
