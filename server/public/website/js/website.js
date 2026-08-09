document.addEventListener('DOMContentLoaded', () => {
  // Show the product lockup briefly once per browsing session. This is a
  // restrained brand reveal, not a blocking loading screen.
  if (!sessionStorage.getItem('serenut_brand_intro_seen')) {
    sessionStorage.setItem('serenut_brand_intro_seen', '1');
    const intro = document.createElement('div');
    intro.className = 'brand-intro';
    intro.setAttribute('aria-hidden', 'true');
    intro.innerHTML = '<img src="/shared/assets/serenut-os-color.svg" alt="">';
    document.body.appendChild(intro);
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.setTimeout(() => {
      intro.classList.add('is-leaving');
      window.setTimeout(() => intro.remove(), reducedMotion ? 0 : 300);
    }, reducedMotion ? 250 : 850);
  }

  const currentPath = window.location.pathname.replace(/\.html$/, '') || '/';
  const icon = (path) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"></path></svg>`;
  const icons = { product:icon('M4 6h16M4 12h16M4 18h10'), plans:icon('M4 4h16v16H4zM8 9h8M8 13h5'), download:icon('M12 3v12m0 0 5-5m-5 5-5-5M5 21h14'), contact:icon('M4 5h16v14H4zM4 7l8 6 8-6') };
  const escapeHtml = (value='') => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let profile = null;
  try { profile = JSON.parse(sessionStorage.getItem('app_profile') || localStorage.getItem('app_profile') || 'null'); } catch (_) {}
  const accountWidget = profile
    ? `<a class="account-widget is-authenticated" href="/app/?flow=panel"><span class="account-avatar">${escapeHtml((profile.name||profile.email||'S').slice(0,1).toUpperCase())}</span><span><strong>${escapeHtml(profile.name||'Hesabım')}</strong><small>Panele git</small></span></a>`
    : `<div class="auth-launcher" aria-label="Hesap işlemleri"><a href="/login">Giriş yap</a><a href="/register?flow=account">Kayıt ol</a></div>`;
  const navigationLinks = `<a href="/platform" ${currentPath==='/platform'?'aria-current="page"':''}>${icons.product}<span>Ürün</span></a><a href="/plans" ${currentPath==='/plans'?'aria-current="page"':''}>${icons.plans}<span>Planlar</span></a><a href="/downloads" ${currentPath==='/downloads'?'aria-current="page"':''}>${icons.download}<span>İndir</span></a><a href="/contact" ${currentPath==='/contact'?'aria-current="page"':''}>${icons.contact}<span>İletişim</span></a>`;
  const headerMarkup = `<div class="container header-row"><a class="brand" href="/">Serenut</a><nav class="desktop-nav" aria-label="Ana navigasyon">${navigationLinks}</nav><div class="header-actions">${accountWidget}</div><button class="menu-toggle" id="menu-toggle" type="button" aria-label="Ana menüyü aç" aria-expanded="false" aria-controls="mobile-panel"><span>Menü</span><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"></path></svg></button></div><div class="mobile-panel app-hidden" id="mobile-panel"><nav class="mobile-nav container" aria-label="Mobil navigasyon">${navigationLinks}<div class="mobile-account">${accountWidget}</div></nav></div>`;
  let siteHeader = document.getElementById('site-header');
  if (!siteHeader) { siteHeader = document.createElement('header'); siteHeader.id='site-header'; siteHeader.className='site-header'; document.body.prepend(siteHeader); }
  siteHeader.innerHTML = headerMarkup;
  let siteFooter = document.querySelector('.site-footer');
  if (!siteFooter) { siteFooter = document.createElement('footer'); siteFooter.className='site-footer'; document.body.append(siteFooter); }
  siteFooter.innerHTML = `<div class="container"><div class="footer-grid"><div><a class="footer-brand" href="/">Serenut</a><p class="footer-intro">Satış, canlı tartım, fiziksel POS doğrulaması, yazıcı, sipariş, stok ve müşteri yönetimini bir araya getiren işletme sistemi.</p></div><div class="footer-column"><strong>Ürün</strong><a href="/platform">Özellikler</a><a href="/platform#hardware">Donanım</a><a href="/plans">Planlar</a><a href="/downloads">Uygulamayı indir</a></div><div class="footer-column"><strong>Destek</strong><a href="/contact">İletişim</a><a href="/login">Müşteri paneli</a><a href="/register?flow=account">Ücretsiz hesap</a></div><div class="footer-column"><strong>Yasal</strong><a href="/privacy">Gizlilik</a><a href="/kvkk">KVKK</a><a href="/terms">Kullanım koşulları</a></div></div><div class="footer-bottom"><span>© 2026 Serenut. Tüm hakları saklıdır.</span><span>Türkiye'de geliştirildi.</span></div></div>`;

  const heroAppImage = document.getElementById('hero-app-image');
  if (heroAppImage) {
    const heroScenes = [
      { src: '/media/windows-dashboard.png', alt: 'Serenut OS Windows işletme özeti ekranı', mobileSrc: '/media/mobile-dashboard.png', mobileAlt: 'Serenut OS mobil işletme özeti ekranı', label: 'Serenut OS · İşletme özeti' },
      { src: '/media/windows-sales.png', alt: 'Serenut OS Windows satış ekranı', mobileSrc: '/media/mobile-sales.png', mobileAlt: 'Serenut OS mobil satış ekranı', label: 'Serenut OS · Satış ekranı' }
    ];
    let heroScene = 0;
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) window.setInterval(() => {
      heroScene = (heroScene + 1) % heroScenes.length;
      const scene = heroScenes[heroScene];
      heroAppImage.src = scene.src;
      heroAppImage.alt = scene.alt;
      const heroMobileImage = document.getElementById('hero-mobile-image');
      heroMobileImage.src = scene.mobileSrc;
      heroMobileImage.alt = scene.mobileAlt;
      document.getElementById('hero-app-label').textContent = scene.label;
    }, 5000);
  }

  if (window.location.pathname === '/platform') {
    const main = document.querySelector('main');
    const anchor = main?.querySelector('.cta-section');
    if (main && anchor) {
      const showcase = document.createElement('section');
      showcase.className = 'section product-showcase';
      showcase.setAttribute('aria-labelledby', 'product-showcase-title');
      showcase.innerHTML = `<div class="container"><div class="section-head"><div class="eyebrow">Gerçek uygulama ekranları</div><h2 id="product-showcase-title">Windows'ta geniş, mobilde sahaya hazır.</h2><p>Aynı işletme verisini masaüstü ve mobil düzenlerde yönetin. Aşağıdaki görüntüler çalışan Serenut OS uygulamasından alınmıştır.</p></div><div class="showcase-stage"><figure class="showcase-desktop"><div class="showcase-window-bar"><span></span><span></span><span></span><b>Serenut OS · Windows</b></div><img id="showcase-desktop-image" src="/media/windows-dashboard.png" alt="Serenut OS Windows işletme özeti ekranı" width="1920" height="1009"><figcaption id="showcase-desktop-caption">İşletme özeti, satış eğilimi ve kritik operasyonlar</figcaption></figure><figure class="showcase-mobile"><div class="showcase-phone-speaker"></div><img id="showcase-mobile-image" src="/media/mobile-dashboard.png" alt="Serenut OS mobil işletme özeti ekranı" width="414" height="861"><figcaption id="showcase-mobile-caption">Mobil işletme özeti</figcaption></figure></div><div class="showcase-controls" role="group" aria-label="Uygulama ekranını seçin"><button class="showcase-control active" type="button" data-scene="dashboard" aria-pressed="true">İşletme özeti</button><button class="showcase-control" type="button" data-scene="sales" aria-pressed="false">Satış ekranı</button></div></div>`;
      main.insertBefore(showcase, anchor);
      const scenes = {
        dashboard: { desktop: '/media/windows-dashboard.png', mobile: '/media/mobile-dashboard.png', desktopAlt: 'Serenut OS Windows işletme özeti ekranı', mobileAlt: 'Serenut OS mobil işletme özeti ekranı', desktopCaption: 'İşletme özeti, satış eğilimi ve kritik operasyonlar', mobileCaption: 'Mobil işletme özeti' },
        sales: { desktop: '/media/windows-sales.png', mobile: '/media/mobile-sales.png', desktopAlt: 'Serenut OS Windows satış ekranı', mobileAlt: 'Serenut OS mobil satış ekranı', desktopCaption: 'Ürün kataloğu, sepet ve ödeme adımları', mobileCaption: 'Mobil katalog ve hızlı satış' }
      };
      let activeScene = 'dashboard';
      const showScene = (name) => {
        const scene = scenes[name]; if (!scene) return;
        activeScene = name;
        const desktop = document.getElementById('showcase-desktop-image');
        const mobile = document.getElementById('showcase-mobile-image');
        desktop.src = scene.desktop; desktop.alt = scene.desktopAlt;
        mobile.src = scene.mobile; mobile.alt = scene.mobileAlt;
        document.getElementById('showcase-desktop-caption').textContent = scene.desktopCaption;
        document.getElementById('showcase-mobile-caption').textContent = scene.mobileCaption;
        document.querySelectorAll('.showcase-control').forEach(button => { const active = button.dataset.scene === name; button.classList.toggle('active', active); button.setAttribute('aria-pressed', String(active)); });
      };
      document.querySelectorAll('.showcase-control').forEach(button => button.addEventListener('click', () => showScene(button.dataset.scene)));
      if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) window.setInterval(() => showScene(activeScene === 'dashboard' ? 'sales' : 'dashboard'), 5000);
    }
  }
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
    const response = await fetch('/api/v1/support/guest-requests', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: document.getElementById('contact-name').value.trim(), email: document.getElementById('contact-email').value.trim(), phone: document.getElementById('contact-phone').value.trim(), company_name: document.getElementById('contact-company').value.trim(), customer_claim: document.getElementById('contact-customer-claim').value, category: document.getElementById('contact-category').value, subject: document.getElementById('contact-subject').value.trim(), message: document.getElementById('contact-message').value.trim(), privacy_consent: document.getElementById('contact-privacy-consent').checked, privacy_notice_version: '2026-08-09' }) });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.message || 'Mesaj gönderilemedi.');
    status.className = 'form-status full success'; status.textContent = data.message || 'Mesajınız iletildi.'; form.reset();
  } catch (error) { status.className = 'form-status full error'; status.textContent = error.message; }
  finally { button.disabled = false; button.textContent = 'Mesajı Gönder'; }
});

if (!document.querySelector('.whatsapp-launcher')) {
  const whatsapp = document.createElement('a');
  whatsapp.className = 'whatsapp-launcher';
  whatsapp.href = 'https://wa.me/905380288202?text=Merhaba%2C%20Serenut%20hakk%C4%B1nda%20bilgi%20almak%20istiyorum.';
  whatsapp.target = '_blank'; whatsapp.rel = 'noopener noreferrer';
  whatsapp.setAttribute('aria-label', 'WhatsApp üzerinden Serenut ile iletişime geçin');
  whatsapp.innerHTML = '<span aria-hidden="true">●</span> WhatsApp';
  document.body.appendChild(whatsapp);
}
