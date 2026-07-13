/* index.js — Customer Self-Service Portal Engine */

const BASE_URL = '/api/v1';
let authToken = sessionStorage.getItem('portal_token') || '';

function escapeHTML(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

let selectedTicketId = null;

// ── 1. SETUP EVENT LISTENERS & CLOCK ─────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  startHeaderClock();
  
  if (authToken) {
    showPortalApp();
  } else {
    showLoginCard();
  }

  // Auth Button Listeners
  document.getElementById('btn-login').addEventListener('click', handleLogin);
  document.getElementById('btn-register').addEventListener('click', handleRegister);
  document.getElementById('btn-logout').addEventListener('click', handleLogout);

  // Tab Switcher Click Bindings (Programmatic binding to satisfy Content Security Policy)
  document.getElementById('tab-login-btn').addEventListener('click', () => switchAuthTab('login'));
  document.getElementById('tab-register-btn').addEventListener('click', () => switchAuthTab('register'));

  // If URL hash is #register, open register tab by default
  if (window.location.hash === '#register') {
    switchAuthTab('register');
  }

  // Navigation tab toggling
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tabId = item.getAttribute('data-tab');
      switchTab(tabId);
    });
  });

  // ── SETTINGS TAB: Profile + Password ─────────────────────────────────────────

  // Save Profile button
  const btnSaveProfile = document.getElementById('btn-save-profile');
  if (btnSaveProfile) {
    btnSaveProfile.addEventListener('click', async () => {
      const name       = document.getElementById('settings-company-name').value.trim();
      const phone      = document.getElementById('settings-company-phone').value.trim();
      const tax_office = document.getElementById('settings-company-tax-office').value.trim();
      const address    = document.getElementById('settings-company-address').value.trim();
      const statusEl  = document.getElementById('profile-status');
      statusEl.style.color = '';
      statusEl.innerText   = '';
      try {
        const res = await portalFetch('/companies/current', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name, phone, tax_office, address })
        });
        if (res.ok) {
          statusEl.style.color = '#10b981';
          statusEl.innerText   = '✓ Firma bilgileri güncellendi.';
          document.getElementById('sidebar-company-name').innerText = name || 'Şirketiniz';
        } else {
          const err = await res.json();
          statusEl.style.color = '#ef4444';
          statusEl.innerText   = err?.message || 'Güncelleme başarısız.';
        }
      } catch (_) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText   = 'Sunucu bağlantı hatası.';
      }
    });
  }

  // Save Password button
  const btnSavePassword = document.getElementById('btn-save-password');
  if (btnSavePassword) {
    btnSavePassword.addEventListener('click', async () => {
      const old_password     = document.getElementById('settings-old-password').value;
      const new_password     = document.getElementById('settings-new-password').value;
      const confirm_password = document.getElementById('settings-confirm-password').value;
      const statusEl = document.getElementById('password-status');
      statusEl.style.color = '';
      statusEl.innerText   = '';
      if (!old_password || !new_password) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText   = 'Lütfen tüm alanları doldurun.';
        return;
      }
      if (new_password !== confirm_password) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText   = 'Yeni şifreler eşleşmiyor.';
        return;
      }
      if (new_password.length < 8) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText   = 'Yeni şifre en az 8 karakter olmalıdır.';
        return;
      }
      try {
        const res = await portalFetch('/auth/change-password', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ old_password, new_password })
        });
        if (res.ok) {
          statusEl.style.color = '#10b981';
          statusEl.innerText   = '✓ Şifreniz güncellendi. Güvenliğiniz için diğer oturumlar kapatıldı.';
          document.getElementById('settings-old-password').value = '';
          document.getElementById('settings-new-password').value = '';
          document.getElementById('settings-confirm-password').value = '';
        } else {
          const err = await res.json();
          statusEl.style.color = '#ef4444';
          statusEl.innerText   = err?.message || 'Şifre güncellenemedi. Mevcut şifrenizi kontrol edin.';
        }
      } catch (_) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText   = 'Sunucu bağlantı hatası.';
      }
    });
  }

  // ── LOGO UPLOAD ────────────────────────────────────────────────────────────
  const logoInput = document.getElementById('logo-file-input');
  if (logoInput) {
    logoInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (!file) return;
      if (file.size > 2 * 1024 * 1024) {
        document.getElementById('logo-status').style.color = '#ef4444';
        document.getElementById('logo-status').innerText = 'Dosya 2MB\'dan küçük olmalıdır.';
        return;
      }
      const reader = new FileReader();
      reader.onload = (ev) => {
        const dataUrl = ev.target.result;
        const img = document.getElementById('logo-preview-img');
        const placeholder = document.getElementById('logo-preview-placeholder');
        img.src = dataUrl;
        img.style.display = 'block';
        placeholder.style.display = 'none';
        document.getElementById('btn-save-logo').disabled = false;
        document.getElementById('btn-save-logo')._logoDataUrl = dataUrl;
      };
      reader.readAsDataURL(file);
    });
  }

  const btnSaveLogo = document.getElementById('btn-save-logo');
  if (btnSaveLogo) {
    btnSaveLogo.addEventListener('click', async () => {
      const statusEl = document.getElementById('logo-status');
      const dataUrl = btnSaveLogo._logoDataUrl;
      if (!dataUrl) return;
      statusEl.innerText = 'Kaydediliyor...';
      statusEl.style.color = 'var(--text-secondary)';
      try {
        const res = await portalFetch('/companies/current', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ logo_url: dataUrl })
        });
        if (res.ok) {
          statusEl.style.color = '#10b981';
          statusEl.innerText = '✓ Logo kaydedildi.';
          // Show in sidebar
          updateSidebarLogo(dataUrl);
        } else {
          statusEl.style.color = '#ef4444';
          statusEl.innerText = 'Logo kaydedilemedi.';
        }
      } catch (_) {
        statusEl.style.color = '#ef4444';
        statusEl.innerText = 'Sunucu bağlantı hatası.';
      }
    });
  }

  // ── USER MANAGEMENT MODALS ────────────────────────────────────────────────

  // Open Add User modal
  const btnCreateUser = document.getElementById('btn-create-user');
  if (btnCreateUser) {
    btnCreateUser.addEventListener('click', async () => {
      document.getElementById('usr-name').value = '';
      document.getElementById('usr-email').value = '';
      document.getElementById('usr-password').value = '';
      document.getElementById('usr-error').innerText = '';
      // Load roles dynamically
      const roles = await loadRoles();
      const sel = document.getElementById('usr-role');
      sel.innerHTML = roles.map(r => {
        const label = r.name === 'owner' ? 'Firma Sahibi' : r.name === 'manager' ? 'Yönetici / Şube Müdürü' : r.name === 'cashier' ? 'Kasiyer (Sadece Satış)' : r.name;
        return `<option value="${r.id}">${label}</option>`;
      }).join('');
      // Default to cashier
      const cashierOpt = [...sel.options].find(o => o.text.toLowerCase().includes('kasiyer'));
      if (cashierOpt) cashierOpt.selected = true;
      document.getElementById('modal-user').classList.add('active');
    });
  }

  document.getElementById('btn-user-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-user').classList.remove('active');
  });

  // Submit new user
  document.getElementById('btn-user-submit')?.addEventListener('click', async () => {
    const name     = document.getElementById('usr-name').value.trim();
    const email    = document.getElementById('usr-email').value.trim();
    const password = document.getElementById('usr-password').value;
    const role_id  = document.getElementById('usr-role').value;
    const errEl    = document.getElementById('usr-error');
    errEl.innerText = '';

    if (!name || !email || !password || !role_id) {
      errEl.innerText = 'Tüm alanları doldurun.';
      return;
    }

    try {
      const res = await portalFetch('/portal/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password, role_id })
      });
      if (res.ok) {
        document.getElementById('modal-user').classList.remove('active');
        loadUsers();
      } else {
        const err = await res.json();
        errEl.innerText = err.message || 'Kullanıcı eklenemedi.';
      }
    } catch (_) {
      errEl.innerText = 'Sunucu bağlantı hatası.';
    }
  });

  // Reset Password modal submit
  document.getElementById('btn-reset-pw-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-reset-password').classList.remove('active');
  });

  document.getElementById('btn-reset-pw-submit')?.addEventListener('click', async () => {
    const new_password = document.getElementById('reset-new-password').value;
    const errEl = document.getElementById('reset-pw-error');
    errEl.innerText = '';
    if (!new_password || new_password.length < 8) {
      errEl.innerText = 'Şifre en az 8 karakter olmalıdır.';
      return;
    }
    if (!_resetTargetUserId) return;
    try {
      const res = await portalFetch(`/portal/users/${_resetTargetUserId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ new_password })
      });
      if (res.ok) {
        document.getElementById('modal-reset-password').classList.remove('active');
        alert('Şifre başarıyla güncellendi.');
      } else {
        const err = await res.json();
        errEl.innerText = err.message || 'Şifre güncellenemedi.';
      }
    } catch (_) {
      errEl.innerText = 'Sunucu bağlantı hatası.';
    }
  });

  // Modal event binders
  setupModalListeners();
});

function updateSidebarLogo(dataUrl) {
  const nameEl = document.getElementById('sidebar-company-name');
  if (!nameEl) return;
  const parent = nameEl.closest('.sidebar-user-card');
  if (!parent) return;
  const avatarDiv = parent.querySelector('div:first-child');
  if (avatarDiv) {
    avatarDiv.innerHTML = `<img src="${dataUrl}" alt="Logo" style="width:40px;height:40px;border-radius:50%;object-fit:cover;">`;
  }
}

function startHeaderClock() {
  setInterval(() => {
    const clock = document.getElementById('header-clock');
    if (clock) {
      clock.innerText = new Date().toLocaleTimeString('tr-TR');
    }
  }, 1000);
}

// ── 2. SESSION CONTROL ───────────────────────────────────────────────────────
function showLoginCard() {
  document.getElementById('auth-wrapper').style.display = 'flex';
  document.getElementById('portal-app').style.display = 'none';
  const nav = document.getElementById('portal-navbar');
  if (nav) nav.style.display = 'block';
  // Restore marketing links when logged out
  const navLinks = document.getElementById('portal-nav-links');
  const navActions = document.getElementById('portal-nav-actions');
  if (navLinks) navLinks.style.display = '';
  if (navActions) navActions.style.display = '';
}

function showPortalApp() {
  document.getElementById('auth-wrapper').style.display = 'none';
  document.getElementById('portal-app').style.display = 'flex';
  // Hide marketing nav links when logged in — only logo remains in header
  const navLinks = document.getElementById('portal-nav-links');
  const navActions = document.getElementById('portal-nav-actions');
  if (navLinks) navLinks.style.display = 'none';
  if (navActions) navActions.style.display = 'none';
  // Load initial company details for sidebar header
  loadCompanyProfileHeader();
  // Switch to default dashboard
  switchTab('dashboard');
}

async function handleLogin() {
  const email = document.getElementById('login-email').value;
  const password = document.getElementById('login-password').value;
  const errorEl = document.getElementById('login-error');
  errorEl.innerText = '';

  if (!email || !password) {
    errorEl.innerText = 'Lütfen e-posta ve şifrenizi girin.';
    return;
  }

  try {
    const res = await fetch(`${BASE_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    const data = await res.json();
    if (!res.ok) {
      errorEl.innerText = data.message || 'Giriş başarısız.';
      return;
    }

    authToken = data.access_token;
    sessionStorage.setItem('portal_token', authToken);
    showPortalApp();
  } catch (err) {
    errorEl.innerText = 'Bağlantı hatası oluştu.';
  }
}

function handleLogout() {
  authToken = '';
  sessionStorage.removeItem('portal_token');
  showLoginCard();
}

// ── AUTH TAB SWITCHER ────────────────────────────────────────────────────────
function switchAuthTab(tab) {
  const loginForm = document.getElementById('form-login');
  const regForm   = document.getElementById('form-register');
  const loginBtn  = document.getElementById('tab-login-btn');
  const regBtn    = document.getElementById('tab-register-btn');

  if (tab === 'register') {
    loginForm.style.display = 'none';
    regForm.style.display   = 'flex';
    loginBtn.classList.remove('active');
    regBtn.classList.add('active');
  } else {
    loginForm.style.display = 'flex';
    regForm.style.display   = 'none';
    loginBtn.classList.add('active');
    regBtn.classList.remove('active');
  }
}

// ── REGISTER HANDLER ─────────────────────────────────────────────────────────
async function handleRegister() {
  const company_name = document.getElementById('reg-company').value.trim();
  const name         = document.getElementById('reg-name').value.trim();
  const email        = document.getElementById('reg-email').value.trim();
  const username     = document.getElementById('reg-username').value.trim();
  const phone        = document.getElementById('reg-phone').value.trim();
  const tax_number   = document.getElementById('reg-taxno').value.trim();
  const password     = document.getElementById('reg-password').value;
  const errorEl      = document.getElementById('register-error');
  const btn          = document.getElementById('btn-register');
  errorEl.innerText  = '';

  if (!company_name || !name || !email || !username || !phone || !tax_number || !password) {
    errorEl.innerText = 'Lütfen yıldızlı (*) tüm zorunlu alanları doldurun.';
    return;
  }
  if (password.length < 6) {
    errorEl.innerText = 'Şifre en az 6 karakter olmalıdır.';
    return;
  }

  btn.disabled = true;
  btn.innerText = 'Kayıt oluşturuluyor...';

  try {
    const res = await fetch(`${BASE_URL}/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_name, name, email, phone, password })
    });

    const data = await res.json();
    if (!res.ok) {
      errorEl.innerText = data.message || 'Kayıt başarısız.';
      return;
    }

    authToken = data.access_token;
    sessionStorage.setItem('portal_token', authToken);
    showPortalApp();
  } catch (err) {
    errorEl.innerText = 'Bağlantı hatası oluştu.';
  } finally {
    btn.disabled = false;
    btn.innerText = 'Ücretsiz Dene — 30 Gün';
  }
}

// Fetch helper with Bearer token injection
async function portalFetch(endpoint, options = {}) {
  const headers = {
    'Authorization': `Bearer ${authToken}`,
    'Content-Type': 'application/json',
    ...(options.headers || {})
  };

  const res = await fetch(`${BASE_URL}${endpoint}`, {
    ...options,
    headers
  });

  if (res.status === 401) {
    handleLogout();
    throw new Error('Unauthorized');
  }

  return res;
}

// Load company details for branding/header
async function loadCompanyProfileHeader() {
  try {
    const res = await portalFetch('/companies/current');
    const company = await res.json();
    document.getElementById('sidebar-company-name').innerText = company.name;
  } catch (_) {
    document.getElementById('sidebar-company-name').innerText = 'Şirketiniz';
  }
}

// ── 3. TAB NAVIGATION CONTROL ────────────────────────────────────────────────
function switchTab(tabId) {
  // Update menu highlights
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach(item => {
    if (item.getAttribute('data-tab') === tabId) {
      item.classList.add('active');
    } else {
      item.classList.remove('active');
    }
  });

  // Switch content panels
  const panels = document.querySelectorAll('.tab-panel');
  panels.forEach(panel => {
    if (panel.id === `tab-${tabId}`) {
      panel.classList.add('active');
    } else {
      panel.classList.remove('active');
    }
  });

  // Header Title
  const titles = {
    dashboard: 'Şirket Genel Özet Raporu',
    stores: 'Şubeleriniz (Mağazalar)',
    devices: 'Aktif POS Cihazları Donanım Durumu',
    users: 'Kasiyer & Personel Hesapları',
    invoices: 'Abonelik Ödemeleri & Faturalar',
    downloads: 'Yazılım İndirme Merkezi',
    tickets: 'Destek Talepleriniz',
    settings: 'Hesap & Profil Ayarları'
  };
  document.getElementById('current-tab-title').innerText = titles[tabId] || 'Portal';

  // Load selected tab data
  loadTab(tabId);
}

function loadTab(tabId) {
  switch (tabId) {
    case 'dashboard':
      loadDashboard();
      break;
    case 'stores':
      loadStores();
      break;
    case 'devices':
      loadDevices();
      break;
    case 'users':
      loadUsers();
      break;
    case 'subscription':
      loadSubscription();
      break;
    case 'invoices':
      loadInvoices();
      break;
    case 'backups':
      loadBackups();
      break;
    case 'downloads':
      // Downloads tab is static HTML — no API call needed
      break;
    case 'tickets':
      loadTickets();
      break;
    case 'settings':
      loadSettings();
      break;
  }
}


// ── 4. DATA LOADING ACTIONS ──────────────────────────────────────────────────

// LOAD PORTAL DASHBOARD
async function loadDashboard() {
  try {
    const res = await portalFetch('/portal/dashboard');
    const data = await res.json();

    // Stats
    document.getElementById('stat-stores').innerText = data.summary.stores;
    document.getElementById('stat-devices').innerText = data.summary.devices;
    document.getElementById('stat-invoices').innerText = data.summary.unpaidInvoices;
    document.getElementById('stat-revenue').innerText = `${data.summary.monthlyRevenue.toLocaleString('tr-TR')} TRY`;

    // Licenses table
    const tbody = document.getElementById('dashboard-licenses-body');
    tbody.innerHTML = '';

    if (data.licenses.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center">Şirketinize ait aktif lisans bulunamadı.</td></tr>';
      return;
    }

    data.licenses.forEach(l => {
      const expires = new Date(l.expires_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong></strong></td>
        <td><span class="badge badge-"></span></td>
        <td> Cihaz</td>
        <td>${expires}</td>
        <td><span class="badge badge-"></span></td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load portal dashboard:', err);
  }
}

// LOAD STORES
async function loadStores() {
  try {
    const res = await portalFetch('/portal/stores');
    const stores = await res.json();
    const tbody = document.getElementById('stores-table-body');
    tbody.innerHTML = '';

    if (stores.length === 0) {
      tbody.innerHTML = '<tr><td colspan="4" class="text-center">Kayıtlı şube bulunamadı.</td></tr>';
      return;
    }

    stores.forEach(s => {
      const created = new Date(s.created_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong></strong></td>
        <td></td>
        <td></td>
        <td>${created}</td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// LOAD DEVICES
async function loadDevices() {
  try {
    const res = await portalFetch('/portal/devices');
    const devices = await res.json();
    const tbody = document.getElementById('devices-table-body');
    tbody.innerHTML = '';

    if (devices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center">Bağlı POS cihazı bulunamadı.</td></tr>';
      return;
    }

    devices.forEach(d => {
      const active = d.last_active_at ? new Date(d.last_active_at).toLocaleString('tr-TR') : 'Hiç';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong></strong></td>
        <td>${d.name || 'Terminal'}</td>
        <td>${d.store_name || '-'}</td>
        <td><span style="font-family:monospace;font-size:0.8rem;">${d.device_hash.substring(0, 16)}...</span></td>
        <td><span class="indicator ${d.is_online ? 'online' : 'offline'}">${d.is_online ? 'Çevrimiçi' : 'Çevrimdışı'}</span></td>
        <td>${active}</td>
        <td><span class="badge badge-"></span></td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// LOAD USERS — card grid with role, status, and action buttons
let _availableRoles = [];

async function loadRoles() {
  if (_availableRoles.length > 0) return _availableRoles;
  try {
    const res = await portalFetch('/portal/roles');
    _availableRoles = await res.json();
  } catch (_) {}
  return _availableRoles;
}

async function loadUsers() {
  const grid = document.getElementById('users-card-grid');
  if (!grid) return;
  grid.innerHTML = '<p style="color:var(--text-secondary);padding:20px;">Yükleniyor...</p>';

  try {
    const [resUsers, roles] = await Promise.all([
      portalFetch('/portal/users'),
      loadRoles()
    ]);
    const users = await resUsers.json();

    if (!Array.isArray(users) || users.length === 0) {
      grid.innerHTML = '<p style="color:var(--text-secondary);padding:20px;">Henüz kullanıcı eklenmemiş. "+ Yeni Kullanıcı Ekle" butonunu kullanın.</p>';
      return;
    }

    grid.innerHTML = '';
    users.forEach(u => {
      const roleObj = roles.find(r => r.id === u.role_id);
      const roleName = roleObj ? (roleObj.name === 'owner' ? '👑 Firma Sahibi' : roleObj.name === 'manager' ? '🏪 Yönetici' : '🧾 Kasiyer') : (u.role_name || '—');
      const isActive = u.is_active !== false;
      const created = new Date(u.created_at).toLocaleDateString('tr-TR');

      const card = document.createElement('div');
      card.className = 'glass-panel';
      card.style.cssText = 'padding: 20px; display: flex; flex-direction: column; gap: 14px; border: 1px solid var(--border-color);';
      card.innerHTML = `
        <div style="display: flex; align-items: center; gap: 14px;">
          <div style="width:44px;height:44px;border-radius:50%;background:rgba(16,185,129,0.1);color:var(--neon-teal);display:flex;align-items:center;justify-content:center;font-size:1.4rem;flex-shrink:0;">
            ${roleName.startsWith('👑') ? '👑' : roleName.startsWith('🏪') ? '🏪' : '🧾'}
          </div>
          <div style="flex:1;min-width:0;">
            <div style="font-weight:600;color:var(--text-primary);font-size:1rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>
            <div style="color:var(--text-secondary);font-size:0.82rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>
          </div>
          <span style="font-size:0.7rem;padding:3px 10px;border-radius:12px;font-weight:700;background:${isActive ? 'rgba(16,185,129,0.15)' : 'rgba(239,68,68,0.15)'};color:${isActive ? '#10b981' : '#ef4444'};">
            ${isActive ? '● AKTİF' : '● PASİF'}
          </span>
        </div>
        <div style="display:flex;justify-content:space-between;align-items:center;font-size:0.8rem;color:var(--text-secondary);">
          <span>${roleName}</span>
          <span>Eklendi: ${created}</span>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;">
          <button onclick="openResetPasswordModal('','${u.name.replace(/'/g,"&#39;")}')" style="flex:1;padding:8px;font-size:0.78rem;border-radius:6px;border:1px solid var(--border-color);background:transparent;color:var(--text-primary);cursor:pointer;">🔑 Şifre Sıfırla</button>
          <button onclick="togglePortalUserActive('', ${isActive})" style="flex:1;padding:8px;font-size:0.78rem;border-radius:6px;border:1px solid var(--border-color);background:transparent;color:${isActive ? '#f59e0b' : '#10b981'};cursor:pointer;">${isActive ? '⏸ Pasife Al' : '▶ Aktifleştir'}</button>
          <button onclick="deletePortalUser('','${u.name.replace(/'/g,"&#39;")}')" style="flex:1;padding:8px;font-size:0.78rem;border-radius:6px;border:1px solid rgba(239,68,68,0.3);background:transparent;color:#ef4444;cursor:pointer;">🗑 Sil</button>
        </div>
      `;
      grid.appendChild(card);
    });
  } catch (_) {
    grid.innerHTML = '<p style="color:#ef4444;padding:20px;">Kullanıcılar yüklenirken hata oluştu.</p>';
  }
}

// Open the reset password modal for a specific user
let _resetTargetUserId = null;
window.openResetPasswordModal = function(userId, userName) {
  _resetTargetUserId = userId;
  document.getElementById('reset-pw-user-name').innerText = `Kullanıcı: ${userName}`;
  document.getElementById('reset-new-password').value = '';
  document.getElementById('reset-pw-error').innerText = '';
  document.getElementById('modal-reset-password').classList.add('active');
};

// Toggle user active/inactive
window.togglePortalUserActive = async function(userId, currentlyActive) {
  try {
    const res = await portalFetch(`/portal/users/${userId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ is_active: !currentlyActive })
    });
    if (res.ok) {
      loadUsers();
    } else {
      alert('İşlem başarısız.');
    }
  } catch (_) {
    alert('Sunucu hatası.');
  }
};

// Delete portal user
window.deletePortalUser = async function(userId, userName) {
  if (!confirm(`"${userName}" adlı kullanıcıyı silmek istediğinize emin misiniz? Bu işlem geri alınamaz.`)) return;
  try {
    const res = await portalFetch(`/portal/users/${userId}`, { method: 'DELETE' });
    if (res.ok) {
      loadUsers();
    } else {
      const err = await res.json();
      alert(err.message || 'Silme işlemi başarısız.');
    }
  } catch (_) {
    alert('Sunucu hatası.');
  }
};

// LOAD INVOICES
async function loadInvoices() {
  try {
    const res = await portalFetch('/portal/invoices');
    const invoices = await res.json();
    const tbody = document.getElementById('invoices-table-body');
    tbody.innerHTML = '';

    if (invoices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center">Fatura kaydı bulunamadı.</td></tr>';
      return;
    }

    invoices.forEach(i => {
      const due = new Date(i.due_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${i.invoice_number || i.id}</strong></td>
        <td>${i.amount} TRY</td>
        <td>${due}</td>
        <td><span class="badge badge-${i.status}">${i.status === 'paid' ? 'Ödendi' : 'Ödenmedi'}</span></td>
        <td>
          <button class="btn-secondary" onclick="downloadInvoicePdf('${i.id}', '${i.invoice_number}')">📄 PDF İndir</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.downloadInvoicePdf = async function(invoiceId, invoiceNumber) {
  try {
    const res = await fetch(`/api/v1/billing/invoices/${invoiceId}/pdf`, {
      headers: {
        'Authorization': `Bearer ${authToken}`
      }
    });
    if (!res.ok) {
      alert('Fatura PDF dosyası bulunamadı.');
      return;
    }
    const blob = await res.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${invoiceNumber || invoiceId}.pdf`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
  } catch (err) {
    alert('Fatura indirilirken hata oluştu.');
  }
};

// LOAD TICKETS
async function loadTickets() {
  try {
    const res = await portalFetch('/portal/tickets');
    const tickets = await res.json();
    const tbody = document.getElementById('tickets-table-body');
    tbody.innerHTML = '';

    if (tickets.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Açık destek talebiniz bulunmamaktadır.</td></tr>';
      return;
    }

    tickets.forEach(t => {
      const updated = new Date(t.updated_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong></strong></td>
        <td></td>
        <td><span class="badge border-amber"></span></td>
        <td><span class="badge badge-"></span></td>
        <td>${updated}</td>
        <td>
          <button class="btn-secondary" onclick="openTicketChat('', '', '')">Yanıtlar / Oku</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.openTicketChat = async function(id, title, status) {
  selectedTicketId = id;
  document.getElementById('ticket-chat-title').innerText = title;
  const badge = document.getElementById('ticket-status-badge');
  badge.innerText = status;
  badge.className = `status-badge badge-${status}`;

  await loadTicketChatMessages(id);
  document.getElementById('modal-ticket-chat').classList.add('active');
};

async function loadTicketChatMessages(ticketId) {
  const container = document.getElementById('ticket-chat-messages');
  container.innerHTML = '';
  try {
    const res = await portalFetch(`/portal/tickets/${ticketId}/messages`);
    const messages = await res.json();

    messages.forEach(msg => {
      const isAdmin = msg.sender_name === 'Serenut Destek';
      const div = document.createElement('div');
      div.className = `chat-msg ${isAdmin ? 'chat-msg-admin' : 'chat-msg-user'}`;
      div.innerHTML = `
        <strong>${msg.sender_name}</strong>
        <p>${msg.message}</p>
        <span class="chat-msg-time">${new Date(msg.created_at).toLocaleTimeString('tr-TR', {hour: '2-digit', minute:'2-digit'})}</span>
      `;
      container.appendChild(div);
    });

    container.scrollTop = container.scrollHeight;
  } catch (_) {}
}

document.getElementById('btn-ticket-send').addEventListener('click', async () => {
  const input = document.getElementById('ticket-reply-text');
  const message = input.value;
  if (!message || !selectedTicketId) return;

  try {
    const res = await portalFetch(`/portal/tickets/${selectedTicketId}/reply`, {
      method: 'POST',
      body: JSON.stringify({ message })
    });
    if (res.ok) {
      input.value = '';
      loadTicketChatMessages(selectedTicketId);
      loadTickets(); // Refresh table
    }
  } catch (_) {}
});

// ── 5. MODALS & SUBMISSIONS ──────────────────────────────────────────────────
function setupModalListeners() {
  const modals = {
    store: {
      open: 'btn-create-store',
      close: 'btn-store-cancel',
      overlay: 'modal-store',
      submit: 'btn-store-submit',
      action: submitCreateStore
    },
    user: {
      open: 'btn-create-user',
      close: 'btn-user-cancel',
      overlay: 'modal-user',
      submit: 'btn-user-submit',
      action: submitCreateUser
    },
    ticket: {
      open: 'btn-create-ticket',
      close: 'btn-tkt-cancel',
      overlay: 'modal-ticket-create',
      submit: 'btn-tkt-submit',
      action: submitCreateTicket
    }
  };

  Object.keys(modals).forEach(key => {
    const m = modals[key];
    const openBtn = document.getElementById(m.open);
    const closeBtn = document.getElementById(m.close);
    const overlay = document.getElementById(m.overlay);
    const submitBtn = document.getElementById(m.submit);

    if (openBtn) {
      openBtn.addEventListener('click', () => overlay.classList.add('active'));
    }
    if (closeBtn) {
      closeBtn.addEventListener('click', () => overlay.classList.remove('active'));
    }
    if (submitBtn) {
      submitBtn.addEventListener('click', async () => {
        const success = await m.action();
        if (success) overlay.classList.remove('active');
      });
    }
  });

  // Chat close
  document.getElementById('btn-ticket-close').addEventListener('click', () => {
    document.getElementById('modal-ticket-chat').classList.remove('active');
    selectedTicketId = null;
  });
}

// SUBMIT CREATE STORE
async function submitCreateStore() {
  const name = document.getElementById('store-name').value;
  const address = document.getElementById('store-address').value;
  if (!name) {
    alert('Şube ismi boş bırakılamaz.');
    return false;
  }

  try {
    const res = await portalFetch('/portal/stores', {
      method: 'POST',
      body: JSON.stringify({ name, address })
    });
    if (res.ok) {
      alert('Yeni şube başarıyla eklendi.');
      loadStores();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// SUBMIT CREATE USER
async function submitCreateUser() {
  const name = document.getElementById('usr-name').value;
  const email = document.getElementById('usr-email').value;
  const password = document.getElementById('usr-password').value;
  const role_id = document.getElementById('usr-role').value;

  if (!name || !email || !password) {
    alert('Lütfen tüm alanları doldurun.');
    return false;
  }

  try {
    const res = await portalFetch('/portal/users', {
      method: 'POST',
      body: JSON.stringify({ name, email, password, role_id })
    });
    if (res.ok) {
      alert('Personel hesabı başarıyla oluşturuldu.');
      loadUsers();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// SUBMIT CREATE SUPPORT TICKET
async function submitCreateTicket() {
  const title = document.getElementById('tkt-title').value;
  const priority = document.getElementById('tkt-priority').value;
  const description = document.getElementById('tkt-desc').value;

  if (!title || !description) {
    alert('Destek konusu ve açıklama zorunludur.');
    return false;
  }

  try {
    const res = await portalFetch('/portal/tickets', {
      method: 'POST',
      body: JSON.stringify({ title, priority, description })
    });
    if (res.ok) {
      alert('Destek talebiniz başarıyla iletildi.');
      loadTickets();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// ── 6.0 SETTINGS (Profile + Password) ─────────────────────────────────────────
async function loadSettings() {
  try {
    const res = await portalFetch('/companies/current');
    if (!res.ok) return;
    const company = await res.json();
    const nameEl     = document.getElementById('settings-company-name');
    const phoneEl    = document.getElementById('settings-company-phone');
    const taxEl      = document.getElementById('settings-company-tax-office');
    const addressEl  = document.getElementById('settings-company-address');
    if (nameEl)    nameEl.value    = company.name    || '';
    if (phoneEl)   phoneEl.value   = company.phone   || '';
    if (taxEl)     taxEl.value     = company.tax_office || '';
    if (addressEl) addressEl.value = company.address || '';
    // Show existing logo
    if (company.logo_url) {
      const img = document.getElementById('logo-preview-img');
      const placeholder = document.getElementById('logo-preview-placeholder');
      const saveBtn = document.getElementById('btn-save-logo');
      if (img) { img.src = company.logo_url; img.style.display = 'block'; }
      if (placeholder) placeholder.style.display = 'none';
      if (saveBtn) { saveBtn.disabled = false; saveBtn._logoDataUrl = company.logo_url; }
      updateSidebarLogo(company.logo_url);
    }
  } catch (_) {}
}

// ── 6. SUBSCRIPTION & BILLING FLOWS ──────────────────────────────────────────
async function loadSubscription() {

  const container = document.getElementById('sub-active-details');
  const cancelBtn = document.getElementById('btn-sub-cancel');
  const reactivateBtn = document.getElementById('btn-sub-reactivate');

  container.innerHTML = '<p>Yükleniyor...</p>';
  cancelBtn.style.display = 'none';
  reactivateBtn.style.display = 'none';

  try {
    const res = await portalFetch('/billing/subscription');
    const sub = await res.json();

    if (!res.ok || sub.status === 'no_subscription') {
      container.innerHTML = `
        <div style="color: #EF4444; font-weight: bold; margin-bottom: 8px;">Aktif Abonelik Bulunmuyor</div>
        <p style="color: #94A3B8; font-size: 0.9rem; margin: 0;">Sistemi kullanabilmek için lütfen aşağıdaki planlardan birini satın alın.</p>
      `;
      return;
    }

    const end = new Date(sub.current_period_end).toLocaleDateString('tr-TR');
    const badgeClass = sub.status === 'active' ? 'active' : 'suspended';
    const statusText = sub.status === 'active' ? 'Aktif (Otomatik Yenileniyor)' : (sub.status === 'grace_period' ? 'Tolerans Süresinde (Ödeme Bekliyor)' : 'Askıya Alındı');

    container.innerHTML = `
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 0.95rem; color: #E2E8F0;">
        <div><strong>Plan:</strong> <span class="badge badge-pro" style="font-size:0.85rem;">${sub.plan_name}</span></div>
        <div><strong>Durum:</strong> <span class="badge badge-${badgeClass}" style="font-size:0.85rem;">${statusText}</span></div>
        <div><strong>Tutar:</strong> ${sub.price} ${sub.currency || 'TRY'} / ay</div>
        <div><strong>Dönem Sonu:</strong> ${end}</div>
        ${sub.cancel_at_period_end ? '<div style="grid-column: span 2; color:#F59E0B; font-weight: 600;">⚠️ Dönem sonunda iptal edilecek.</div>' : ''}
      </div>
    `;

    if (sub.status === 'active' && !sub.cancel_at_period_end) {
      cancelBtn.style.display = 'inline-block';
    } else if (sub.cancel_at_period_end || sub.status === 'suspended') {
      reactivateBtn.style.display = 'inline-block';
    }
  } catch (err) {
    container.innerHTML = '<p style="color: #EF4444;">Abonelik bilgileri yüklenemedi.</p>';
  }
}

window.initiatePlanPurchase = async function(planId) {
  try {
    const res = await portalFetch('/billing/subscribe', {
      method: 'POST',
      body: JSON.stringify({ plan_id: planId })
    });
    const data = await res.json();

    if (!res.ok) {
      alert(data.message || 'Ödeme işlemi başlatılamadı.');
      return;
    }

    // Open payment checkout in a secure popup window
    const width = 500;
    const height = 600;
    const left = (screen.width - width) / 2;
    const top = (screen.height - height) / 2;
    
    const popup = window.open(
      data.checkoutUrl,
      'Serenut Güvenli Ödeme',
      `width=${width},height=${height},top=${top},left=${left},scrollbars=yes`
    );

    // Listen for payment completion postMessage
    const messageListener = (event) => {
      if (event.data && (event.data.status === 'success' || event.data.status === 'pending')) {
        if (event.data.status === 'pending') {
          alert('Banka havalesi bildiriminiz alınmıştır. Yönetici onayı sonrası aboneliğiniz aktif edilecektir.');
        } else {
          alert('Ödemeniz başarıyla doğrulandı ve aboneliğiniz aktif edildi!');
        }
        window.removeEventListener('message', messageListener);
        loadSubscription();
      }
    };
    window.addEventListener('message', messageListener);

  } catch (err) {
    alert('Ödeme başlatılırken hata oluştu.');
  }
};

// ── 7. CLOUD BACKUPS MANAGEMENT ──────────────────────────────────────────────
async function loadBackups() {
  try {
    const res = await portalFetch('/portal/backups');
    const backups = await res.json();
    const tbody = document.getElementById('backups-table-body');
    tbody.innerHTML = '';

    if (backups.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Kayıtlı bulut yedeği bulunamadı.</td></tr>';
      return;
    }

    backups.forEach(b => {
      const date = new Date(b.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${b.filename}</strong></td>
        <td>${b.size}</td>
        <td>${date}</td>
        <td><span class="badge border-teal">${b.type}</span></td>
        <td><span class="badge badge-active">Hazır</span></td>
        <td>
          <button class="btn-secondary" onclick="downloadBackup('${b.filename}')">⬇ Indir</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

async function downloadBackup(filename) {
  try {
    const res = await portalFetch('/portal/backups/download/' + filename);
    if (!res.ok) throw new Error('Download failed');
    const blob = await res.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.style.display = 'none';
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    a.remove();
  } catch (err) {
    alert('Yedek indirilirken hata oluştu: ' + err.message);
  }
}

window.downloadBackup = downloadBackup;


async function triggerBackup() {
  const btn = document.getElementById('btn-create-backup');
  btn.disabled = true;
  btn.innerText = 'Yedek Alınıyor...';

  try {
    const res = await portalFetch('/portal/backups', { method: 'POST' });
    if (res.ok) {
      alert('Yeni bulut yedeği başarıyla alındı.');
      loadBackups();
    } else {
      alert('Yedek alınamadı.');
    }
  } catch (err) {
    alert('Yedek alma sırasında hata oluşt.');
  } finally {
    btn.disabled = false;
    btn.innerText = '+ Manuel Bulut Yedeği Al';
  }
}

// ── 8. CANCELLATION / REACTIVATION MODALS ────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  // Backups button
  const backupBtn = document.getElementById('btn-create-backup');
  if (backupBtn) {
    backupBtn.addEventListener('click', triggerBackup);
  }

  // Cancel modal trigger
  const cancelBtn = document.getElementById('btn-sub-cancel');
  const cancelModal = document.getElementById('modal-sub-cancel');
  
  if (cancelBtn) {
    cancelBtn.addEventListener('click', () => {
      cancelModal.classList.add('active');
    });
  }

  const cancelClose = document.getElementById('btn-cancel-modal-close');
  if (cancelClose) {
    cancelClose.addEventListener('click', () => {
      cancelModal.classList.remove('active');
    });
  }

  const cancelSubmit = document.getElementById('btn-cancel-modal-submit');
  if (cancelSubmit) {
    cancelSubmit.addEventListener('click', async () => {
      const reason = document.getElementById('cancel-reason').value;
      const note = document.getElementById('cancel-note').value;

      try {
        const res = await portalFetch('/billing/cancel', {
          method: 'POST',
          body: JSON.stringify({ reason: `${reason}: ${note}` })
        });

        if (res.ok) {
          alert('Abonelik yenilemeniz iptal edildi. Dönem sonuna kadar kullanabilirsiniz.');
          cancelModal.classList.remove('active');
          loadSubscription();
        } else {
          alert('Abonelik iptal edilemedi.');
        }
      } catch (_) {
        alert('İşlem sırasında hata oluştu.');
      }
    });
  }

  // Reactivate action
  const reactivateBtn = document.getElementById('btn-sub-reactivate');
  if (reactivateBtn) {
    reactivateBtn.addEventListener('click', async () => {
      if (!confirm('Aboneliğinizi yeniden aktifleştirmek istiyor musunuz?')) return;
      try {
        const res = await portalFetch('/billing/reactivate', { method: 'POST' });
        if (res.ok) {
          alert('Aboneliğiniz başarıyla yeniden aktif edildi!');
          loadSubscription();
        } else {
          alert('Abonelik aktifleştirilemedi.');
        }
      } catch (_) {
        alert('İşlem sırasında hata oluştu.');
      }
    });
  }
});
