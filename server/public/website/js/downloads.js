const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

document.addEventListener('DOMContentLoaded', async () => {
  const root = document.getElementById('downloads-container');
  if (!root) return;

  function renderFallback() {
    root.innerHTML = `
      <article class="feature-card">
        <div class="eyebrow">Windows</div>
        <h3>Serenut OS v1.1.9</h3>
        <p>Masaüstü kurulum paketi. WebSocket kararlılığı, otomatik yeniden bağlanma ve telemetri kayıtları.</p>
        <a class="btn btn-primary" href="/api/v1/updates/download/windows/latest" download>Paketi İndir</a>
      </article>
      <article class="feature-card">
        <div class="eyebrow">Android APK</div>
        <h3>Serenut OS v1.1.9</h3>
        <p>Mobil ve kiosk cihazlar için Android uygulama paketi. Otomatik senkronizasyon ve çevrimdışı mod desteği.</p>
        <a class="btn btn-primary" href="/api/v1/updates/download/android/latest" download>Paketi İndir</a>
      </article>
    `;
  }

  try {
    const res = await fetch('/api/v1/releases/history');
    if (!res.ok) {
      renderFallback();
      return;
    }
    const all = await res.json();
    if (!Array.isArray(all) || all.length === 0) {
      renderFallback();
      return;
    }

    const seen = new Set();
    const rows = all.filter(r => {
      const p = String(r.platform).toLowerCase();
      if (seen.has(p)) return false;
      seen.add(p);
      return true;
    });

    root.innerHTML = rows.map(r => {
      const platformKey = String(r.platform).toLowerCase();
      const platformLabel = platformKey === 'android' ? 'Android APK' : 'Windows';
      const downloadUrl = `/api/v1/updates/download/${encodeURIComponent(platformKey)}/latest`;
      const isAvailable = r.is_available !== false; // Default to true if not explicitly false

      return `
        <article class="feature-card">
          <div class="eyebrow">${esc(platformLabel)}</div>
          <h3>Serenut OS ${esc(r.version_code)}</h3>
          <p>${esc(r.release_notes || 'Kararlılık ve performans güncellemeleri.')}</p>
          <a class="btn btn-primary" href="${downloadUrl}" download>Paketi İndir</a>
        </article>
      `;
    }).join('');
  } catch (_) {
    renderFallback();
  }
});

