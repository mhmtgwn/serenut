/* ═══════════════════════════════════════════════════════════════
   SERENUT OS — Ortak JavaScript
   ═══════════════════════════════════════════════════════════════ */

'use strict';

// ── Navbar Scroll ──────────────────────────────────────────────
(function initNavScroll() {
  const nav = document.querySelector('.nav');
  if (!nav) return;
  const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 20);
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();

// ── Mobile Menu Toggle ─────────────────────────────────────────
(function initMobileMenu() {
  const nav    = document.querySelector('.nav'); // ← başa taşındı (TDZ fix)
  const toggle = document.getElementById('nav-toggle');
  const links  = document.getElementById('nav-links');
  if (!toggle || !links) return;

  toggle.addEventListener('click', () => {
    const open = links.classList.toggle('open');
    toggle.setAttribute('aria-expanded', String(open));
    // animate hamburger → X
    const spans = toggle.querySelectorAll('span');
    if (open) {
      spans[0].style.transform = 'rotate(45deg) translate(5px, 5px)';
      spans[1].style.opacity   = '0';
      spans[2].style.transform = 'rotate(-45deg) translate(5px, -5px)';
    } else {
      spans.forEach(s => { s.style.transform = ''; s.style.opacity = ''; });
    }
  });

  // close on outside click
  document.addEventListener('click', (e) => {
    if (nav && !nav.contains(e.target) && links.classList.contains('open')) {
      links.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
      toggle.querySelectorAll('span').forEach(s => { s.style.transform = ''; s.style.opacity = ''; });
    }
  });
})();

// ── Scroll Reveal ──────────────────────────────────────────────
(function initReveal() {
  const items = document.querySelectorAll('.reveal');
  if (!items.length || !('IntersectionObserver' in window)) {
    items.forEach(el => el.classList.add('visible'));
    return;
  }
  const obs = new IntersectionObserver((entries) => {
    entries.forEach(e => { if (e.isIntersecting) { e.target.classList.add('visible'); obs.unobserve(e.target); } });
  }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
  items.forEach(el => obs.observe(el));
})();

// ── Active Nav Link ────────────────────────────────────────────
(function initActiveLink() {
  const path = window.location.pathname.split('/').pop() || 'index.html';
  document.querySelectorAll('.nav__link').forEach(a => {
    const href = a.getAttribute('href');
    if (href === path || (path === '' && href === 'index.html')) {
      a.classList.add('active');
    }
  });
})();

// ── Smooth Scroll for Anchors ──────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('a[href^="#"]').forEach(a => {
    a.addEventListener('click', e => {
      const id = a.getAttribute('href').slice(1);
      const target = document.getElementById(id);
      if (target) {
        e.preventDefault();
        const offset = parseInt(getComputedStyle(document.documentElement).getPropertyValue('--nav-height')) || 72;
        const top = target.getBoundingClientRect().top + window.scrollY - offset - 16;
        window.scrollTo({ top, behavior: 'smooth' });
      }
    });
  });
});

// ── FAQ Accordion ──────────────────────────────────────────────
(function initFaq() {
  document.querySelectorAll('.faq-question').forEach(btn => {
    btn.addEventListener('click', () => {
      const answer = btn.nextElementSibling;
      const isOpen = btn.classList.contains('open');

      // close all
      document.querySelectorAll('.faq-question.open').forEach(b => {
        b.classList.remove('open');
        b.nextElementSibling.classList.remove('open');
        b.setAttribute('aria-expanded', 'false');
      });

      if (!isOpen) {
        btn.classList.add('open');
        answer.classList.add('open');
        btn.setAttribute('aria-expanded', 'true');
      }
    });
  });
})();

// ── Number Counter Animation ───────────────────────────────────
(function initCounters() {
  const counters = document.querySelectorAll('[data-count]');
  if (!counters.length) return;

  const obs = new IntersectionObserver((entries) => {
    entries.forEach(e => {
      if (!e.isIntersecting) return;
      const el  = e.target;
      const end = parseFloat(el.dataset.count);
      const dur = 1800;
      const step = 16;
      let start = null;

      const tick = (ts) => {
        if (!start) start = ts;
        const progress = Math.min((ts - start) / dur, 1);
        const ease = 1 - Math.pow(1 - progress, 3); // ease-out cubic
        const val = end * ease;
        el.textContent = el.dataset.suffix
          ? (val % 1 === 0 ? Math.round(val) : val.toFixed(1)) + el.dataset.suffix
          : Math.round(val).toLocaleString('tr-TR');
        if (progress < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      obs.unobserve(el);
    });
  }, { threshold: 0.5 });

  counters.forEach(el => obs.observe(el));
})();

// ── Wizard Step Manager ────────────────────────────────────────
window.SerenutWizard = (function() {
  let currentStep = 1;
  let totalSteps  = 3;

  function goTo(step) {
    if (step < 1 || step > totalSteps) return;

    // hide all panels
    document.querySelectorAll('.wizard-panel').forEach((p, i) => {
      p.style.display = (i + 1 === step) ? 'block' : 'none';
    });

    // update step indicators
    document.querySelectorAll('.wizard-step').forEach((s, i) => {
      s.classList.remove('active', 'done');
      if (i + 1 === step) s.classList.add('active');
      if (i + 1 < step)  s.classList.add('done');
    });

    // update progress bar if exists
    const bar = document.querySelector('.wizard-progress-fill');
    if (bar) bar.style.width = ((step - 1) / (totalSteps - 1) * 100) + '%';

    currentStep = step;
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function next() {
    if (!validateCurrentStep()) return;
    goTo(currentStep + 1);
  }

  function prev() {
    goTo(currentStep - 1);
  }

  function validateCurrentStep() {
    const panel = document.querySelectorAll('.wizard-panel')[currentStep - 1];
    if (!panel) return true;
    let valid = true;
    panel.querySelectorAll('[required]').forEach(input => {
      if (!input.value.trim()) {
        input.classList.add('error');
        valid = false;
      } else {
        input.classList.remove('error');
      }
    });
    return valid;
  }

  return { goTo, next, prev, current: () => currentStep };
})();

// ── Toast Notification ─────────────────────────────────────────
window.showToast = function(message, type = 'success', duration = 3500) {
  const existing = document.querySelector('.serenut-toast');
  if (existing) existing.remove();

  const toast = document.createElement('div');
  toast.className = 'serenut-toast';
  toast.innerHTML = `
    <span class="toast-icon">${type === 'success' ? '✓' : type === 'error' ? '✕' : 'ℹ'}</span>
    <span>${message}</span>
  `;

  const style = toast.style;
  style.cssText = `
    position:fixed; bottom:32px; right:32px; z-index:9999;
    display:flex; align-items:center; gap:10px;
    padding:14px 20px; border-radius:12px;
    font-family:inherit; font-size:0.9rem; font-weight:600;
    background:${type === 'success' ? 'rgba(22,163,74,0.9)' : type === 'error' ? 'rgba(239,68,68,0.9)' : 'rgba(59,130,246,0.9)'};
    color:#fff; backdrop-filter:blur(12px);
    box-shadow:0 8px 32px rgba(0,0,0,0.4);
    transform:translateY(8px); opacity:0;
    transition:all 0.3s cubic-bezier(0.4,0,0.2,1);
  `;

  document.body.appendChild(toast);
  requestAnimationFrame(() => {
    toast.style.transform = 'translateY(0)';
    toast.style.opacity = '1';
  });
  setTimeout(() => {
    toast.style.transform = 'translateY(8px)';
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, duration);
};

// ── Utility: Format phone ──────────────────────────────────────
window.formatPhone = function(input) {
  let val = input.value.replace(/\D/g, '');
  if (val.startsWith('90')) val = val.slice(2);
  if (val.startsWith('0')) val = val.slice(1);
  val = val.slice(0, 10);
  if (val.length >= 7)
    input.value = val.slice(0,3) + ' ' + val.slice(3,6) + ' ' + val.slice(6,8) + ' ' + val.slice(8);
  else if (val.length >= 4)
    input.value = val.slice(0,3) + ' ' + val.slice(3,6) + ' ' + val.slice(6);
  else
    input.value = val;
};
