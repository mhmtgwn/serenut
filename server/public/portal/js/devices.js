/* ==========================================================================
   SERENUT OS V2 - PORTAL DEVICES MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';

export async function loadDevices() {
  const tbody = document.getElementById('devices-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Cihazlar yükleniyor...</td></tr>';

  try {
    const devices = await apiFetch('/portal/devices');
    tbody.innerHTML = '';

    if (devices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Bağlı aktif terminal bulunmamaktadır.</td></tr>';
      return;
    }

    devices.forEach(dev => {
      const tr = document.createElement('tr');
      const badgeClass = dev.status === 'revoked' ? 'badge-danger' : 'badge-active';
      const hashDisplay = dev.device_hash ? `${dev.device_hash.substring(0, 16)}...` : '—';
      const isOnline = dev.is_online;

      tr.innerHTML = `
        <td><strong>${dev.id || '—'}</strong></td>
        <td>${dev.name || 'Terminal'}</td>
        <td>${dev.store_name || 'Şube Tanımsız'}</td>
        <td><span style="font-family: monospace; font-size:0.82rem;">${hashDisplay}</span></td>
        <td><span class="indicator ${isOnline ? 'online' : 'offline'}">${isOnline ? 'Çevrimiçi' : 'Çevrimdışı'}</span></td>
        <td>${formatDate(dev.last_active_at, true)}</td>
        <td><span class="badge ${badgeClass}">${translateStatus(dev.status)}</span></td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load devices:', err);
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Cihazlar listesi yüklenemedi.</td></tr>';
  }
}
