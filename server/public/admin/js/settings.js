/* ==========================================================================
   SERENUT OS V2 - ADMIN SETTINGS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { showToast } from '/shared/js/ui.js';

export async function loadSettings() {
  try {
    const config = await apiFetch('/admin/settings');
    
    document.getElementById('set-iyzico-api-key').value = config.iyzicoApiKey || '';
    document.getElementById('set-iyzico-secret-key').value = config.iyzicoSecretKey || '';
    document.getElementById('set-iyzico-url').value = config.iyzicoBaseUrl || '';
    document.getElementById('set-sms-provider').value = config.smsProvider || '';
    document.getElementById('set-sms-api-key').value = config.smsApiKey || '';
    document.getElementById('set-backup-frequency').value = config.backupFrequency || 'daily';

  } catch (err) {
    console.error('Failed to load system config settings:', err);
  }
}

export async function submitSaveSystemConfig() {
  const iyzicoApiKey = document.getElementById('set-iyzico-api-key').value.trim();
  const iyzicoSecretKey = document.getElementById('set-iyzico-secret-key').value.trim();
  const iyzicoBaseUrl = document.getElementById('set-iyzico-url').value.trim();
  const smsProvider = document.getElementById('set-sms-provider').value.trim();
  const smsApiKey = document.getElementById('set-sms-api-key').value.trim();
  const backupFrequency = document.getElementById('set-backup-frequency').value;
  const statusEl = document.getElementById('config-status');

  statusEl.className = 'text-muted';
  statusEl.innerText = 'Güncelleniyor...';

  try {
    await apiFetch('/admin/settings', {
      method: 'PUT',
      body: {
        iyzicoApiKey,
        iyzicoSecretKey,
        iyzicoBaseUrl,
        smsProvider,
        smsApiKey,
        backupFrequency
      }
    });

    statusEl.className = 'text-green font-semibold';
    statusEl.innerText = '✓ Sistem ayarları kaydedildi ve servisler yeniden yüklendi.';
  } catch (err) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = err.message || 'Ayarlar kaydedilemedi.';
  }
}

export async function submitSavePassword() {
  const old_password = document.getElementById('settings-old-password').value;
  const new_password = document.getElementById('settings-new-password').value;
  const confirm_password = document.getElementById('settings-confirm-password').value;
  const statusEl = document.getElementById('password-status');

  statusEl.className = 'text-muted';
  statusEl.innerText = '';

  if (!old_password || !new_password) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = 'Lütfen tüm alanları doldurun.';
    return;
  }

  if (new_password !== confirm_password) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = 'Yeni şifreler eşleşmiyor.';
    return;
  }

  if (new_password.length < 8) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = 'Yeni şifre en az 8 karakter olmalıdır.';
    return;
  }

  try {
    await apiFetch('/auth/change-password', {
      method: 'POST',
      body: { old_password, new_password }
    });
    statusEl.className = 'text-green font-semibold';
    statusEl.innerText = '✓ Giriş şifreniz güncellendi.';
    
    document.getElementById('settings-old-password').value = '';
    document.getElementById('settings-new-password').value = '';
    document.getElementById('settings-confirm-password').value = '';
  } catch (err) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = err.message || 'Şifre değiştirilemedi.';
  }
}
