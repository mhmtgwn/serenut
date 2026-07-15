/* ==========================================================================
   SERENUT OS V3 - WEBSITE CORE ENGINE
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  initLucideIcons();
  setupMobileNav();
  setupScrollHeader();
  highlightActiveLink();
  setupContactForm();
  setupScrollReveal();
});

/**
 * Initialize Lucide icons if library is loaded
 */
function initLucideIcons() {
  if (typeof lucide !== 'undefined' && lucide.createIcons) {
    lucide.createIcons();
  }
}

/**
 * Mobile navigation with scroll lock and overlay
 */
function setupMobileNav() {
  const toggleBtn = document.getElementById('nav-toggle');
  const navLinks = document.getElementById('nav-links');
  const overlay = document.getElementById('mobile-overlay');

  if (!toggleBtn || !navLinks) return;

  const closeMenu = () => {
    navLinks.classList.remove('active');
    toggleBtn.classList.remove('active');
    document.body.classList.remove('menu-open');
    if (overlay) overlay.classList.remove('active');
  };

  const openMenu = () => {
    navLinks.classList.add('active');
    toggleBtn.classList.add('active');
    document.body.classList.add('menu-open');
    if (overlay) overlay.classList.add('active');
  };

  toggleBtn.addEventListener('click', () => {
    if (navLinks.classList.contains('active')) {
      closeMenu();
    } else {
      openMenu();
    }
  });

  // Close menu on overlay click
  if (overlay) {
    overlay.addEventListener('click', closeMenu);
  }

  // Close menu on nav link click (mobile)
  navLinks.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', () => {
      if (window.innerWidth <= 768) {
        closeMenu();
      }
    });
  });

  // Close menu on Escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && navLinks.classList.contains('active')) {
      closeMenu();
    }
  });

  // Close menu on resize to desktop
  window.addEventListener('resize', () => {
    if (window.innerWidth > 768 && navLinks.classList.contains('active')) {
      closeMenu();
    }
  });
}

/**
 * Adds background to navigation header on page scroll
 */
function setupScrollHeader() {
  const header = document.getElementById('main-header');
  if (!header) return;

  const onScroll = () => {
    if (window.scrollY > 20) {
      header.classList.add('nav-scrolled');
    } else {
      header.classList.remove('nav-scrolled');
    }
  };

  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll(); // Check initial state
}

/**
 * Checks pathname to highlight current active navigation node
 */
function highlightActiveLink() {
  const path = window.location.pathname;
  const links = document.querySelectorAll('.nav-link');

  links.forEach(link => {
    const href = link.getAttribute('href');
    if (path.endsWith(href) || (path === '/' && href === 'index.html')) {
      link.classList.add('active');
    } else {
      // Don't remove active class that was set in HTML
      // link.classList.remove('active');
    }
  });
}

/**
 * Setup public contact form submission logic to backend API
 */
function setupContactForm() {
  const form = document.getElementById('contact-form');
  if (!form) return;

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = document.getElementById('contact-name').value.trim();
    const email = document.getElementById('contact-email').value.trim();
    const message = document.getElementById('contact-message').value.trim();
    const statusMsg = document.getElementById('contact-status-msg');

    if (statusMsg) {
      statusMsg.style.color = 'var(--color-text-muted)';
      statusMsg.innerText = 'Gönderiliyor...';
    }

    try {
      const response = await fetch('/api/v1/support/public-contact', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          name,
          email,
          phone: '',
          subject: 'Web Sitesi İletişim Formu Mesajı',
          message
        })
      });

      const resData = await response.json();
      if (!response.ok) {
        throw new Error(resData.message || 'Gönderim esnasında bir sorun oluştu.');
      }

      if (statusMsg) {
        statusMsg.style.color = 'var(--color-primary)';
        statusMsg.innerText = 'Mesajınız başarıyla iletildi. En kısa sürede dönüş yapacağız.';
      }
      form.reset();
    } catch (err) {
      if (statusMsg) {
        statusMsg.style.color = 'var(--color-error)';
        statusMsg.innerText = err.message || 'Gönderilemedi. Lütfen tekrar deneyiniz.';
      }
    }
  });
}

/**
 * Scroll reveal animation using IntersectionObserver
 */
function setupScrollReveal() {
  const revealElements = document.querySelectorAll('.reveal');
  if (!revealElements.length) return;

  // Respect reduced motion preference
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    revealElements.forEach(el => el.classList.add('revealed'));
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('revealed');
        observer.unobserve(entry.target);
      }
    });
  }, {
    threshold: 0.1,
    rootMargin: '0px 0px -40px 0px'
  });

  revealElements.forEach(el => observer.observe(el));
}
