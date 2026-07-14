/* ==========================================================================
   SERENUT OS V2 - ADMIN DEVICES MANAGEMENT MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadDevices() {
  const tbody = document.getElementById('device-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Cihazlar yükleniyor...</td></tr>';

  try {
    const devices = await apiFetch('/admin/devices');
    tbody.innerHTML = '';

    if (devices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Kayıtlı POS terminali bulunamadı.</td></tr>';
      return;
    }

    devices.forEach(d => {
      const activeTime = formatDate(d.last_active_at, true);
      const tr = document.createElement('tr');
      const badgeClass = d.status === 'active' ? 'badge-active' : 'badge-danger';
      const isOnline = d.is_online;

      tr.innerHTML = `
        <td><strong>${d.id}</strong></td>
        <td>${d.company_name || 'Şirket Tanımsız'}</td>
        <td>${d.store_name || "—"}</td>
        <td><span style="font-family:monospace; font-size:0.8rem;">${d.device_hash.substring(0, 16)}...</span></td>
        <td><span class="badge ${badgeClass}">${translateStatus(d.status)}</span></td>
        <td>${activeTime}</td>
        <td><span class="indicator ${isOnline ? 'online' : 'offline'}">${isOnline ? 'Çevrimiçi' : 'Çevrimdışı'}</span></td>
        <td>
          <button class="btn btn-secondary btn-sm btn-device-swap" style="background:#8B5CF6; color:white; border:none;" data-comp-id="${d.company_id}" data-id="${d.id}" data-name="${d.name || '-'}">Değiştir</button>
          <button class="btn btn-secondary btn-sm btn-device-toggle" data-id="${d.id}">
            ${d.status === 'active' ? 'Engelle' : 'Etkinleştir'}
          </button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    // Bind event handlers dynamically
    tbody.querySelectorAll('.btn-device-swap').forEach(btn => {
      btn.onclick = () => {
        openDeviceSwapModal(
          btn.getAttribute('data-comp-id'),
          btn.getAttribute('data-id'),
          btn.getAttribute('data-name')
        );
      };
    });
    tbody.querySelectorAll('.btn-device-toggle').forEach(btn => {
      btn.onclick = () => {
        toggleDeviceStatus(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error('Failed to load system devices list:', err);
    tbody.innerHTML = '<tr><td colspan="8" class="text-center text-danger">Cihazlar listesi yüklenemedi.</td></tr>';
  }
}

async function toggleDeviceStatus(deviceId) {
  try {
    await apiFetch(`/admin/devices/${deviceId}/toggle`, { method: 'POST' });
    showToast('Cihaz blokaj durumu güncellendi.', 'success');
    loadDevices();
  } catch (err) {
    showToast(err.message || 'Cihaz durumu güncellenemedi.', 'error');
  }
}

function openDeviceSwapModal(companyId, oldDeviceId, oldDeviceName) {
  document.getElementById('swap-company-id').value = companyId;
  document.getElementById('swap-old-device-id').value = oldDeviceId;
  document.getElementById('swap-old-device-name').value = oldDeviceName;
  document.getElementById('modal-device-swap').classList.add('active');
}

export async function submitDeviceSwap() {
  const company_id = document.getElementById('swap-company-id').value;
  const old_device_id = document.getElementById('swap-old-device-id').value;
  const new_device_name = document.getElementById('swap-new-device-name').value.trim();
  const new_device_hash = document.getElementById('swap-new-device-hash').value.trim();

  if (!new_device_name || !new_device_hash) {
    alert('Yeni cihaz ismi ve donanım hash kodu (UUID) girmelisiniz.');
    return false;
  }

  try {
    await apiFetch('/admin/devices/swap', {
      method: 'POST',
      body: { company_id, old_device_id, new_device_name, new_device_hash }
    });
    showToast('Cihaz donanım eşleşmesi güncellendi.', 'success');
    loadDevices();
    return true;
  } catch (err) {
    alert(err.message || 'Cihaz değişimi başarısız.');
    return false;
  }
}
