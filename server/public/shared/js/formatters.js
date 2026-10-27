/* ==========================================================================
   SERENUT OS V2 - FORMATTERS AND HELPERS
   ========================================================================== */

/**
 * Escapes HTML characters to prevent XSS injections
 * @param {string|number} value 
 * @returns {string}
 */
export function escapeHtml(value = '') {
  if (value === null || value === undefined) return '';
  return String(value).replace(/[&<>"']/g, (character) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]
  ));
}

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
 * Localizes status, role, and category strings into Turkish
 * @param {string} status 
 * @returns {string}
 */
export function translateStatus(status) {
  if (status === null || status === undefined || status === '') return '—';
  const dictionary = {
    // Subscription & License States
    'active': 'Aktif',
    'inactive': 'Pasif',
    'trial': 'Deneme Süresi',
    'trialing': 'Deneme Süresi',
    'expired': 'Süresi Doldu',
    'suspended': 'Askıya Alındı',
    'grace_period': 'Ödeme Bekliyor',
    'no_subscription': 'Abonelik Yok',
    'subscription_yok': 'Abonelik Yok',
    'revoked': 'İptal Edildi',
    'blocked': 'Engellendi',
    'yanked': 'Geri Çekildi',
    'stable': 'Kararlı',
    'beta': 'Beta',
    'online': 'Çevrimiçi',
    'offline': 'Çevrimdışı',
    'configured': 'Yapılandırıldı',
    'not_configured': 'Yapılandırılmadı',

    // Plan Tiers
    'basic': 'Başlangıç',
    'pro': 'Profesyonel',
    'pro_plus': 'Kurumsal',
    'enterprise': 'Kurumsal',

    // Support & Guest Request States
    'open': 'Açık',
    'in_progress': 'İşlemde',
    'pending_customer': 'Müşteri Yanıtı Bekleniyor',
    'resolved': 'Çözüldü',
    'closed': 'Kapalı',
    'unverified': 'Yeni Başvuru',
    'under_review': 'İnceleniyor',
    'routed_to_sales': 'Satışa Yönlendirildi',
    'existing_customer': 'Mevcut Müşteri',
    'prospective_customer': 'Potansiyel Müşteri',

    // Support Categories
    'technical': 'Teknik',
    'license': 'Lisans',
    'billing': 'Ödeme',
    'account': 'Hesap ve Giriş',
    'usage': 'Kullanım',
    'other': 'Diğer',

    // Invoices & Payments States
    'paid': 'Ödendi',
    'unpaid': 'Ödenmedi',
    'pending_review': 'Onay Bekliyor',
    'verification_pending': 'Doğrulama Bekliyor',
    'pending': 'Beklemede',
    'failed': 'Başarısız',
    'completed': 'Tamamlandı',
    'cancelled': 'İptal Edildi',
    'canceled': 'İptal Edildi',
    'rejected': 'Reddedildi',

    // Roles & Severity
    'owner': 'Firma Sahibi',
    'admin': 'Yönetici',
    'manager': 'Mağaza Müdürü',
    'cashier': 'Kasiyer',
    'staff': 'Personel',
    'employee': 'Çalışan',
    'sysadmin': 'Sistem Yöneticisi',
    'critical': 'Kritik',
    'error': 'Hata',
    'warning': 'Uyarı',
    'info': 'Bilgi',
    'up': 'Çalışıyor',
    'down': 'Kesinti'
  };

  return dictionary[String(status).toLowerCase()] || status || '—';
}
