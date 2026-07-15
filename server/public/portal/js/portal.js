/* ==========================================================================
   SERENUT OS V2 - PORTAL ENGINE AND NAVIGATION BOOTSTRAPPER
   ========================================================================== */

import { setAuthToken, clearAuthToken, getAuthToken } from '/shared/js/api-client.js';
import { isAuthenticated, setUserProfile, getUserProfile } from '/shared/js/auth.js';
import { showToast } from '/shared/js/ui.js';

// Sub-module Imports
import { loadDashboard } from './dashboard.js';
import { loadSubscription, submitReactivateSubscription, submitCancelSubscription } from './subscription.js';
import { loadInvoices, submitBankTransferNotification } from './billing.js';
import { loadLicenses } from './licenses.js';
import { loadUsers, submitCreateUser, submitResetPassword } from './users.js';
import { loadStores, submitCreateStore } from './stores.js';
import { loadDevices } from './devices.js';
import { loadDownloads } from './downloads.js';
import { loadTickets, submitCreateTicket, submitTicketReply } from './support.js';
import { loadSettings, submitSaveProfile, submitSavePassword, handleLogoFileSelect, submitSaveLogo } from './settings.js';

document.addEventListener('DOMContentLoaded', () => {
  startHeaderClock();
  
  if (isAuthenticated()) {
    showPortalApp();
  } else {
    showLoginCard();
  }

  // Auth Button Event Listeners
  document.getElementById('btn-login')?.addEventListener('click', handleLogin);
  document.getElementById('btn-register')?.addEventListener('click', handleRegister);
  document.getElementById('btn-logout')?.addEventListener('click', handleLogout);

  // Auth Card tab switches
  document.getElementById('tab-login-btn')?.addEventListener('click', () => switchAuthTab('login'));
  document.getElementById('tab-register-btn')?.addEventListener('click', () => switchAuthTab('register'));

  // If URL hash is #register, open register tab automatically
  if (window.location.hash === '#register' || window.location.hash.startsWith('#register')) {
    switchAuthTab('register');
  }

  // Sidebar item tab navigations
  document.querySelectorAll('.sidebar-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const tabId = item.getAttribute('data-tab');
      if (tabId) switchTab(tabId);
    });
  });

  // Mobile drawer toggle
  document.getElementById('nav-toggle')?.addEventListener('click', () => {
    document.querySelector('.sidebar')?.classList.toggle('active');
  });

  // Bind settings listeners
  document.getElementById('btn-save-profile')?.addEventListener('click', submitSaveProfile);
  document.getElementById('btn-save-password')?.addEventListener('click', submitSavePassword);
  document.getElementById('logo-file-input')?.addEventListener('change', handleLogoFileSelect);
  document.getElementById('btn-save-logo')?.addEventListener('click', submitSaveLogo);

  // Bind user action buttons
  document.getElementById('btn-reset-pw-submit')?.addEventListener('click', submitResetPassword);

  // Bind support ticket reply
  document.getElementById('btn-ticket-send')?.addEventListener('click', submitTicketReply);

  // Setup modal close buttons
  setupModals();
});

/**
 * Initializes clocks in the header
 */
function startHeaderClock() {
  const clock = document.getElementById('header-clock');
  if (clock) {
    setInterval(() => {
      clock.innerText = new Date().toLocaleTimeString('tr-TR');
    }, 1000);
  }
}

/**
 * Shows login card and clears app shell UI
 */
function showLoginCard() {
  document.getElementById('auth-wrapper').style.display = 'flex';
  document.getElementById('portal-app').style.display = 'none';
}

/**
 * Bootstraps portal app views and loads current profile details
 */
function showPortalApp() {
  document.getElementById('auth-wrapper').style.display = 'none';
  document.getElementById('portal-app').style.display = 'flex';

  // Load current user profile details to sidebar
  const profile = getUserProfile();
  if (profile) {
    document.getElementById('sidebar-user-name').innerText = profile.name || 'Müşteri';
    document.getElementById('sidebar-company-name').innerText = profile.company_name || 'Şirketiniz';
  }

  // Check if we have a pending checkout from plans page
  const planId = sessionStorage.getItem('selected_plan_id');
  if (planId) {
    switchTab('subscription');
  } else {
    // Switch to default overview
    switchTab('dashboard');
  }
}

/**
 * Custom Tab Swapping controller
 * @param {string} tabId 
 */
function switchTab(tabId) {
  // Update sidebar active highlights
  document.querySelectorAll('.sidebar-item').forEach(item => {
    if (item.getAttribute('data-tab') === tabId) {
      item.classList.add('active');
    } else {
      item.classList.remove('active');
    }
  });

  // Hide all screens, show current
  document.querySelectorAll('.tab-panel').forEach(panel => {
    if (panel.id === `tab-${tabId}`) {
      panel.classList.add('active');
    } else {
      panel.classList.remove('active');
    }
  });

  // Update current header title
  const titles = {
    dashboard: 'Şirket Genel Özet Raporu',
    subscription: 'Abonelik & Ödeme Yönetimi',
    licenses: 'Lisans Anahtarlarınız',
    users: 'Personel & Kasiyer Yetkileri',
    stores: 'Kayıtlı Mağaza Şubeleriniz',
    devices: 'POS Terminalleri Donanım Durumu',
    downloads: 'Dosya İndirme Merkezi',
    support: 'Müşteri Destek Talepleri',
    settings: 'Hesap & Profil Ayarları'
  };

  const titleEl = document.getElementById('current-tab-title');
  if (titleEl) {
    titleEl.innerText = titles[tabId] || 'Müşteri Portalı';
  }

  // Close mobile sidebar drawer after click
  document.querySelector('.sidebar')?.classList.remove('active');

  // Trigger sub-module specific data loads
  loadTabData(tabId);
}

function loadTabData(tabId) {
  switch (tabId) {
    case 'dashboard':
      loadDashboard();
      break;
    case 'subscription':
      loadSubscription();
      loadInvoices();
      break;
    case 'licenses':
      loadLicenses();
      break;
    case 'users':
      loadUsers();
      break;
    case 'stores':
      loadStores();
      break;
    case 'devices':
      loadDevices();
      break;
    case 'downloads':
      loadDownloads();
      break;
    case 'support':
      loadTickets();
      break;
    case 'settings':
      loadSettings();
      break;
  }
}

/**
 * Switches between login and signup auth cards
 * @param {'login'|'register'} mode 
 */
function switchAuthTab(mode) {
  const loginForm = document.getElementById('form-login');
  const regForm = document.getElementById('form-register');
  const loginBtn = document.getElementById('tab-login-btn');
  const regBtn = document.getElementById('tab-register-btn');

  if (mode === 'register') {
    loginForm.style.display = 'none';
    regForm.style.display = 'flex';
    loginBtn.classList.remove('active');
    regBtn.classList.add('active');
  } else {
    loginForm.style.display = 'flex';
    regForm.style.display = 'none';
    loginBtn.classList.add('active');
    regBtn.classList.remove('active');
  }
}

/**
 * Form login handler
 */
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
      errorEl.innerText = data.message || 'Giriş bilgileri hatalı.';
      return;
    }

    setAuthToken(data.access_token);
    setUserProfile(data.user);
    showPortalApp();
  } catch (err) {
    errorEl.innerText = 'Bağlantı hatası oluştu.';
  }
}

/**
 * Form registration handler
 */
async function handleRegister() {
  const company_name = document.getElementById('reg-company').value.trim();
  const name = document.getElementById('reg-name').value.trim();
  const email = document.getElementById('reg-email').value.trim();
  const phone = document.getElementById('reg-phone').value.trim();
  const password = document.getElementById('reg-password').value;
  const errorEl = document.getElementById('register-error');
  const btn = document.getElementById('btn-register');

  errorEl.innerText = '';
  if (!company_name || !name || !email || !phone || !password) {
    errorEl.innerText = 'Lütfen yıldızlı (*) tüm alanları doldurun.';
    return;
  }

  if (password.length < 6) {
    errorEl.innerText = 'Şifreniz en az 6 karakter olmalıdır.';
    return;
  }

  // Preserve pre-selected plan if returning from website plans.html
  const plan_id = sessionStorage.getItem('selected_plan_id') || 'plan-basic';

  btn.disabled = true;
  btn.innerText = 'Hesap Oluşturuluyor...';

  try {
    const res = await fetch('/api/v1/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_name, name, email, phone, password, plan_id })
    });

    const data = await res.json();
    if (!res.ok) {
      errorEl.innerText = data.message || 'Kayıt oluşturulamadı.';
      return;
    }

    setAuthToken(data.access_token);
    setUserProfile(data.user);
    
    // We do NOT clear selected_plan_id here anymore. 
    // It will be cleared after successful checkout in the billing module.

    showPortalApp();
  } catch (err) {
    errorEl.innerText = 'Sunucuyla bağlantı kurulamadı.';
  } finally {
    btn.disabled = false;
    btn.innerText = 'Kayıt Ol';
  }
}

/**
 * Handles clearing credentials and redirects to login card
 */
function handleLogout() {
  clearAuthToken();
  showLoginCard();
}

/**
 * Modal visibility binds and action controls
 */
function setupModals() {
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

  // Modal resets
  document.getElementById('btn-reset-pw-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-reset-password').classList.remove('active');
  });

  // Ticket chat modal close
  document.getElementById('btn-ticket-close')?.addEventListener('click', () => {
    document.getElementById('modal-ticket-chat').classList.remove('active');
  });

  // Bank wire notifications cancel
  document.getElementById('btn-transfer-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-bank-transfer').classList.remove('active');
  });
  document.getElementById('btn-transfer-submit')?.addEventListener('click', submitBankTransferNotification);

  // Success payment reference card close
  document.getElementById('btn-success-close')?.addEventListener('click', () => {
    document.getElementById('modal-transfer-success').classList.remove('active');
  });

  // Subscription cancel modals
  document.getElementById('btn-sub-cancel')?.addEventListener('click', () => {
    document.getElementById('modal-sub-cancel').classList.add('active');
  });
  document.getElementById('btn-cancel-modal-close')?.addEventListener('click', () => {
    document.getElementById('modal-sub-cancel').classList.remove('active');
  });
  document.getElementById('btn-cancel-modal-submit')?.addEventListener('click', async () => {
    const reason = document.getElementById('cancel-reason').value;
    const note = document.getElementById('cancel-note').value.trim();
    const success = await submitCancelSubscription(reason, note);
    if (success) {
      document.getElementById('modal-sub-cancel').classList.remove('active');
    }
  });

  // Subscription reactivation
  document.getElementById('btn-sub-reactivate')?.addEventListener('click', submitReactivateSubscription);
}
