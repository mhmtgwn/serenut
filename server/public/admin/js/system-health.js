/* ==========================================================================
   SERENUT OS V2 - ADMIN SYSTEM HEALTH AND TELEMETRY MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

/**
 * Loads Delta Sync monitor logs
 */
export async function loadSyncMonitor() {
  try {
    const data = await apiFetch('/admin/sync/monitor');

    document.getElementById('sync-pending').innerText = data.summary.pending || 0;
    document.getElementById('sync-failed').innerText = data.summary.failed || 0;
    document.getElementById('sync-completed').innerText = data.summary.completed || 0;

    const tbody = document.getElementById('sync-table-body');
    if (tbody) {
      tbody.innerHTML = '';
      const jobs = data.failed_jobs || [];

      if (jobs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Bekleyen eşitleme arızası kaydı bulunmamaktadır.</td></tr>';
        return;
      }

      jobs.forEach(job => {
        const created = formatDate(job.created_at, true);
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${job.company_name}</td>
          <td>${job.device_name}</td>
          <td><strong>${job.entity_type}</strong></td>
          <td>${job.entity_id}</td>
          <td class="text-red">${job.error_message || "—"}</td>
          <td>${created}</td>
        `;
        tbody.appendChild(tr);
      });
    }
  } catch (err) {
    console.error('Failed to load sync monitor stats:', err);
  }
}

/**
 * Loads SMS delivery stats and quota metrics
 */
export async function loadSmsLogs() {
  try {
    const data = await apiFetch('/admin/sms/stats');

    document.getElementById('sms-sent').innerText = data.summary.sent || 0;
    document.getElementById('sms-failed').innerText = data.summary.failed || 0;
    document.getElementById('sms-quota').innerText = `${data.summary.dailyQuotaUsed || 0} / ${data.summary.maxDailyQuota || 0}`;

    const tbody = document.getElementById('sms-table-body');
    if (tbody) {
      tbody.innerHTML = '';
      const logs = data.logs || [];

      if (logs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">SMS gönderim kaydı bulunamadı.</td></tr>';
        return;
      }

      logs.forEach(l => {
        const created = formatDate(l.created_at, true);
        const tr = document.createElement('tr');
        const badgeClass = l.status === 'sent' ? 'badge-active' : 'badge-danger';

        tr.innerHTML = `
          <td>${created}</td>
          <td>${l.company_name}</td>
          <td>${l.phone}</td>
          <td>${l.message}</td>
          <td><span class="badge ${badgeClass}">${l.status}</span></td>
        `;
        tbody.appendChild(tr);
      });
    }
  } catch (err) {
    console.error('Failed to load SMS stats logs:', err);
  }
}

/**
 * Loads Incident center cases list
 */
export async function loadIncidents() {
  try {
    const incidents = await apiFetch('/admin/incidents');
    const tbody = document.getElementById('incidents-table-body');
    if (!tbody) return;

    tbody.innerHTML = '';

    if (incidents.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Kayıtlı sistem olayı bulunmuyor.</td></tr>';
      return;
    }

    incidents.forEach(inc => {
      const date = formatDate(inc.created_at, true);
      const tr = document.createElement('tr');
      const statusBadge = inc.status === 'open' ? 'badge-active' : inc.status === 'resolved' ? 'badge-trial' : 'badge-danger';

      tr.innerHTML = `
        <td><strong>#${inc.id.substring(0, 8)}</strong></td>
        <td>${inc.company_name || 'Tüm Platform'}</td>
        <td><span class="badge badge-trial">${inc.severity}</span></td>
        <td><strong>${inc.title}</strong></td>
        <td>${inc.description || "—"}</td>
        <td><span class="badge ${statusBadge}">${inc.status}</span></td>
        <td>${date}</td>
        <td>
          ${inc.status === 'open' ? `<button class="btn btn-secondary btn-sm btn-incident-assign" data-id="${inc.id}">Üstlen</button>` : ''}
          ${inc.status !== 'resolved' ? `<button class="btn btn-secondary btn-sm text-green btn-incident-resolve" data-id="${inc.id}">Çözüldü</button>` : '✓ Tamamlandı'}
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-incident-assign').forEach(btn => {
      btn.onclick = () => assignIncident(btn.getAttribute('data-id'));
    });
    tbody.querySelectorAll('.btn-incident-resolve').forEach(btn => {
      btn.onclick = () => resolveIncident(btn.getAttribute('data-id'));
    });

  } catch (err) {
    console.error('Failed to load incidents:', err);
  }
}

async function assignIncident(incidentId) {
  try {
    await apiFetch(`/admin/incidents/${incidentId}/assign`, { method: 'POST' });
    showToast('Incident takibi üzerinize atandı.', 'success');
    loadIncidents();
  } catch (err) {
    showToast(err.message || 'Üstlenilemedi.', 'error');
  }
}

async function resolveIncident(incidentId) {
  const notes = prompt('Lütfen çözüm açıklamasını giriniz:');
  if (notes === null) return;

  try {
    await apiFetch(`/admin/incidents/${incidentId}/resolve`, {
      method: 'POST',
      body: { resolution_notes: notes }
    });
    showToast('Incident çözüldü olarak işaretlendi.', 'success');
    loadIncidents();
  } catch (err) {
    showToast(err.message || 'Çözülemedi.', 'error');
  }
}

export async function submitCreateIncident() {
  const company_id = document.getElementById('inc-comp-select').value;
  const severity = document.getElementById('inc-severity').value;
  const title = document.getElementById('inc-title').value.trim();
  const description = document.getElementById('inc-desc').value.trim();

  if (!title || !description) {
    alert('Başlık ve açıklama zorunludur.');
    return false;
  }

  try {
    await apiFetch('/admin/incidents', {
      method: 'POST',
      body: { company_id: company_id || null, severity, title, description }
    });
    showToast('Incident kaydı oluşturuldu.', 'success');
    loadIncidents();
    return true;
  } catch (err) {
    alert(err.message || 'Incident kaydedilemedi.');
    return false;
  }
}

/**
 * Loads Security IP ban list
 */
export async function loadSecurity() {
  try {
    const list = await apiFetch('/admin/security/blacklist');
    const tbody = document.getElementById('blacklist-table-body');
    if (!tbody) return;

    tbody.innerHTML = '';

    if (list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Yasaklı IP adresi bulunmamaktadır.</td></tr>';
      return;
    }

    list.forEach(b => {
      const date = formatDate(b.created_at, true);
      const tr = document.createElement('tr');

      tr.innerHTML = `
        <td><strong>${b.ip_address}</strong></td>
        <td>${b.reason || "—"}</td>
        <td>${b.banned_by_name || "—"}</td>
        <td>${date}</td>
        <td>
          <button class="btn btn-secondary btn-sm text-green btn-unban" data-ip="${b.ip_address}">Engeli Kaldır</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-unban').forEach(btn => {
      btn.onclick = () => unbanIp(btn.getAttribute('data-ip'));
    });

  } catch (err) {
    console.error('Failed to load blacklist:', err);
  }
}

async function unbanIp(ipAddress) {
  const confirmed = await showConfirm(
    'IP Ban Kaldırma',
    `"${ipAddress}" adresinin engelini kaldırmak istediğinize emin misiniz?`
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/security/ban-ip/${ipAddress}`, { method: 'DELETE' });
    showToast('IP adresi engeli kaldırıldı.', 'success');
    loadSecurity();
  } catch (err) {
    showToast(err.message || 'Engeli kaldırılamadı.', 'error');
  }
}

export async function submitBanIp() {
  const ip = document.getElementById('ban-ip-val').value.trim();
  const reason = document.getElementById('ban-reason').value.trim();

  if (!ip || !reason) {
    alert('IP adresi ve yasaklama gerekçesi zorunludur.');
    return false;
  }

  try {
    await apiFetch('/admin/security/ban-ip', {
      method: 'POST',
      body: { ip, reason }
    });
    showToast('IP adresi kara listeye eklendi.', 'success');
    loadSecurity();
    return true;
  } catch (err) {
    alert(err.message || 'IP kara listeye eklenemedi.');
    return false;
  }
}

/**
 * Loads Crash log indices
 */
export async function loadCrashLogs() {
  const tbody = document.getElementById('crash-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Hatalar listeleniyor...</td></tr>';

  try {
    const logs = await apiFetch('/admin/crash-logs');
    tbody.innerHTML = '';

    if (logs.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Kayıtlı crash log kaydı bulunmuyor.</td></tr>';
      return;
    }

    logs.forEach(l => {
      const created = formatDate(l.created_at, true);
      const tr = document.createElement('tr');

      tr.innerHTML = `
        <td>${created}</td>
        <td>${l.company_name}</td>
        <td>${l.device_name || "—"}</td>
        <td class="text-red"><strong>${l.error_message.substring(0, 60)}...</strong></td>
        <td>${l.app_version || "—"}</td>
        <td>
          <button class="btn btn-secondary btn-sm btn-crash-stack" data-id="${l.id}">Stack Trace</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-crash-stack').forEach(btn => {
      btn.onclick = () => viewCrashStackTrace(btn.getAttribute('data-id'));
    });

  } catch (err) {
    console.error('Failed to load crash logs:', err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Hatalar yüklenemedi.</td></tr>';
  }
}

async function viewCrashStackTrace(logId) {
  try {
    const logs = await apiFetch('/admin/crash-logs');
    const record = logs.find(l => l.id === logId);
    if (record) {
      document.getElementById('viewer-title').innerText = 'Crash Stack Trace Detayı';
      document.getElementById('viewer-content').innerText = record.stack_trace || 'Stack trace bulunamadı.';
      document.getElementById('modal-viewer').classList.add('active');
    }
  } catch (err) {
    showToast('Detay yüklenemedi.', 'error');
  }
}
