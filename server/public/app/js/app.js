import { clearAuthSession, apiFetch } from '/shared/js/api-client.js';
import { isAuthenticated, setUserProfile } from '/shared/js/auth.js';
import { escapeHtml } from '/shared/js/formatters.js';

const overviewGrid = document.getElementById('overview-grid');
const modulePanel = document.getElementById('module-panel');
const embedPanel = document.getElementById('embed-panel');
document.body.dataset.bootStage = 'script-ready';

let navigationItems = [];
let selectedModuleId = 'home';
let realtimeSocket = null;
let realtimeReconnectTimer = null;
let realtimeRefreshTimer = null;
let realtimeCompanyId = '';

const navIcon = () => '<svg class="nav-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 5h14v14H5z"></path></svg>';

function initApp() {
  document.body.dataset.bootStage = 'initializing';
  if (!isAuthenticated()) {
    window.location.replace(`/login?next=${encodeURIComponent(window.location.pathname + window.location.search + window.location.hash)}`);
    return;
  }

  document.getElementById('btn-logout')?.addEventListener('click', () => {
    clearAuthSession();
    window.location.replace('/login');
  });
  document.getElementById('btn-home')?.addEventListener('click', () => selectModule('home'));
  document.getElementById('sidebar-toggle')?.addEventListener('click', () => document.body.classList.toggle('sidebar-open'));
  document.getElementById('app-nav')?.addEventListener('click', (event) => {
    if (event.target.closest('[data-module-id]')) document.body.classList.remove('sidebar-open');
  });
  document.addEventListener('click', (event) => {
    if (!document.body.classList.contains('sidebar-open')) return;
    if (event.target.closest('.shell-sidebar, #sidebar-toggle')) return;
    document.body.classList.remove('sidebar-open');
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') document.body.classList.remove('sidebar-open');
  });

  bootShell();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initApp);
} else {
  initApp();
}

async function bootShell() {
  document.body.dataset.bootStage = 'loading-profile';
  setBootState('loading');
  try {
    const me = await apiFetch('/users/me');
    document.body.dataset.bootStage = 'loading-workspace';
    const bootstrap = await apiFetch('/app/bootstrap');
    document.body.dataset.bootStage = 'rendering';
    setUserProfile(me);
    renderShell(bootstrap);
    startRealtime();
  } catch (error) {
    if (error?.status === 401 || error?.status === 403) {
      clearAuthSession();
      const reason = error.status === 403 ? 'portal_access_denied' : 'session_expired';
      window.location.replace(`/login?error=${reason}`);
      return;
    }
    setBootState('error', error?.message || 'Panel verileri yüklenemedi.');
  }
}

function setBootState(state, detail = '') {
  const panel = document.getElementById('boot-state');
  const retry = document.getElementById('boot-retry');
  document.body.classList.toggle('app-booting', state !== 'ready');
  document.body.dataset.bootStage = state;
  panel?.classList.toggle('app-hidden', state === 'ready');
  retry?.classList.toggle('app-hidden', state !== 'error');
  if (state === 'error') {
    document.getElementById('boot-state-title').innerText = 'Çalışma alanı yüklenemedi';
    document.getElementById('boot-state-copy').innerText = detail;
    retry.onclick = bootShell;
  }
}

function renderShell(bootstrap) {
  realtimeCompanyId = bootstrap.company?.id || bootstrap.user?.company_id || '';
  const isSysadmin = (bootstrap.user?.roles || []).includes('sysadmin');
  navigationItems = normalizeNavigation(bootstrap.navigation);
  if (!navigationItems.length) {
    throw new Error('Bu hesap için kullanılabilir bir panel alanı bulunamadı.');
  }
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
    .map((role) => `<span class="role-chip">${escapeHtml(role)}</span>`)
    .join('');
  document.getElementById('company-meta').innerHTML = `
    <div><strong>Şirket:</strong> ${escapeHtml(bootstrap.company?.name || '—')}</div>
    <div><strong>Kod:</strong> ${escapeHtml(bootstrap.company?.business_code || '—')}</div>
    <div><strong>Durum:</strong> ${escapeHtml(bootstrap.company?.status || '—')}</div>
  `;

  renderNav(navigationItems);
  renderModuleCards(navigationItems);
  selectModule(resolveInitialModule(bootstrap));
  setBootState('ready');
}

function normalizeNavigation(navigation) {
  if (!Array.isArray(navigation)) return [];
  const validModules = new Set(['home', 'portal', 'admin']);
  return navigation.filter((item) =>
    item && typeof item.id === 'string' && typeof item.label === 'string' &&
    typeof item.href === 'string' && validModules.has(item.module)
  );
}

function renderNav(items) {
  const nav = document.getElementById('app-nav');
  const labels = { overview: 'Genel', operations: 'Operasyon', commerce: 'Ticari', platform: 'Yönetim', account: 'Hesap' };
  nav.innerHTML = '';

  ['overview', 'operations', 'commerce', 'platform', 'account'].forEach((section) => {
    const sectionItems = items.filter((item) => item.section === section);
    if (!sectionItems.length) return;
    nav.insertAdjacentHTML('beforeend', `<div class="nav-section-label">${labels[section]}</div>`);
    sectionItems.forEach((item) => {
      nav.insertAdjacentHTML('beforeend', `
        <a class="nav-link" href="${item.href}" data-module-id="${item.id}">
          ${navIcon()}<span>${escapeHtml(item.label)}</span>
          <span class="nav-link-desc">${escapeHtml(item.description)}</span>
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
      <div class="module-card-icon">${navIcon()}</div><h3>${escapeHtml(item.label)}</h3>
      <p>${escapeHtml(item.description)}</p>
      <button class="btn btn-primary btn-sm" data-module-id="${item.id}">Modülü Aç</button>
    </article>
  `).join('');
  grid.querySelectorAll('[data-module-id]').forEach((button) => {
    button.addEventListener('click', () => selectModule(button.getAttribute('data-module-id')));
  });
}

function resolveInitialModule(bootstrap) {
  const hashId = window.location.hash.replace('#', '').trim();
  const requested = hashId && navigationItems.find((item) =>
    item.id === hashId || item.href.split('#')[1] === hashId
  );
  if (requested) return requested.id;
  const landing = navigationItems.find((item) =>
    item.id === bootstrap.landing_module_id || item.href === bootstrap.landing_route
  );
  return landing?.id || navigationItems.find((item) => item.module === 'home')?.id || navigationItems[0].id;
}

async function selectModule(moduleId) {
  const activeId = moduleId || 'home';
  selectedModuleId = activeId;
  document.body.classList.remove('sidebar-open');
  const item = navigationItems.find((entry) => entry.id === activeId);
  document.querySelectorAll('.nav-link').forEach((link) => {
    link.classList.toggle('active', link.getAttribute('data-module-id') === activeId);
  });

  if (!item) {
    const fallback = navigationItems.find((entry) => entry.module === 'home') || navigationItems[0];
    if (fallback && fallback.id !== activeId) return selectModule(fallback.id);
    setBootState('error', 'İstenen panel alanı bulunamadı.');
    return;
  }

  if (item.module === 'home') {
    document.querySelector('.shell-title').innerText = 'Çalışma Alanı';
    overviewGrid.classList.remove('app-hidden');
    modulePanel.classList.remove('app-hidden');
    embedPanel.classList.add('app-hidden');
    window.location.hash = item.href.split('#')[1] || item.id;
    return;
  }

  document.querySelector('.shell-title').innerText = item.label;
  document.getElementById('embed-title').innerText = item.label;
  document.getElementById('embed-description').innerText = item.description;
  overviewGrid.classList.add('app-hidden');
  modulePanel.classList.add('app-hidden');
  embedPanel.classList.remove('app-hidden');
  window.location.hash = item.id;
  const content = document.getElementById('embed-content');
  content.innerHTML = '<div class="module-loading">Modül yükleniyor…</div>';
  try {
    const { loadModule } = await import('./module-runtime.js?v=20260730-panel-flow4');
    await loadModule(item);
  } catch (error) {
    content.innerHTML = `
      <div class="module-error" role="alert">
        <strong>${escapeHtml(item.label)} yüklenemedi</strong>
        <p>${escapeHtml(error?.message || 'Modül başlatılamadı.')}</p>
        <button class="btn btn-primary" id="module-retry" type="button">Tekrar Dene</button>
      </div>
    `;
    document.getElementById('module-retry').onclick = () => selectModule(item.id);
  }
}

function startRealtime() {
  if (realtimeSocket?.readyState === WebSocket.OPEN || !isAuthenticated()) return;
  clearTimeout(realtimeReconnectTimer);
  const token = sessionStorage.getItem('app_token') || localStorage.getItem('app_token');
  if (!token) return;

  const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
  const url = `${scheme}://${window.location.host}/api/v1/realtime/live?token=${encodeURIComponent(token)}&reconnectCount=0`;
  try {
    realtimeSocket = new WebSocket(url);
    realtimeSocket.onopen = () => {
      if (!realtimeCompanyId) return;
      ['orders', 'inventory', 'customers', 'payments', 'license', 'notifications', 'settings']
        .forEach((topic) => realtimeSocket.send(JSON.stringify({ action: 'subscribe', topic: `tenant/${realtimeCompanyId}/${topic}` })));
    };
    realtimeSocket.onmessage = (event) => {
      let message;
      try { message = JSON.parse(event.data); } catch (_) { return; }
      if (message?.type) scheduleModuleRefresh(message.type);
    };
    realtimeSocket.onclose = () => {
      realtimeSocket = null;
      if (isAuthenticated()) realtimeReconnectTimer = setTimeout(startRealtime, 5000);
    };
    realtimeSocket.onerror = () => realtimeSocket?.close();
  } catch (_) {
    realtimeReconnectTimer = setTimeout(startRealtime, 5000);
  }
}

function scheduleModuleRefresh(eventType) {
  clearTimeout(realtimeRefreshTimer);
  realtimeRefreshTimer = setTimeout(() => {
    document.dispatchEvent(new CustomEvent('serenut:realtime', { detail: { eventType } }));
    if (selectedModuleId !== 'home') selectModule(selectedModuleId);
  }, 400);
}
