/* ==========================================================================
   SERENUT OS V2 - WEBSITE CORE ENGINE
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  setupMobileNav();
  setupScrollHeader();
  highlightActiveLink();
  setupContactForm();
});

/**
 * Mobile navigation sliding drawer toggle
 */
function setupMobileNav() {
  const toggleBtn = document.getElementById('nav-toggle');
  const navLinks = document.getElementById('nav-links');

  if (toggleBtn && navLinks) {
    toggleBtn.addEventListener('click', () => {
      navLinks.classList.toggle('active');
      toggleBtn.classList.toggle('active');
    });
  }
}

/**
 * Adds background shadow to navigation header on page scroll
 */
function setupScrollHeader() {
  const header = document.getElementById('main-header');
  if (!header) return;

  window.addEventListener('scroll', () => {
    if (window.scrollY > 50) {
      header.classList.add('nav-scrolled');
    } else {
      header.classList.remove('nav-scrolled');
    }
  });
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
      link.classList.remove('active');
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
      statusMsg.className = 'text-muted';
      statusMsg.style.color = '#94a3b8';
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
        statusMsg.style.color = '#10b981';
        statusMsg.innerText = '✓ Mesajınız başarıyla iletildi. En kısa sürede dönüş yapacağız.';
      }
      form.reset();
    } catch (err) {
      if (statusMsg) {
        statusMsg.style.color = '#ef4444';
        statusMsg.innerText = err.message || 'Gönderilemedi. Lütfen tekrar deneyiniz.';
      }
    }
  });
}
