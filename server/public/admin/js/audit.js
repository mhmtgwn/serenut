/* ==========================================================================
   SERENUT OS V2 - ADMIN AUDIT LOGS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';

export async function loadAuditLogs() {
  const tbody = document.getElementById('audit-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Denetim kayıtları yükleniyor...</td></tr>';

  try {
    const logs = await apiFetch('/admin/audit-logs');
    tbody.innerHTML = '';

    if (logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Denetim kaydı bulunamadı.</td></tr>';
      return;
    }

    logs.forEach(l => {
      const created = formatDate(l.created_at, true);
      const tr = document.createElement('tr');

      tr.innerHTML = `
        <td>${created}</td>
        <td><strong>${l.user_name || "—"}</strong></td>
        <td>${l.action}</td>
        <td>${l.entity || "—"}</td>
        <td>${l.entity_id || "—"}</td>
        <td><span style="font-family:monospace; font-size:0.82rem;">${l.ip_address}</span></td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load audit logs:', err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Kayıtlar listelenemedi.</td></tr>';
  }
}
