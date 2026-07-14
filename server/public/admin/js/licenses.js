/* ==========================================================================
   SERENUT OS V2 - ADMIN LICENSES MANAGEMENT MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadLicenses() {
  const tbody = document.getElementById('license-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Lisanslar yükleniyor...</td></tr>';

  try {
    const licenses = await apiFetch('/admin/licenses');
    tbody.innerHTML = '';

    if (licenses.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Kayıtlı lisans bulunamadı.</td></tr>';
      return;
    }

    licenses.forEach(l => {
      const expires = formatDate(l.expires_at);
      const tr = document.createElement('tr');
      const badgeClass = l.status === 'active' ? 'badge-active' : l.status === 'trial' ? 'badge-trial' : 'badge-danger';

      tr.innerHTML = `
        <td><strong>${l.license_key}</strong></td>
        <td>${l.company_name || 'Şirket Tanımsız'}</td>
        <td><span class="badge badge-trial">${l.tier || 'basic'}</span></td>
        <td>${l.allowed_devices_count} Cihaz</td>
        <td>${expires}</td>
        <td><span class="badge ${badgeClass}">${translateStatus(l.status)}</span></td>
        <td>
          <button class="btn btn-secondary btn-sm text-green btn-lic-renew" data-id="${l.id}">Yenile (+1 Yıl)</button>
          <button class="btn btn-secondary btn-sm btn-lic-toggle" data-id="${l.id}" data-status="${l.status}">
            ${l.status === 'active' ? 'Askıya Al' : 'Etkinleştir'}
          </button>
          <button class="btn btn-secondary btn-sm btn-lic-qr" data-id="${l.id}" data-key="${l.license_key}" style="background:#10B981; color:white; border:none;">Offline QR</button>
          <button class="btn btn-secondary btn-sm text-red btn-lic-revoke" data-id="${l.id}">İptal Et</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    // Bind event handlers dynamically
    tbody.querySelectorAll('.btn-lic-renew').forEach(btn => {
      btn.onclick = () => renewLicense(btn.getAttribute('data-id'));
    });
    tbody.querySelectorAll('.btn-lic-toggle').forEach(btn => {
      btn.onclick = () => toggleLicenseStatus(btn.getAttribute('data-id'), btn.getAttribute('data-status'));
    });
    tbody.querySelectorAll('.btn-lic-qr').forEach(btn => {
      btn.onclick = () => triggerOfflineActivation(btn.getAttribute('data-id'), btn.getAttribute('data-key'));
    });
    tbody.querySelectorAll('.btn-lic-revoke').forEach(btn => {
      btn.onclick = () => revokeLicense(btn.getAttribute('data-id'));
    });

  } catch (err) {
    console.error('Failed to load licenses:', err);
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Lisanslar listesi yüklenemedi.</td></tr>';
  }
}

async function renewLicense(licenseId) {
  const confirmed = await showConfirm(
    'Lisans Yenileme Onayı',
    'Bu lisansın geçerlilik süresini +365 gün (1 yıl) uzatmak istediğinize emin misiniz?'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/licenses/${licenseId}/renew`, {
      method: 'POST',
      body: { additional_days: 365 }
    });
    showToast('Lisans süresi 365 gün uzatıldı.', 'success');
    loadLicenses();
  } catch (err) {
    showToast(err.message || 'Lisans yenilenemedi.', 'error');
  }
}

async function toggleLicenseStatus(licenseId, currentStatus) {
  const isSuspending = currentStatus === 'active';
  
  const confirmed = await showConfirm(
    isSuspending ? 'Lisans Askıya Alma' : 'Lisans Etkinleştirme',
    isSuspending
      ? 'Bu lisansı askıya almak istediğinize emin misiniz? Bu anahtarı kullanan POS cihazının satışı ve eşitlemesi bloke edilecektir.'
      : 'Bu lisansı yeniden etkinleştirmek istediğinize emin misiniz?'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/licenses/${licenseId}/suspend`, {
      method: 'POST',
      body: { suspend: isSuspending }
    });
    showToast(`Lisans başarıyla ${isSuspending ? 'askıya alındı' : 'aktif edildi'}.`, 'success');
    loadLicenses();
  } catch (err) {
    showToast(err.message || 'İşlem başarısız.', 'error');
  }
}

async function revokeLicense(licenseId) {
  const confirmed = await showConfirm(
    '🚨 KRİTİK: Lisans İptal Onayı',
    'Bu lisansı kalıcı olarak İPTAL (revoke) etmek istediğinize emin misiniz? Bu işlem geri alınamaz ve cihazın bulut bağlantısı kalıcı olarak koparılır!'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/licenses/${licenseId}/revoke`, { method: 'POST' });
    showToast('Lisans kalıcı olarak iptal edildi.', 'success');
    loadLicenses();
  } catch (err) {
    showToast(err.message || 'İptal işlemi başarısız.', 'error');
  }
}

async function triggerOfflineActivation(licenseId, licenseKey) {
  const deviceHash = prompt('Lütfen aktivasyon yapılacak POS terminalinin UUID (donanım hash) kodunu girin:');
  if (!deviceHash) return;

  try {
    const data = await apiFetch(`/admin/licenses/${licenseId}/offline-activation`, {
      method: 'POST',
      body: { device_hash: deviceHash }
    });

    document.getElementById('offline-token-text').value = data.activationToken;
    document.getElementById('qr-placeholder-graphics').innerText = `OFFLINE:\n${licenseKey.substring(0, 8)}...`;
    document.getElementById('modal-offline-activation').classList.add('active');
  } catch (err) {
    alert(err.message || 'Offline aktivasyon tokeni üretilemedi.');
  }
}

export async function submitCreateLicense() {
  const company_id = document.getElementById('lic-comp-select').value;
  const tier = document.getElementById('lic-tier').value;
  const allowed_devices_count = document.getElementById('lic-device-limit').value;
  const expires_in_days = document.getElementById('lic-days').value;

  if (!company_id || !tier) {
    alert('Şirket ve paket seçimi zorunludur.');
    return false;
  }

  try {
    await apiFetch('/admin/licenses', {
      method: 'POST',
      body: { company_id, tier, allowed_devices_count, expires_in_days }
    });
    showToast('Lisans anahtarı başarıyla oluşturuldu.', 'success');
    loadLicenses();
    return true;
  } catch (err) {
    alert(err.message || 'Lisans oluşturulamadı.');
    return false;
  }
}

export async function submitCreateBulkLicenses() {
  const company_id = document.getElementById('bulk-lic-comp-select').value;
  const tier = document.getElementById('bulk-lic-tier').value;
  const allowed_devices_count = document.getElementById('bulk-lic-device-limit').value;
  const expires_in_days = document.getElementById('bulk-lic-days').value;
  const count = document.getElementById('bulk-lic-count').value;

  if (!company_id || !count) {
    alert('Şirket seçimi ve adet zorunludur.');
    return false;
  }

  try {
    const data = await apiFetch('/admin/licenses/bulk', {
      method: 'POST',
      body: { company_id, tier, allowed_devices_count, expires_in_days, count }
    });
    alert(`${data.license_keys.length} adet lisans anahtarı başarıyla üretildi.`);
    loadLicenses();
    return true;
  } catch (err) {
    alert(err.message || 'Toplu lisans üretilemedi.');
    return false;
  }
}
