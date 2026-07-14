/* ==========================================================================
   SERENUT OS V2 - ADMIN CONTROL CENTER ROUTER & NAVIGATION ENGINE
   ========================================================================== */

import { setAuthToken, clearAuthToken } from '/shared/js/api-client.js';
import { isAuthenticated, setUserProfile, getUserProfile } from '/shared/js/auth.js';
import { showToast } from '/shared/js/ui.js';

// Sub-module Imports
import { loadDashboard } from './dashboard.js';
import { loadCompanies, submitCreateCompany } from './companies.js';
import { loadAdminProfile } from './users.js';
import { loadSubscriptionsIntel } from './subscriptions.js';
import { loadPendingTransfers } from './transfers.js';
import { loadPaymentsLog } from './payments.js';
import { loadPlans, savePlanDetails } from './plans.js';
import { loadLicenses, submitCreateLicense, submitCreateBulkLicenses } from './licenses.js';
import { loadDevices, submitDeviceSwap } from './devices.js';
import { loadUpdates, submitCreateUpdate } from './releases.js';
import { loadTickets, submitTicketReply, submitCreateInternalNote } from './support.js';
import { loadAuditLogs } from './audit.js';
import {
  loadSyncMonitor,
  loadSmsLogs,
  loadIncidents,
  loadSecurity,
  loadCrashLogs,
  submitCreateIncident,
  submitBanIp
} from './system-health.js';
import { loadSettings, submitSaveSystemConfig, submitSavePassword } from './settings.js';

document.addEventListener('DOMContentLoaded', () => {
  startClock();

  if (isAuthenticated()) {
    showAdminApp();
  } else {
    showLoginCard();
  }

  // Bind auth buttons
  document.getElementById('btn-login')?.addEventListener('click', handleLogin);
  document.getElementById('btn-logout')?.addEventListener('click', handleLogout);

  // Mobile sidebar drawer
  document.getElementById('nav-toggle')?.addEventListener('click', () => {
    document.querySelector('.sidebar')?.classList.toggle('active');
  });

  // Bind navigation sidebar
  document.querySelectorAll('.sidebar-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tabId = item.getAttribute('data-tab');
      if (tabId) switchTab(tabId);
    });
  });

  // Bind forms save events
  document.getElementById('btn-save-sysconfig')?.addEventListener('click', submitSaveSystemConfig);
  document.getElementById('btn-save-password')?.addEventListener('click', submitSavePassword);

  // Bind dynamic actions
  document.getElementById('btn-plan-save')?.addEventListener('click', savePlanDetails);
  document.getElementById('btn-ticket-send')?.addEventListener('click', submitTicketReply);
  document.getElementById('btn-note-submit')?.addEventListener('click', submitCreateInternalNote);

  setupModals();
});

function startClock() {
  const el = document.getElementById('header-clock');
  if (el) {
    setInterval(() => {
      el.innerText = new Date().toLocaleTimeString('tr-TR');
    }, 1000);
  }
}

function showLoginCard() {
  document.getElementById('login-container').style.display = 'flex';
  document.getElementById('admin-app').style.display = 'none';
}

function showAdminApp() {
  document.getElementById('login-container').style.display = 'none';
  document.getElementById('admin-app').style.display = 'flex';

  const user = getUserProfile();
  if (user) {
    document.getElementById('admin-profile-name').innerText = user.name || 'Sistem Yöneticisi';
  }

  switchTab('dashboard');
}

function switchTab(tabId) {
  // Update sidebar selection state
  document.querySelectorAll('.sidebar-item').forEach(item => {
    if (item.getAttribute('data-tab') === tabId) {
      item.classList.add('active');
    } else {
      item.classList.remove('active');
    }
  });

  // Switch tab-panels
  document.querySelectorAll('.tab-panel').forEach(panel => {
    if (panel.id === `tab-${tabId}`) {
      panel.classList.add('active');
    } else {
      panel.classList.remove('active');
    }
  });

  // Set topbar header title
  const titleEl = document.getElementById('current-tab-title');
  const titles = {
    dashboard: 'Yönetim Kontrol Paneli',
    companies: 'Kayıtlı Müşteri Şirketleri',
    users: 'Sistem Yöneticileri Oturumları',
    subscriptions: 'Ticari Abonelik Zekası & MRR',
    transfers: 'Bekleyen Banka Havale Onayları',
    payments: 'Cari Borç & Fatura Takip Listesi',
    plans: 'Lisans Abonelik Paket Ayarları',
    licenses: 'Aktif SaaS Lisans Anahtarları',
    devices: 'POS Terminalleri Donanım Kontrolü',
    releases: 'OTA Terminal Sürümleri Yayınlama',
    support: 'Müşteri Destek Operasyonları',
    audit: 'Sistem Yöneticisi İşlem Günlükleri',
    health: 'Sistem Servisleri & Telemetri Raporları'
  };

  if (titleEl) {
    titleEl.innerText = titles[tabId] || 'Kontrol Merkezi';
  }

  // Close drawer
  document.querySelector('.sidebar')?.classList.remove('active');

  // Trigger content-specific loaders
  loadTabData(tabId);
}

function loadTabData(tabId) {
  switch (tabId) {
    case 'dashboard':
      loadDashboard();
      break;
    case 'companies':
      loadCompanies();
      break;
    case 'users':
      loadAdminProfile();
      break;
    case 'subscriptions':
      loadSubscriptionsIntel();
      break;
    case 'transfers':
      loadPendingTransfers();
      break;
    case 'payments':
      loadPaymentsLog();
      break;
    case 'plans':
      loadPlans();
      break;
    case 'licenses':
      loadLicenses();
      break;
    case 'devices':
      loadDevices();
      break;
    case 'releases':
      loadUpdates();
      break;
    case 'support':
      loadTickets();
      break;
    case 'audit':
      loadAuditLogs();
      break;
    case 'health':
      loadSyncMonitor();
      loadSmsLogs();
      loadIncidents();
      loadSecurity();
      loadCrashLogs();
      break;
  }
}

async function handleLogin() {
  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;
  const errorEl = document.getElementById('login-error');

  errorEl.innerText = '';
  if (!email || !password) {
    errorEl.innerText = 'Lütfen tüm alanları doldurun.';
    return;
  }

  try {
    const res = await fetch('/api/v1/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });

    const data = await res.json();
    if (!res.ok) {
      errorEl.innerText = data.message || 'Giriş başarısız.';
      return;
    }

    // Confirm that the user role contains 'sysadmin' before granting entry
    const isSysAdmin = data.user && data.user.roles && data.user.roles.includes('sysadmin');
    if (!isSysAdmin) {
      errorEl.innerText = 'Hata: Bu panele giriş yetkiniz bulunmamaktadır.';
      return;
    }

    setAuthToken(data.access_token);
    setUserProfile(data.user);
    showAdminApp();
  } catch (err) {
    errorEl.innerText = 'Bağlantı hatası oluştu.';
  }
}

function handleLogout() {
  clearAuthToken();
  showLoginCard();
}

function setupModals() {
  // Modal configurations
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
      action: submitCreateLicense
    },
    bulkLicense: {
      open: 'btn-create-bulk-license',
      close: 'btn-bulk-lic-cancel',
      overlay: 'modal-bulk-license',
      submit: 'btn-bulk-lic-submit',
      action: submitCreateBulkLicenses
    },
    update: {
      open: 'btn-create-update',
      close: 'btn-up-cancel',
      overlay: 'modal-update',
      submit: 'btn-up-submit',
      action: submitCreateUpdate
    },
    incident: {
      open: 'btn-create-incident',
      close: 'btn-inc-cancel',
      overlay: 'modal-incident',
      submit: 'btn-inc-submit',
      action: submitCreateIncident
    },
    ipBan: {
      open: 'btn-create-ipban',
      close: 'btn-ipban-cancel',
      overlay: 'modal-ipban',
      submit: 'btn-ipban-submit',
      action: submitBanIp
    }
  };

  Object.keys(modals).forEach(key => {
    const config = modals[key];
    
    document.getElementById(config.open)?.addEventListener('click', () => {
      document.getElementById(config.overlay)?.classList.add('active');
    });

    document.getElementById(config.close)?.addEventListener('click', () => {
      document.getElementById(config.overlay)?.classList.remove('active');
    });

    document.getElementById(config.submit)?.addEventListener('click', async () => {
      const success = await config.action();
      if (success) {
        document.getElementById(config.overlay)?.classList.remove('active');
      }
    });
  });

  // General text detail viewer close
  document.getElementById('btn-viewer-close')?.addEventListener('click', () => {
    document.getElementById('modal-viewer').classList.remove('active');
  });

  // Plan editing card close
  document.getElementById('btn-plan-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-plan').classList.remove('active');
  });

  // Offline activations QR cards close
  document.getElementById('btn-offline-close')?.addEventListener('click', () => {
    document.getElementById('modal-offline-activation').classList.remove('active');
  });

  // Ticket chat modal close
  document.getElementById('btn-ticket-close')?.addEventListener('click', () => {
    document.getElementById('modal-ticket').classList.remove('active');
  });

  // Device swap modal cancels
  document.getElementById('btn-swap-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-device-swap').classList.remove('active');
  });
  document.getElementById('btn-swap-submit')?.addEventListener('click', async () => {
    const success = await submitDeviceSwap();
    if (success) {
      document.getElementById('modal-device-swap').classList.remove('active');
    }
  });
}
