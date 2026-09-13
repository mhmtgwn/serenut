/**
 * components.js — Nutopia Fındık Değirmeni
 * Header ve Footer HTML'yi tüm sayfalara dinamik olarak enjekte eder.
 * Her sayfanın <body>'si başına <div id="site-header"></div> olmalı.
 * Her sayfanın <body>'si sonuna <div id="site-footer"></div> olmalı.
 */

(function () {
  'use strict';

  /* -----------------------------------------------------------------------
     Mevcut sayfayı belirle (nav linklerinde active class için)
     ----------------------------------------------------------------------- */
  const currentPath = window.location.pathname.replace(/\/$/, '') || '/';
  const pageMap = {
    '/':             'nav-anasayfa',
    '/degirmen':     'nav-degirmen',
    '/urunler':      'nav-urunler',
    '/hakkimizda':   'nav-hakkimizda',
    '/iletisim':     'nav-iletisim',
  };
  // .html uzantısını da destekle
  const pathClean = currentPath.replace(/\.html$/, '');
  const activeId = pageMap[pathClean] || null;

  /* -----------------------------------------------------------------------
     HEADER HTML
     ----------------------------------------------------------------------- */
  const HEADER_HTML = /* html */`
<header class="site-header" id="siteHeader">
  <div class="container header-inner">
    <a href="/" class="brand" aria-label="Nutopia Fındık Değirmeni — Ana Sayfa">
      <img src="/images/nutopia-logo.png" alt="Nutopia Fındık Değirmeni Logo" class="brand-logo" width="46" height="46" style="border-radius: 50%; border: 1.5px solid var(--gold); object-fit: cover;">
      <div>
        <span class="brand-name">Nutopia</span>
        <span class="brand-sub">Fındık Değirmeni</span>
      </div>
    </a>

    <nav class="nav-main" aria-label="Ana navigasyon">
      <a href="/"            id="nav-anasayfa">Ana Sayfa</a>
      <a href="/degirmen"    id="nav-degirmen">Değirmen Hizmetleri</a>
      <a href="/urunler"     id="nav-urunler">Nutopiano</a>
      <a href="/hakkimizda"  id="nav-hakkimizda">Hakkımızda</a>
      <a href="/iletisim"    id="nav-iletisim">İletişim</a>
    </nav>

    <div class="header-cta">
      <a class="btn btn-dark btn-sm"
         href="https://wa.me/905380288202?text=Merhaba%2C%20Nutopia%20Fındık%20Değirmeni%20hakkında%20bilgi%20almak%20istiyorum."
         target="_blank" rel="noopener noreferrer">
        WhatsApp Bilgi Al
      </a>
    </div>

    <button class="menu-toggle" id="menuToggle"
            aria-label="Menüyü aç/kapat" aria-expanded="false" aria-controls="mobileNav">
      <svg width="17" height="13" viewBox="0 0 17 13" fill="none" stroke="currentColor"
           stroke-width="1.8" stroke-linecap="round" aria-hidden="true">
        <line x1="0" y1="1"  x2="17" y2="1"/>
        <line x1="0" y1="6.5" x2="17" y2="6.5"/>
        <line x1="0" y1="12" x2="17" y2="12"/>
      </svg>
      Menü
    </button>
  </div>

  <nav class="mobile-nav" id="mobileNav" aria-label="Mobil navigasyon">
    <a href="/">Ana Sayfa</a>
    <a href="/degirmen">Değirmen Hizmetleri</a>
    <a href="/urunler">Nutopiano Ürünleri</a>
    <a href="/hakkimizda">Hakkımızda</a>
    <a href="/iletisim">İletişim</a>
    <a href="https://wa.me/905380288202" target="_blank" rel="noopener noreferrer"
       style="color: var(--wa); font-weight: 600;">
      WhatsApp İletişim →
    </a>
  </nav>
</header>`;

  /* -----------------------------------------------------------------------
     FOOTER HTML
     ----------------------------------------------------------------------- */
  const FOOTER_HTML = /* html */`
<footer class="site-footer">
  <div class="container">
    <div class="footer-grid">

      <div>
        <div class="footer-brand brand">
          <img src="/images/nutopia-logo.png" alt="Nutopia Fındık Değirmeni Logo" class="brand-logo" width="46" height="46" style="border-radius: 50%; border: 1.5px solid var(--gold); object-fit: cover; background: #fff;">
          <div>
            <span class="brand-name">Nutopia</span>
            <span class="brand-sub">Fındık Değirmeni</span>
          </div>
        </div>
        <p class="footer-intro">
          Fındığın dalından sofraya uzanan yolculuğunda kırma, kavurma, zar soyma,
          ezme ve vakumlu paketleme hizmetleriyle yanınızdayız. Nutopiano markamız
          altında taze ürünler sunuyoruz.
        </p>
        <p style="font-size:.75rem; color: rgba(245,235,221,.3); margin-top:10px;">
          Nutopia: İşletme &nbsp;·&nbsp; Nutopiano: Ürün Markası
        </p>
      </div>

      <div class="footer-col">
        <h4>Değirmen Hizmetleri</h4>
        <ul>
          <li><a href="/degirmen">Fındık Kırma</a></li>
          <li><a href="/degirmen">Kavurma</a></li>
          <li><a href="/degirmen">Zar Soyma</a></li>
          <li><a href="/degirmen">Fındık Ezmesi</a></li>
          <li><a href="/degirmen">Vakumlu Paketleme</a></li>
        </ul>
      </div>

      <div class="footer-col">
        <h4>Nutopiano</h4>
        <ul>
          <li><a href="/urunler">Sütlü Fındık Kreması</a></li>
          <li><a href="/urunler">Kakaolu Fındık Kreması</a></li>
          <li><a href="/urunler">%100 Fındık Ezmesi</a></li>
          <li><a href="/urunler">Fındık Krokan</a></li>
          <li><a href="/urunler">Çiğ & Kavrulmuş Fındık</a></li>
          <li><a href="/urunler">Kabuklu Fındık</a></li>
        </ul>
      </div>

      <div class="footer-col">
        <h4>İletişim</h4>
        <ul>
          <li><a href="tel:05380288202">0538 028 82 02</a></li>
          <li><a href="https://wa.me/905380288202" target="_blank" rel="noopener">WhatsApp Hattı</a></li>
          <li><a href="/iletisim">Ormanlı / Kdz. Ereğli</a></li>
          <li><a href="/hakkimizda">Hakkımızda</a></li>
        </ul>
      </div>

    </div>

    <div class="footer-bottom">
      <span>© <span class="js-year"></span> Nutopia Fındık Değirmeni — Tüm hakları saklıdır.</span>
      <span>Nutopiano tescilli ürün markasıdır.</span>
    </div>
  </div>
</footer>

<!-- Floating WhatsApp -->
<a class="wa-float"
   href="https://wa.me/905380288202?text=Merhaba%2C%20Nutopia%20Fındık%20Değirmeni%27nden%20bilgi%20almak%20istiyorum."
   target="_blank" rel="noopener noreferrer" aria-label="WhatsApp'tan bilgi alın">
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M20.52 3.48A11.81 11.81 0 0 0 12 0C5.38 0 0 5.38 0 12c0 2.11.55 4.17 1.6 6L0 24l6.3-1.65A11.93 11.93 0 0 0 12 24c6.62 0 12-5.38 12-12 0-3.2-1.25-6.21-3.48-8.52zM12 22c-1.85 0-3.67-.5-5.25-1.44l-.37-.22-3.87 1.01 1.04-3.77-.24-.38A9.94 9.94 0 0 1 2 12C2 6.48 6.48 2 12 2c2.67 0 5.18 1.04 7.07 2.93A9.94 9.94 0 0 1 22 12c0 5.52-4.48 10-10 10zm5.44-7.4c-.3-.15-1.76-.87-2.03-.97s-.47-.15-.67.15-.77.97-.94 1.17-.35.22-.64.07c-.3-.15-1.25-.46-2.38-1.47a8.94 8.94 0 0 1-1.65-2.05c-.17-.3-.02-.46.13-.6.13-.13.3-.34.45-.51s.2-.3.3-.5.05-.37-.02-.52c-.07-.15-.67-1.6-.91-2.19-.24-.57-.49-.5-.67-.5h-.57c-.2 0-.52.07-.8.37s-1.05 1.02-1.05 2.5 1.07 2.9 1.22 3.1c.15.2 2.1 3.2 5.1 4.49.71.31 1.27.5 1.7.63.71.23 1.36.2 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.69.25-1.28.17-1.41-.07-.13-.27-.2-.57-.35z"/>
  </svg>
  WhatsApp Bilgi Al
</a>`;

  /* -----------------------------------------------------------------------
     INJECT
     ----------------------------------------------------------------------- */
  function inject() {
    // Header
    const headerSlot = document.getElementById('site-header');
    if (headerSlot) headerSlot.outerHTML = HEADER_HTML;

    // Footer
    const footerSlot = document.getElementById('site-footer');
    if (footerSlot) footerSlot.outerHTML = FOOTER_HTML;

    // Active nav link
    if (activeId) {
      const el = document.getElementById(activeId);
      if (el) el.classList.add('current');
    }

    // Yıl
    document.querySelectorAll('.js-year').forEach(el => {
      el.textContent = new Date().getFullYear();
    });

    // Header scroll efekti
    const header = document.getElementById('siteHeader');
    if (header) {
      const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 40);
      window.addEventListener('scroll', onScroll, { passive: true });
      onScroll();
    }

    // Mobil menü
    const menuBtn = document.getElementById('menuToggle');
    const mobileNav = document.getElementById('mobileNav');
    if (menuBtn && mobileNav) {
      menuBtn.addEventListener('click', () => {
        const open = mobileNav.classList.toggle('open');
        menuBtn.setAttribute('aria-expanded', String(open));
      });
      mobileNav.querySelectorAll('a').forEach(a => {
        a.addEventListener('click', () => {
          mobileNav.classList.remove('open');
          menuBtn.setAttribute('aria-expanded', 'false');
        });
      });
      document.addEventListener('click', e => {
        if (!menuBtn.contains(e.target) && !mobileNav.contains(e.target)) {
          mobileNav.classList.remove('open');
          menuBtn.setAttribute('aria-expanded', 'false');
        }
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
