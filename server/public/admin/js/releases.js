/* ==========================================================================
   SERENUT OS V2 - ADMIN OTA RELEASES MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadUpdates() {
  const tbody = document.getElementById('updates-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Sürümler yükleniyor...</td></tr>';

  try {
    const updates = await apiFetch('/admin/updates');
    tbody.innerHTML = '';

    if (updates.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Yayınlanmış güncelleme paketi bulunamadı.</td></tr>';
      return;
    }

    updates.forEach(u => {
      const created = formatDate(u.created_at);
      const tr = document.createElement('tr');

      tr.innerHTML = `
        <td><strong>${u.version_code}</strong></td>
        <td><span class="badge badge-trial">${u.platform.toUpperCase()}</span></td>
        <td><a href="${u.download_url}" target="_blank" style="color:var(--info-400); font-weight:600;">Paketi İndir</a></td>
        <td><span style="font-family:monospace; font-size:0.8rem;">${u.sha256_hash.substring(0, 16)}...</span></td>
        <td>${u.is_mandatory ? '<span class="badge badge-danger">Zorunlu</span>' : '<span class="badge badge-active">İsteğe Bağlı</span>'}</td>
        <td>${created}</td>
        <td>
          <button class="btn btn-danger btn-sm btn-delete-update" data-id="${u.id}">Sil</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-delete-update').forEach(btn => {
      btn.onclick = () => {
        deleteUpdate(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error('Failed to load OTA releases logs:', err);
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Güncellemeler listesi yüklenemedi.</td></tr>';
  }
}

async function deleteUpdate(updateId) {
  const confirmed = await showConfirm(
    'Sürüm Silme Onayı',
    'Bu sürüm paketini sistemden kaldırmak istediğinize emin misiniz? Terminaller bu dosyayı indiremeyecektir.'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/updates/${updateId}`, { method: 'DELETE' });
    showToast('Sürüm paketi kaldırıldı.', 'success');
    loadUpdates();
  } catch (err) {
    showToast(err.message || 'Hata oluştu.', 'error');
  }
}

export async function submitCreateUpdate() {
  const version_code = document.getElementById('up-code').value.trim();
  const platform = document.getElementById('up-platform').value;
  const download_url = document.getElementById('up-url').value.trim();
  const sha256_hash = document.getElementById('up-hash').value.trim();
  const is_mandatory = document.getElementById('up-mandatory').checked;
  const release_notes = document.getElementById('up-notes').value.trim();

  if (!version_code || !download_url || !sha256_hash) {
    alert('Lütfen zorunlu tüm alanları doldurun.');
    return false;
  }

  try {
    await apiFetch('/admin/updates', {
      method: 'POST',
      body: { version_code, platform, download_url, sha256_hash, is_mandatory, release_notes }
    });
    showToast('Yeni OTA sürüm paketi yayınlandı.', 'success');
    loadUpdates();
    return true;
  } catch (err) {
    alert(err.message || 'Sürüm yayınlanamadı.');
    return false;
  }
}
