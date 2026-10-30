# 26 — Tasarım Sistemi, Arayüz Bileşen Kütüphanesi ve Erişilebilirlik Standartları (UI Kit & Tokens)

> Bu belge; hem son kullanıcı vitrininde (Next.js SSR/ISR) hem de Yönetim & Şoför SPA'sında (React + Vite) kullanılacak ortak tasarım belirteçlerini (Design Tokens), Radix UI tabanlı atomik bileşen standartlarını, erişilebilirlik (WCAG 2.2 AA) kurallarını ve tipografi hiyerarşisini belirler.
> Amaç: Sıfırdan temiz, tutarlı, zanaatkâr ruhunu modern teknolojiyle birleştiren yüksek performanslı bir arayüz dili oluşturmak.

---

## 1. TASARIM BELİRTEÇLERİ (DESIGN TOKENS - CSS VARIABLES)

```css
:root {
  /* ── 1.1 Renk Paleti (Doğal, Karadeniz ve Fındık Dokusu) ── */
  --color-brand-primary: #3d2314;       /* Koyu Fındık Kabuğu (Ana Başlıklar, Ana Butonlar) */
  --color-brand-primary-hover: #29160a;
  --color-brand-secondary: #243e2b;     /* Karadeniz Orman Yeşili (Güven, Başarı, Kargo Rozetleri) */
  --color-brand-secondary-hover: #172a1d;
  --color-brand-accent: #c48c34;        /* Altın Sarısı / Kavrulmuş Fındık İçi (Fiyatlar, Yıldızlar, Vurgular) */
  --color-brand-accent-hover: #a37225;

  /* Nötr & Arka Plan Tonları */
  --color-surface-base: #fcfaf6;        /* Doğal Keten / Kırık Beyaz Zemin */
  --color-surface-card: #ffffff;        /* Kart Zeminleri */
  --color-surface-subtle: #f3ede2;      /* Hafif Gri/Bej Ayırıcı Alanlar */
  --color-surface-overlay: rgba(36, 22, 13, 0.6); /* Modal Karartması */

  /* Tipografi Renkleri */
  --color-text-main: #24160d;           /* Yüksek Kontrastlı Gövde Metni (12.8:1 Kontrast) */
  --color-text-muted: #6e5d53;          /* İkincil Bilgiler, Açıklamalar (4.8:1 Kontrast) */
  --color-text-inverse: #ffffff;        /* Koyu Zemin Üzeri Beyaz Metin */

  /* Geri Bildirim Renkleri */
  --color-status-success: #1f7a3f;      /* Başarılı Sipariş, Stokta Var */
  --color-status-warning: #b86200;      /* Kritik Stok, Nemli Fındık Uyarısı */
  --color-status-error: #b3261e;        /* Yetersiz Stok, Hatalı Ödeme */
  --color-status-info: #1a628a;         /* Kargo Yolda, Bilgilendirme */

  /* Kenarlıklar */
  --color-border-subtle: #e8ded1;
  --color-border-strong: #c7b6a1;
  --color-border-focus: #c48c34;

  /* ── 1.2 Tipografi Ölçeği (Modular Scale 1.250 - Major Third) ── */
  --font-family-serif: 'Playfair Display', Georgia, 'Times New Roman', serif; /* Başlıklar, Fiyat */
  --font-family-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; /* Arayüz, Okuma Metinleri */
  --font-family-mono: 'JetBrains Mono', 'Fira Code', monospace; /* Sipariş No, Kodlar */

  --font-size-xs: 0.75rem;    /* 12px - Rozetler, Alt Notlar */
  --font-size-sm: 0.875rem;   /* 14px - İkincil Butonlar, Yardımcı Metinler */
  --font-size-base: 1rem;     /* 16px - Temel Gövde Metni */
  --font-size-lg: 1.125rem;   /* 18px - Vurgulu Paragraflar, Şoför Ekranı Temel Yazısı */
  --font-size-xl: 1.25rem;    /* 20px - Kart Başlıkları, H3 */
  --font-size-2xl: 1.5rem;    /* 24px - Bölüm Başlıkları, H2 */
  --font-size-3xl: 2rem;      /* 32px - Sayfa Başlıkları, H1 */
  --font-size-4xl: 2.75rem;   /* 44px - Hero Başlıkları */

  /* ── 1.3 Boşluk ve Grid Sistemi (4px Temelli) ── */
  --space-1: 0.25rem;  /* 4px */
  --space-2: 0.5rem;   /* 8px */
  --space-3: 0.75rem;  /* 12px */
  --space-4: 1rem;     /* 16px */
  --space-6: 1.5rem;   /* 24px */
  --space-8: 2rem;     /* 32px */
  --space-12: 3rem;    /* 48px */
  --space-16: 4rem;    /* 64px */

  /* ── 1.4 Kenar Yuvarlama (Radii) ── */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 14px;
  --radius-full: 9999px; /* Çip ve Hap Butonlar */

  /* ── 1.5 Gölgeler (Elevation) ── */
  --shadow-sm: 0 1px 3px rgba(36, 22, 13, 0.06);
  --shadow-md: 0 4px 12px rgba(36, 22, 13, 0.08);
  --shadow-lg: 0 12px 32px rgba(36, 22, 13, 0.12);
  --shadow-drawer: -4px 0 24px rgba(36, 22, 13, 0.15);
}
```

---

## 2. ATOMİK BİLEŞEN SÖZLEŞMELERİ (`packages/ui`)

Tüm bileşenler **Radix UI Primitives** üzerine inşa edilir; WAI-ARIA erişilebilirlik standartlarını yerleşik olarak barındırır.

### 2.1 Buton Bileşeni (`Button`)
- **Varyantlar:**
  - `primary`: Zemin: `--color-brand-primary`, Yazı: Beyaz.
  - `secondary`: Zemin: `--color-brand-secondary`, Yazı: Beyaz.
  - `accent / gold`: Zemin: `--color-brand-accent`, Yazı: Koyu Fındık (`#24160d`).
  - `outline`: Şeffaf zemin, 1.5px `--color-border-strong` kenarlık.
  - `ghost`: Kenarlıksız, hover durumunda `--color-surface-subtle`.
- **Boyutlar:**
  - `sm`: Yükseklik 36px, font 14px.
  - `md`: Yükseklik 44px (Masaüstü standart dokunma alanı).
  - `lg`: Yükseklik 54px (Ödeme butonu ve Şoför ekranı için büyük buton).
- **Durumlar:** `default`, `hover`, `active`, `focus-visible` (3px altın çerçeve), `disabled` (%40 opaklık), `loading` (Spinner ikonu + metin gizleme).

### 2.2 Fiyat Gösterim Bileşeni (`PriceTag`)
- **İşlev:** `bigint` kuruş değerini alır ve kurallara göre biçimlendirir.
- **Özellikler:**
  ```tsx
  interface PriceTagProps {
    amountKurus: bigint | number;
    compareAtKurus?: bigint | number;
    currency?: 'TRY';
    size?: 'sm' | 'md' | 'lg' | 'xl';
  }
  ```
- **Çıktı Biçimi:** `16500` kuruş -> `165,00 ₺` (`Intl.NumberFormat('tr-TR')`). İndirim varsa eski fiyat üstü çizili gri renkte yanına eklenir.

### 2.3 Sayısal Adet Artırıcı (`QuantityStepper`)
- **Erişilebilirlik:** Eksi ve Artı butonlarında `aria-label="Adedi Azalt"` / `aria-label="Adedi Artır"`.
- **Input:** `role="spinbutton"`, `aria-valuenow`, `aria-valuemin="1"`, `aria-valuemax="X"`.
- **Hızlı Tepki:** Uzun basmada sürekli artış/azalış koruması.

### 2.4 Açılır Çekmece (`Drawer` / `CartDrawer`)
- **Radix:** `@radix-ui/react-dialog` tabanlı.
- **Davranış:** Açıldığında arkadaki sayfayı kaydırmaya kapatır (`body-scroll-lock`), `ESC` tuşu veya karartmaya tıklamayla kapanır, odak (focus) çekmece içine hapsedilir (`focus-trap`).

---

## 3. ERİŞİLEBİLİRLİK (WCAG 2.2 AA) ZORUNLULUKLARI

1. **Kontrast Oranları:**
   - Standart gövde metinleri arka planla en az **4.5:1** kontrast oranına sahiptir (`--color-text-main` / `--color-surface-base` oranı **12.8:1** ile standartların çok üzerindedir).
   - Büyük başlıklar ve buton metinleri en az **3.0:1** kontrast oranına sahiptir.
2. **Klavye ile Gezinme (Keyboard Navigation):**
   - Tüm interaktif öğeler (linkler, butonlar, form alanları) `Tab` tuşu ile sırayla erişilebilir olmalıdır.
   - Odaklanılan öğenin etrafında daima belirgin **3px Altın Odak Halkası (`outline: 3px solid var(--color-brand-accent)`)** görünür.
   - Sayfanın en üstünde klavye kullanıcıları için gizli `"İçeriğe Atla (Skip to Content)"` linki bulunur.
3. **Ekran Okuyucu (Screen Reader) Desteği:**
   - Tüm resimlerde anlamlı `alt` metni zorunludur. Dekoratif resimlerde `alt=""` ve `aria-hidden="true"`.
   - Sepet sayısı değiştiğinde ekran okuyucuya bildirim vermek için `aria-live="polite"` kullanılır.
   - Form hataları ilgili input alanıyla `aria-describedby="hata-mesaji-id"` ile ilişkilendirilir.
4. **Hareket Hassasiyeti (Reduced Motion):**
   - Kullanıcının işletim sisteminde "Hareketi Azalt" seçeneği açıksa tüm CSS geçiş ve animasyonları kapatılır:
   ```css
   @media (prefers-reduced-motion: reduce) {
     *, *::before, *::after {
       animation-duration: 0.01ms !important;
       transition-duration: 0.01ms !important;
       scroll-behavior: auto !important;
     }
   }
   ```
5. **Dokunma Hedefi Boyutları (Touch Targets):**
   - Mobilde ve Şoför uygulamasında tüm tıklanabilir buton ve simgelerin fiziksel alanı en az **48 x 48 piksel**dir.

