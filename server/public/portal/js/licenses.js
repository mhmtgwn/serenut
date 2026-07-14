/* ==========================================================================
   SERENUT OS V2 - PORTAL LICENSES MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';

/**
 * Loads licenses specifically for the Licenses tab view
 */
export async function loadLicenses() {
  const tbody = document.getElementById('licenses-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Lisanslar yükleniyor...</td></tr>';

  try {
    const data = await apiFetch('/portal/dashboard');
    const licenses = data.licenses || [];
    
    tbody.innerHTML = '';

    if (licenses.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Aktif lisansınız bulunmamaktadır.</td></tr>';
      return;
    }

    licenses.forEach(lic => {
      const tr = document.createElement('tr');
      const badgeClass = lic.status === 'active' ? 'badge-active' : lic.status === 'trial' ? 'badge-trial' : 'badge-suspended';
      const deviceCount = lic.allowed_devices_count || 1;

      tr.innerHTML = `
        <td><strong>${lic.license_key || '—'}</strong></td>
        <td><span class="badge badge-trial">${lic.tier || 'basic'}</span></td>
        <td>${deviceCount} Cihaz</td>
        <td>${formatDate(lic.expires_at)}</td>
        <td><span class="badge ${badgeClass}">${translateStatus(lic.status)}</span></td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load licenses:', err);
    tbody.innerHTML = '<tr><td colspan="5" class="text-center text-danger">Lisanslar yüklenemedi.</td></tr>';
  }
}
