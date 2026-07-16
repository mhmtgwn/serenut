import { setAuthToken, setRefreshToken, clearAuthToken, apiFetch } from '/shared/js/api-client.js';
import { isAuthenticated, setUserProfile } from '/shared/js/auth.js';
import { loadModule } from './module-runtime.js';

const authView = document.getElementById('auth-view');
const shellView = document.getElementById('shell-view');
const registerLayer = document.getElementById('register-layer');
const resetLayer = document.getElementById('reset-layer');
const embedPanel = document.getElementById('embed-panel');
const overviewGrid = document.getElementById('overview-grid');
const modulePanel = document.getElementById('module-panel');
const embedContent = document.getElementById('embed-content');

let navigationItems = [];

document.addEventListener('DOMContentLoaded', () => {
  bindEvents();

  if (isAuthenticated()) {
    bootShell();
    return;
  }

  showAuth();
  handleInitialIntent();
});

function bindEvents() {
  document.getElementById('open-register')?.addEventListener('click', () => openLayer('register'));
  document.getElementById('open-reset')?.addEventListener('click', () => openLayer('reset'));
  document.getElementById('close-register')?.addEventListener('click', closeLayers);
  document.getElementById('close-reset')?.addEventListener('click', closeLayers);
  document.getElementById('btn-login')?.addEventListener('click', handleLogin);
  document.getElementById('btn-register')?.addEventListener('click', handleRegister);
  document.getElementById('btn-request-reset')?.addEventListener('click', requestReset);
  document.getElementById('btn-apply-reset')?.addEventListener('click', applyReset);
  document.getElementById('btn-logout')?.addEventListener('click', () => {
    clearAuthToken();
    showAuth();
  });
  document.getElementById('btn-home')?.addEventListener('click', () => selectModule('home'));
  document.getElementById('sidebar-toggle')?.addEventListener('click', () => document.body.classList.toggle('sidebar-open'));
}

function handleInitialIntent() {
  const params = new URLSearchParams(window.location.search);
  if (params.get('token')) {
    openLayer('reset');
    return;
  }

  if (window.location.hash.startsWith('#register')) {
    openLayer('register');
  }
}

function openLayer(type) {
  closeLayers();
  if (type === 'register') {
    registerLayer?.classList.remove('app-hidden');
    return;
  }
  resetLayer?.classList.remove('app-hidden');
}

function closeLayers() {
  registerLayer?.classList.add('app-hidden');
  resetLayer?.classList.add('app-hidden');
}

function showAuth() {
  authView?.classList.remove('app-hidden');
  shellView?.classList.add('app-hidden');
  closeLayers();
}

function showShell() {
  authView?.classList.add('app-hidden');
  shellView?.classList.remove('app-hidden');
  closeLayers();
}

async function handleLogin() {
  const statusEl = document.getElementById('login-status');
  statusEl.innerText = '';

  try {
    const res = await fetch('/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: document.getElementById('login-email').value.trim(),
        password: document.getElementById('login-password').value
      })
    });
    const data = await res.json();
    if (!res.ok) {
      if (data?.error?.code === 'EMAIL_NOT_VERIFIED') {
        const email = document.getElementById('login-email').value.trim();
        statusEl.innerText = `${data.error.message} `;
        const resend = document.createElement('button');
        resend.type = 'button';
        resend.className = 'ghost-link';
        resend.innerText = 'Bağlantıyı yeniden gönder';
        resend.addEventListener('click', () => resendVerification(email, resend));
        statusEl.appendChild(resend);
        return;
      }
      throw new Error(data?.error?.message || data?.message || 'Giriş başarısız.');
    }
    setAuthToken(data.access_token);
    setRefreshToken(data.refresh_token);
    setUserProfile(data.user);
    await bootShell();
  } catch (error) {
    statusEl.innerText = error.message;
  }
}

async function handleRegister() {
  const statusEl = document.getElementById('register-status');
  statusEl.innerText = '';

  try {
    const res = await fetch('/api/v1/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        company_name: document.getElementById('register-company').value.trim(),
        name: document.getElementById('register-name').value.trim(),
        email: document.getElementById('register-email').value.trim(),
        phone: document.getElementById('register-phone').value.trim(),
        tax_number: document.getElementById('register-tax-number').value.trim(),
        tax_office: document.getElementById('register-tax-office').value.trim(),
        city: document.getElementById('register-city').value.trim(),
        district: document.getElementById('register-district').value.trim(),
        address: document.getElementById('register-address').value.trim(),
        accept_terms: document.getElementById('accept-terms').checked,
        accept_privacy: document.getElementById('accept-privacy').checked,
        accept_kvkk: document.getElementById('accept-kvkk').checked,
        accept_marketing: document.getElementById('accept-marketing').checked,
        password: document.getElementById('register-password').value
      })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.message || 'Kayıt oluşturulamadı.');
    statusEl.className = 'auth-status text-sm text-green';
    statusEl.innerText = data.message;
    document.getElementById('btn-register').disabled = true;
  } catch (error) {
    statusEl.innerText = error.message;
  }
}

async function resendVerification(email, button) {
  button.disabled = true;
  try {
    const res = await fetch('/api/v1/auth/resend-verification', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email })
    });
    const data = await res.json();
    button.innerText = res.ok ? data.message : 'Gönderilemedi';
  } catch (_) {
    button.innerText = 'Gönderilemedi';
  }
}

async function requestReset() {
  const statusEl = document.getElementById('reset-status');
  statusEl.className = 'auth-status text-sm';

  try {
    const res = await fetch('/api/v1/auth/forgot-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: document.getElementById('reset-email').value.trim() })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.message || 'Link gönderilemedi.');
    statusEl.classList.add('text-green');
    statusEl.innerText = data.message;
  } catch (error) {
    statusEl.classList.add('text-red');
    statusEl.innerText = error.message;
  }
}

async function applyReset() {
  const statusEl = document.getElementById('reset-status');
  const params = new URLSearchParams(window.location.search);
  const token = params.get('token');
  const newPassword = document.getElementById('reset-password').value;
  const confirmPassword = document.getElementById('reset-password-confirm').value;

  statusEl.className = 'auth-status text-sm';

  if (!token) {
    statusEl.classList.add('text-red');
    statusEl.innerText = 'Geçerli reset token bulunamadı.';
    return;
  }

  if (newPassword !== confirmPassword) {
    statusEl.classList.add('text-red');
    statusEl.innerText = 'Şifreler eşleşmiyor.';
    return;
  }

  try {
    const res = await fetch('/api/v1/auth/reset-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, newPassword })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data?.message || 'Şifre güncellenemedi.');
    history.replaceState({}, '', '/app/');
    statusEl.classList.add('text-green');
    statusEl.innerText = data.message;
    closeLayers();
  } catch (error) {
    statusEl.classList.add('text-red');
    statusEl.innerText = error.message;
  }
}

async function bootShell() {
  try {
    const me = await apiFetch('/users/me');
    const bootstrap = await apiFetch('/app/bootstrap');
    setUserProfile(me);
    renderShell(bootstrap);
    showShell();
  } catch (_) {
    showAuth();
  }
}

function renderShell(bootstrap) {
  navigationItems = bootstrap.navigation || [];

  document.getElementById('tenant-name').innerText = bootstrap.company?.name || 'Tenant';
  document.getElementById('user-name').innerText = bootstrap.user?.name || 'Kullanıcı';
  document.getElementById('user-roles').innerText = (bootstrap.user?.roles || []).join(', ') || 'rol yok';
  document.getElementById('shell-subtitle').innerText = `Aktif şirket: ${bootstrap.company?.name || 'Tanımsız'} • Başlangıç rotası: ${bootstrap.landing_route}`;
  document.getElementById('workspace-note').innerText = bootstrap.workspaces?.platform
    ? 'Bu kullanıcı hem platform hem firma modüllerine erişebilir.'
    : 'Bu kullanıcı firma modülleri ile sınırlandırılmıştır.';

  document.getElementById('role-chips').innerHTML = (bootstrap.user?.roles || [])
    .map((role) => `<span class="role-chip">${role}</span>`)
    .join('');

  document.getElementById('company-meta').innerHTML = `
    <div><strong>Şirket:</strong> ${bootstrap.company?.name || '—'}</div>
    <div><strong>Kod:</strong> ${bootstrap.company?.business_code || '—'}</div>
    <div><strong>Durum:</strong> ${bootstrap.company?.status || '—'}</div>
  `;

  renderNav(navigationItems);
  renderModuleCards(navigationItems);
  selectModule(resolveInitialModule(bootstrap));
}

function renderNav(items) {
  const nav = document.getElementById('app-nav');
  const labels = {
    overview: 'Genel',
    operations: 'Operasyon',
    commerce: 'Ticari',
    platform: 'Platform',
    account: 'Hesap'
  };
  const sections = ['overview', 'operations', 'commerce', 'platform', 'account'];

  nav.innerHTML = '';
  sections.forEach((section) => {
    const sectionItems = items.filter((item) => item.section === section);
    if (!sectionItems.length) return;

    nav.insertAdjacentHTML('beforeend', `<div class="nav-section-label">${labels[section]}</div>`);
    sectionItems.forEach((item) => {
      nav.insertAdjacentHTML('beforeend', `
        <a class="nav-link" href="${item.href}" data-module-id="${item.id}">
          <span>${item.label}</span>
          <span class="nav-link-desc">${item.description}</span>
        </a>
      `);
    });
  });

  nav.querySelectorAll('[data-module-id]').forEach((link) => {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      selectModule(link.getAttribute('data-module-id'));
    });
  });
}

function renderModuleCards(items) {
  const grid = document.getElementById('module-grid');
  grid.innerHTML = items.map((item) => `
    <article class="module-card">
      <h3>${item.label}</h3>
      <p>${item.description}</p>
      <button class="btn btn-primary btn-sm" data-module-id="${item.id}">Modülü Aç</button>
    </article>
  `).join('');

  grid.querySelectorAll('[data-module-id]').forEach((button) => {
    button.addEventListener('click', () => selectModule(button.getAttribute('data-module-id')));
  });
}

function resolveInitialModule(bootstrap) {
  const hashId = window.location.hash.replace('#', '').trim();
  if (hashId && navigationItems.some((item) => item.id === hashId)) {
    return hashId;
  }

  const landing = navigationItems.find((item) => item.href === bootstrap.landing_route);
  return landing?.id || 'home';
}

async function selectModule(moduleId) {
  const activeId = moduleId || 'home';
  document.body.classList.remove('sidebar-open');
  const item = navigationItems.find((entry) => entry.id === activeId);

  document.querySelectorAll('.nav-link').forEach((link) => {
    link.classList.toggle('active', link.getAttribute('data-module-id') === activeId);
  });

  if (!item || activeId === 'home' || item.module === 'home') {
    overviewGrid.classList.remove('app-hidden');
    modulePanel.classList.remove('app-hidden');
    embedPanel.classList.add('app-hidden');
    window.location.hash = 'home';
    return;
  }

  document.getElementById('embed-title').innerText = item.label;
  document.getElementById('embed-description').innerText = item.description;
  await loadModule(item);

  overviewGrid.classList.add('app-hidden');
  modulePanel.classList.add('app-hidden');
  embedPanel.classList.remove('app-hidden');
  window.location.hash = item.id;
}
