/* ==========================================================================
   SERENUT OS V2 - DOWNLOADS BINDER
   ========================================================================== */

import { apiFetch, getAuthToken } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';

document.addEventListener('DOMContentLoaded', () => {
  initDownloadsPage();
});

async function initDownloadsPage() {
  const container = document.getElementById('releases-history-container');
  if (!container) return;

  try {
    container.innerHTML = `
      <div class="loading-container" style="grid-column: 1 / -1;">
        <div class="spinner"></div>
        <p style="color: var(--neutral-400);">Yazılım sürümleri yükleniyor...</p>
      </div>
    `;

    // Fetch public release history
    const history = await apiFetch('/releases/history');

    if (history.length === 0) {
      container.innerHTML = `
        <div class="empty-state" style="grid-column: 1 / -1;">
          <div class="empty-state-icon">📂</div>
          <div class="empty-state-title">Sürüm Bulunamadı</div>
          <div class="empty-state-desc">Sistemde yayınlanmış güncel bir yazılım paketi bulunmamaktadır.</div>
        </div>
      `;
      return;
    }

    container.innerHTML = '';
    history.forEach(rel => {
      const card = document.createElement('div');
      card.className = 'card';
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = 'var(--space-4)';
      
      const isAndroid = String(rel.platform).toLowerCase() === 'android';
      const badgeClass = isAndroid ? 'badge-trial' : 'badge-active';
      const badgeLabel = isAndroid ? '📱 Android APK' : '💻 Windows Desktop';

      card.innerHTML = `
        <div class="flex justify-between items-center flex-wrap gap-2">
          <span class="badge ${badgeClass}">${badgeLabel}</span>
          <span class="text-muted text-sm">${formatDate(rel.created_at)}</span>
        </div>
        <h3 class="font-bold">Serenut OS Sürüm ${rel.version_code}</h3>
        <p class="text-muted text-sm" style="flex:1;">
          ${rel.release_notes ? rel.release_notes.replace(/\n/g, '<br>') : 'Hata gidermeleri ve performans optimizasyonları içerir.'}
        </p>
        <button class="btn btn-primary w-full mt-2" onclick="handleDownloadRequest('${rel.id}')">
          İndir ve Yükle
        </button>
      `;
      container.appendChild(card);
    });

  } catch (err) {
    console.error('Failed to load releases history:', err);
    container.innerHTML = `
      <div class="alert alert-danger" style="grid-column: 1 / -1; width: 100%;">
        Sunucu bağlantı hatası nedeniyle sürüm listesi yüklenemedi.
      </div>
    `;
  }
}

// Window scope download click check
window.handleDownloadRequest = async function(releaseId) {
  const token = getAuthToken();
  if (!token) {
    alert('Yazılım paketi indirmek için müşteri hesabınıza giriş yapmış olmanız ve aktif bir lisansınızın bulunması gerekmektedir. Giriş sayfasına yönlendiriliyorsunuz.');
    window.location.href = '/portal/';
  } else {
    const btn = document.querySelector(`button[onclick*="${releaseId}"]`);
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
    } catch (err) {
      console.error('Download failed:', err);
      alert(`İndirme başarısız: ${err.message}`);
    } finally {
      if (btn) {
        btn.innerText = originalText;
        btn.disabled = false;
      }
    }
  }
};
