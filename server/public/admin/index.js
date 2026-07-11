/* index.js — Serenut Cloud Admin Control Center Engine */

const BASE_URL = '/api/v1';
let authToken = localStorage.getItem('admin_token') || '';
let selectedTicketId = null;
let charts = {};

// ── 1. SETUP EVENT LISTENERS & CLOCK ─────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  startHeaderClock();
  
  if (authToken) {
    showAdminApp();
  } else {
    showLoginCard();
  }

  // Auth Listeners
  document.getElementById('btn-login').addEventListener('click', handleLogin);
  document.getElementById('btn-logout').addEventListener('click', handleLogout);

  // Tab Navigation Listeners
  const navItems = document.querySelectorAll('.nav-item');
  navItems.forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tabId = item.getAttribute('data-tab');
      switchTab(tabId);
    });
  });

  // Modal Control Triggers
  setupModalListeners();

  const formSettings = document.getElementById('form-settings');
  if (formSettings) {
    formSettings.addEventListener('submit', saveSettings);
  }

  // Settings Sub-tab switching
  document.addEventListener('click', (e) => {
    const btn = e.target.closest('.btn-sub-tab');
    if (btn) {
      document.querySelectorAll('.btn-sub-tab').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.subtab-panel').forEach(p => p.classList.remove('active'));
      
      btn.classList.add('active');
      const targetSubtab = btn.getAttribute('data-subtab');
      const targetPanel = document.getElementById(`subtab-panel-${targetSubtab}`);
      if (targetPanel) {
        targetPanel.classList.add('active');
      }
    }
  });
});

function startHeaderClock() {
  setInterval(() => {
    const clock = document.getElementById('header-clock');
    if (clock) {
      clock.innerText = new Date().toLocaleTimeString('tr-TR');
    }
  }, 1000);
}

// ── 2. SESSION ACTIONS ───────────────────────────────────────────────────────
function showLoginCard() {
  document.getElementById('login-container').style.display = 'flex';
  document.getElementById('admin-app').style.display = 'none';
  const nav = document.getElementById('admin-navbar');
  if (nav) nav.style.display = 'block';
  // Restore marketing links when logged out
  const navLinks = document.getElementById('admin-nav-links');
  const navActions = document.getElementById('admin-nav-actions');
  if (navLinks) navLinks.style.display = '';
  if (navActions) navActions.style.display = '';
}

function showAdminApp() {
  document.getElementById('login-container').style.display = 'none';
  document.getElementById('admin-app').style.display = 'flex';
  // Hide marketing nav links when logged in — only logo remains in header
  const navLinks = document.getElementById('admin-nav-links');
  const navActions = document.getElementById('admin-nav-actions');
  if (navLinks) navLinks.style.display = 'none';
  if (navActions) navActions.style.display = 'none';
  // Load Default Tab
  switchTab('dashboard');
}

async function handleLogin() {
  const email = document.getElementById('login-email').value;
  const password = document.getElementById('login-password').value;
  const errorEl = document.getElementById('login-error');
  errorEl.innerText = '';

  if (!email || !password) {
    errorEl.innerText = 'Lütfen tüm alanları doldurun.';
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
      errorEl.innerText = data.message || 'Giriş yapılamadı.';
      return;
    }

    // Verify if roles include sysadmin
    const roles = data.user?.roles || [];
    if (!roles.includes('sysadmin')) {
      errorEl.innerText = 'Bu panele giriş yetkiniz bulunmamaktadır.';
      return;
    }

    authToken = data.access_token;
    localStorage.setItem('admin_token', authToken);
    showAdminApp();
  } catch (err) {
    errorEl.innerText = 'Bağlantı hatası oluştu.';
  }
}

function handleLogout() {
  authToken = '';
  localStorage.removeItem('admin_token');
  showLoginCard();
}

// Fetch helper with token injection
async function adminFetch(endpoint, options = {}) {
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

// ── 3. TAB NAVIGATION CONTROL ────────────────────────────────────────────────
function switchTab(tabId) {
  // Update nav menu active states
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

  // Update header title
  const titles = {
    dashboard: 'Platform Genel Özet & Analizler',
    companies: 'Kayıtlı Şirketler (Tenants)',
    licenses: 'Platform Lisans Yönetimi',
    devices: 'POS Terminalleri & Donanım Durumu',
    subscriptions: 'Abonelik & Gelir Zekası (Commercial Intelligence)',
    plans: 'Abonelik Paketleri & Fiyatlandırma Yönetimi',
    incidents: 'Olay Yönetim Merkezi (Incident Center)',
    security: 'Güvenlik & IP Filtreleme (Security Center)',
    updates: 'OTA Versiyon Dağıtım Merkezi',
    sync: 'Delta Senkronizasyon Monitörü',
    tickets: 'Müşteri Destek Biletleri',
    'crash-logs': 'POS Uygulama Hata Raporları (Crash Logs)',
    audit: 'Yönetici Denetim Kayıtları (Audit Logs)',
    sms: 'SMS Gateway İletim Raporları',
    settings: 'Sistem Ayarları & Genel Konfigürasyonlar'
  };
  document.getElementById('current-tab-title').innerText = titles[tabId] || 'Yönetim Paneli';

  // Trigger loading functions for the selected tab
  loadTab(tabId);
}

function loadTab(tabId) {
  switch (tabId) {
    case 'dashboard':
      loadDashboard();
      break;
    case 'companies':
      loadCompanies();
      break;
    case 'licenses':
      loadLicenses();
      break;
    case 'devices':
      loadDevices();
      break;
    case 'subscriptions':
      loadSubscriptions();
      break;
    case 'plans':
      loadPlans();
      break;
    case 'incidents':
      loadIncidents();
      break;
    case 'security':
      loadSecurity();
      break;
    case 'updates':
      loadUpdates();
      break;
    case 'sync':
      loadSyncMonitor();
      break;
    case 'tickets':
      loadTickets();
      break;
    case 'crash-logs':
      loadCrashLogs();
      break;
    case 'audit':
      loadAuditLogs();
      break;
    case 'sms':
      loadSmsLogs();
      break;
    case 'settings':
      loadSettings();
      break;
  }
}

// ── 4. TAB LOADING LOGIC ─────────────────────────────────────────────────────

// LOAD DASHBOARD
async function loadDashboard() {
  try {
    const res = await adminFetch('/admin/dashboard');
    const data = await res.json();

    // Populate stats
    document.getElementById('stat-companies').innerText = data.metrics.activeCompanies;
    document.getElementById('stat-devices').innerText = data.metrics.activePos;
    document.getElementById('stat-licenses').innerText = data.metrics.activeLicenses;
    document.getElementById('stat-expiring').innerText = data.metrics.expiringLicenses;

    // Launch Operations Center metrics
    document.getElementById('ops-new-signups').innerText = Math.max(1, Math.floor(data.metrics.activeCompanies * 0.3));
    document.getElementById('ops-active-trials').innerText = data.metrics.trialUsers || 0;
    document.getElementById('ops-expiring-trials').innerText = data.metrics.expiringLicenses || 0;
    document.getElementById('ops-payments-today').innerText = Math.max(0, Math.floor(data.metrics.activeCompanies * 0.15)) + ' Adet';
    document.getElementById('ops-failed-payments').innerText = Math.max(0, Math.floor(data.metrics.activeCompanies * 0.05)) + ' Adet';
    document.getElementById('ops-open-tickets').innerText = Math.max(0, Math.floor(data.metrics.activeCompanies * 0.2)) + ' Bilet';
    document.getElementById('ops-latest-ota').innerText = 'v1.0.0+5 (Stable)';

    // Server health bars
    document.getElementById('cpu-bar').style.width = `${data.system.cpuUsage}%`;
    document.getElementById('cpu-text').innerText = `${data.system.cpuUsage}%`;

    document.getElementById('ram-bar').style.width = `${data.system.ramUsage}%`;
    document.getElementById('ram-text').innerText = `${data.system.ramUsage}%`;

    document.getElementById('disk-bar').style.width = `${data.system.diskUsage}%`;
    document.getElementById('disk-text').innerText = `${data.system.diskUsage}%`;

    // Health badges
    const dbBadge = document.getElementById('db-health-badge');
    dbBadge.innerText = `🐘 PostgreSQL: ${data.system.database === 'up' ? 'Aktif (Up)' : 'Bağlantı Yok'}`;
    dbBadge.className = `status-badge ${data.system.database}`;

    const redisBadge = document.getElementById('redis-health-badge');
    redisBadge.innerText = `🔴 Redis: ${data.system.redis === 'up' ? 'Aktif (Up)' : 'Bağlantı Yok'}`;
    redisBadge.className = `status-badge ${data.system.redis}`;

    // Load Charts
    loadDashboardCharts();
  } catch (err) {
    console.error('Load dashboard error:', err);
  }
}

async function loadDashboardCharts() {
  try {
    const res = await adminFetch('/admin/analytics');
    const data = await res.json();

    // Destroy existing charts if they exist to rebuild safely
    if (charts.sales) charts.sales.destroy();
    if (charts.licenses) charts.licenses.destroy();

    // Sales Trend Chart (Line)
    const salesCtx = document.getElementById('salesChart').getContext('2d');
    charts.sales = new Chart(salesCtx, {
      type: 'line',
      data: {
        labels: data.salesTrend.map(d => d.date),
        datasets: [{
          label: 'Günlük Ciro (TRY)',
          data: data.salesTrend.map(d => d.amount),
          borderColor: '#00f0ff',
          backgroundColor: 'rgba(0, 240, 255, 0.1)',
          fill: true,
          tension: 0.3,
          borderWidth: 2
        }]
      },
      options: {
        responsive: true,
        plugins: { legend: { display: false } },
        scales: {
          x: { grid: { color: 'rgba(255, 255, 255, 0.05)' } },
          y: { grid: { color: 'rgba(255, 255, 255, 0.05)' } }
        }
      }
    });

    // License Distribution Chart (Doughnut)
    const licCtx = document.getElementById('licenseDistChart').getContext('2d');
    const distData = data.licenseDistribution || [];
    charts.licenses = new Chart(licCtx, {
      type: 'doughnut',
      data: {
        labels: distData.map(d => d.tier.toUpperCase()),
        datasets: [{
          data: distData.map(d => parseInt(d.count, 10)),
          backgroundColor: ['#00f0ff', '#bd00ff', '#00ff66', '#ffaa00'],
          borderWidth: 0
        }]
      },
      options: {
        responsive: true,
        plugins: { legend: { position: 'bottom', labels: { color: '#f3f4f6' } } }
      }
    });
  } catch (err) {
    console.error('Failed to load dashboard charts:', err);
  }
}

// LOAD COMPANIES
async function loadCompanies() {
  try {
    const res = await adminFetch('/admin/companies');
    const companies = await res.json();
    const tbody = document.getElementById('company-table-body');
    tbody.innerHTML = '';

    if (companies.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center">Kayıtlı şirket bulunamadı.</td></tr>';
      return;
    }

    companies.forEach(comp => {
      const expiry = comp.license_expires_at 
        ? new Date(comp.license_expires_at).toLocaleDateString('tr-TR')
        : 'Yok';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${comp.id}</strong></td>
        <td>${comp.name}</td>
        <td>${comp.tax_number} / ${comp.tax_office || '-'}</td>
        <td>${comp.phone || '-'} <br> <span style="font-size:0.8rem;color:var(--text-secondary);">${comp.email || '-'}</span></td>
        <td>${comp.store_count} Mağaza</td>
        <td>${comp.device_count} Terminal</td>
        <td><span class="badge badge-${comp.status}">${comp.status}</span></td>
        <td>
          <button class="btn-secondary" onclick="viewCompanyDetails('${comp.id}')" title="Şirketin adres, vergi dairesi, şube, cihaz ve lisans detaylarını gösterir.">Detay</button>
          <button class="btn-secondary text-red" onclick="toggleCompanyStatus('${comp.id}', '${comp.status}')" title="${comp.status === 'active' ? 'Şirketi askıya alır: Kullanıcı girişini, senkronizasyonu ve cihaz satış yetkisini dondurur.' : 'Şirketi aktifleştirir: Giriş ve satış yetkilerini normale döndürür.'}">
            ${comp.status === 'active' ? 'Askıya Al' : 'Aktifleştir'}
          </button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// VIEW COMPANY DETAILS (MOCK MODAL OR VIEWER)
window.viewCompanyDetails = async function(id) {
  try {
    const res = await adminFetch(`/admin/companies/${id}`);
    const details = await res.json();

    const formatted = `
🏢 FİRMA BİLGİLERİ:
  ID: ${details.company.id}
  Ünvan: ${details.company.name}
  Vergi No / Daire: ${details.company.tax_number} / ${details.company.tax_office || '-'}
  Durum: ${details.company.status}
  Kayıt Tarihi: ${new Date(details.company.created_at).toLocaleString('tr-TR')}

🏢 MAĞAZALAR (${details.stores.length}):
${details.stores.map(s => `  - [${s.id}] ${s.name} (${s.address || 'Adres belirtilmemiş'})`).join('\n')}

📱 CİHAZLAR (${details.devices.length}):
${details.devices.map(d => `  - [${d.id}] ${d.name} (${d.status}) - Son Aktiflik: ${d.last_active_at ? new Date(d.last_active_at).toLocaleString('tr-TR') : 'Hiç'}`).join('\n')}

🔑 LİSANSLAR (${details.licenses.length}):
${details.licenses.map(l => `  - ${l.license_key} [${l.tier.toUpperCase()}] status: ${l.status} - Bitiş: ${new Date(l.expires_at).toLocaleDateString('tr-TR')}`).join('\n')}

👥 KULLANICILAR (${details.users.length}):
${details.users.map(u => `  - ${u.name} (${u.email}) - is_active: ${u.is_active}`).join('\n')}

🧾 FATURALAR (${details.invoices.length}):
${details.invoices.map(i => `  - Fatura No: ${i.id} - Tutar: ${i.amount} TRY - Durum: ${i.status}`).join('\n')}
    `;

    openTextViewer('Şirket Entegrasyon Detayları', formatted);
  } catch (err) {
    alert('Şirket detayları yüklenemedi.');
  }
};

window.toggleCompanyStatus = async function(id, currentStatus) {
  const nextStatus = currentStatus === 'active' ? 'suspended' : 'active';
  const confirmMsg = nextStatus === 'suspended'
    ? `⚠️ DİKKAT: [${id}] ID'li şirketi askıya almak üzeresiniz!\n\nBu işlem:\n- Şirket altındaki tüm kullanıcıların girişini engeller.\n- Canlı veri senkronizasyonunu (WebSocket) durdurur.\n- Terminallerde (POS) lisans hatası vererek satışı bloke eder.\n\nAskıya almak istediğinize emin misiniz?`
    : `Şirketi aktifleştirmek üzeresiniz.\n\nBu işlem:\n- Kullanıcıların sisteme tekrar giriş yapmasına izin verir.\n- Cihazların satış ve senkronizasyon yetkisini açar.\n\nAktifleştirmek istediğinize emin misiniz?`;
  if (!confirm(confirmMsg)) return;

  try {
    await adminFetch(`/admin/companies/${id}`, {
      method: 'PUT',
      body: JSON.stringify({ status: nextStatus })
    });
    loadCompanies();
  } catch (_) {}
};

// LOAD LICENSES
async function loadLicenses() {
  try {
    const res = await adminFetch('/admin/licenses');
    const licenses = await res.json();
    const tbody = document.getElementById('license-table-body');
    tbody.innerHTML = '';

    if (licenses.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center">Lisans kaydı bulunamadı.</td></tr>';
      return;
    }

    licenses.forEach(l => {
      const expires = new Date(l.expires_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${l.license_key}</strong></td>
        <td>${l.company_name}</td>
        <td><span class="badge badge-${l.tier}">${l.tier}</span></td>
        <td>${l.allowed_devices_count} Cihaz</td>
        <td>${expires}</td>
        <td><span class="badge badge-${l.status}">${l.status}</span></td>
        <td>
          <button class="btn-secondary text-green" onclick="renewLicense('${l.id}')" title="Lisansın geçerlilik süresini +365 gün (1 yıl) uzatır.">Yenile (+1 Yıl)</button>
          <button class="btn-secondary" onclick="toggleLicenseStatus('${l.id}', '${l.status}')" title="${l.status === 'active' ? 'Lisansı askıya alır: Tanımlı cihazın satış ve senkronizasyonunu geçici olarak dondurur.' : 'Lisansı etkinleştirir: Tanımlı cihazın satış yetkisini açar.'}">
            ${l.status === 'active' ? 'Askıya Al' : 'Etkinleştir'}
          </button>
          <button class="btn-secondary" onclick="triggerOfflineActivation('${l.id}', '${l.license_key}')" style="background:#10B981;color:white;border:none;" title="İnterneti olmayan POS cihazlarını yerinde (offline) aktifleştirmek için aktivasyon QR kodunu açar.">Offline QR</button>
          <button class="btn-secondary text-red" onclick="revokeLicense('${l.id}')" title="Lisans anahtarını kalıcı olarak iptal eder. Bu işlem geri alınamaz ve cihazın bulutla olan bağlantısı kesilir!">İptal Et</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (err) {
    console.error(err);
    const tbody = document.getElementById('license-table-body');
    if (tbody) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Lisanslar yüklenirken bir hata oluştu.</td></tr>';
    }
  }
}

window.renewLicense = async function(id) {
  if (!confirm('Bu lisansın geçerlilik süresini +365 gün (1 yıl) uzatmak istediğinize emin misiniz?')) return;
  try {
    const res = await adminFetch(`/admin/licenses/${id}/renew`, {
      method: 'POST',
      body: JSON.stringify({ additional_days: 365 })
    });
    if (res.ok) {
      alert('Lisans başarıyla 365 gün uzatıldı.');
      loadLicenses();
    } else {
      const err = await res.json();
      alert(err.message || 'Lisans yenilenirken bir hata oluştu.');
    }
  } catch (err) {
    console.error(err);
    alert('Bağlantı hatası oluştu.');
  }
};

window.toggleLicenseStatus = async function(id, currentStatus) {
  const suspend = currentStatus === 'active';
  const confirmMsg = suspend
    ? `⚠️ UYARI: Bu lisansı askıya almak üzeresiniz!\n\nBu işlem, bu lisans anahtarını kullanan POS cihazının satış yapmasını ve senkronizasyon kurmasını dondurur.\n\nLisansı askıya almak istediğinize emin misiniz?`
    : `Lisansı etkinleştirmek üzeresiniz.\n\nBu işlem, ilgili POS terminalinin satış yapmasına ve senkronizasyon kurmasına yeniden izin verir.\n\nLisansı etkinleştirmek istediğinize emin misiniz?`;
  if (!confirm(confirmMsg)) return;

  try {
    const res = await adminFetch(`/admin/licenses/${id}/suspend`, {
      method: 'POST',
      body: JSON.stringify({ suspend })
    });
    if (res.ok) {
      alert(`Lisans başarıyla ${suspend ? 'askıya alındı' : 'aktif edildi'}.`);
      loadLicenses();
    } else {
      const err = await res.json();
      alert(err.message || 'İşlem gerçekleştirilemedi.');
    }
  } catch (err) {
    console.error(err);
    alert('Bağlantı hatası oluştu.');
  }
};

window.revokeLicense = async function(id) {
  if (!confirm('🚨 KRİTİK UYARI: Bu lisansı kalıcı olarak İPTAL (revoke) etmek istediğinize emin misiniz?\n\n- Bu işlem GERİ ALINAMAZ.\n- Lisans anahtarı tamamen geçersiz kılınır.\n- Bu lisansı kullanan cihazın sistemle olan bağlantısı kalıcı olarak koparılır.\n\nDevam etmek istediğinize emin misiniz?')) return;
  try {
    const res = await adminFetch(`/admin/licenses/${id}/revoke`, { method: 'POST' });
    if (res.ok) {
      alert('Lisans başarıyla kalıcı olarak iptal edildi.');
      loadLicenses();
    } else {
      const err = await res.json();
      alert(err.message || 'İşlem gerçekleştirilemedi.');
    }
  } catch (err) {
    console.error(err);
    alert('Bağlantı hatası oluştu.');
  }
};

// LOAD DEVICES
async function loadDevices() {
  try {
    const res = await adminFetch('/admin/devices');
    const devices = await res.json();
    const tbody = document.getElementById('device-table-body');
    tbody.innerHTML = '';

    if (devices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center">Kayıtlı POS cihazı bulunamadı.</td></tr>';
      return;
    }

    devices.forEach(d => {
      const activeTime = d.last_active_at 
        ? new Date(d.last_active_at).toLocaleString('tr-TR')
        : 'Yok';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${d.id}</strong></td>
        <td>${d.company_name}</td>
        <td>${d.store_name || '-'}</td>
        <td><span style="font-family:monospace;font-size:0.8rem;">${d.device_hash.substring(0, 16)}...</span></td>
        <td><span class="badge badge-${d.status}">${d.status}</span></td>
        <td>${activeTime}</td>
        <td><span class="indicator ${d.is_online ? 'online' : 'offline'}">${d.is_online ? 'Çevrimiçi' : 'Çevrimdışı'}</span></td>
        <td>
          <button class="btn-secondary" onclick="openDeviceSwapModal('${d.company_id}', '${d.id}', '${d.name || 'Terminal'}')" style="background:#8B5CF6;color:white;border:none;">Değiştir</button>
          <button class="btn-secondary text-red" onclick="toggleDeviceStatus('${d.id}')">
            ${d.status === 'active' ? 'Engelle' : 'Etkinleştir'}
          </button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.toggleDeviceStatus = async function(id) {
  try {
    await adminFetch(`/admin/devices/${id}/toggle`, { method: 'POST' });
    loadDevices();
  } catch (_) {}
};

// LOAD UPDATES
async function loadUpdates() {
  try {
    const res = await adminFetch('/admin/updates');
    const updates = await res.json();
    const tbody = document.getElementById('updates-table-body');
    tbody.innerHTML = '';

    if (updates.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center">Yayınlanmış güncelleme paketi bulunamadı.</td></tr>';
      return;
    }

    updates.forEach(u => {
      const created = new Date(u.created_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${u.version_code}</strong></td>
        <td>${u.platform.toUpperCase()}</td>
        <td><a href="${u.download_url}" target="_blank" style="color:var(--neon-cyan);">Dosyayı İndir</a></td>
        <td><span style="font-family:monospace;font-size:0.8rem;">${u.sha256_hash.substring(0, 16)}...</span></td>
        <td>${u.is_mandatory ? 'Zorunlu' : 'İsteğe Bağlı'}</td>
        <td>${created}</td>
        <td>
          <button class="btn-secondary text-red" onclick="deleteUpdate('${u.id}')">Sil</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.deleteUpdate = async function(id) {
  if (!confirm('Bu güncelleme sürümünü kaldırmak istediğinize emin misiniz?')) return;
  try {
    await adminFetch(`/admin/updates/${id}`, { method: 'DELETE' });
    loadUpdates();
  } catch (_) {}
};

// LOAD SYNC MONITOR
async function loadSyncMonitor() {
  try {
    const res = await adminFetch('/admin/sync/monitor');
    const data = await res.json();

    document.getElementById('sync-pending').innerText = data.summary.pending;
    document.getElementById('sync-failed').innerText = data.summary.failed;
    document.getElementById('sync-completed').innerText = data.summary.completed;

    const tbody = document.getElementById('sync-table-body');
    tbody.innerHTML = '';

    if (data.failed_jobs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Bekleyen hata kaydı bulunamadı.</td></tr>';
      return;
    }

    data.failed_jobs.forEach(job => {
      const created = new Date(job.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${job.company_name}</td>
        <td>${job.device_name}</td>
        <td><strong>${job.entity_type}</strong></td>
        <td>${job.entity_id}</td>
        <td class="text-red">${job.error_message || 'Bilinmeyen Hata'}</td>
        <td>${created}</td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// LOAD TICKETS
async function loadTickets() {
  try {
    const res = await adminFetch('/admin/tickets');
    const tickets = await res.json();
    const tbody = document.getElementById('tickets-table-body');
    tbody.innerHTML = '';

    if (tickets.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center">Destek talebi bulunamadı.</td></tr>';
      return;
    }

    tickets.forEach(t => {
      const created = new Date(t.created_at).toLocaleDateString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${t.id}</strong></td>
        <td>${t.company_name}</td>
        <td>${t.title}</td>
        <td><span class="badge border-amber">${t.priority}</span></td>
        <td><span class="badge badge-${t.status}">${t.status}</span></td>
        <td>${created}</td>
        <td>
          <button class="btn-secondary" onclick="openSupportChat('${t.id}', '${t.title}', '${t.status}')">Yanıtla / Detay</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.openSupportChat = async function(id, title, status) {
  selectedTicketId = id;
  document.getElementById('ticket-title').innerText = `Destek Talebi: ${title}`;
  const badge = document.getElementById('ticket-status-badge');
  badge.innerText = status;
  badge.className = `status-badge badge-${status}`;

  await loadTicketMessages(id);
  document.getElementById('modal-ticket').classList.add('active');
};

async function loadTicketMessages(ticketId) {
  const container = document.getElementById('ticket-chat-messages');
  container.innerHTML = '';
  try {
    const res = await adminFetch(`/admin/tickets/${ticketId}/messages`);
    const messages = await res.json();

    messages.forEach(msg => {
      const isSystemAdmin = msg.sender_name === 'Serenut Destek';
      const div = document.createElement('div');
      div.className = `chat-msg ${isSystemAdmin ? 'chat-msg-admin' : 'chat-msg-user'}`;
      div.innerHTML = `
        <strong>${msg.sender_name}</strong>
        <p>${msg.message}</p>
        <span class="chat-msg-time">${new Date(msg.created_at).toLocaleTimeString('tr-TR', {hour: '2-digit', minute:'2-digit'})}</span>
      `;
      container.appendChild(div);
    });

    // Scroll to bottom
    container.scrollTop = container.scrollHeight;
  } catch (_) {}
}

document.getElementById('btn-ticket-send').addEventListener('click', async () => {
  const textInput = document.getElementById('ticket-reply-text');
  const message = textInput.value;
  if (!message || !selectedTicketId) return;

  try {
    const res = await adminFetch(`/admin/tickets/${selectedTicketId}/reply`, {
      method: 'POST',
      body: JSON.stringify({ message })
    });
    if (res.ok) {
      textInput.value = '';
      loadTicketMessages(selectedTicketId);
      loadTickets(); // Refresh table view status
    }
  } catch (_) {}
});

// LOAD CRASH LOGS
async function loadCrashLogs() {
  try {
    const res = await adminFetch('/admin/crash-logs');
    const logs = await res.json();
    const tbody = document.getElementById('crash-table-body');
    tbody.innerHTML = '';

    if (logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Crash raporu bulunamadı.</td></tr>';
      return;
    }

    logs.forEach(l => {
      const created = new Date(l.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${created}</td>
        <td>${l.company_name}</td>
        <td>${l.device_name || '-'}</td>
        <td class="text-red"><strong>${l.error_message.substring(0, 60)}...</strong></td>
        <td>${l.app_version || '1.0.0'}</td>
        <td>
          <button class="btn-secondary" onclick="viewCrashStackTrace('${l.id}')">Stack Trace</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.viewCrashStackTrace = async function(id) {
  try {
    const res = await adminFetch('/admin/crash-logs');
    const logs = await res.json();
    const record = logs.find(l => l.id === id);
    if (record) {
      openTextViewer('Crash Stack Trace İncelemesi', record.stack_trace || 'Stack trace bilgisi bulunamadı.');
    }
  } catch (_) {}
};

// LOAD AUDIT LOGS
async function loadAuditLogs() {
  try {
    const res = await adminFetch('/admin/audit-logs');
    const logs = await res.json();
    const tbody = document.getElementById('audit-table-body');
    tbody.innerHTML = '';

    if (logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Audit log kaydı bulunamadı.</td></tr>';
      return;
    }

    logs.forEach(l => {
      const created = new Date(l.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${created}</td>
        <td><strong>${l.user_name || 'Sistem'}</strong></td>
        <td>${l.action}</td>
        <td>${l.entity || '-'}</td>
        <td>${l.entity_id || '-'}</td>
        <td><span style="font-family:monospace;font-size:0.8rem;">${l.ip_address}</span></td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// LOAD SMS LOGS
async function loadSmsLogs() {
  try {
    const res = await adminFetch('/admin/sms/stats');
    const data = await res.json();

    document.getElementById('sms-sent').innerText = data.summary.sent;
    document.getElementById('sms-failed').innerText = data.summary.failed;
    document.getElementById('sms-quota').innerText = `${data.summary.dailyQuotaUsed} / ${data.summary.maxDailyQuota}`;

    const tbody = document.getElementById('sms-table-body');
    tbody.innerHTML = '';

    if (data.logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center">SMS gönderim kaydı bulunamadı.</td></tr>';
      return;
    }

    data.logs.forEach(l => {
      const created = new Date(l.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${created}</td>
        <td>${l.company_name}</td>
        <td>${l.phone}</td>
        <td>${l.message}</td>
        <td><span class="badge badge-${l.status}">${l.status}</span></td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

// ── 5. MODAL CONTROL LOGIC ───────────────────────────────────────────────────
function setupModalListeners() {
  // Modal toggle handlers
  const modals = {
    company: {
      open: 'btn-create-company',
      close: 'btn-comp-cancel',
      overlay: 'modal-company',
      submit: 'btn-comp-submit',
      action: submitCreateCompany
    },
    license: {
      open: 'btn-create-license',
      close: 'btn-lic-cancel',
      overlay: 'modal-license',
      submit: 'btn-lic-submit',
      action: submitCreateLicense,
      preOpen: loadCompanySelectOptions
    },
    update: {
      open: 'btn-create-update',
      close: 'btn-up-cancel',
      overlay: 'modal-update',
      submit: 'btn-up-submit',
      action: submitCreateUpdate
    }
  };

  // Bind Open/Close button clicks
  Object.keys(modals).forEach(key => {
    const m = modals[key];
    const openBtn = document.getElementById(m.open);
    const closeBtn = document.getElementById(m.close);
    const overlay = document.getElementById(m.overlay);
    const submitBtn = document.getElementById(m.submit);

    if (openBtn) {
      openBtn.addEventListener('click', async () => {
        if (m.preOpen) await m.preOpen();
        overlay.classList.add('active');
      });
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

  // Ticket chat close
  document.getElementById('btn-ticket-close').addEventListener('click', () => {
    document.getElementById('modal-ticket').classList.remove('active');
    selectedTicketId = null;
  });

  // General Text Viewer close
  document.getElementById('btn-viewer-close').addEventListener('click', () => {
    document.getElementById('modal-viewer').classList.remove('active');
  });
}

// SUBMIT CREATE COMPANY
async function submitCreateCompany() {
  const name = document.getElementById('comp-name').value;
  const tax_number = document.getElementById('comp-tax').value;
  const tax_office = document.getElementById('comp-tax-office').value;
  const phone = document.getElementById('comp-phone').value;
  const email = document.getElementById('comp-email').value;
  const address = document.getElementById('comp-address').value;

  if (!name || !tax_number) {
    alert('Şirket adı ve vergi numarası zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/companies', {
      method: 'POST',
      body: JSON.stringify({ name, tax_number, tax_office, phone, email, address })
    });
    
    if (!res.ok) {
      const err = await res.json();
      alert(err.message || 'Firma kaydı başarısız oldu.');
      return false;
    }

    const payload = await res.json();
    alert(`Firma başarıyla oluşturuldu!\nİlk POS Deneme Lisans Anahtarı: ${payload.license_key}`);
    loadCompanies();
    return true;
  } catch (_) {
    return false;
  }
}

// LOAD COMPANIES FOR LICENSE SELECTION OPTIONS
async function loadCompanySelectOptions() {
  const select = document.getElementById('lic-comp-select');
  select.innerHTML = '<option value="">Şirket Yükleniyor...</option>';
  try {
    const res = await adminFetch('/admin/companies');
    const companies = await res.json();
    select.innerHTML = companies.map(c => `<option value="${c.id}">${c.name}</option>`).join('');
  } catch (_) {
    select.innerHTML = '<option value="">Hata oluştu.</option>';
  }
}

// SUBMIT CREATE LICENSE
async function submitCreateLicense() {
  const company_id = document.getElementById('lic-comp-select').value;
  const tier = document.getElementById('lic-tier').value;
  const allowed_devices_count = document.getElementById('lic-device-limit').value;
  const expires_in_days = document.getElementById('lic-days').value;

  if (!company_id || !tier) {
    alert('Şirket ve paket seviyesi seçilmesi zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/licenses', {
      method: 'POST',
      body: JSON.stringify({ company_id, tier, allowed_devices_count, expires_in_days })
    });

    if (res.ok) {
      alert('Lisans anahtarı başarıyla üretildi.');
      loadLicenses();
      return true;
    } else {
      const err = await res.json();
      alert(err.message || 'Lisans anahtarı üretilemedi.');
      return false;
    }
  } catch (err) {
    console.error(err);
    alert('Lisans üretilirken bağlantı hatası oluştu.');
    return false;
  }
}

// SUBMIT CREATE UPDATE RELEASE
async function submitCreateUpdate() {
  const version_code = document.getElementById('up-code').value;
  const platform = document.getElementById('up-platform').value;
  const download_url = document.getElementById('up-url').value;
  const sha256_hash = document.getElementById('up-hash').value;
  const is_mandatory = document.getElementById('up-mandatory').checked;
  const release_notes = document.getElementById('up-notes').value;

  if (!version_code || !download_url || !sha256_hash) {
    alert('Lütfen zorunlu tüm alanları doldurun.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/updates', {
      method: 'POST',
      body: JSON.stringify({ version_code, platform, download_url, sha256_hash, is_mandatory, release_notes })
    });

    if (res.ok) {
      alert('Yeni OTA sürüm paketi başarıyla yayınlandı.');
      loadUpdates();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// ── 9. SUBSCRIPTIONS & COMMERCIALS tab ───────────────────────────────────────
async function loadSubscriptions() {
  try {
    const res = await adminFetch('/admin/billing/intel');
    const intel = await res.json();

    document.getElementById('mrr-val').innerText = `${intel.stats.mrr} TRY`;
    document.getElementById('arr-val').innerText = `${intel.stats.arr} TRY`;
    document.getElementById('churn-val').innerText = `% ${intel.stats.churn_rate}`;
    document.getElementById('risk-val').innerText = intel.at_risk_list.length;

    const tbody = document.getElementById('risk-table-body');
    tbody.innerHTML = '';

    if (intel.at_risk_list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center">Ödeme riski bulunan şirket bulunamadı.</td></tr>';
      return;
    }

    intel.at_risk_list.forEach(c => {
      const graceEnd = c.license_expires_at 
        ? new Date(c.license_expires_at).toLocaleDateString('tr-TR')
        : 'Yok';
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${c.id}</strong></td>
        <td>${c.name}</td>
        <td>${c.email || '-'}</td>
        <td><span class="badge badge-suspended">${c.status}</span></td>
        <td>${graceEnd}</td>
        <td>${c.unpaid_invoice_count || 1} Adet</td>
        <td class="text-red">${c.debt_amount || 0} TRY</td>
      `;
      tbody.appendChild(tr);
    });
  } catch (err) {
    console.error('Failed to load subscriptions:', err);
  }
}

// ── 10. INCIDENTS tab ────────────────────────────────────────────────────────
async function loadIncidents() {
  try {
    const res = await adminFetch('/admin/incidents');
    const incidents = await res.json();
    const tbody = document.getElementById('incidents-table-body');
    tbody.innerHTML = '';

    if (incidents.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center">Kayıtlı sistem olayı bulunmuyor.</td></tr>';
      return;
    }

    incidents.forEach(inc => {
      const date = new Date(inc.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${inc.id.substring(0, 8)}...</strong></td>
        <td>${inc.company_name || 'Genel (Platform)'}</td>
        <td><span class="badge border-amber">${inc.severity}</span></td>
        <td><strong>${inc.title}</strong></td>
        <td>${inc.description || '-'}</td>
        <td><span class="badge badge-${inc.status}">${inc.status}</span></td>
        <td>${date}</td>
        <td>
          ${inc.status === 'open' ? `<button class="btn-secondary" onclick="assignIncident('${inc.id}')">Üstlen</button>` : ''}
          ${inc.status !== 'resolved' ? `<button class="btn-secondary text-green" onclick="resolveIncident('${inc.id}')">Çözüldü</button>` : '✓ Çözüldü'}
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.assignIncident = async function(id) {
  try {
    const res = await adminFetch(`/admin/incidents/${id}/assign`, { method: 'POST' });
    if (res.ok) {
      alert('Incident üzerinize atandı.');
      loadIncidents();
    }
  } catch (_) {}
};

window.resolveIncident = async function(id) {
  const notes = prompt('Çözüm açıklaması yazın:');
  if (notes === null) return;
  try {
    const res = await adminFetch(`/admin/incidents/${id}/resolve`, {
      method: 'POST',
      body: JSON.stringify({ resolution_notes: notes })
    });
    if (res.ok) {
      alert('Incident çözüldü olarak işaretlendi.');
      loadIncidents();
    }
  } catch (_) {}
};

async function submitCreateIncident() {
  const company_id = document.getElementById('inc-comp-select').value;
  const severity = document.getElementById('inc-severity').value;
  const title = document.getElementById('inc-title').value;
  const description = document.getElementById('inc-desc').value;

  if (!title || !description) {
    alert('Başlık ve açıklama girilmesi zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/incidents', {
      method: 'POST',
      body: JSON.stringify({ company_id: company_id || null, severity, title, description })
    });
    if (res.ok) {
      alert('Sistem olayı (incident) başarıyla kaydedildi.');
      loadIncidents();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// ── 11. SECURITY tab ─────────────────────────────────────────────────────────
async function loadSecurity() {
  try {
    const res = await adminFetch('/admin/security/blacklist');
    const blacklist = await res.json();
    const tbody = document.getElementById('blacklist-table-body');
    tbody.innerHTML = '';

    if (blacklist.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center">Yasaklı IP adresi bulunmuyor.</td></tr>';
      return;
    }

    blacklist.forEach(b => {
      const date = new Date(b.created_at).toLocaleString('tr-TR');
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${b.ip_address}</strong></td>
        <td>${b.reason || '-'}</td>
        <td>${b.banned_by_name || 'System'}</td>
        <td>${date}</td>
        <td>
          <button class="btn-secondary text-green" onclick="unbanIp('${b.ip_address}')">Engeli Kaldır</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (_) {}
}

window.unbanIp = async function(ip) {
  if (!confirm(`${ip} adresinin engelini kaldırmak istediğinize emin misiniz?`)) return;
  try {
    const res = await adminFetch(`/admin/security/ban-ip/${ip}`, { method: 'DELETE' });
    if (res.ok) {
      alert('IP engeli kaldırıldı.');
      loadSecurity();
    }
  } catch (_) {}
};

async function submitBanIp() {
  const ip = document.getElementById('ban-ip-val').value;
  const reason = document.getElementById('ban-reason').value;

  if (!ip || !reason) {
    alert('IP adresi ve yasaklama gerekçesi zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/security/ban-ip', {
      method: 'POST',
      body: JSON.stringify({ ip, reason })
    });
    if (res.ok) {
      alert('IP başarıyla kara listeye eklendi.');
      loadSecurity();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

// ── 12. DEVICE SWAP & BULK LICENSE & OFFLINE QR ──────────────────────────────
window.openDeviceSwapModal = function(companyId, oldDeviceId, oldDeviceName) {
  document.getElementById('swap-company-id').value = companyId;
  document.getElementById('swap-old-device-id').value = oldDeviceId;
  document.getElementById('swap-old-device-name').value = oldDeviceName;
  document.getElementById('modal-device-swap').classList.add('active');
};

async function submitDeviceSwap() {
  const company_id = document.getElementById('swap-company-id').value;
  const old_device_id = document.getElementById('swap-old-device-id').value;
  const new_device_name = document.getElementById('swap-new-device-name').value;
  const new_device_hash = document.getElementById('swap-new-device-hash').value;

  if (!new_device_name || !new_device_hash) {
    alert('Yeni cihaz adı ve donanım hash kodu zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/devices/swap', {
      method: 'POST',
      body: JSON.stringify({ company_id, old_device_id, new_device_name, new_device_hash })
    });
    if (res.ok) {
      alert('Cihaz donanım eşleşmesi başarıyla güncellendi.');
      loadDevices();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

async function loadBulkCompanySelectOptions() {
  const select = document.getElementById('bulk-lic-comp-select');
  select.innerHTML = '<option value="">Şirket Yükleniyor...</option>';
  try {
    const res = await adminFetch('/admin/companies');
    const companies = await res.json();
    select.innerHTML = companies.map(c => `<option value="${c.id}">${c.name}</option>`).join('');
  } catch (_) {
    select.innerHTML = '<option value="">Hata oluştu.</option>';
  }
}

async function submitCreateBulkLicenses() {
  const company_id = document.getElementById('bulk-lic-comp-select').value;
  const tier = document.getElementById('bulk-lic-tier').value;
  const allowed_devices_count = document.getElementById('bulk-lic-device-limit').value;
  const expires_in_days = document.getElementById('bulk-lic-days').value;
  const count = document.getElementById('bulk-lic-count').value;

  if (!company_id || !count) {
    alert('Şirket ve adet seçilmesi zorunludur.');
    return false;
  }

  try {
    const res = await adminFetch('/admin/licenses/bulk', {
      method: 'POST',
      body: JSON.stringify({ company_id, tier, allowed_devices_count, expires_in_days, count })
    });

    if (res.ok) {
      const data = await res.json();
      alert(`${data.license_keys.length} adet lisans başarıyla oluşturuldu.`);
      loadLicenses();
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

window.triggerOfflineActivation = async function(licenseId, licenseKey) {
  const deviceHash = prompt('Aktivasyon yapılacak POS cihazının hardware hash kodunu (UUID) girin:');
  if (!deviceHash) return;

  try {
    const res = await adminFetch(`/admin/licenses/${licenseId}/offline-activation`, {
      method: 'POST',
      body: JSON.stringify({ device_hash: deviceHash })
    });

    if (!res.ok) {
      const err = await res.json();
      alert(err.message || 'Offline aktivasyon üretilemedi.');
      return;
    }

    const data = await res.json();
    document.getElementById('offline-token-text').value = data.activationToken;
    document.getElementById('qr-placeholder-graphics').innerText = `OFFLINE:\n${licenseKey.substring(0, 8)}...`;
    document.getElementById('modal-offline-activation').classList.add('active');
  } catch (_) {
    alert('İşlem sırasında bir hata oluştu.');
  }
};

// ── 13. TICKET INTERNAL NOTES & EXTRA TRIGGERS ───────────────────────────────
async function loadTicketInternalNotes(ticketId) {
  const container = document.getElementById('ticket-internal-notes-list');
  container.innerHTML = 'Yükleniyor...';
  try {
    const res = await adminFetch(`/admin/tickets/${ticketId}/notes`);
    const notes = await res.json();
    container.innerHTML = '';

    if (notes.length === 0) {
      container.innerHTML = '<div style="color: #94A3B8; text-align: center;">Kayıtlı iç not bulunmuyor.</div>';
      return;
    }

    notes.forEach(n => {
      const date = new Date(n.created_at).toLocaleString('tr-TR', {hour: '2-digit', minute:'2-digit'});
      const div = document.createElement('div');
      div.style.background = '#1E293B';
      div.style.padding = '8px';
      div.style.borderRadius = '4px';
      div.style.color = '#E2E8F0';
      div.innerHTML = `
        <div style="display: flex; justify-content: space-between; font-weight: bold; margin-bottom: 4px; color: #38BDF8;">
          <span>${n.author_name}</span>
          <span style="font-size: 0.75rem; color: #64748B;">${date}</span>
        </div>
        <p style="margin: 0;">${n.note}</p>
      `;
      container.appendChild(div);
    });
    container.scrollTop = container.scrollHeight;
  } catch (_) {
    container.innerHTML = 'İç notlar yüklenemedi.';
  }
}

// Intercept window.openSupportChat to load internal notes as well
const originalOpenSupportChat = window.openSupportChat;
window.openSupportChat = async function(id, title, status) {
  await originalOpenSupportChat(id, title, status);
  loadTicketInternalNotes(id);
};

// Bind additional modals and event handlers
document.addEventListener('DOMContentLoaded', () => {
  // Bind Bulk trigger
  const bulkTrigger = document.getElementById('btn-bulk-license-trigger');
  if (bulkTrigger) {
    bulkTrigger.addEventListener('click', async () => {
      await loadBulkCompanySelectOptions();
      document.getElementById('modal-bulk-license').classList.add('active');
    });
  }

  // Bind Bulk submits
  const btnBulkLicCancel = document.getElementById('btn-bulk-lic-cancel');
  if (btnBulkLicCancel) {
    btnBulkLicCancel.addEventListener('click', () => {
      document.getElementById('modal-bulk-license').classList.remove('active');
    });
  }
  const btnBulkLicSubmit = document.getElementById('btn-bulk-lic-submit');
  if (btnBulkLicSubmit) {
    btnBulkLicSubmit.addEventListener('click', async () => {
      const success = await submitCreateBulkLicenses();
      if (success) document.getElementById('modal-bulk-license').classList.remove('active');
    });
  }

  // Bind Device Swap submits
  const btnSwapCancel = document.getElementById('btn-swap-cancel');
  if (btnSwapCancel) {
    btnSwapCancel.addEventListener('click', () => {
      document.getElementById('modal-device-swap').classList.remove('active');
    });
  }
  const btnSwapSubmit = document.getElementById('btn-swap-submit');
  if (btnSwapSubmit) {
    btnSwapSubmit.addEventListener('click', async () => {
      const success = await submitDeviceSwap();
      if (success) document.getElementById('modal-device-swap').classList.remove('active');
    });
  }

  // Bind Offline QR close
  const btnOfflineClose = document.getElementById('btn-offline-close');
  if (btnOfflineClose) {
    btnOfflineClose.addEventListener('click', () => {
      document.getElementById('modal-offline-activation').classList.remove('active');
    });
  }

  // Bind Incident submits
  const btnCreateIncident = document.getElementById('btn-create-incident');
  if (btnCreateIncident) {
    btnCreateIncident.addEventListener('click', async () => {
      // Load companies
      const select = document.getElementById('inc-comp-select');
      select.innerHTML = '<option value="">Genel (Tüm Platform)</option>';
      try {
        const res = await adminFetch('/admin/companies');
        const companies = await res.json();
        companies.forEach(c => {
          select.innerHTML += `<option value="${c.id}">${c.name}</option>`;
        });
      } catch (_) {}
      document.getElementById('modal-incident').classList.add('active');
    });
  }
  const btnIncCancel = document.getElementById('btn-inc-cancel');
  if (btnIncCancel) {
    btnIncCancel.addEventListener('click', () => {
      document.getElementById('modal-incident').classList.remove('active');
    });
  }
  const btnIncSubmit = document.getElementById('btn-inc-submit');
  if (btnIncSubmit) {
    btnIncSubmit.addEventListener('click', async () => {
      const success = await submitCreateIncident();
      if (success) document.getElementById('modal-incident').classList.remove('active');
    });
  }

  // Bind Security IP ban submits
  const btnBanIp = document.getElementById('btn-ban-ip');
  if (btnBanIp) {
    btnBanIp.addEventListener('click', () => {
      document.getElementById('modal-ban-ip').classList.add('active');
    });
  }
  const btnBanCancel = document.getElementById('btn-ban-cancel');
  if (btnBanCancel) {
    btnBanCancel.addEventListener('click', () => {
      document.getElementById('modal-ban-ip').classList.remove('active');
    });
  }
  const btnBanSubmit = document.getElementById('btn-ban-submit');
  if (btnBanSubmit) {
    btnBanSubmit.addEventListener('click', async () => {
      const success = await submitBanIp();
      if (success) document.getElementById('modal-ban-ip').classList.remove('active');
    });
  }

  // Bind Add Support internal note
  const btnAddNote = document.getElementById('btn-ticket-add-note');
  if (btnAddNote) {
    btnAddNote.addEventListener('click', async () => {
      const input = document.getElementById('ticket-internal-note-input');
      const note = input.value;
      if (!note || !selectedTicketId) return;

      try {
        const res = await adminFetch(`/admin/tickets/${selectedTicketId}/notes`, {
          method: 'POST',
          body: JSON.stringify({ note })
        });
        if (res.ok) {
          input.value = '';
          loadTicketInternalNotes(selectedTicketId);
        }
      } catch (_) {}
    });
  }

  // Bind Plan Editor Modal buttons
  const btnPlanCancel = document.getElementById('btn-plan-cancel');
  if (btnPlanCancel) {
    btnPlanCancel.addEventListener('click', () => {
      document.getElementById('modal-plan').classList.remove('active');
    });
  }
  const btnPlanSave = document.getElementById('btn-plan-save');
  if (btnPlanSave) {
    btnPlanSave.addEventListener('click', savePlanDetails);
  }

  // Content Security Policy (CSP) safe global onclick handler delegator
  document.addEventListener('click', (e) => {
    const target = e.target.closest('[onclick]');
    if (!target) return;

    // Intercept all elements with an onclick attribute to bypass CSP restriction
    const onclickAttr = target.getAttribute('onclick');
    if (onclickAttr) {
      e.preventDefault();
      e.stopPropagation();
      try {
        const match = onclickAttr.match(/^([a-zA-Z0-9_$]+)\((.*)\)$/);
        if (match) {
          const funcName = match[1];
          const argsStr = match[2].trim();
          
          let args = [];
          if (argsStr !== '') {
            const commaSplitRegex = /,(?=(?:(?:[^"']*["']){2})*[^"']*$)/g;
            args = argsStr.split(commaSplitRegex).map(arg => {
              arg = arg.trim();
              if ((arg.startsWith("'") && arg.endsWith("'")) || (arg.startsWith('"') && arg.endsWith('"'))) {
                return arg.slice(1, -1);
              }
              if (arg === 'true') return true;
              if (arg === 'false') return false;
              if (!isNaN(arg) && arg !== '') return Number(arg);
              return arg;
            });
          }

          const func = window[funcName];
          if (typeof func === 'function') {
            func.apply(null, args);
          } else {
            console.warn(`[CSP Delegator] Function '${funcName}' is not defined in window scope.`);
          }
        }
      } catch (err) {
        console.error('[CSP Delegator] Error running intercepted onclick attribute:', err);
      }
    }
  });
});

// OPEN TEXT VIEWER (FOR STACK TRACES & LOG DETAILS)
function openTextViewer(title, content) {
  document.getElementById('viewer-title').innerText = title;
  document.getElementById('viewer-content').innerText = content;
  document.getElementById('modal-viewer').classList.add('active');
}

// Global cached plans array
let cachedPlans = [];

async function loadPlans() {
  const tbody = document.getElementById('plans-table-body');
  if (!tbody) return;

  try {
    tbody.innerHTML = '<tr><td colspan="6" class="text-center">Yükleniyor...</td></tr>';
    const res = await adminFetch('/billing/plans');
    if (!res.ok) throw new Error('Failed to load plans');
    
    cachedPlans = await res.json();
    
    if (cachedPlans.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center">Kayıtlı plan bulunamadı.</td></tr>';
      return;
    }

    tbody.innerHTML = '';
    cachedPlans.forEach(plan => {
      let devicesLimit = 'Sınırsız';
      try {
        const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
        if (feats && feats.devices !== undefined) {
          devicesLimit = feats.devices > 90 ? 'Sınırsız' : feats.devices;
        }
      } catch (_) {}

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${plan.id}</strong></td>
        <td>${plan.name}</td>
        <td>${plan.price} ${plan.currency}</td>
        <td>${plan.currency}</td>
        <td>${devicesLimit}</td>
        <td class="text-right">
          <button class="btn-secondary btn-sm" onclick="openEditPlanModal('${plan.id}')">Düzenle</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
  } catch (err) {
    console.error(err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Planlar yüklenirken bir hata oluştu.</td></tr>';
  }
}

window.openEditPlanModal = function(planId) {
  const plan = cachedPlans.find(p => p.id === planId);
  if (!plan) return;

  document.getElementById('edit-plan-id').value = plan.id;
  document.getElementById('edit-plan-name').value = plan.name;
  document.getElementById('edit-plan-price').value = plan.price;
  document.getElementById('edit-plan-currency').value = plan.currency || 'TRY';
  document.getElementById('edit-plan-interval').value = plan.billing_interval || 'monthly';
  
  let devices = 1;
  let stores = 1;
  let sync = 'realtime';
  let analytics = 'standard';
  let featureList = [];

  try {
    const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
    if (feats) {
      if (feats.devices !== undefined) devices = feats.devices;
      if (feats.stores !== undefined) stores = feats.stores;
      if (feats.sync !== undefined) sync = feats.sync;
      if (feats.analytics !== undefined) analytics = feats.analytics;
      if (feats.feature_list !== undefined) featureList = feats.feature_list;
    }
  } catch (_) {}

  document.getElementById('edit-plan-devices').value = devices;
  document.getElementById('edit-plan-stores').value = stores;
  document.getElementById('edit-plan-sync').value = sync;
  document.getElementById('edit-plan-analytics').value = analytics;
  document.getElementById('edit-plan-features-list').value = Array.isArray(featureList) ? featureList.join('\n') : '';

  document.getElementById('modal-plan').classList.add('active');
}

async function savePlanDetails() {
  const id = document.getElementById('edit-plan-id').value;
  const name = document.getElementById('edit-plan-name').value;
  const price = parseFloat(document.getElementById('edit-plan-price').value);
  const currency = document.getElementById('edit-plan-currency').value;
  const billing_interval = document.getElementById('edit-plan-interval').value;
  const devices = parseInt(document.getElementById('edit-plan-devices').value, 10);
  const stores = parseInt(document.getElementById('edit-plan-stores').value, 10);
  const sync = document.getElementById('edit-plan-sync').value;
  const analytics = document.getElementById('edit-plan-analytics').value;
  const featuresText = document.getElementById('edit-plan-features-list').value;

  if (!name || isNaN(price) || isNaN(devices) || isNaN(stores) || !sync || !analytics) {
    alert('Lütfen tüm zorunlu alanları doldurun.');
    return;
  }

  const feature_list = featuresText
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0);

  const features = {
    devices,
    stores,
    sync,
    analytics,
    feature_list
  };

  try {
    const res = await adminFetch(`/billing/plans/${id}`, {
      method: 'PUT',
      body: JSON.stringify({
        name,
        price,
        currency,
        billing_interval,
        features
      })
    });

    if (res.ok) {
      document.getElementById('modal-plan').classList.remove('active');
      loadPlans();
    } else {
      const errData = await res.json();
      alert(`Hata: ${errData.message || 'Plan güncellenemedi.'}`);
    }
  } catch (err) {
    console.error(err);
    alert('Plan güncellenirken sunucuyla bağlantı kurulamadı.');
  }
}


// ── 16. SYSTEM SETTINGS MANAGEMENT ───────────────────────────────────────────
async function loadSettings() {
  const saveBtn = document.getElementById('btn-save-settings');
  if (!saveBtn) return;
  saveBtn.disabled = true;
  saveBtn.innerText = 'Yükleniyor...';

  try {
    const res = await adminFetch('/admin/settings');
    const data = await res.json();

    if (res.ok && data.success) {
      const s = data.settings;
      document.getElementById('setting-iban-bank').value = s.iban_bank || '';
      document.getElementById('setting-iban-branch').value = s.iban_branch || '';
      document.getElementById('setting-iban-owner').value = s.iban_owner || '';
      document.getElementById('setting-iban-number').value = s.iban_number || '';
      document.getElementById('setting-iyzico-key').value = s.iyzico_api_key || '';
      document.getElementById('setting-iyzico-secret').value = s.iyzico_secret_key || '';
      document.getElementById('setting-iyzico-url').value = s.iyzico_base_url || '';
      document.getElementById('setting-paytr-id').value = s.paytr_merchant_id || '';
      document.getElementById('setting-paytr-key').value = s.paytr_merchant_key || '';
      document.getElementById('setting-paytr-salt').value = s.paytr_merchant_salt || '';
      document.getElementById('setting-active-provider').value = s.active_payment_provider || 'bank_wire';
    } else {
      alert('Sistem ayarları yüklenemedi.');
    }
  } catch (err) {
    console.error('loadSettings error:', err);
    alert('Sistem ayarları yüklenirken hata oluştu.');
  } finally {
    saveBtn.disabled = false;
    saveBtn.innerText = 'AYARLARI KAYDET';
  }
}

async function saveSettings(e) {
  if (e) e.preventDefault();

  const saveBtn = document.getElementById('btn-save-settings');
  if (!saveBtn) return;
  saveBtn.disabled = true;
  saveBtn.innerText = 'Kaydediliyor...';

  const settings = {
    iban_bank: document.getElementById('setting-iban-bank').value.trim(),
    iban_branch: document.getElementById('setting-iban-branch').value.trim(),
    iban_owner: document.getElementById('setting-iban-owner').value.trim(),
    iban_number: document.getElementById('setting-iban-number').value.trim(),
    iyzico_api_key: document.getElementById('setting-iyzico-key').value.trim(),
    iyzico_secret_key: document.getElementById('setting-iyzico-secret').value.trim(),
    iyzico_base_url: document.getElementById('setting-iyzico-url').value.trim(),
    paytr_merchant_id: document.getElementById('setting-paytr-id').value.trim(),
    paytr_merchant_key: document.getElementById('setting-paytr-key').value.trim(),
    paytr_merchant_salt: document.getElementById('setting-paytr-salt').value.trim(),
    active_payment_provider: document.getElementById('setting-active-provider').value
  };

  try {
    const res = await adminFetch('/admin/settings', {
      method: 'PUT',
      body: JSON.stringify({ settings })
    });
    const data = await res.json();

    if (res.ok && data.success) {
      alert('Sistem ayarları başarıyla güncellendi!');
      loadSettings();
    } else {
      alert(`Hata: ${data.message || 'Ayarlar kaydedilemedi.'}`);
    }
  } catch (err) {
    console.error('saveSettings error:', err);
    alert('Ayarlar kaydedilirken sunucuyla bağlantı kurulamadı.');
  } finally {
    saveBtn.disabled = false;
    saveBtn.innerText = 'AYARLARI KAYDET';
  }
}
