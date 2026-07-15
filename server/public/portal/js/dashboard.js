/* ==========================================================================
   SERENUT OS V2 - PORTAL DASHBOARD MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency, formatDate, translateStatus } from '/shared/js/formatters.js';

export async function loadDashboard() {
  const container = document.getElementById('tab-dashboard');
  if (!container) return;

  try {
    const data = await apiFetch('/portal/dashboard');
    
    // Bind stats metrics
    document.getElementById('stat-stores').innerText = data.summary.stores || 0;
    document.getElementById('stat-devices').innerText = data.summary.devices || 0;
    document.getElementById('stat-invoices').innerText = data.summary.unpaidInvoices || 0;
    document.getElementById('stat-revenue').innerText = formatCurrency(data.summary.monthlyRevenue || 0);

    // Populate active licenses table
    const tbody = document.getElementById('dashboard-licenses-body');
    if (tbody) {
      tbody.innerHTML = '';
      const licenses = data.licenses || [];

      if (licenses.length === 0) {
        tbody.innerHTML = `
          <tr>
            <td colspan="6" class="text-center text-muted">Şirketinize tanımlı aktif lisans kaydı bulunamadı.</td>
          </tr>
        `;
        return;
      }

      licenses.forEach(lic => {
        const tr = document.createElement('tr');
        const badgeClass = lic.status === 'active' ? 'badge-active' : lic.status === 'trial' ? 'badge-trial' : 'badge-suspended';
        
        tr.innerHTML = `
          <td><strong>${lic.license_key || '—'}</strong></td>
          <td><span class="badge badge-trial">${lic.tier || 'basic'}</span></td>
          <td>${lic.allowed_devices_count || lic.device_limit || 1} Cihaz</td>
          <td>${formatDate(lic.expires_at)}</td>
          <td><span class="badge ${badgeClass}">${translateStatus(lic.status)}</span></td>
          <td><button class="btn btn-secondary btn-sm btn-copy-license" data-key="${lic.license_key || ''}">Kopyala</button></td>
        `;
        tbody.appendChild(tr);
      });

      tbody.querySelectorAll('.btn-copy-license').forEach(btn => {
        btn.addEventListener('click', async () => {
          const key = btn.getAttribute('data-key');
          if (!key) return;
          await navigator.clipboard?.writeText(key);
          btn.innerText = 'Kopyalandı';
          setTimeout(() => { btn.innerText = 'Kopyala'; }, 1500);
        });
      });
    }

  } catch (err) {
    console.error('Failed to load dashboard summary:', err);
  }
}
