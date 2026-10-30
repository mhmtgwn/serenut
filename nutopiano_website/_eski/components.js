/**
 * components.js — Nutopia Fındık Değirmeni & Nutopiano
 * Header, Footer, Top Bar, Cart Drawer, Kupon Sistemi, Besin Değerleri QuickView ve Lightbox
 */

(function () {
  'use strict';

  /* -----------------------------------------------------------------------
     1. MEVCUT SAYFAYI BELİRLE (Active Nav)
     ----------------------------------------------------------------------- */
  const currentPath = window.location.pathname.replace(/\/$/, '') || '/';
  const pageMap = {
    '/':             'nav-anasayfa',
    '/degirmen':     'nav-degirmen',
    '/urunler':      'nav-urunler',
    '/hakkimizda':   'nav-hakkimizda',
    '/iletisim':     'nav-iletisim',
  };
  const pathClean = currentPath.replace(/\.html$/, '');
  const activeId = pageMap[pathClean] || null;

  /* -----------------------------------------------------------------------
     2. HEADER HTML (Top Bar Dahil)
     ----------------------------------------------------------------------- */
  const HEADER_HTML = /* html */`
<header class="site-header" id="siteHeader">
  <!-- Canlı Durum & Üst Duyuru Şeridi -->
  <div class="top-announcement-bar">
    <div class="container top-announcement-inner">
      <div class="top-announcement-left">
        <span class="live-pulse-dot"></span>
        <span><strong>Değirmenimiz Açık:</strong> Bugün taze kavurma & taş değirmende ezme çekimi devam ediyor.</span>
      </div>
      <div class="top-announcement-right">
        <span>🚚 750 ₺ Üzeri Kargo Bedava</span>
        <span class="top-announcement-sep">·</span>
        <span>🎖️ Şehit & Gaziye %20 İndirim</span>
        <span class="top-announcement-sep">·</span>
        <a href="tel:05380288202" style="color: inherit; font-weight: 600; text-decoration: none;">📞 0538 028 82 02</a>
      </div>
    </div>
  </div>

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

    <div class="header-cta" style="display: flex; align-items: center; gap: 8px;">
      <a class="btn btn-dark btn-sm"
         href="https://wa.me/905380288202?text=Merhaba%2C%20Nutopia%20Fındık%20Değirmeni%20hakkında%20bilgi%20almak%20istiyorum."
         target="_blank" rel="noopener noreferrer">
        WhatsApp Bilgi Al
      </a>
      <button class="header-cart-btn" id="headerCartBtn" aria-label="Alışveriş Sepeti">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="9" cy="21" r="1"></circle>
          <circle cx="20" cy="21" r="1"></circle>
          <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path>
        </svg>
        <span class="cart-badge" id="cartBadge">0</span>
      </button>
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
    <a href="javascript:void(0)" id="mobileCartLink" style="font-weight: 600; color: var(--gold-dark); display: flex; align-items: center; justify-content: space-between;">
      <span>🛒 Alışveriş Sepeti</span>
      <span class="cart-badge" id="mobileCartBadge" style="position: static;">0</span>
    </a>
    <a href="https://wa.me/905380288202" target="_blank" rel="noopener noreferrer"
       style="color: var(--wa); font-weight: 600;">
      WhatsApp İletişim →
    </a>
  </nav>
</header>`;

  /* -----------------------------------------------------------------------
     3. FOOTER HTML
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
     4. CART DRAWER & MODAL HTML
     ----------------------------------------------------------------------- */
  const CART_COMPONENTS_HTML = /* html */`
<!-- Floating Cart Button -->
<button class="cart-float-btn" id="cartFloatBtn" aria-label="Alışveriş Sepeti">
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
    <circle cx="9" cy="21" r="1"></circle>
    <circle cx="20" cy="21" r="1"></circle>
    <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path>
  </svg>
  <span class="cart-float-count" id="cartFloatCount">0</span>
</button>

<!-- Cart Overlay -->
<div class="cart-overlay" id="cartOverlay" aria-hidden="true"></div>

<!-- Cart Drawer -->
<aside class="cart-drawer" id="cartDrawer" aria-label="Alışveriş Sepeti" aria-hidden="true">
  <div class="cart-drawer-header">
    <div class="cart-drawer-title-wrap">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2">
        <circle cx="9" cy="21" r="1"></circle>
        <circle cx="20" cy="21" r="1"></circle>
        <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path>
      </svg>
      <h3>Sepetiniz <span class="cart-count-badge" id="cartCountBadge">(0)</span></h3>
    </div>
    <button class="cart-drawer-close" id="cartDrawerClose" aria-label="Sepeti Kapat">&times;</button>
  </div>

  <div class="cart-shipping-banner" id="cartShippingBanner">
    <div class="cart-shipping-text" id="cartShippingText">
      <span>🚚 750 ₺ üzeri siparişlerde <strong>KARGO BEDAVA!</strong></span>
      <span id="shippingRemainingText"></span>
    </div>
    <div class="cart-shipping-track">
      <div class="cart-shipping-bar" id="cartShippingBar" style="width: 0%;"></div>
    </div>
  </div>

  <div class="cart-drawer-body" id="cartDrawerBody">
    <!-- Items dynamically injected -->
  </div>

  <div class="cart-drawer-footer" id="cartDrawerFooter">
    <!-- Kupon Alanı -->
    <div class="cart-coupon-wrap">
      <div class="cart-coupon-input-group">
        <input type="text" id="cartCouponInput" placeholder="Kupon / İndirim Kodu (örn: HOSGELDIN10)" autocomplete="off">
        <button type="button" id="cartCouponApplyBtn">Uygula</button>
      </div>
      <div id="cartCouponStatus" class="cart-coupon-status" style="display: none;"></div>
    </div>

    <!-- Sipariş Notu -->
    <div class="cart-note-toggle" id="cartNoteToggle">
      <span>📝 Sipariş / Hediye Notu Ekle</span>
    </div>
    <div class="cart-note-box" id="cartNoteBox" style="display: none;">
      <textarea id="cartOrderNote" placeholder="Siparişiniz veya teslimatınız için özel bir notunuz var mı?"></textarea>
    </div>

    <!-- Tutar Özeti -->
    <div class="cart-summary">
      <div class="cart-summary-row">
        <span>Ara Toplam</span>
        <span id="cartSubtotal">₺0,00</span>
      </div>
      <div class="cart-summary-row cart-discount-row" id="cartDiscountRow" style="display: none;">
        <span id="cartDiscountLabel">Kupon İndirimi</span>
        <span id="cartDiscountAmount">-₺0,00</span>
      </div>
      <div class="cart-summary-row">
        <span>Kargo</span>
        <span id="cartShippingCost">₺79,90</span>
      </div>
      <div class="cart-summary-row cart-total-row">
        <span>Genel Toplam</span>
        <span id="cartGrandTotal">₺0,00</span>
      </div>
    </div>

    <div class="cart-actions">
      <button class="btn btn-wa-cart" id="cartWhatsAppCheckoutBtn">
        <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
          <path d="M20.52 3.48A11.81 11.81 0 0 0 12 0C5.38 0 0 5.38 0 12c0 2.11.55 4.17 1.6 6L0 24l6.3-1.65A11.93 11.93 0 0 0 12 24c6.62 0 12-5.38 12-12 0-3.2-1.25-6.21-3.48-8.52zM12 22c-1.85 0-3.67-.5-5.25-1.44l-.37-.22-3.87 1.01 1.04-3.77-.24-.38A9.94 9.94 0 0 1 2 12C2 6.48 6.48 2 12 2c2.67 0 5.18 1.04 7.07 2.93A9.94 9.94 0 0 1 22 12c0 5.52-4.48 10-10 10zm5.44-7.4c-.3-.15-1.76-.87-2.03-.97s-.47-.15-.67.15-.77.97-.94 1.17-.35.22-.64.07c-.3-.15-1.25-.46-2.38-1.47a8.94 8.94 0 0 1-1.65-2.05c-.17-.3-.02-.46.13-.6.13-.13.3-.34.45-.51s.2-.3.3-.5.05-.37-.02-.52c-.07-.15-.67-1.6-.91-2.19-.24-.57-.49-.5-.67-.5h-.57c-.2 0-.52.07-.8.37s-1.05 1.02-1.05 2.5 1.07 2.9 1.22 3.1c.15.2 2.1 3.2 5.1 4.49.71.31 1.27.5 1.7.63.71.23 1.36.2 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.69.25-1.28.17-1.41-.07-.13-.27-.2-.57-.35z"/>
        </svg>
        <span>WhatsApp ile Siparişi Tamamla</span>
      </button>
      <button class="btn btn-gold btn-checkout-modal" id="cartOpenCheckoutModalBtn">
        <span>Adres Gir & Hızlı Sipariş Ver →</span>
      </button>
    </div>
  </div>
</aside>

<!-- Quick Checkout & Address Modal -->
<div class="checkout-modal-overlay" id="checkoutModalOverlay" aria-hidden="true">
  <div class="checkout-modal" id="checkoutModal" role="dialog" aria-modal="true" aria-labelledby="modalCheckoutTitle">
    <div class="checkout-modal-header">
      <h3 id="modalCheckoutTitle">Hızlı Sipariş & Teslimat Bilgisi</h3>
      <button class="cart-drawer-close" id="checkoutModalClose" aria-label="Kapat">&times;</button>
    </div>
    <div class="checkout-modal-body">
      <div style="background: var(--gold-pale); border: 1px solid rgba(201,154,69,0.3); border-radius: var(--r-sm); padding: 10px 14px; font-size: 0.82rem; color: var(--green);">
        💡 Bilgilerinizi girip siparişi onayladığınızda paketiniz özenle hazırlanır ve WhatsApp üzerinden takip kodunuz iletilir.
      </div>

      <div class="checkout-form-group">
        <label for="checkoutName">Adınız ve Soyadınız *</label>
        <input type="text" id="checkoutName" placeholder="Örn: Ahmet Yılmaz" required>
      </div>

      <div class="checkout-form-group">
        <label for="checkoutPhone">Telefon Numaranız (WhatsApp) *</label>
        <input type="tel" id="checkoutPhone" placeholder="Örn: 05XX XXX XX XX" required>
      </div>

      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
        <div class="checkout-form-group">
          <label for="checkoutCity">İl *</label>
          <input type="text" id="checkoutCity" placeholder="Örn: İstanbul" required>
        </div>
        <div class="checkout-form-group">
          <label for="checkoutDistrict">İlçe *</label>
          <input type="text" id="checkoutDistrict" placeholder="Örn: Kadıköy" required>
        </div>
      </div>

      <div class="checkout-form-group">
        <label for="checkoutAddress">Açık Teslimat Adresi *</label>
        <textarea id="checkoutAddress" rows="2" placeholder="Mahalle, cadde, sokak, bina ve daire no..." required></textarea>
      </div>

      <div class="checkout-form-group">
        <label>Ödeme Tercihiniz</label>
        <div class="checkout-payment-methods">
          <div class="payment-method-card active" data-method="havale">
            <div class="payment-method-title">🏦 Havale / EFT (%5 İndirimli)</div>
            <div class="payment-method-desc">Sipariş sonrası doğrudan işletme IBAN hesabımıza ödeme.</div>
          </div>
          <div class="payment-method-card" data-method="kapida">
            <div class="payment-method-title">📦 Kapıda Ödeme</div>
            <div class="payment-method-desc">Teslimatta kuryeye nakit veya kart ile ödeme.</div>
          </div>
        </div>
      </div>

      <div class="checkout-bank-details" id="checkoutBankDetails">
        <div><strong>Banka:</strong> Ziraat Bankası</div>
        <div><strong>Hesap Sahibi:</strong> Nutopia Gıda & Fındık Değirmeni</div>
        <div><strong>IBAN:</strong> TR12 0001 0000 0000 0000 00</div>
        <div style="margin-top: 6px; font-size: 0.76rem; color: var(--gold-dark); font-weight: 600;">
          🎉 Havale ile ödemede %5 ek indirim uygulanacaktır.
        </div>
      </div>

      <div style="border-top: 1px solid var(--line); padding-top: 12px; display: flex; justify-content: space-between; align-items: baseline;">
        <span style="font-size: 0.88rem; color: var(--muted);">Ödenecek Tutar:</span>
        <span style="font-family: var(--font-serif); font-size: 1.3rem; font-weight: 700; color: var(--green);" id="modalTotalAmount">₺0,00</span>
      </div>

      <button class="btn btn-dark" id="checkoutSubmitBtn" style="width: 100%; padding: 13px; font-size: 0.95rem;">
        Siparişi Onayla ve Tamamla →
      </button>
    </div>
  </div>
</div>

<!-- PRODUCT QUICK VIEW & NUTRITION FACTS MODAL -->
<div class="quickview-modal-overlay" id="quickviewModalOverlay" aria-hidden="true">
  <div class="quickview-modal" id="quickviewModal" role="dialog" aria-modal="true" aria-labelledby="qvTitle">
    <button class="cart-drawer-close qv-close-btn" id="quickviewClose" aria-label="Kapat">&times;</button>
    <div class="qv-body">
      <div class="qv-media">
        <img id="qvImage" src="/images/urun-ezme.png" alt="Nutopiano Ürünü">
        <div class="qv-badge-tag" id="qvBadge">Saf Ezme</div>
      </div>
      <div class="qv-details">
        <span class="product-family" id="qvFamily">Krema Serisi</span>
        <h3 class="qv-title" id="qvTitle">Ürün Adı</h3>
        <p class="qv-desc" id="qvDesc">Açıklama</p>

        <!-- Nutrition Facts Table (100g İçin) -->
        <div class="nutrition-facts-box">
          <div class="nutrition-head">Besin Değerleri (100 g için ortalama)</div>
          <div class="nutrition-grid">
            <div class="nutrition-col"><span class="nutrition-val" id="qvCal">628</span><span class="nutrition-lbl">Enerji (kcal)</span></div>
            <div class="nutrition-col"><span class="nutrition-val" id="qvProtein">15.2 g</span><span class="nutrition-lbl">Protein</span></div>
            <div class="nutrition-col"><span class="nutrition-val" id="qvFat">60.8 g</span><span class="nutrition-lbl">Doğal Yağ</span></div>
            <div class="nutrition-col"><span class="nutrition-val" id="qvCarb">16.7 g</span><span class="nutrition-lbl">Karbonhidrat</span></div>
          </div>
        </div>

        <div class="qv-ingredients-box">
          <strong>İçindekiler:</strong> <span id="qvIngredients">%100 Kavrulmuş Karadeniz Fındığı.</span>
        </div>

        <div class="qv-allergen-box" id="qvAllergen">
          ⚠️ <strong>Alerjen Uyarısı:</strong> Fındık içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.
        </div>

        <div class="qv-action-area">
          <div class="qv-price-row">
            <span class="qv-price" id="qvPrice">₺195</span>
            <span class="qv-variant-label" id="qvVariantLabel">320 g Cam Kavanoz</span>
          </div>
          <button type="button" class="btn btn-dark btn-lg" id="qvAddToCartBtn" style="width: 100%;">
            🛒 Bu Ürünü Sepete Ekle
          </button>
        </div>
      </div>
    </div>
  </div>
</div>

<!-- FULLSCREEN IMAGE LIGHTBOX -->
<div class="lightbox-overlay" id="lightboxOverlay" aria-hidden="true">
  <button class="lightbox-close" id="lightboxClose" aria-label="Kapat">&times;</button>
  <img id="lightboxImg" src="" alt="Büyük Görsel">
  <div id="lightboxCaption" class="lightbox-caption"></div>
</div>

<!-- Toast element -->
<div class="nutopia-toast" id="nutopiaToast">
  <span style="color: var(--gold); font-size: 1.2rem;">✓</span>
  <span id="nutopiaToastText">Ürün sepete eklendi!</span>
</div>`;

  /* -----------------------------------------------------------------------
     5. ÜRÜN & BESİN DEĞERLERİ BİLGİ BANKASI
     ----------------------------------------------------------------------- */
  const PRODUCTS_DATA = {
    'Sütlü Fındık Kreması': {
      family: 'Krema Serisi',
      name: 'Sütlü Fındık Kreması',
      desc: 'Doğal Karadeniz fındığının yoğun lezzetini yumuşacık sütlü krema dokusuyla buluşturur. Kahvaltı sofralarının ve gurme tatlı tariflerinin vazgeçilmez favorisidir.',
      img: '/images/urun-sutlu.png?v=3',
      badge: 'Krema Serisi',
      calories: '542 kcal',
      protein: '9.4 g',
      fat: '34.2 g',
      carb: '52.1 g',
      ingredients: 'Karadeniz Fındığı (%45), Süt Tozu, Şeker Pancarı Şekeri, Doğal Vanilya Aroması.',
      allergen: 'Fındık ve süt ürünü (laktoz) içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.',
      price: 165,
      variant: '300 g Cam Kavanoz'
    },
    'Kakaolu Fındık Kreması': {
      family: 'Krema Serisi',
      name: 'Kakaolu Fındık Kreması',
      desc: 'Fındığın zengin aroması ve birinci sınıf kakaonun karakteristik çikolata lezzetinin buluştuğu ipeksi, akışkan ve yoğun özel krema.',
      img: '/images/urun-kakaolu.png?v=3',
      badge: 'Krema Serisi',
      calories: '535 kcal',
      protein: '8.8 g',
      fat: '33.6 g',
      carb: '53.4 g',
      ingredients: 'Karadeniz Fındığı (%45), Doğal Kakao Tozu, Şeker Pancarı Şekeri, Süt Tozu, Doğal Vanilya.',
      allergen: 'Fındık ve süt ürünü (laktoz) içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.',
      price: 165,
      variant: '300 g Cam Kavanoz'
    },
    '%100 Fındık Ezmesi': {
      family: 'Saf Ezme',
      name: '%100 Fındık Ezmesi',
      desc: 'Yalnızca taş değirmenimizde çekilmiş seçme Karadeniz fındığı. İlave şeker, palm yağı, koruyucu veya emülgatör içermez. Doğal fındık yağı üstte toplanabilir; karıştırarak tüketiniz.',
      img: '/images/urun-ezme.png?v=3',
      badge: 'Saf & Şekersiz',
      calories: '628 kcal',
      protein: '15.2 g',
      fat: '60.8 g',
      carb: '16.7 g',
      ingredients: '%100 Kavrulmuş Karadeniz Fındığı. (İlave şeker, tuz, yağ YOKTUR)',
      allergen: 'Yalnızca fındık içerir. Vegan ve glutensiz tüketime %100 uygundur.',
      price: 195,
      variant: '320 g Cam Kavanoz'
    },
    'Fındık Krokan': {
      family: 'Geleneksel Tat',
      name: 'Fındık Krokan',
      desc: 'Kavrulmuş fındığın çıtır dokusunu karamelize lezzetle buluşturan geleneksel krokan. Kahve yanına ve tatlı süslemelerine harika eşlik eder.',
      img: '/images/urun-krokan.png?v=3',
      badge: 'Geleneksel Çıtır',
      calories: '512 kcal',
      protein: '9.6 g',
      fat: '31.4 g',
      carb: '54.2 g',
      ingredients: 'Kavrulmuş Fındık (%60), Şeker Pancarı Şekeri.',
      allergen: 'Fındık içerir.',
      price: 145,
      variant: '250 g Özel Paket'
    },
    'Kavrulmuş Fındık': {
      family: 'Çıtır Lezzet',
      name: 'Kavrulmuş Fındık',
      desc: 'Özel derecede fırınlanmış, zarları özenle soyulmuş ve hava almaz vakum poşette anında kapatılmış çıtır Karadeniz fındığı.',
      img: '/images/urun-kavrulmus.png?v=3',
      badge: 'Vakumlu Tazelik',
      calories: '646 kcal',
      protein: '15.0 g',
      fat: '62.4 g',
      carb: '17.6 g',
      ingredients: '%100 Kavrulmuş ve Zarı Soyulmuş Karadeniz Fındığı.',
      allergen: 'Fındık içerir.',
      price: 275,
      variant: '500 g Vakumlu Paket'
    },
    'Çiğ Fındık': {
      family: 'Seçme İç Fındık',
      name: 'Çiğ Fındık',
      desc: 'Hiçbir kavurma veya işlem görmeden sunulan, besin değeri, E vitamini ve doğal antioksidanları en üst düzeyde seçilmiş iç fındık.',
      img: '/images/findik-kase-doga.png',
      badge: 'Doğal & Çiğ',
      calories: '628 kcal',
      protein: '15.0 g',
      fat: '60.8 g',
      carb: '16.7 g',
      ingredients: '%100 Doğal Çiğ İç Karadeniz Fındığı.',
      allergen: 'Fındık içerir.',
      price: 260,
      variant: '500 g Vakumlu Paket'
    },
    'Kabuklu Fındık': {
      family: 'Kabuklu',
      name: 'Kabuklu Fındık',
      desc: 'Doğal sert kabuğu içinde, dalından toplandığı geleneksel haliyle kurutulmuş ve elenmiş Karadeniz fındığı.',
      img: '/images/nutopia-onluk.png',
      badge: 'Geleneksel Hasat',
      calories: '628 kcal',
      protein: '15.0 g',
      fat: '60.8 g',
      carb: '16.7 g',
      ingredients: 'Doğal Kabuklu Karadeniz Fındığı.',
      allergen: 'Fındık içerir.',
      price: 220,
      variant: '1 kg Paket'
    }
  };

  /* -----------------------------------------------------------------------
     6. CART STATE & SHOPPING LOGIC
     ----------------------------------------------------------------------- */
  const FREE_SHIPPING_THRESHOLD = 750;
  const STANDARD_SHIPPING_FEE = 79.90;

  const COUPONS = {
    'HOSGELDIN10': { type: 'percent', val: 10, label: '%10 Hoş Geldin İndirimi' },
    'GAZI20':       { type: 'percent', val: 20, label: '%20 Şehit/Gazi İndirimi' },
    'FINDIK50':     { type: 'fixed',   val: 50, label: '₺50 İndirim' }
  };

  class CartManager {
    constructor() {
      this.items = this.loadCart();
      this.orderNote = localStorage.getItem('nutopia_order_note') || '';
      this.appliedCoupon = this.loadCoupon();
      this.selectedPaymentMethod = 'havale';
      this.activeQuickViewProduct = null;
    }

    loadCart() {
      try {
        const data = localStorage.getItem('nutopia_cart');
        return data ? JSON.parse(data) : [];
      } catch (e) {
        return [];
      }
    }

    loadCoupon() {
      try {
        const c = localStorage.getItem('nutopia_coupon');
        return c ? JSON.parse(c) : null;
      } catch (e) {
        return null;
      }
    }

    saveCart() {
      try {
        localStorage.setItem('nutopia_cart', JSON.stringify(this.items));
        localStorage.setItem('nutopia_order_note', this.orderNote);
        if (this.appliedCoupon) {
          localStorage.setItem('nutopia_coupon', JSON.stringify(this.appliedCoupon));
        } else {
          localStorage.removeItem('nutopia_coupon');
        }
      } catch (e) {}
      this.updateUI();
    }

    applyCoupon(code) {
      const cleanCode = (code || '').trim().toUpperCase();
      if (!cleanCode) return { success: false, msg: 'Lütfen bir kupon kodu giriniz.' };

      if (COUPONS[cleanCode]) {
        this.appliedCoupon = { code: cleanCode, ...COUPONS[cleanCode] };
        this.saveCart();
        return { success: true, msg: `🎉 "${cleanCode}" kuponu başarıyla uygulandı (${this.appliedCoupon.label})!` };
      } else {
        return { success: false, msg: 'Geçersiz kupon kodu. (Örn: HOSGELDIN10, GAZI20)' };
      }
    }

    removeCoupon() {
      this.appliedCoupon = null;
      this.saveCart();
    }

    getDiscount() {
      if (!this.appliedCoupon) return 0;
      const subtotal = this.getSubtotal();
      if (this.appliedCoupon.type === 'percent') {
        return subtotal * (this.appliedCoupon.val / 100);
      }
      if (this.appliedCoupon.type === 'fixed') {
        return Math.min(subtotal, this.appliedCoupon.val);
      }
      return 0;
    }

    addItem(product) {
      const key = `${product.name}__${product.variant}`;
      const existing = this.items.find(i => `${i.name}__${i.variant}` === key);
      const qty = product.quantity || 1;

      if (existing) {
        existing.quantity += qty;
      } else {
        this.items.push({
          id: product.id || String(Date.now()),
          name: product.name,
          variant: product.variant || '',
          price: Number(product.price) || 0,
          image: product.image || '/images/urun-ezme.png',
          quantity: qty
        });
      }

      this.saveCart();
      this.showToast(`"${product.name} (${product.variant})" sepete eklendi!`);
      this.openDrawer();
    }

    updateQuantity(index, delta) {
      if (this.items[index]) {
        this.items[index].quantity += delta;
        if (this.items[index].quantity <= 0) {
          this.items.splice(index, 1);
        }
        this.saveCart();
      }
    }

    removeItem(index) {
      if (this.items[index]) {
        this.items.splice(index, 1);
        this.saveCart();
      }
    }

    clearCart() {
      this.items = [];
      this.saveCart();
    }

    getTotalCount() {
      return this.items.reduce((sum, item) => sum + item.quantity, 0);
    }

    getSubtotal() {
      return this.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    }

    getShippingCost() {
      const subtotal = this.getSubtotal();
      if (subtotal === 0) return 0;
      return subtotal >= FREE_SHIPPING_THRESHOLD ? 0 : STANDARD_SHIPPING_FEE;
    }

    getGrandTotal(applyHavaleDiscount = false) {
      const sub = this.getSubtotal();
      if (sub === 0) return 0;
      const discount = this.getDiscount();
      const discountedSub = Math.max(0, sub - discount);
      const ship = this.getShippingCost();

      let total = discountedSub + ship;
      if (applyHavaleDiscount) {
        total = (discountedSub * 0.95) + ship;
      }
      return total;
    }

    formatMoney(num) {
      return '₺' + num.toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    openDrawer() {
      const drawer = document.getElementById('cartDrawer');
      const overlay = document.getElementById('cartOverlay');
      if (drawer && overlay) {
        drawer.classList.add('open');
        overlay.classList.add('open');
        drawer.setAttribute('aria-hidden', 'false');
        overlay.setAttribute('aria-hidden', 'false');
      }
    }

    closeDrawer() {
      const drawer = document.getElementById('cartDrawer');
      const overlay = document.getElementById('cartOverlay');
      if (drawer && overlay) {
        drawer.classList.remove('open');
        overlay.classList.remove('open');
        drawer.setAttribute('aria-hidden', 'true');
        overlay.setAttribute('aria-hidden', 'true');
      }
    }

    openCheckoutModal() {
      if (this.items.length === 0) {
        this.showToast('Sepetiniz henüz boş!');
        return;
      }
      this.closeDrawer();
      const modal = document.getElementById('checkoutModalOverlay');
      if (modal) {
        modal.classList.add('open');
        modal.setAttribute('aria-hidden', 'false');
        this.updateModalTotal();
      }
    }

    closeCheckoutModal() {
      const modal = document.getElementById('checkoutModalOverlay');
      if (modal) {
        modal.classList.remove('open');
        modal.setAttribute('aria-hidden', 'true');
      }
    }

    openQuickView(productKey) {
      const product = PRODUCTS_DATA[productKey];
      if (!product) return;

      this.activeQuickViewProduct = product;

      document.getElementById('qvTitle').textContent = product.name;
      document.getElementById('qvFamily').textContent = product.family;
      document.getElementById('qvDesc').textContent = product.desc;
      document.getElementById('qvImage').src = product.img;
      document.getElementById('qvBadge').textContent = product.badge;

      document.getElementById('qvCal').textContent = product.calories;
      document.getElementById('qvProtein').textContent = product.protein;
      document.getElementById('qvFat').textContent = product.fat;
      document.getElementById('qvCarb').textContent = product.carb;

      document.getElementById('qvIngredients').textContent = product.ingredients;
      document.getElementById('qvAllergen').innerHTML = `⚠️ <strong>Alerjen:</strong> ${product.allergen}`;

      document.getElementById('qvPrice').textContent = this.formatMoney(product.price);
      document.getElementById('qvVariantLabel').textContent = product.variant;

      const overlay = document.getElementById('quickviewModalOverlay');
      if (overlay) {
        overlay.classList.add('open');
        overlay.setAttribute('aria-hidden', 'false');
      }
    }

    closeQuickView() {
      const overlay = document.getElementById('quickviewModalOverlay');
      if (overlay) {
        overlay.classList.remove('open');
        overlay.setAttribute('aria-hidden', 'true');
      }
    }

    openLightbox(imgSrc, caption = '') {
      const overlay = document.getElementById('lightboxOverlay');
      const img = document.getElementById('lightboxImg');
      const cap = document.getElementById('lightboxCaption');
      if (overlay && img) {
        img.src = imgSrc;
        if (cap) cap.textContent = caption;
        overlay.classList.add('open');
        overlay.setAttribute('aria-hidden', 'false');
      }
    }

    closeLightbox() {
      const overlay = document.getElementById('lightboxOverlay');
      if (overlay) {
        overlay.classList.remove('open');
        overlay.setAttribute('aria-hidden', 'true');
      }
    }

    showToast(text) {
      const toast = document.getElementById('nutopiaToast');
      const toastText = document.getElementById('nutopiaToastText');
      if (toast && toastText) {
        toastText.textContent = text;
        toast.classList.add('show');
        clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => {
          toast.classList.remove('show');
        }, 3200);
      }
    }

    updateModalTotal() {
      const totalEl = document.getElementById('modalTotalAmount');
      if (totalEl) {
        const isHavale = this.selectedPaymentMethod === 'havale';
        totalEl.textContent = this.formatMoney(this.getGrandTotal(isHavale));
      }
    }

    updateUI() {
      const totalCount = this.getTotalCount();
      const subtotal = this.getSubtotal();
      const discount = this.getDiscount();
      const shipping = this.getShippingCost();
      const grandTotal = this.getGrandTotal();

      // Badges
      const cartBadge = document.getElementById('cartBadge');
      const mobileBadge = document.getElementById('mobileCartBadge');
      const floatCount = document.getElementById('cartFloatCount');
      const countBadge = document.getElementById('cartCountBadge');
      const bottomNavBadge = document.getElementById('mobileBottomCartBadge');

      [cartBadge, mobileBadge, floatCount, bottomNavBadge].forEach(el => {
        if (el) {
          el.textContent = totalCount;
          el.style.display = totalCount > 0 ? 'flex' : 'none';
        }
      });
      if (countBadge) countBadge.textContent = `(${totalCount})`;

      // Floating button visibility
      const floatBtn = document.getElementById('cartFloatBtn');
      if (floatBtn) {
        floatBtn.style.display = totalCount > 0 ? 'flex' : 'none';
      }

      // Free shipping progress bar
      const shippingBar = document.getElementById('cartShippingBar');
      const shippingRemainingText = document.getElementById('shippingRemainingText');
      if (shippingBar && shippingRemainingText) {
        if (subtotal === 0) {
          shippingBar.style.width = '0%';
          shippingRemainingText.textContent = '';
        } else if (subtotal >= FREE_SHIPPING_THRESHOLD) {
          shippingBar.style.width = '100%';
          shippingRemainingText.innerHTML = '<strong style="color: var(--gold-dark);">Tebrikler, Kargo Ücretsiz!</strong>';
        } else {
          const percent = Math.min(100, Math.round((subtotal / FREE_SHIPPING_THRESHOLD) * 100));
          shippingBar.style.width = percent + '%';
          const diff = FREE_SHIPPING_THRESHOLD - subtotal;
          shippingRemainingText.textContent = `${this.formatMoney(diff)} daha ekleyin`;
        }
      }

      // Kupon Alanı & İndirim Gösterimi
      const discountRow = document.getElementById('cartDiscountRow');
      const discountLabel = document.getElementById('cartDiscountLabel');
      const discountAmount = document.getElementById('cartDiscountAmount');
      const couponStatus = document.getElementById('cartCouponStatus');

      if (discountRow) {
        if (discount > 0 && this.appliedCoupon) {
          discountRow.style.display = 'flex';
          if (discountLabel) discountLabel.textContent = `İndirim (${this.appliedCoupon.label})`;
          if (discountAmount) discountAmount.textContent = `-${this.formatMoney(discount)}`;
          if (couponStatus) {
            couponStatus.className = 'cart-coupon-status success';
            couponStatus.style.display = 'block';
            couponStatus.innerHTML = `✓ "${this.appliedCoupon.code}" kuponu aktif. <a href="javascript:void(0)" id="cartRemoveCouponBtn" style="color: #b91c1c; margin-left: 6px; text-decoration: underline;">Kaldır</a>`;
          }
        } else {
          discountRow.style.display = 'none';
          if (couponStatus) couponStatus.style.display = 'none';
        }
      }

      // Summary
      const subtotalEl = document.getElementById('cartSubtotal');
      const shippingEl = document.getElementById('cartShippingCost');
      const grandTotalEl = document.getElementById('cartGrandTotal');
      const footerEl = document.getElementById('cartDrawerFooter');

      if (subtotalEl) subtotalEl.textContent = this.formatMoney(subtotal);
      if (shippingEl) {
        shippingEl.textContent = subtotal === 0 ? '₺0,00' : (shipping === 0 ? 'Ücretsiz' : this.formatMoney(shipping));
        shippingEl.style.color = shipping === 0 && subtotal > 0 ? 'var(--wa)' : 'inherit';
      }
      if (grandTotalEl) grandTotalEl.textContent = this.formatMoney(grandTotal);
      if (footerEl) footerEl.style.display = totalCount === 0 ? 'none' : 'block';

      // Items list
      const bodyEl = document.getElementById('cartDrawerBody');
      if (bodyEl) {
        if (this.items.length === 0) {
          bodyEl.innerHTML = `
            <div class="cart-empty">
              <div class="cart-empty-icon">
                <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
                  <circle cx="9" cy="21" r="1"></circle>
                  <circle cx="20" cy="21" r="1"></circle>
                  <path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"></path>
                </svg>
              </div>
              <h4>Sepetiniz Henüz Boş</h4>
              <p>Doğal, katkısız ve taze Karadeniz fındık ürünlerimizi hemen keşfedin.</p>
              <a href="/urunler" class="btn btn-gold btn-sm" onclick="window.NutopiaCart.closeDrawer()">
                Ürünleri İncele →
              </a>
            </div>
          `;
        } else {
          bodyEl.innerHTML = this.items.map((item, idx) => `
            <div class="cart-item">
              <img src="${item.image}" alt="${item.name}" class="cart-item-img" onerror="this.src='/images/urun-ezme.png'">
              <div class="cart-item-info">
                <div class="cart-item-title">${item.name}</div>
                ${item.variant ? `<div class="cart-item-variant">${item.variant}</div>` : ''}
                <div class="cart-item-bottom">
                  <div class="cart-stepper">
                    <button type="button" data-cart-action="dec" data-index="${idx}" aria-label="Adet Azalt">-</button>
                    <span>${item.quantity}</span>
                    <button type="button" data-cart-action="inc" data-index="${idx}" aria-label="Adet Artır">+</button>
                  </div>
                  <div class="cart-item-price">${this.formatMoney(item.price * item.quantity)}</div>
                </div>
              </div>
              <button class="cart-item-remove" data-cart-action="remove" data-index="${idx}" aria-label="Ürünü Sil">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <polyline points="3 6 5 6 21 6"></polyline>
                  <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
                </svg>
              </button>
            </div>
          `).join('');
        }
      }
    }

    buildWhatsAppMessage(customerInfo = null) {
      let lines = [];
      lines.push('🌿 *NUTOPIANO SİPARİŞİ*');
      lines.push('------------------------------');

      this.items.forEach((item, index) => {
        const itemLine = `${index + 1}. *${item.name}* (${item.variant}) x ${item.quantity} adet = ${this.formatMoney(item.price * item.quantity)}`;
        lines.push(itemLine);
      });

      lines.push('------------------------------');
      lines.push(`📦 *Ara Toplam:* ${this.formatMoney(this.getSubtotal())}`);

      const discount = this.getDiscount();
      if (discount > 0 && this.appliedCoupon) {
        lines.push(`🎟️ *Kupon İndirimi (${this.appliedCoupon.code}):* -${this.formatMoney(discount)}`);
      }

      const ship = this.getShippingCost();
      lines.push(`🚚 *Kargo:* ${ship === 0 ? 'Ücretsiz (750 ₺ Üzeri Kampanyası)' : this.formatMoney(ship)}`);

      if (customerInfo && customerInfo.paymentMethod === 'havale') {
        lines.push(`💳 *Ödeme Türü:* Havale / EFT (%5 İndirimli)`);
        lines.push(`💰 *Ödenecek Net Tutar:* ${this.formatMoney(this.getGrandTotal(true))}`);
      } else {
        const paymentLabel = customerInfo && customerInfo.paymentMethod === 'kapida' ? 'Kapıda Ödeme' : 'Online / WhatsApp';
        lines.push(`💳 *Ödeme Türü:* ${paymentLabel}`);
        lines.push(`💰 *Genel Toplam:* ${this.formatMoney(this.getGrandTotal(false))}`);
      }

      const note = document.getElementById('cartOrderNote')?.value || this.orderNote;
      if (note && note.trim()) {
        lines.push('');
        lines.push(`📝 *Sipariş / Hediye Notu:* ${note.trim()}`);
      }

      if (customerInfo) {
        lines.push('');
        lines.push('📍 *TESLİMAT BİLGİLERİ:*');
        lines.push(`👤 *Alıcı:* ${customerInfo.name}`);
        lines.push(`📞 *Telefon:* ${customerInfo.phone}`);
        lines.push(`🏠 *Adres:* ${customerInfo.address}`);
        lines.push(`🏙️ *Şehir / İlçe:* ${customerInfo.district} / ${customerInfo.city}`);
      } else {
        lines.push('');
        lines.push('Siparişimi iletmek ve adres/ödeme detaylarını netleştirmek istiyorum.');
      }

      return lines.join('\n');
    }

    checkoutWhatsApp(customerInfo = null) {
      if (this.items.length === 0) {
        this.showToast('Sepetiniz boş!');
        return;
      }
      const message = this.buildWhatsAppMessage(customerInfo);
      const url = `https://wa.me/905380288202?text=${encodeURIComponent(message)}`;
      window.open(url, '_blank');
    }
  }

  /* -----------------------------------------------------------------------
     7. ENJEKSİYON VE OLAY DİNLEYİCİLERİ
     ----------------------------------------------------------------------- */
  function initApp() {
    // 1. Header & Footer Enjeksiyonu
    const headerSlot = document.getElementById('site-header');
    if (headerSlot) headerSlot.outerHTML = HEADER_HTML;

    const footerSlot = document.getElementById('site-footer');
    if (footerSlot) footerSlot.outerHTML = FOOTER_HTML;

    // 2. Cart Drawer & Modal Enjeksiyonu
    const cartContainer = document.createElement('div');
    cartContainer.id = 'cartContainerRoot';
    cartContainer.innerHTML = CART_COMPONENTS_HTML;
    document.body.appendChild(cartContainer);

    // 3. Aktif Nav Linki
    if (activeId) {
      const el = document.getElementById(activeId);
      if (el) el.classList.add('current');
    }

    // 4. Yıl Güncelleme
    document.querySelectorAll('.js-year').forEach(el => {
      el.textContent = new Date().getFullYear();
    });

    // 5. Header Scroll Efekti
    const header = document.getElementById('siteHeader');
    if (header) {
      const onScroll = () => header.classList.toggle('scrolled', window.scrollY > 40);
      window.addEventListener('scroll', onScroll, { passive: true });
      onScroll();
    }

    // 6. Mobil Nav Menü Kontrolü
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

    // 7. Cart Manager Başlat
    const cart = new CartManager();
    window.NutopiaCart = cart;

    // 8. Event Listeners: Sepet Açma / Kapatma
    const openCartHandler = (e) => {
      if (e) e.preventDefault();
      cart.openDrawer();
    };

    document.getElementById('headerCartBtn')?.addEventListener('click', openCartHandler);
    document.getElementById('mobileCartLink')?.addEventListener('click', openCartHandler);
    document.getElementById('cartFloatBtn')?.addEventListener('click', openCartHandler);

    document.getElementById('cartDrawerClose')?.addEventListener('click', () => cart.closeDrawer());
    document.getElementById('cartOverlay')?.addEventListener('click', () => cart.closeDrawer());

    // Sepet İçi Aksiyonlar (+ / - / sil)
    document.getElementById('cartDrawerBody')?.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-cart-action]');
      if (!btn) return;
      const action = btn.dataset.cartAction;
      const idx = parseInt(btn.dataset.index, 10);

      if (action === 'inc') cart.updateQuantity(idx, 1);
      if (action === 'dec') cart.updateQuantity(idx, -1);
      if (action === 'remove') cart.removeItem(idx);
    });

    // Kupon Uygulama / Kaldırma
    document.getElementById('cartCouponApplyBtn')?.addEventListener('click', () => {
      const inp = document.getElementById('cartCouponInput');
      const res = cart.applyCoupon(inp?.value);
      const statusEl = document.getElementById('cartCouponStatus');
      if (statusEl) {
        statusEl.className = res.success ? 'cart-coupon-status success' : 'cart-coupon-status error';
        statusEl.textContent = res.msg;
        statusEl.style.display = 'block';
      }
    });

    document.addEventListener('click', (e) => {
      if (e.target.id === 'cartRemoveCouponBtn') {
        cart.removeCoupon();
      }
    });

    // Not Kutusu Toggle
    document.getElementById('cartNoteToggle')?.addEventListener('click', () => {
      const box = document.getElementById('cartNoteBox');
      if (box) {
        box.style.display = box.style.display === 'none' ? 'block' : 'none';
      }
    });

    // WhatsApp Sipariş Tamamlama
    document.getElementById('cartWhatsAppCheckoutBtn')?.addEventListener('click', () => {
      cart.checkoutWhatsApp();
    });

    // Hızlı Adres / Checkout Modal Açma
    document.getElementById('cartOpenCheckoutModalBtn')?.addEventListener('click', () => {
      cart.openCheckoutModal();
    });
    document.getElementById('checkoutModalClose')?.addEventListener('click', () => {
      cart.closeCheckoutModal();
    });
    document.getElementById('checkoutModalOverlay')?.addEventListener('click', (e) => {
      if (e.target.id === 'checkoutModalOverlay') {
        cart.closeCheckoutModal();
      }
    });

    // Quick View Modal Kapatma
    document.getElementById('quickviewClose')?.addEventListener('click', () => cart.closeQuickView());
    document.getElementById('quickviewModalOverlay')?.addEventListener('click', (e) => {
      if (e.target.id === 'quickviewModalOverlay') {
        cart.closeQuickView();
      }
    });

    // Quick View Sepete Ekle Butonu
    document.getElementById('qvAddToCartBtn')?.addEventListener('click', () => {
      if (cart.activeQuickViewProduct) {
        cart.addItem({
          name: cart.activeQuickViewProduct.name,
          variant: cart.activeQuickViewProduct.variant,
          price: cart.activeQuickViewProduct.price,
          image: cart.activeQuickViewProduct.img,
          quantity: 1
        });
        cart.closeQuickView();
      }
    });

    // Lightbox Kapatma
    document.getElementById('lightboxClose')?.addEventListener('click', () => cart.closeLightbox());
    document.getElementById('lightboxOverlay')?.addEventListener('click', (e) => {
      if (e.target.id === 'lightboxOverlay') {
        cart.closeLightbox();
      }
    });

    // ESC Tuşu ile Modalleri Kapatma
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        cart.closeDrawer();
        cart.closeCheckoutModal();
        cart.closeQuickView();
        cart.closeLightbox();
      }
    });

    // Ödeme Yöntemi Seçimi (Modal İçi)
    document.querySelectorAll('.payment-method-card').forEach(cardEl => {
      cardEl.addEventListener('click', () => {
        document.querySelectorAll('.payment-method-card').forEach(c => c.classList.remove('active'));
        cardEl.classList.add('active');
        cart.selectedPaymentMethod = cardEl.dataset.method;

        const bankDetails = document.getElementById('checkoutBankDetails');
        if (bankDetails) {
          bankDetails.style.display = cardEl.dataset.method === 'havale' ? 'block' : 'none';
        }
        cart.updateModalTotal();
      });
    });

    // Modal Form Gönderimi (WhatsApp Sipariş Oluşturma)
    document.getElementById('checkoutSubmitBtn')?.addEventListener('click', () => {
      const name = document.getElementById('checkoutName')?.value.trim();
      const phone = document.getElementById('checkoutPhone')?.value.trim();
      const city = document.getElementById('checkoutCity')?.value.trim();
      const district = document.getElementById('checkoutDistrict')?.value.trim();
      const address = document.getElementById('checkoutAddress')?.value.trim();

      if (!name || !phone || !city || !district || !address) {
        alert('Lütfen teslimat için tüm zorunlu alanları (*) doldurunuz.');
        return;
      }

      const customerInfo = {
        name,
        phone,
        city,
        district,
        address,
        paymentMethod: cart.selectedPaymentMethod
      };

      cart.checkoutWhatsApp(customerInfo);
      cart.closeCheckoutModal();
      cart.showToast('Sipariş taslağınız WhatsApp üzerinden iletildi!');
    });

    // 9. Ürün Kartları İçi Varyant, QuickView ve "Sepete Ekle" Butonları Dinleme
    document.addEventListener('click', (e) => {
      // Quick View Tetikleme
      const qvTrigger = e.target.closest('[data-quickview]');
      if (qvTrigger) {
        e.preventDefault();
        const productName = qvTrigger.dataset.quickview || qvTrigger.closest('.product-card')?.querySelector('.product-name')?.textContent.trim();
        if (productName) {
          cart.openQuickView(productName);
        }
        return;
      }

      // Lightbox Tetikleme
      const lbTrigger = e.target.closest('[data-lightbox]') || e.target.closest('.gallery-strip-card img');
      if (lbTrigger) {
        const src = lbTrigger.getAttribute('src');
        const alt = lbTrigger.getAttribute('alt') || 'Nutopia Fındık Değirmeni';
        if (src) {
          cart.openLightbox(src, alt);
        }
        return;
      }

      // Varyant Hapına Tıklama
      const pill = e.target.closest('.variant-pill');
      if (pill) {
        const group = pill.closest('.product-variant-group');
        const card = pill.closest('.product-card') || pill.closest('article');
        if (group && card) {
          group.querySelectorAll('.variant-pill').forEach(p => p.classList.remove('active'));
          pill.classList.add('active');

          const price = pill.dataset.price;
          const priceDisplay = card.querySelector('.product-card-price');
          if (priceDisplay && price) {
            priceDisplay.textContent = '₺' + Number(price).toLocaleString('tr-TR');
          }
        }
        return;
      }

      // "Sepete Ekle" Butonuna Tıklama
      const addBtn = e.target.closest('.btn-card-add');
      if (addBtn) {
        e.preventDefault();
        const card = addBtn.closest('.product-card') || addBtn.closest('article');
        if (!card) return;

        const name = card.querySelector('.product-name')?.textContent.trim() || 'Nutopiano Ürünü';
        const img = card.querySelector('.product-img img')?.getAttribute('src') || '';
        const activeVariant = card.querySelector('.variant-pill.active');

        let variant = '';
        let price = 0;

        if (activeVariant) {
          variant = activeVariant.textContent.trim();
          price = Number(activeVariant.dataset.price) || 0;
        } else {
          price = Number(addBtn.dataset.price) || 165;
          variant = addBtn.dataset.variant || 'Standart';
        }

        cart.addItem({
          name,
          variant,
          price,
          image: img,
          quantity: 1
        });

        // Buton geri bildirimi
        addBtn.classList.add('added');
        const originalText = addBtn.innerHTML;
        addBtn.innerHTML = '<span>✓ Eklendi</span>';
        setTimeout(() => {
          addBtn.classList.remove('added');
          addBtn.innerHTML = originalText;
        }, 1500);
      }
    });

    // 10. FAQ (Sıkça Sorulan Sorular) Akordeon Dinleyici
    document.addEventListener('click', (e) => {
      const qBtn = e.target.closest('.faq-question');
      if (qBtn) {
        const item = qBtn.closest('.faq-item');
        if (item) {
          const wasActive = item.classList.contains('active');
          item.closest('.faq-wrap')?.querySelectorAll('.faq-item').forEach(i => i.classList.remove('active'));
          if (!wasActive) {
            item.classList.add('active');
          }
        }
      }
    });

    // 11. Değirmen Maliyet & Mahsul Hesaplayıcısı (Milling Calculator)
    const initCalculator = () => {
      const weightSlider = document.getElementById('calcWeightSlider');
      const weightVal = document.getElementById('calcWeightVal');
      const radioCards = document.querySelectorAll('.calc-radio-card');
      const sehitGaziCheck = document.getElementById('calcSehitGaziCheck');

      if (!weightSlider || !weightVal) return;

      const calcTotal = () => {
        const kg = parseInt(weightSlider.value, 10) || 50;
        weightVal.textContent = kg + ' kg';

        const activeRadio = document.querySelector('.calc-radio-card.active');
        const unitPrice = activeRadio ? parseFloat(activeRadio.dataset.unitPrice) : 70;
        const yieldPercent = activeRadio ? parseFloat(activeRadio.dataset.yield || '0.5') : 0.5;

        // Randıman hesabı: kabukludan tahmini iç fındık
        const estYield = Math.round(kg * yieldPercent);
        const yieldEl = document.getElementById('calcEstYield');
        if (yieldEl) yieldEl.textContent = `~${estYield} kg`;

        let total = kg * unitPrice;
        if (sehitGaziCheck && sehitGaziCheck.checked) {
          total = total * 0.80; // %20 indirim
        }

        const subtotalEl = document.getElementById('calcSubtotalDisp');
        const totalEl = document.getElementById('calcTotalDisp');
        if (subtotalEl) subtotalEl.textContent = '₺' + Math.round(kg * unitPrice).toLocaleString('tr-TR');
        if (totalEl) totalEl.textContent = '₺' + Math.round(total).toLocaleString('tr-TR');

        // WhatsApp butonuna aktar
        const waBtn = document.getElementById('calcWaBookBtn');
        if (waBtn) {
          const serviceName = activeRadio?.querySelector('.calc-radio-title')?.textContent.trim() || 'Fındık İşleme';
          const isGazi = sehitGaziCheck && sehitGaziCheck.checked ? ' (%20 Şehit/Gazi İndirimli)' : '';
          const msg = `Merhaba, ${kg} kg fındığım için "${serviceName}" hizmeti almak istiyorum. Tahmini tutar: ₺${Math.round(total).toLocaleString('tr-TR')}${isGazi}. Randevu ve teslimat hakkında bilgi alabilir miyim?`;
          waBtn.href = `https://wa.me/905380288202?text=${encodeURIComponent(msg)}`;
        }
      };

      weightSlider.addEventListener('input', calcTotal);

      radioCards.forEach(card => {
        card.addEventListener('click', () => {
          radioCards.forEach(c => c.classList.remove('active'));
          card.classList.add('active');
          calcTotal();
        });
      });

      if (sehitGaziCheck) {
        sehitGaziCheck.addEventListener('change', calcTotal);
      }

      calcTotal();
    };

    // 12. Ürün Filtreleme & Arama (urunler.html)
    const initProductFilter = () => {
      const tabs = document.querySelectorAll('.cat-tab');
      const searchInput = document.getElementById('productSearchInput');
      const cards = document.querySelectorAll('.product-card[data-cat]');
      const groups = document.querySelectorAll('.product-category-group');

      if (cards.length === 0) return;

      let activeCategory = 'all';
      let searchQuery = '';

      const applyFilters = () => {
        cards.forEach(card => {
          const cardCat = card.dataset.cat || '';
          const cardKeywords = (card.dataset.keywords || '').toLowerCase();
          const cardTitle = (card.querySelector('.product-name')?.textContent || '').toLowerCase();

          const matchesCat = (activeCategory === 'all' || cardCat === activeCategory);
          const matchesSearch = !searchQuery || cardTitle.includes(searchQuery) || cardKeywords.includes(searchQuery);

          if (matchesCat && matchesSearch) {
            card.classList.remove('hidden-by-filter');
          } else {
            card.classList.add('hidden-by-filter');
          }
        });

        // Kategori başlıklarını kontrol et: grupta kart kalmadıysa gizle
        groups.forEach(group => {
          const visibleCards = group.querySelectorAll('.product-card:not(.hidden-by-filter)');
          group.style.display = visibleCards.length === 0 ? 'none' : 'block';
        });
      };

      tabs.forEach(tab => {
        tab.addEventListener('click', () => {
          tabs.forEach(t => t.classList.remove('active'));
          tab.classList.add('active');
          activeCategory = tab.dataset.category || 'all';
          applyFilters();
        });
      });

      if (searchInput) {
        searchInput.addEventListener('input', (e) => {
          searchQuery = e.target.value.toLowerCase().trim();
          applyFilters();
        });
      }
    };

    // 13. Canlı Sosyal Kanıt Bildirimleri (Live Social Proof Ticker)
    const initSocialProofToast = () => {
      const activities = [
        { icon: "🌰", text: "İstanbul / Kadıköy'den 2x %100 Fındık Ezmesi siparişi verildi.", time: "4 dakika önce" },
        { icon: "🌾", text: "Zonguldak / Kdz. Ereğli'den 220 kg Fındık Kırma & Kavurma randevusu alındı.", time: "16 dakika önce" },
        { icon: "🎁", text: "Ankara'dan bir kurumsal firma 40 adet Lüks Hediye Kutusu teklifi talep etti.", time: "38 dakika önce" },
        { icon: "🍯", text: "İzmir'den 1x Sütlü Krema ve 1x Fındık Krokan siparişi kargoya verildi.", time: "52 dakika önce" },
        { icon: "🎖️", text: "Şehit ve Gazi ailemiz %20 indirimli değirmen randevusu oluşturdu.", time: "2 saat önce" }
      ];

      const toast = document.createElement('div');
      toast.className = 'live-social-toast';
      toast.id = 'liveSocialToast';
      toast.setAttribute('aria-live', 'polite');
      toast.innerHTML = `
        <div class="live-social-icon" id="liveSocialIcon">🌰</div>
        <div class="live-social-body">
          <div class="live-social-text" id="liveSocialText">...</div>
          <div class="live-social-time">
            <span class="live-social-dot"></span>
            <span id="liveSocialTime">...</span>
          </div>
        </div>
        <button type="button" class="live-social-close" id="liveSocialClose" aria-label="Bildirimi Kapat">×</button>
      `;
      document.body.appendChild(toast);

      const iconEl = toast.querySelector('#liveSocialIcon');
      const textEl = toast.querySelector('#liveSocialText');
      const timeEl = toast.querySelector('#liveSocialTime');
      const closeBtn = toast.querySelector('#liveSocialClose');

      let currentIndex = 0;
      let isDismissed = false;

      closeBtn.addEventListener('click', () => {
        toast.classList.remove('show');
        isDismissed = true;
      });

      const showNotification = () => {
        if (isDismissed) return;
        const item = activities[currentIndex];
        iconEl.textContent = item.icon;
        textEl.textContent = item.text;
        timeEl.textContent = item.time;

        toast.classList.add('show');

        setTimeout(() => {
          toast.classList.remove('show');
        }, 5500);

        currentIndex = (currentIndex + 1) % activities.length;
      };

      // İlk bildirim 4.5 sn sonra, ardından her 26 saniyede bir
      setTimeout(() => {
        showNotification();
        setInterval(showNotification, 26000);
      }, 4500);
    };

    // 14. Mobil Alt Sabit Navigasyon Çubuğu (Mobile Bottom Bar)
    const initMobileBottomNav = () => {
      const bottomBar = document.createElement('div');
      bottomBar.className = 'mobile-bottom-bar';
      bottomBar.id = 'mobileBottomBar';
      bottomBar.innerHTML = `
        <a href="/" class="mobile-nav-link ${pathClean === '/' ? 'active' : ''}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
          <span>Ana Sayfa</span>
        </a>
        <a href="/degirmen" class="mobile-nav-link ${pathClean === '/degirmen' ? 'active' : ''}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
          <span>Değirmen</span>
        </a>
        <a href="/urunler" class="mobile-nav-link ${pathClean === '/urunler' ? 'active' : ''}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>
          <span>Ürünler</span>
        </a>
        <a href="javascript:void(0)" class="mobile-nav-link" id="mobileBottomCartBtn">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/></svg>
          <span>Sepet</span>
          <span class="mobile-nav-badge" id="mobileBottomCartBadge" style="display:none;">0</span>
        </a>
        <a href="https://wa.me/905380288202" class="mobile-nav-link" target="_blank" rel="noopener noreferrer" style="color:#25D366;">
          <svg viewBox="0 0 24 24" fill="#25D366"><path d="M20.52 3.48A11.81 11.81 0 0 0 12 0C5.38 0 0 5.38 0 12c0 2.11.55 4.17 1.6 6L0 24l6.3-1.65A11.93 11.93 0 0 0 12 24c6.62 0 12-5.38 12-12 0-3.2-1.25-6.21-3.48-8.52zM12 22c-1.85 0-3.67-.5-5.25-1.44l-.37-.22-3.87 1.01 1.04-3.77-.24-.38A9.94 9.94 0 0 1 2 12C2 6.48 6.48 2 12 2c2.67 0 5.18 1.04 7.07 2.93A9.94 9.94 0 0 1 22 12c0 5.52-4.48 10-10 10zm5.44-7.4c-.3-.15-1.76-.87-2.03-.97s-.47-.15-.67.15-.77.97-.94 1.17-.35.22-.64.07c-.3-.15-1.25-.46-2.38-1.47a8.94 8.94 0 0 1-1.65-2.05c-.17-.3-.02-.46.13-.6.13-.13.3-.34.45-.51s.2-.3.3-.5.05-.37-.02-.52c-.07-.15-.67-1.6-.91-2.19-.24-.57-.49-.5-.67-.5h-.57c-.2 0-.52.07-.8.37s-1.05 1.02-1.05 2.5 1.07 2.9 1.22 3.1c.15.2 2.1 3.2 5.1 4.49.71.31 1.27.5 1.7.63.71.23 1.36.2 1.87.12.57-.09 1.76-.72 2.01-1.41.25-.69.25-1.28.17-1.41-.07-.13-.27-.2-.57-.35z"/></svg>
          <span>WhatsApp</span>
        </a>
      `;
      document.body.appendChild(bottomBar);

      const cartBtn = document.getElementById('mobileBottomCartBtn');
      if (cartBtn) {
        cartBtn.addEventListener('click', () => cart.openDrawer());
      }
    };

    // Global erişim
    window.NutopiaCart = cart;

    // Başlatıcılar
    initCalculator();
    initProductFilter();
    initSocialProofToast();
    initMobileBottomNav();

    // İlk UI render
    cart.updateUI();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initApp);
  } else {
    initApp();
  }
})();

