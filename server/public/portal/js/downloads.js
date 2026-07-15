/* ==========================================================================
   SERENUT OS V2 - PORTAL SECURE DOWNLOADS MODULE
   ========================================================================== */

import { apiFetch, getAuthToken } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

export async function loadDownloads() {
  const container = document.getElementById('portal-downloads-grid');
  if (!container) return;

  container.innerHTML = '<p class="text-muted">İndirilebilir paketler yükleniyor...</p>';

  try {
    const history = await apiFetch('/releases/history');
    container.innerHTML = '';

    if (history.length === 0) {
      container.innerHTML = '<p class="text-muted" style="text-align:center; grid-column: 1 / -1;">Yayınlanmış terminal paketi bulunamadı.</p>';
      return;
    }

    history.forEach(rel => {
      const card = document.createElement('div');
      const pendingReleaseId = sessionStorage.getItem('pending_download_release_id');
      card.className = `card ${pendingReleaseId === rel.id ? 'border-teal' : ''}`;
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = 'var(--space-3)';

      const isAndroid = String(rel.platform).toLowerCase() === 'android';
      const badgeClass = isAndroid ? 'badge-trial' : 'badge-active';
      const platformLabel = isAndroid ? '📱 Android APK' : '💻 Windows Desktop';

      card.innerHTML = `
        <div class="flex justify-between items-center gap-2">
          <span class="badge ${badgeClass}">${platformLabel}</span>
          <span class="text-muted text-xs">${formatDate(rel.created_at)}</span>
        </div>
        <h4 class="font-bold">Sürüm ${rel.version_code}</h4>
        <p class="text-muted text-xs" style="flex:1;">
          ${rel.release_notes ? rel.release_notes.replace(/\n/g, '<br>') : 'Kararlılık iyileştirmeleri ve hata düzeltmeleri.'}
        </p>
        ${pendingReleaseId === rel.id ? '<div class="badge badge-trial">Son seçtiğiniz indirme</div>' : ''}
        <button class="btn btn-primary btn-sm btn-download-release w-full mt-2" data-id="${rel.id}">
          Güvenli İndir
        </button>
      `;
      container.appendChild(card);
    });

    container.querySelectorAll('.btn-download-release').forEach(btn => {
      btn.onclick = () => {
        downloadRelease(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error('Failed to load secure releases:', err);
    container.innerHTML = '<p class="text-danger">İndirme listesi yüklenemedi.</p>';
  }
}

async function downloadRelease(releaseId) {
  const token = getAuthToken();
  if (!token) {
    showToast('Oturum anahtarı bulunamadı.', 'error');
    return;
  }
  
  const btn = document.querySelector(`.btn-download-release[data-id="${releaseId}"]`);
  let originalText = '';
  if (btn) {
    originalText = btn.innerText;
    btn.innerText = 'İndiriliyor...';
    btn.disabled = true;
  }

  try {
    const response = await fetch(`/api/v1/releases/download/${releaseId}`, {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });

    if (!response.ok) {
      const errorJson = await response.json().catch(() => ({}));
      throw new Error(errorJson.message || errorJson.error || `HTTP Hata: ${response.status}`);
    }

    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    
    const disposition = response.headers.get('content-disposition');
    let filename = `serenut-release-${releaseId}`;
    if (disposition && disposition.indexOf('attachment') !== -1) {
      const filenameRegex = /filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/;
      const matches = filenameRegex.exec(disposition);
      if (matches != null && matches[1]) { 
        filename = matches[1].replace(/['"]/g, '');
      }
    }
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    window.URL.revokeObjectURL(url);
    a.remove();
    sessionStorage.removeItem('pending_download_release_id');
    showToast('İndirme tamamlandı.', 'success');
  } catch (err) {
    console.error('Download failed:', err);
    showToast(`İndirme başarısız: ${err.message}`, 'error');
  } finally {
    if (btn) {
      btn.innerText = originalText;
      btn.disabled = false;
    }
  }
}
