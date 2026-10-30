/**
 * Nutopia Fındık Değirmeni & Nutopiano Web Sitesi
 * Etkileşim ve UI Kontrol Betiği
 */

document.addEventListener('DOMContentLoaded', () => {
  // 1. Dinamik Yıl
  const currentYearSpan = document.getElementById('currentYear');
  if (currentYearSpan) {
    currentYearSpan.textContent = new Date().getFullYear();
  }

  // 2. Sticky Header Scroll Efekti
  const header = document.querySelector('.header');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      header?.classList.add('scrolled');
    } else {
      header?.classList.remove('scrolled');
    }
  }, { passive: true });

  // 3. Mobil Menü Aç / Kapat
  const mobileMenuBtn = document.getElementById('mobileMenuBtn');
  const navLinks = document.getElementById('navLinks');

  if (mobileMenuBtn && navLinks) {
    mobileMenuBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      navLinks.classList.toggle('active');
      const icon = mobileMenuBtn.querySelector('i');
      if (icon) {
        if (navLinks.classList.contains('active')) {
          icon.className = 'fa-solid fa-xmark';
        } else {
          icon.className = 'fa-solid fa-bars';
        }
      }
    });

    // Menü içindeki linke tıklanınca menüyü kapat
    const links = navLinks.querySelectorAll('a');
    links.forEach(link => {
      link.addEventListener('click', () => {
        navLinks.classList.remove('active');
        const icon = mobileMenuBtn.querySelector('i');
        if (icon) icon.className = 'fa-solid fa-bars';
      });
    });

    // Sayfa dışına tıklanınca menüyü kapat
    document.addEventListener('click', (e) => {
      if (!navLinks.contains(e.target) && !mobileMenuBtn.contains(e.target)) {
        navLinks.classList.remove('active');
        const icon = mobileMenuBtn.querySelector('i');
        if (icon) icon.className = 'fa-solid fa-bars';
      }
    });
  }

  // 4. WhatsApp Sipariş / Bilgi Tıklamaları (Konsol & Analitik İpuçları)
  const waButtons = document.querySelectorAll('a[href*="wa.me"]');
  waButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      const productTitle = btn.closest('.product-card')?.querySelector('.product-title')?.textContent;
      if (productTitle) {
        console.log(`[Nutopiano] WhatsApp Bilgi Talebi: ${productTitle.trim()}`);
      }
    });
  });
});
