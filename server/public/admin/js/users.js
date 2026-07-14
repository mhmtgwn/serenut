/* ==========================================================================
   SERENUT OS V2 - ADMIN USERS & PROFILE MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadAdminProfile() {
  const profileContainer = document.getElementById('admin-profile-details');
  const sessionsTbody = document.getElementById('admin-sessions-tbody');
  
  if (!profileContainer || !sessionsTbody) return;

  profileContainer.innerHTML = '<p class="text-muted">Profil yükleniyor...</p>';
  sessionsTbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Oturumlar yükleniyor...</td></tr>';

  try {
    // 1. Fetch current admin details
    const me = await apiFetch('/users/me');
    profileContainer.innerHTML = `
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-3); font-size: 0.95rem;">
        <div><strong>Adı Soyadı:</strong> ${me.name}</div>
        <div><strong>Giriş E-postası:</strong> ${me.email}</div>
        <div><strong>Yetki Rolleri:</strong> ${me.roles.map(r => `<span class="badge badge-trial">${r.toUpperCase()}</span>`).join(' ')}</div>
        <div><strong>Kayıt Tarihi:</strong> ${formatDate(me.created_at)}</div>
      </div>
    `;

    // 2. Fetch active session list
    const sessions = await apiFetch('/users/sessions');
    sessionsTbody.innerHTML = '';

    if (sessions.length === 0) {
      sessionsTbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Aktif oturum kaydı bulunamadı.</td></tr>';
      return;
    }

    sessions.forEach(sess => {
      const tr = document.createElement('tr');
      const isCurrent = sess.ip_address === 'customer_portal' || sess.ip_address === 'admin_panel'; // Or custom flag

      tr.innerHTML = `
        <td><strong>${sess.ip_address}</strong></td>
        <td><span style="font-size:0.8rem; color:var(--neutral-400);">${sess.user_agent || 'Bilinmeyen İstemci'}</span></td>
        <td>${formatDate(sess.created_at, true)}</td>
        <td>${sess.is_revoked ? '<span class="badge badge-danger">Sonlandırıldı</span>' : '<span class="badge badge-active">Aktif</span>'}</td>
        <td>
          ${sess.is_revoked ? '—' : `<button class="btn btn-danger btn-sm btn-terminate-session" data-id="${sess.id}">Oturumu Kapat</button>`}
        </td>
      `;
      sessionsTbody.appendChild(tr);
    });

    sessionsTbody.querySelectorAll('.btn-terminate-session').forEach(btn => {
      btn.onclick = () => terminateSession(btn.getAttribute('data-id'));
    });

  } catch (err) {
    console.error('Failed to load admin profile sessions:', err);
    profileContainer.innerHTML = '<p class="text-danger">Profil bilgileri yüklenemedi.</p>';
    sessionsTbody.innerHTML = '<tr><td colspan="5" class="text-center text-danger">Oturum listesi yüklenemedi.</td></tr>';
  }
}

async function terminateSession(sessionId) {
  const confirmed = await showConfirm(
    'Oturumu Sonlandırma Onayı',
    'Bu aktif oturumu sonlandırmak istediğinize emin misiniz? İlgili cihaz veya tarayıcı yeniden giriş yapmak zorunda kalacaktır.'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/users/sessions/${sessionId}`, { method: 'DELETE' });
    showToast('Oturum başarıyla sonlandırıldı.', 'success');
    loadAdminProfile();
  } catch (err) {
    showToast(err.message || 'Oturum sonlandırılamadı.', 'error');
  }
}
