document.addEventListener('DOMContentLoaded', () => {
  const currentPath = window.location.pathname.replace(/\.html$/, '') || '/';
  const icon = (path) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"></path></svg>`;
  const icons = { product:icon('M4 6h16M4 12h16M4 18h10'), plans:icon('M4 4h16v16H4zM8 9h8M8 13h5'), download:icon('M12 3v12m0 0 5-5m-5 5-5-5M5 21h14'), contact:icon('M4 5h16v14H4zM4 7l8 6 8-6') };
  const escapeHtml = (value='') => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let profile = null;
  try { profile = JSON.parse(sessionStorage.getItem('app_profile') || sessionStorage.getItem('portal_profile') || 'null'); } catch (_) {}
  const accountWidget = profile
    ? `<a class="account-widget is-authenticated" href="/app/"><span class="account-avatar">${escapeHtml((profile.name||profile.email||'S').slice(0,1).toUpperCase())}</span><span><strong>${escapeHtml(profile.name||'Hesabım')}</strong><small>Panele git</small></span></a>`
    : `<div class="account-widget"><span class="account-avatar">S</span><span class="account-links"><a href="/app/">Giriş yap</a><a href="/app/#register">Kayıt ol</a></span></div>`;
  const headerMarkup = `<div class="container header-row"><a class="brand" href="/">Serenut</a><nav class="desktop-nav"><a href="/platform" ${currentPath==='/platform'?'aria-current="page"':''}>${icons.product}<span>Ürün</span></a><a href="/plans" ${currentPath==='/plans'?'aria-current="page"':''}>${icons.plans}<span>Planlar</span></a><a href="/downloads" ${currentPath==='/downloads'?'aria-current="page"':''}>${icons.download}<span>İndir</span></a><a href="/contact" ${currentPath==='/contact'?'aria-current="page"':''}>${icons.contact}<span>İletişim</span></a></nav><div class="header-actions">${accountWidget}</div></div>`;
  let siteHeader = document.getElementById('site-header');
  if (!siteHeader) { siteHeader = document.createElement('header'); siteHeader.id='site-header'; siteHeader.className='site-header'; document.body.prepend(siteHeader); }
  siteHeader.innerHTML = headerMarkup;
  let siteFooter = document.querySelector('.site-footer');
  if (!siteFooter) { siteFooter = document.createElement('footer'); siteFooter.className='site-footer'; document.body.append(siteFooter); }
  siteFooter.innerHTML = `<div class="container"><div class="footer-grid"><div><a class="footer-brand" href="/">Serenut</a><p class="footer-intro">Satış, sipariş, stok ve müşteri yönetimini Windows ve Android'de bir araya getiren işletme sistemi.</p></div><div class="footer-column"><strong>Ürün</strong><a href="/platform">Özellikler</a><a href="/plans">Planlar</a><a href="/downloads">Uygulamayı indir</a></div><div class="footer-column"><strong>Destek</strong><a href="/contact">İletişim</a><a href="/app/">Müşteri paneli</a><a href="/app/#register">Ücretsiz hesap</a></div><div class="footer-column"><strong>Yasal</strong><a href="/privacy">Gizlilik</a><a href="/kvkk">KVKK</a><a href="/terms">Kullanım koşulları</a></div></div><div class="footer-bottom"><span>© 2026 Serenut. Tüm hakları saklıdır.</span><span>Türkiye'de geliştirildi.</span></div></div>`;
  const toggle = document.getElementById('menu-toggle');
  const panel = document.getElementById('mobile-panel');
  const header = siteHeader;

  toggle?.addEventListener('click', () => {
    panel?.classList.toggle('app-hidden');
    toggle.setAttribute('aria-expanded', String(!panel?.classList.contains('app-hidden')));
  });

  panel?.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => panel.classList.add('app-hidden'));
  });

  const syncHeader = () => {
    header?.classList.toggle('scrolled', window.scrollY > 12);
  };

  window.addEventListener('scroll', syncHeader, { passive: true });
  syncHeader();
});

document.getElementById('contact-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector('button[type="submit"]');
  const status = document.getElementById('contact-status');
  button.disabled = true; button.textContent = 'Gönderiliyor…'; status.textContent = '';
  try {
    const response = await fetch('/api/v1/support/public-contact', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: document.getElementById('contact-name').value.trim(), email: document.getElementById('contact-email').value.trim(), phone: document.getElementById('contact-phone').value.trim(), subject: document.getElementById('contact-subject').value, message: document.getElementById('contact-message').value.trim() }) });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.message || 'Mesaj gönderilemedi.');
    status.className = 'form-status full success'; status.textContent = data.message || 'Mesajınız iletildi.'; form.reset();
  } catch (error) { status.className = 'form-status full error'; status.textContent = error.message; }
  finally { button.disabled = false; button.textContent = 'Mesajı Gönder'; }
});
