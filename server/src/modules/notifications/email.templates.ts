// server/src/modules/notifications/email.templates.ts
// Serenut Platform — Tüm Transactional Email Şablonları
//
// 12 şablon — tüm müşteri yaşam döngüsü kapsanmıştır:
//   1.  welcome_trial      — Trial aktivasyonu
//   2.  trial_expiring_7   — 7 gün kala
//   3.  trial_expiring_1   — 1 gün kala
//   4.  trial_expired      — Trial sona erdi
//   5.  welcome_paid       — Ödeme aboneliği aktif
//   6.  invoice_issued     — Fatura oluşturuldu
//   7.  payment_success    — Ödeme alındı
//   8.  payment_failed     — Ödeme başarısız
//   9.  payment_retry      — Tekrar deneniyor (24s, 72s, 7g)
//   10. subscription_cancelled — Abonelik iptal edildi
//   11. password_reset     — Şifre sıfırlama
//   12. new_device_login   — Yeni cihaz aktivasyonu

interface EmailVars {
  companyName?: string;
  userName?: string;
  userEmail?: string;
  daysRemaining?: number;
  expiryDate?: string;
  planName?: string;
  amount?: string;
  currency?: string;
  invoiceNumber?: string;
  invoiceDate?: string;
  nextBillingDate?: string;
  downloadLink?: string;
  upgradeLink?: string;
  paymentLink?: string;
  resetLink?: string;
  deviceName?: string;
  deviceTime?: string;
  revokeLink?: string;
  cancelLink?: string;
  retryCount?: number;
  supportEmail?: string;
  verificationLink?: string;
}

export function emailVerificationEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = 'Serenut hesabınızı doğrulayın';
  const html = wrapEmail(subject, `
    <h1>E-posta adresinizi doğrulayın</h1>
    <p>Merhaba ${vars.userName || ''}, Serenut firma hesabınızı açmak için aşağıdaki bağlantıyı kullanın.</p>
    <a href="${vars.verificationLink}" class="btn">Hesabımı Doğrula</a>
    <div class="warning-box"><p>Bu bağlantı 30 dakika ve yalnızca bir kez geçerlidir.</p></div>
    <p>Bu kaydı siz oluşturmadıysanız e-postayı yok sayabilirsiniz.</p>
  `);
  return { subject, html };
}

// ── ORTAK HTML ÇERÇEVE ────────────────────────────────────────────────────────
function wrapEmail(title: string, content: string): string {
  return `<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>
  body{margin:0;padding:0;background:#0F172A;font-family:'Segoe UI',Arial,sans-serif}
  .wrapper{max-width:600px;margin:0 auto;padding:24px 16px}
  .card{background:#1E293B;border-radius:12px;overflow:hidden;border:1px solid #334155}
  .header{background:linear-gradient(135deg,#16A34A 0%,#15803D 100%);padding:32px 32px 24px;text-align:center}
  .logo{color:#fff;font-size:22px;font-weight:700;letter-spacing:1px;margin:0}
  .tagline{color:#BBF7D0;font-size:13px;margin:4px 0 0}
  .body{padding:32px}
  h1{color:#F1F5F9;font-size:22px;font-weight:700;margin:0 0 12px}
  p{color:#CBD5E1;font-size:15px;line-height:1.7;margin:0 0 16px}
  .highlight{color:#4ADE80;font-weight:600}
  .info-box{background:#0F172A;border-radius:8px;border-left:4px solid #16A34A;padding:16px 20px;margin:20px 0}
  .info-box p{margin:4px 0;font-size:14px}
  .btn{display:inline-block;background:#16A34A;color:#fff;text-decoration:none;padding:14px 32px;border-radius:8px;font-weight:700;font-size:15px;margin:16px 0;letter-spacing:0.5px}
  .btn-danger{background:#DC2626}
  .btn-amber{background:#D97706}
  .divider{height:1px;background:#334155;margin:24px 0}
  .footer{padding:20px 32px;text-align:center}
  .footer p{color:#64748B;font-size:12px;margin:4px 0}
  .footer a{color:#4ADE80;text-decoration:none}
  .warning-box{background:#431407;border-radius:8px;border-left:4px solid #EA580C;padding:16px 20px;margin:20px 0}
  .warning-box p{margin:4px 0;font-size:14px;color:#FED7AA}
</style>
</head>
<body>
<div class="wrapper">
<div class="card">
  <div class="header">
    <p class="logo">SERENUT OS</p>
    <p class="tagline">Akıllı Satış Noktası Yönetim Platformu</p>
  </div>
  <div class="body">
    ${content}
  </div>
  <div class="footer">
    <p>Bu e-postayı almak istemiyorsanız <a href="#">aboneliği iptal edin</a>.</p>
    <p>Sorularınız için: <a href="mailto:destek@serenut.com">destek@serenut.com</a></p>
    <p style="margin-top:12px;color:#475569">© ${new Date().getFullYear()} Serenut Yazılım A.Ş. — Tüm hakları saklıdır.</p>
  </div>
</div>
</div>
</body>
</html>`;
}

// ── 1. HOŞ GELDİNİZ — TRIAL ──────────────────────────────────────────────────
export function welcomeTrialEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `Serenut OS'e hoş geldiniz — 30 günlük ücretsiz denemeniz başladı!`;
  const html = wrapEmail(subject, `
    <h1>Hoş geldiniz, ${vars.companyName || 'değerli müşterimiz'}! 🎉</h1>
    <p>Serenut OS ailesine katıldığınız için teşekkürler. 30 günlük ücretsiz deneme süreniz bugün başladı.</p>
    <div class="info-box">
      <p><strong>📅 Deneme Bitiş:</strong> <span class="highlight">${vars.expiryDate || '30 gün sonra'}</span></p>
      <p><strong>📦 Plan:</strong> <span class="highlight">${vars.planName || 'Pro'}</span></p>
      <p><strong>📧 Hesap:</strong> ${vars.userEmail || ''}</p>
    </div>
    <p>Uygulamayı aşağıdaki linkten indirip lisans anahtarınızı girerek hemen başlayabilirsiniz:</p>
    <a href="${vars.downloadLink || 'https://serenut.com/download'}" class="btn">Uygulamayı İndir</a>
    <div class="divider"></div>
    <p style="font-size:13px;color:#64748B">Herhangi bir sorunuzda destek ekibimiz yardıma hazır: <a href="mailto:destek@serenut.com" style="color:#4ADE80">destek@serenut.com</a></p>
  `);
  return { subject, html };
}

// ── 2. TRIAL BİTİŞ UYARISI — 7 GÜN ─────────────────────────────────────────
export function trialExpiring7Email(vars: EmailVars): { subject: string; html: string } {
  const subject = `⏰ Deneme süreniz ${vars.daysRemaining || 7} gün içinde doluyor`;
  const html = wrapEmail(subject, `
    <h1>Deneme süreniz bitiyor ⏰</h1>
    <p>Merhaba${vars.companyName ? ` ${vars.companyName}` : ''},</p>
    <p>Serenut OS ücretsiz deneme süreniz <span class="highlight">${vars.daysRemaining || 7} gün</span> içinde sona erecek. Kesintisiz kullanım için abonelik başlatmanızı öneririz.</p>
    <div class="info-box">
      <p><strong>📅 Deneme Bitiş:</strong> ${vars.expiryDate}</p>
      <p><strong>📦 Önerilen Plan:</strong> ${vars.planName || 'Pro'} — ${vars.amount || '₺900'}/ay</p>
    </div>
    <a href="${vars.upgradeLink || 'https://serenut.com/portal'}" class="btn">Hemen Abonelik Başlat</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">Abonelik başlatmazsanız deneme süreniz dolduğunda uygulamaya erişiminiz geçici olarak kısıtlanacaktır. Tüm verileriniz güvende kalacak.</p>
  `);
  return { subject, html };
}

// ── 3. TRIAL BİTİŞ UYARISI — 1 GÜN ─────────────────────────────────────────
export function trialExpiring1Email(vars: EmailVars): { subject: string; html: string } {
  const subject = `🚨 Son gün! Deneme süreniz yarın bitiyor`;
  const html = wrapEmail(subject, `
    <h1>Son 24 saat! 🚨</h1>
    <p>Merhaba${vars.companyName ? ` ${vars.companyName}` : ''},</p>
    <p>Deneme süreniz <strong>yarın</strong> sona eriyor. Hizmet kesintisi yaşamamak için abonelik başlatın.</p>
    <div class="warning-box">
      <p>⚠️ <strong>Yarından itibaren uygulamaya erişiminiz kısıtlanacak.</strong></p>
      <p>Tüm verileriniz güvende — abonelik başlatınca anında erişim yeniden açılacak.</p>
    </div>
    <a href="${vars.upgradeLink || 'https://serenut.com/portal'}" class="btn">Şimdi Abonelik Başlat</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">Sorularınız için: <a href="mailto:destek@serenut.com" style="color:#4ADE80">destek@serenut.com</a> — 7/24 destek</p>
  `);
  return { subject, html };
}

// ── 4. TRIAL SONA ERDİ ────────────────────────────────────────────────────────
export function trialExpiredEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `Deneme süreniz sona erdi — Verileriniz güvende`;
  const html = wrapEmail(subject, `
    <h1>Deneme süreniz sona erdi</h1>
    <p>Serenut OS ücretsiz deneme süreniz doldu. Uygulamaya erişiminiz geçici olarak kısıtlandı.</p>
    <div class="info-box">
      <p>✅ <strong>Tüm verileriniz güvende</strong> — 30 gün boyunca saklanacak.</p>
      <p>💾 Abonelik başlatırsanız anında erişiminiz yeniden açılır.</p>
    </div>
    <a href="${vars.upgradeLink || 'https://serenut.com/portal'}" class="btn">Abonelik Başlat</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">30 gün içinde abonelik başlatmazsanız verileriniz silinebilir. Verilerinizi dışa aktarmak için bizimle iletişime geçin.</p>
  `);
  return { subject, html };
}

// ── 5. HOŞ GELDİNİZ — ÖDEME BAŞARILI ────────────────────────────────────────
export function welcomePaidEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `✅ Aboneliğiniz aktif edildi — ${vars.planName || 'Pro Plan'}`;
  const html = wrapEmail(subject, `
    <h1>Aboneliğiniz aktif! ✅</h1>
    <p>Merhaba${vars.companyName ? ` ${vars.companyName}` : ''}, aboneliğiniz başarıyla oluşturuldu.</p>
    <div class="info-box">
      <p><strong>📦 Plan:</strong> ${vars.planName || 'Pro'}</p>
      <p><strong>💰 Tutar:</strong> ${vars.amount} ${vars.currency || 'TRY'}/ay</p>
      <p><strong>📅 Sonraki Ödeme:</strong> ${vars.nextBillingDate}</p>
      <p><strong>🧾 Fatura No:</strong> ${vars.invoiceNumber}</p>
    </div>
    <a href="${vars.downloadLink || 'https://serenut.com/portal/invoices'}" class="btn">Faturayı İndir</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">Aboneliğinizi yönetmek için <a href="https://serenut.com/portal" style="color:#4ADE80">müşteri portalını</a> ziyaret edin.</p>
  `);
  return { subject, html };
}

// ── 6. FATURA OLUŞTURULDU ─────────────────────────────────────────────────────
export function invoiceIssuedEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `🧾 Faturanız hazır: ${vars.invoiceNumber}`;
  const html = wrapEmail(subject, `
    <h1>Yeni faturanız oluşturuldu 🧾</h1>
    <div class="info-box">
      <p><strong>Fatura No:</strong> ${vars.invoiceNumber}</p>
      <p><strong>Tarih:</strong> ${vars.invoiceDate}</p>
      <p><strong>Tutar:</strong> ${vars.amount} ${vars.currency || 'TRY'}</p>
      <p><strong>Son Ödeme:</strong> ${vars.nextBillingDate}</p>
    </div>
    <a href="${vars.paymentLink || 'https://serenut.com/portal/invoices'}" class="btn">Faturayı Görüntüle & İndir</a>
  `);
  return { subject, html };
}

// ── 7. ÖDEME BAŞARILI ─────────────────────────────────────────────────────────
export function paymentSuccessEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `✅ Ödeme alındı — ${vars.invoiceNumber}`;
  const html = wrapEmail(subject, `
    <h1>Ödemeniz alındı ✅</h1>
    <p>${vars.amount} ${vars.currency || 'TRY'} tutarındaki ödemeniz başarıyla işlendi.</p>
    <div class="info-box">
      <p><strong>Fatura No:</strong> ${vars.invoiceNumber}</p>
      <p><strong>Tutar:</strong> ${vars.amount} ${vars.currency || 'TRY'}</p>
      <p><strong>Sonraki Ödeme:</strong> ${vars.nextBillingDate}</p>
    </div>
    <a href="${vars.downloadLink || 'https://serenut.com/portal/invoices'}" class="btn">Makbuzu İndir</a>
  `);
  return { subject, html };
}

// ── 8. ÖDEME BAŞARISIZ ────────────────────────────────────────────────────────
export function paymentFailedEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `⚠️ Ödeme alınamadı — Kart bilgilerinizi güncelleyin`;
  const html = wrapEmail(subject, `
    <h1>Ödeme alınamadı ⚠️</h1>
    <p>${vars.amount} ${vars.currency || 'TRY'} tutarındaki ödemeniz gerçekleştirilemedi.</p>
    <div class="warning-box">
      <p>⚠️ Aboneliğiniz 7 günlük tolerans süresi içindedir. Bu süre içinde ödeme yapmazsanız hizmetiniz askıya alınacaktır.</p>
    </div>
    <a href="${vars.paymentLink || 'https://serenut.com/portal/billing'}" class="btn btn-amber">Kartı Güncelle & Öde</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">Ödeme sorunlarınız için: <a href="mailto:destek@serenut.com" style="color:#4ADE80">destek@serenut.com</a></p>
  `);
  return { subject, html };
}

// ── 9. ÖDEME YENİDEN DENENİYOR ────────────────────────────────────────────────
export function paymentRetryEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `🔄 Ödemeniz tekrar deneniyor (Deneme ${vars.retryCount}/3)`;
  const html = wrapEmail(subject, `
    <h1>Ödeme yeniden deneniyor 🔄</h1>
    <p>Kayıtlı kartınız üzerinden ödeme tekrar deneniyor.</p>
    <div class="info-box">
      <p><strong>Deneme:</strong> ${vars.retryCount}/3</p>
      <p><strong>Tutar:</strong> ${vars.amount} ${vars.currency || 'TRY'}</p>
    </div>
    <p>Ödeme başarısız olmaya devam ederse kart bilgilerinizi güncellemenizi öneririz:</p>
    <a href="${vars.paymentLink || 'https://serenut.com/portal/billing'}" class="btn btn-amber">Kartı Güncelle</a>
  `);
  return { subject, html };
}

// ── 10. ABONELİK İPTAL EDİLDİ ────────────────────────────────────────────────
export function subscriptionCancelledEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `Aboneliğiniz iptal edildi`;
  const html = wrapEmail(subject, `
    <h1>Aboneliğiniz iptal edildi</h1>
    <p>Abonelik iptali talebiniz alındı. Mevcut dönem sonuna (<strong>${vars.expiryDate}</strong>) kadar kullanıma devam edebilirsiniz.</p>
    <div class="info-box">
      <p>📁 Verilerinizi indirmek için 30 gün süreniz var.</p>
      <p>🔄 Fikrinizi değiştirirseniz aboneliği yeniden başlatabilirsiniz.</p>
    </div>
    <a href="${vars.upgradeLink || 'https://serenut.com/portal'}" class="btn">Aboneliği Yeniden Başlat</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">İptal nedeninizi paylaşmak ister misiniz? <a href="mailto:destek@serenut.com" style="color:#4ADE80">Geri bildirim gönderin</a></p>
  `);
  return { subject, html };
}

// ── 11. ŞİFRE SIFIRLAMA ───────────────────────────────────────────────────────
export function passwordResetEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `🔐 Şifre sıfırlama isteği`;
  const html = wrapEmail(subject, `
    <h1>Şifre Sıfırlama 🔐</h1>
    <p>Hesabınız için şifre sıfırlama isteği aldık.</p>
    <div class="warning-box">
      <p>⚠️ Bu link <strong>1 saat</strong> geçerlidir. Siz istemediyseniz bu e-postayı görmezden gelebilirsiniz.</p>
    </div>
    <a href="${vars.resetLink}" class="btn">Şifremi Sıfırla</a>
    <p style="font-size:13px;color:#64748B;margin-top:16px">Güvenlik sorunu için: <a href="mailto:destek@serenut.com" style="color:#4ADE80">destek@serenut.com</a></p>
  `);
  return { subject, html };
}

// ── 12. YENİ CİHAZ GİRİŞİ ────────────────────────────────────────────────────
export function newDeviceLoginEmail(vars: EmailVars): { subject: string; html: string } {
  const subject = `🔔 Yeni cihaz hesabınıza eklendi`;
  const html = wrapEmail(subject, `
    <h1>Yeni cihaz aktivasyonu 🔔</h1>
    <p>Hesabınıza yeni bir cihaz eklendi.</p>
    <div class="info-box">
      <p><strong>Cihaz:</strong> ${vars.deviceName}</p>
      <p><strong>Zaman:</strong> ${vars.deviceTime}</p>
    </div>
    <p>Siz yapmadıysanız lisansı hemen iptal edin:</p>
    <a href="${vars.revokeLink || 'https://serenut.com/portal/devices'}" class="btn btn-danger">Cihazı İptal Et</a>
  `);
  return { subject, html };
}

// ── SMS ŞABLONları ────────────────────────────────────────────────────────────
export const SmsTemplates = {
  trialExpiring: (daysRemaining: number) =>
    `Serenut OS: Deneme süreniz ${daysRemaining} gün içinde doluyor. Abonelik için: https://serenut.com/portal`,

  paymentFailed: (amount: string) =>
    `Serenut OS: ${amount} TL tutarindaki odemeniz alinamadi. Guncelleme icin: https://serenut.com/portal/billing`,

  activationOtp: (code: string) =>
    `Serenut OS aktivasyon kodunuz: ${code}. 5 dakika gecerlidir.`,

  newDevice: (deviceName: string) =>
    `Serenut OS: ${deviceName} cihazi hesabiniza eklendi. Siz degilseniz: https://serenut.com/portal/devices`,

  subscriptionActivated: (planName: string) =>
    `Serenut OS: ${planName} aboneliginiz aktif edildi. Iyi satislar!`,
};
