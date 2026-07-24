document.addEventListener('DOMContentLoaded', () => {
  const currentPath = window.location.pathname.replace(/\.html$/, '') || '/';
  const icon = (path) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"></path></svg>`;
  const icons = { product:icon('M4 6h16M4 12h16M4 18h10'), plans:icon('M4 4h16v16H4zM8 9h8M8 13h5'), download:icon('M12 3v12m0 0 5-5m-5 5-5-5M5 21h14'), contact:icon('M4 5h16v14H4zM4 7l8 6 8-6') };
  const escapeHtml = (value='') => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let profile = null;
  try { profile = JSON.parse(sessionStorage.getItem('app_profile') || sessionStorage.getItem('portal_profile') || 'null'); } catch (_) {}
  const accountWidget = profile
    ? `<a class="account-widget is-authenticated" href="/app/"><span class="account-avatar">${escapeHtml((profile.name||profile.email||'S').slice(0,1).toUpperCase())}</span><span><strong>${escapeHtml(profile.name||'Hesabım')}</strong><small>Panele git</small></span></a>`
    : `<div class="auth-launcher" aria-label="Hesap işlemleri"><a href="/app/">Giriş yap</a><a href="/app/#register">Kayıt ol</a></div>`;
  const navigationLinks = `<a href="/platform" ${currentPath==='/platform'?'aria-current="page"':''}>${icons.product}<span>Ürün</span></a><a href="/plans" ${currentPath==='/plans'?'aria-current="page"':''}>${icons.plans}<span>Planlar</span></a><a href="/downloads" ${currentPath==='/downloads'?'aria-current="page"':''}>${icons.download}<span>İndir</span></a><a href="/contact" ${currentPath==='/contact'?'aria-current="page"':''}>${icons.contact}<span>İletişim</span></a>`;
  const headerMarkup = `<div class="container header-row"><a class="brand" href="/">Serenut</a><nav class="desktop-nav" aria-label="Ana navigasyon">${navigationLinks}</nav><div class="header-actions">${accountWidget}</div><button class="menu-toggle" id="menu-toggle" type="button" aria-label="Ana menüyü aç" aria-expanded="false" aria-controls="mobile-panel"><span>Menü</span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"></path></svg></button></div><div class="mobile-panel app-hidden" id="mobile-panel"><nav class="mobile-nav container" aria-label="Mobil navigasyon">${navigationLinks}<div class="mobile-account">${accountWidget}</div></nav></div>`;
  let siteHeader = document.getElementById('site-header');
  if (!siteHeader) { siteHeader = document.createElement('header'); siteHeader.id='site-header'; siteHeader.className='site-header'; document.body.prepend(siteHeader); }
  siteHeader.innerHTML = headerMarkup;
  const requestedAuth = new URLSearchParams(window.location.search).get('auth');
  if (requestedAuth === 'login' || requestedAuth === 'register') {
    window.location.replace(requestedAuth === 'register' ? '/app/#register' : '/app/');
    return;
  }
  let siteFooter = document.querySelector('.site-footer');
  if (!siteFooter) { siteFooter = document.createElement('footer'); siteFooter.className='site-footer'; document.body.append(siteFooter); }
  siteFooter.innerHTML = `<div class="container"><div class="footer-grid"><div><a class="footer-brand" href="/">Serenut</a><p class="footer-intro">Satış, canlı tartım, fiziksel POS doğrulaması, yazıcı, sipariş, stok ve müşteri yönetimini bir araya getiren işletme sistemi.</p></div><div class="footer-column"><strong>Ürün</strong><a href="/platform">Özellikler</a><a href="/platform#hardware">Donanım</a><a href="/plans">Planlar</a><a href="/downloads">Uygulamayı indir</a></div><div class="footer-column"><strong>Destek</strong><a href="/contact">İletişim</a><a href="/app/">Müşteri paneli</a><a href="/app/#register">Ücretsiz hesap</a></div><div class="footer-column"><strong>Yasal</strong><a href="/privacy">Gizlilik</a><a href="/kvkk">KVKK</a><a href="/terms">Kullanım koşulları</a></div></div><div class="footer-bottom"><span>© 2026 Serenut. Tüm hakları saklıdır.</span><span>Türkiye'de geliştirildi.</span></div></div>`;
  const toggle = document.getElementById('menu-toggle');
  const panel = document.getElementById('mobile-panel');
  const header = siteHeader;

  const closeMenu = ({ restoreFocus = false } = {}) => {
    if (!panel || panel.classList.contains('app-hidden')) return;
    panel.classList.add('app-hidden');
    toggle?.setAttribute('aria-expanded', 'false');
    toggle?.setAttribute('aria-label', 'Ana menüyü aç');
    if (restoreFocus) toggle?.focus();
  };

  toggle?.addEventListener('click', () => {
    panel?.classList.toggle('app-hidden');
    const isOpen = !panel?.classList.contains('app-hidden');
    toggle.setAttribute('aria-expanded', String(isOpen));
    toggle.setAttribute('aria-label', isOpen ? 'Ana menüyü kapat' : 'Ana menüyü aç');
    if (isOpen) panel?.querySelector('a')?.focus();
  });

  panel?.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => closeMenu());
  });

  document.addEventListener('click', (event) => {
    if (!header?.contains(event.target)) closeMenu();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !panel?.classList.contains('app-hidden')) {
      closeMenu({ restoreFocus: true });
    }
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 760 && !panel?.classList.contains('app-hidden')) {
      closeMenu();
    }
  });

  let authModal = null;

  const openAuthModal = (targetUrl) => {
    const embedUrl = targetUrl.includes('#register') 
      ? '/app/?embed=1#register' 
      : '/app/?embed=1';

    if (!authModal) {
      authModal = document.createElement('div');
      authModal.id = 'auth-modal';
      authModal.className = 'auth-modal-backdrop app-hidden';
      authModal.innerHTML = `
        <div class="auth-modal-dialog">
          <button class="auth-modal-close" id="auth-modal-close" type="button" aria-label="Kapat">×</button>
          <iframe id="auth-modal-iframe" title="Giriş ve Kayıt Ekranı" src="about:blank"></iframe>
        </div>
      `;
      document.body.appendChild(authModal);

      document.getElementById('auth-modal-close')?.addEventListener('click', closeAuthModal);
      authModal.addEventListener('click', (e) => {
        if (e.target === authModal) closeAuthModal();
      });
    }

    const iframe = document.getElementById('auth-modal-iframe');
    if (iframe) iframe.src = embedUrl;
    authModal.classList.remove('app-hidden');
    document.body.style.overflow = 'hidden';
  };

  const closeAuthModal = () => {
    if (!authModal) return;
    authModal.classList.add('app-hidden');
    const iframe = document.getElementById('auth-modal-iframe');
    if (iframe) iframe.src = 'about:blank';
    document.body.style.overflow = '';
  };

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && authModal && !authModal.classList.contains('app-hidden')) {
      closeAuthModal();
    }
  });

  window.addEventListener('message', (event) => {
    if (event.data?.type === 'serenut-authenticated') {
      try {
        if (event.data.token) sessionStorage.setItem('app_token', event.data.token);
        if (event.data.user) sessionStorage.setItem('app_profile', JSON.stringify(event.data.user));
      } catch (_) {}
      closeAuthModal();
      window.location.href = '/app/';
    }
  });

  document.addEventListener('click', (e) => {
    const authLink = e.target.closest('.auth-launcher a, a[href="/app/"], a[href="/app/#register"]');
    if (authLink && !profile) {
      e.preventDefault();
      closeMenu();
      const href = authLink.getAttribute('href') || '/app/';
      openAuthModal(href);
    }
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
