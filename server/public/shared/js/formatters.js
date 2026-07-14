/* ==========================================================================
   SERENUT OS V2 - FORMATTERS AND HELPERS
   ========================================================================== */

/**
 * Formats numeric values to currency notation
 * @param {number|string} amount 
 * @param {string} currency 
 * @returns {string}
 */
export function formatCurrency(amount, currency = 'TRY') {
  const numericAmount = Number(amount) || 0;
  const formatter = new Intl.NumberFormat('tr-TR', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2
  });
  return formatter.format(numericAmount);
}

/**
 * Formats ISO timestamps to standard Turkish locale
 * @param {string|Date} dateStr 
 * @param {boolean} showTime 
 * @returns {string}
 */
export function formatDate(dateStr, showTime = false) {
  if (!dateStr) return '—';
  const date = new Date(dateStr);
  if (isNaN(date.getTime())) return '—';
  
  const options = {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    ...(showTime ? { hour: '2-digit', minute: '2-digit' } : {})
  };
  return date.toLocaleDateString('tr-TR', options);
}

/**
 * Localizes billing cycle status strings
 * @param {string} status 
 * @returns {string}
 */
export function translateStatus(status) {
  const dictionary = {
    // Subscription States
    'active': 'Aktif',
    'trial': 'Deneme Süresi',
    'expired': 'Süresi Doldu',
    'suspended': 'Askıya Alındı',
    'grace_period': 'Ödeme Bekliyor',
    'no_subscription': 'Abonelik Yok',

    // Support States
    'open': 'Açık',
    'in_progress': 'İşlemde',
    'resolved': 'Çözüldü',
    'closed': 'Kapalı',

    // Invoices & Payments States
    'paid': 'Ödendi',
    'unpaid': 'Ödenmedi',
    'pending_review': 'Onay Bekliyor',
    'pending': 'Beklemede',
    'failed': 'Başarısız',
    'completed': 'Tamamlandı'
  };

  return dictionary[String(status).toLowerCase()] || status || '—';
}
