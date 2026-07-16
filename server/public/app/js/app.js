import { setAuthToken, setRefreshToken, clearAuthToken, apiFetch } from '/shared/js/api-client.js';
import { isAuthenticated, setUserProfile } from '/shared/js/auth.js';
import { loadModule } from './module-runtime.js?v=20260716-payments2';

const authView = document.getElementById('auth-view');
const shellView = document.getElementById('shell-view');
const registerLayer = document.getElementById('register-layer');
const resetLayer = document.getElementById('reset-layer');
const embedPanel = document.getElementById('embed-panel');
const overviewGrid = document.getElementById('overview-grid');
const modulePanel = document.getElementById('module-panel');
const embedContent = document.getElementById('embed-content');

let navigationItems = [];

const navIconPaths = {
  'workspace-home': 'M4 11l8-7 8 7v9H4z M9 20v-6h6v6',
  'company-dashboard': 'M4 20V8l8-4 8 4v12 M8 12h2m4 0h2M8 16h2m4 0h2',
  'sales-operations': 'M4 6h16v12H4z M8 10h8m-8 4h5',
  'team-management': 'M16 20v-2a4 4 0 00-4-4H7a4 4 0 00-4 4v2 M9.5 10a3 3 0 100-6 3 3 0 000 6z M17 11a3 3 0 000-6',
  'billing-center': 'M4 6h16v12H4z M4 10h16 M8 15h3',
  'support-center': 'M4 5h16v12H8l-4 3z M8 9h8m-8 4h5',
  'platform-overview': 'M4 19V9m5 10V5m5 14v-7m5 7V3',
  'platform-companies': 'M3 20h18M5 20V8l7-4 7 4v12M9 11h2m2 0h2M9 15h2m2 0h2',
  'platform-billing': 'M12 3v18m5-14H9.5a3.5 3.5 0 000 7H14a3 3 0 010 6H6',
  'platform-subscriptions': 'M4 7h16v13H4z M8 3h8v4 M8 12h8m-8 4h5',
  'platform-plans': 'M4 5h16v14H4z M8 9h8m-8 4h8',
  'platform-licenses': 'M5 4h14v16H5z M9 8h6m-6 4h6m-6 4h3',
  'platform-releases': 'M12 3v12m0 0 5-5m-5 5-5-5M5 21h14',
  'platform-health': 'M3 12h4l2-6 4 12 2-6h6',
  'platform-support': 'M4 5h16v12H8l-4 3z M8 9h8m-8 4h5',
  'account-settings': 'M12 15.5a3.5 3.5 0 100-7 3.5 3.5 0 000 7z M19.4 15a1.7 1.7 0 00.34 1.88l.06.06-2 3.46-.08-.02a1.7 1.7 0 00-1.8.22l-.45.26a1.7 1.7 0 00-.8 1.63V22h-4v-.09a1.7 1.7 0 00-.8-1.63l-.45-.26a1.7 1.7 0 00-1.8-.22l-.08.02-2-3.46.06-.06A1.7 1.7 0 005 15v-.52a1.7 1.7 0 00-1.14-1.6L3.8 12.85v-4l.08-.02A1.7 1.7 0 005 7.23v-.52a1.7 1.7 0 00-.34-1.88l-.06-.06 2-3.46.08.02a1.7 1.7 0 001.8-.22l.45-.26A1.7 1.7 0 009.73-.58V-.67h4v.09a1.7 1.7 0 00.8 1.63l.45.26a1.7 1.7 0 001.8.22l.08-.02 2 3.46-.06.06a1.7 1.7 0 00-.34 1.88v.52a1.7 1.7 0 001.14 1.6l.08.02v4l-.08.02A1.7 1.7 0 0019.4 15z'
};
const navIcon = (id) => `<svg class="nav-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${navIconPaths[id] || navIconPaths['workspace-home']}"></path></svg>`;

document.addEventListener('DOMContentLoaded', () => {
  const isEmbed = new URLSearchParams(window.location.search).get('embed') === '1';
  if (isEmbed) document.body.classList.add('embed-mode');
  bindEvents();

  if (isAuthenticated()) {
    bootShell();
    return;
  }

  if (!isEmbed) {
    const intent = window.location.hash.startsWith('#register') ? 'register' : 'login';
    window.location.replace(`/?auth=${intent}`);
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
    if (document.body.classList.contains('embed-mode')) {
      showAuth();
      return;
    }
    window.location.replace('/?auth=login');
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
    if (document.body.classList.contains('embed-mode')) {
      window.parent.postMessage({ type: 'serenut-authenticated' }, window.location.origin);
      return;
    }
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
  const isSysadmin = (bootstrap.user?.roles || []).includes('sysadmin');
  const adminNavigation = [
    ['platform-overview','Genel Bakış','Günlük ticari durum ve bekleyen işler.'],
    ['platform-companies','Firmalar','Firma hesaplarını ve ayrıntılarını yönetin.'],
    ['platform-subscriptions','Abonelikler','Deneme, aktif ve sona eren abonelikleri izleyin.'],
    ['platform-billing','Ödemeler','Havale ve EFT bildirimlerini onaylayın.'],
    ['platform-plans','Planlar','Satış planlarını ve fiyatlarını düzenleyin.'],
    ['platform-licenses','Lisanslar ve Cihazlar','Lisans süreleri ile bağlı cihazları yönetin.'],
    ['platform-releases','Güncellemeler','Windows ve Android sürümlerini yayınlayın.'],
    ['platform-support','Destek','Firmalardan gelen talepleri yönetin.'],
    ['platform-health','Sistem','Servis sağlığını ve sistem olaylarını izleyin.']
  ].map(([id,label,description])=>({id,label,description,section:'platform',href:`/app/#${id}`,module:'admin'}));
  const customerDefinitions = {
    'company-dashboard':['Genel Bakış','Firma, lisans ve kullanım özeti.','overview'],
    'sales-operations':['Cihazlar ve SMS','Bağlı cihazlar ve SMS ana cihazı.','operations'],
    'team-management':['Ekip','Alt kullanıcılar ve görev rolleri.','operations'],
    'billing-center':['Abonelik ve Ödemeler','Plan, lisans ve ödeme geçmişi.','commerce'],
    'support-center':['Destek','Destek talepleri ve yanıt geçmişi.','commerce'],
    'account-settings':['Firma Ayarları','Firma, profil ve oturum ayarları.','account']
  };
  const allowedCustomerIds = new Set((bootstrap.navigation || []).map(item=>item.id));
  const customerNavigation = Object.entries(customerDefinitions).filter(([id])=>allowedCustomerIds.has(id)).map(([id,[label,description,section]])=>({id,label,description,section,href:`/app/#${id}`,module:'customer'}));
  navigationItems = isSysadmin ? adminNavigation : customerNavigation;
  document.body.classList.toggle('sysadmin-shell', isSysadmin);
  document.body.classList.toggle('customer-shell', !isSysadmin);

  document.querySelector('.sidebar-brand').innerText = isSysadmin ? 'Serenut Yönetim' : 'Serenut OS';
  document.getElementById('tenant-name').innerText = isSysadmin ? 'Sistem sahibi paneli' : (bootstrap.company?.name || 'Firma');
  document.getElementById('user-name').innerText = bootstrap.user?.name || 'Kullanıcı';
  document.getElementById('user-roles').innerText = (bootstrap.user?.roles || []).join(', ') || 'rol yok';
  document.getElementById('shell-subtitle').innerText = isSysadmin
    ? 'Firmaları, ödemeleri, lisansları ve uygulama yayınlarını yönetin.'
    : `Aktif firma: ${bootstrap.company?.name || 'Tanımsız'}`;
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
    platform: 'Yönetim',
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
          ${navIcon(item.id)}<span>${item.label}</span>
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
      <div class="module-card-icon">${navIcon(item.id)}</div><h3>${item.label}</h3>
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
  return landing?.id || navigationItems[0]?.id || 'home';
}

async function selectModule(moduleId) {
  const activeId = moduleId || 'home';
  document.body.classList.remove('sidebar-open');
  const item = navigationItems.find((entry) => entry.id === activeId);

  document.querySelectorAll('.nav-link').forEach((link) => {
    link.classList.toggle('active', link.getAttribute('data-module-id') === activeId);
  });

  if (!item || activeId === 'home' || item.module === 'home') {
    document.querySelector('.shell-title').innerText = 'Çalışma Alanı';
    overviewGrid.classList.remove('app-hidden');
    modulePanel.classList.remove('app-hidden');
    embedPanel.classList.add('app-hidden');
    window.location.hash = 'home';
    return;
  }

  document.querySelector('.shell-title').innerText = item.label;
  document.getElementById('embed-title').innerText = item.label;
  document.getElementById('embed-description').innerText = item.description;
  await loadModule(item);

  overviewGrid.classList.add('app-hidden');
  modulePanel.classList.add('app-hidden');
  embedPanel.classList.remove('app-hidden');
  window.location.hash = item.id;
}
