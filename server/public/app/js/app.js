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
let realtimeConnecting = false;
let realtimeReconnectTimer = null;
let realtimeRefreshTimer = null;
let realtimeCompanyId = '';

const iconPaths = {
  'workspace-home': '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10.5V20h13v-9.5"/><path d="M9.5 20v-6h5v6"/>',
  'company-dashboard': '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  'sales-operations': '<path d="M4 18V9"/><path d="M10 18V5"/><path d="M16 18v-6"/><path d="M22 18H2"/>',
  'company-stores': '<path d="M4 10v10h16V10"/><path d="M3 10 5 4h14l2 6"/><path d="M8 20v-6h4v6"/><path d="M3 10c1 2 3 2 4 0 1 2 3 2 4 0 1 2 3 2 4 0 1 2 3 2 4 0"/>',
  'company-devices': '<rect x="4" y="3" width="16" height="13" rx="2"/><path d="M8 21h8M12 16v5"/>',
  'team-management': '<circle cx="9" cy="8" r="3"/><path d="M3 20c0-4 2.5-6 6-6s6 2 6 6"/><path d="M16 5c2.5.5 3.5 3.5 1.5 5M17 14c2.5.7 4 2.5 4 6"/>',
  'billing-center': '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h4"/>',
  'company-licenses': '<path d="M14 4a5 5 0 1 0 3.5 8.5L22 17v3h-3v-2h-2v-2h-2l-1.5-1.5"/><circle cx="9" cy="9" r="1"/>',
  'company-downloads': '<path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 20h16"/>',
  'support-center': '<path d="M4 13a8 8 0 0 1 16 0"/><path d="M4 13v4a2 2 0 0 0 2 2h2v-7H4M20 13v4a2 2 0 0 1-2 2h-2v-7h4"/>',
  'notification-channels': '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.5 9.6 9.6 0 0 1-4-.9L3 21l1.7-4.6A8.4 8.4 0 1 1 21 11.5Z"/><path d="M8 10h8M8 14h5"/>',
  'system-diagnostics': '<path d="M4 12h3l2-5 4 10 2-5h5"/><rect x="2" y="3" width="20" height="18" rx="2"/>',
  'platform-overview': '<path d="M4 19V9M10 19V5M16 19v-7M22 19H2"/>',
  'platform-companies': '<path d="M4 21V5h10v16M14 9h6v12M7 9h4M7 13h4M7 17h4M17 13h1M17 17h1"/>',
  'platform-billing': '<path d="M12 2v20M17 6.5c-1-1-2.5-1.5-5-1.5-3 0-5 1.5-5 4s2 3.5 5 3.5 5 1 5 3.5-2 4-5 4c-2.5 0-4-.5-5-1.5"/>',
  'platform-subscriptions': '<path d="M4 4h16v16H4z"/><path d="M8 8h8M8 12h8M8 16h5"/>',
  'platform-plans': '<path d="M5 3h14v18H5z"/><path d="M9 7h6M9 11h6M9 15h4"/>',
  'platform-releases': '<path d="M12 3v12M7 10l5 5 5-5"/><path d="M4 20h16"/>',
  'platform-licenses': '<path d="M14 4a5 5 0 1 0 3.5 8.5L22 17v3h-3v-2h-2v-2h-2l-1.5-1.5"/><circle cx="9" cy="9" r="1"/>',
  'platform-devices': '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 21h8M12 16v5"/>',
  'platform-health': '<path d="M3 12h4l2-5 4 10 2-5h6"/>',
  'platform-maintenance': '<path d="m14 6 4-4 4 4-4 4"/><path d="M18 2v8M4 14l-2 2 6 6 2-2"/><path d="m9 17 8-8"/>',
  'platform-security': '<path d="M12 3 5 6v5c0 5 3 8 7 10 4-2 7-5 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-5"/>',
  'platform-support': '<path d="M4 13a8 8 0 0 1 16 0"/><path d="M4 13v5h4v-6H4M20 13v5h-4v-6h4"/>',
  'platform-mail': '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>',
  'account-settings': '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1-2.8 2.8-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.6v.2h-4V21a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1L4.2 17l.1-.1a1.7 1.7 0 0 0 .3-1.9A1.7 1.7 0 0 0 3 14H2.8v-4H3a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9L4.2 7 7 4.2l.1.1A1.7 1.7 0 0 0 9 4.6 1.7 1.7 0 0 0 10 3V2.8h4V3a1.7 1.7 0 0 0 1 1.6 1.7 1.7 0 0 0 1.9-.3l.1-.1L19.8 7l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.6 1h.2v4H21a1.7 1.7 0 0 0-1.6 1Z"/>'
};
const navIcon = (id) => `<svg class="nav-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${iconPaths[id] || iconPaths['workspace-home']}</svg>`;

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
  const labels = { overview: 'Genel', customers: 'Müşteriler', commerce: 'Ticari', communication: 'İletişim', operations: 'Operasyon', security: 'Güvenlik', platform: 'Yönetim', account: 'Hesap' };
  nav.innerHTML = '';

  ['overview', 'customers', 'commerce', 'communication', 'operations', 'security', 'platform', 'account'].forEach((section) => {
    const sectionItems = items.filter((item) => item.section === section);
    if (!sectionItems.length) return;
    nav.insertAdjacentHTML('beforeend', `<div class="nav-section-label">${labels[section]}</div>`);
    sectionItems.forEach((item) => {
      nav.insertAdjacentHTML('beforeend', `
        <a class="nav-link" href="${item.href}" data-module-id="${item.id}">
          ${navIcon(item.id)}<span>${escapeHtml(item.label)}</span>
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
      <div class="module-card-icon">${navIcon(item.id)}</div><h3>${escapeHtml(item.label)}</h3>
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
    const { loadModule } = await import('./module-runtime.js?v=20260813-whatsapp1');
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

window.addEventListener('hashchange', () => {
  const hashId = window.location.hash.replace('#', '').trim();
  if (!hashId || hashId === selectedModuleId) return;
  const target = navigationItems.find((item) => item.id === hashId || item.href.split('#')[1] === hashId);
  if (target) selectModule(target.id);
});

async function startRealtime() {
  if (realtimeConnecting ||
      realtimeSocket?.readyState === WebSocket.OPEN ||
      realtimeSocket?.readyState === WebSocket.CONNECTING ||
      !isAuthenticated()) return;
  clearTimeout(realtimeReconnectTimer);
  realtimeConnecting = true;

  try {
    const ticketResponse = await apiFetch('/realtime/ticket', {
      method: 'POST',
      body: {},
    });
    const ticket = ticketResponse?.ticket;
    if (!ticket || !isAuthenticated()) throw new Error('realtime_ticket_missing');

    const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const url = `${scheme}://${window.location.host}/api/v1/realtime/live?ticket=${encodeURIComponent(ticket)}&reconnectCount=0`;
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
  } finally {
    realtimeConnecting = false;
  }
}

function scheduleModuleRefresh(eventType) {
  clearTimeout(realtimeRefreshTimer);
  realtimeRefreshTimer = setTimeout(() => {
    document.dispatchEvent(new CustomEvent('serenut:realtime', { detail: { eventType } }));
    if (selectedModuleId !== 'home') selectModule(selectedModuleId);
  }, 400);
}
