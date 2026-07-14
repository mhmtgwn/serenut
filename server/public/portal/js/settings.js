/* ==========================================================================
   SERENUT OS V2 - PORTAL SETTINGS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { showToast } from '/shared/js/ui.js';

let currentCompanyVersion = 1;

export async function loadSettings() {
  try {
    const company = await apiFetch('/companies/current');
    currentCompanyVersion = company.version || 1;
    
    document.getElementById('settings-company-name').value = company.name || '';
    document.getElementById('settings-company-phone').value = company.phone || '';
    document.getElementById('settings-company-tax-office').value = company.tax_office || '';
    document.getElementById('settings-company-address').value = company.address || '';

    // Render logo details if present
    if (company.logo_url) {
      const img = document.getElementById('logo-preview-img');
      const placeholder = document.getElementById('logo-preview-placeholder');
      const saveBtn = document.getElementById('btn-save-logo');
      
      if (img) {
        img.src = company.logo_url;
        img.style.display = 'block';
      }
      if (placeholder) {
        placeholder.style.display = 'none';
      }
      if (saveBtn) {
        saveBtn.disabled = false;
        saveBtn._logoDataUrl = company.logo_url;
      }
      updateSidebarLogo(company.logo_url);
    }
  } catch (err) {
    console.error('Failed to load profile settings:', err);
  }
}

export async function submitSaveProfile() {
  const name = document.getElementById('settings-company-name').value.trim();
  const phone = document.getElementById('settings-company-phone').value.trim();
  const tax_office = document.getElementById('settings-company-tax-office').value.trim();
  const address = document.getElementById('settings-company-address').value.trim();
  const statusEl = document.getElementById('profile-status');

  statusEl.className = 'text-muted';
  statusEl.innerText = 'Güncelleniyor...';

  try {
    const updated = await apiFetch('/company', {
      method: 'PATCH',
      body: { 
        name, 
        phone, 
        tax_office, 
        address,
        expected_version: currentCompanyVersion
      }
    });
    currentCompanyVersion = updated.version || currentCompanyVersion;
    statusEl.className = 'text-green font-semibold';
    statusEl.innerText = '✓ Firma bilgileri güncellendi.';
    
    // Update topbar brand details or sidebar
    const brandName = document.getElementById('sidebar-company-name');
    if (brandName) brandName.innerText = name;
  } catch (err) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = err.message || 'Güncelleme başarısız.';
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
    statusEl.innerText = '✓ Şifreniz başarıyla güncellendi.';
    
    document.getElementById('settings-old-password').value = '';
    document.getElementById('settings-new-password').value = '';
    document.getElementById('settings-confirm-password').value = '';
  } catch (err) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = err.message || 'Şifre güncellenemedi.';
  }
}

export async function handleLogoFileSelect(e) {
  const file = e.target.files[0];
  if (!file) return;

  if (file.size > 2 * 1024 * 1024) {
    document.getElementById('logo-status').className = 'text-red';
    document.getElementById('logo-status').innerText = 'Dosya boyutu 2MB\'dan küçük olmalıdır.';
    return;
  }

  const reader = new FileReader();
  reader.onload = (event) => {
    const dataUrl = event.target.result;
    const img = document.getElementById('logo-preview-img');
    const placeholder = document.getElementById('logo-preview-placeholder');
    const saveBtn = document.getElementById('btn-save-logo');
    
    img.src = dataUrl;
    img.style.display = 'block';
    placeholder.style.display = 'none';
    
    saveBtn.disabled = false;
    saveBtn._logoDataUrl = dataUrl;
  };
  reader.readAsDataURL(file);
}

export async function submitSaveLogo() {
  const statusEl = document.getElementById('logo-status');
  const saveBtn = document.getElementById('btn-save-logo');
  const dataUrl = saveBtn._logoDataUrl;

  if (!dataUrl) return;

  statusEl.className = 'text-muted';
  statusEl.innerText = 'Kaydediliyor...';

  try {
    const updated = await apiFetch('/company', {
      method: 'PATCH',
      body: { 
        logo_url: dataUrl,
        expected_version: currentCompanyVersion
      }
    });
    currentCompanyVersion = updated.version || currentCompanyVersion;
    statusEl.className = 'text-green font-semibold';
    statusEl.innerText = '✓ Logo başarıyla güncellendi.';
    updateSidebarLogo(dataUrl);
  } catch (err) {
    statusEl.className = 'text-red font-semibold';
    statusEl.innerText = err.message || 'Logo kaydedilemedi.';
  }
}

function updateSidebarLogo(dataUrl) {
  const avatarContainer = document.getElementById('sidebar-company-avatar');
  if (avatarContainer) {
    avatarContainer.innerHTML = `<img src="${dataUrl}" alt="Logo" style="width:100%; height:100%; border-radius:50%; object-fit:cover;">`;
  }
}
