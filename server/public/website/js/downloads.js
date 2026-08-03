const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

document.addEventListener('DOMContentLoaded', async () => {
  const root = document.getElementById('downloads-container');
  if (!root) return;

  function cleanVer(v) {
    if (!v) return '';
    const s = String(v).split('+')[0].trim();
    return s.startsWith('v') ? s : `v${s}`;
  }

  function renderCards(windows, android) {
    const winVer  = windows ? esc(cleanVer(windows.version_code)) : '';
    const apkVer  = android ? esc(cleanVer(android.version_code)) : '';
    const winNote = windows ? esc(windows.release_notes  || 'Masaüstü kurulum paketi.') : 'Masaüstü kurulum paketi.';
    const apkNote = android ? esc(android.release_notes  || 'Android uygulama paketi.') : 'Android uygulama paketi.';
    root.innerHTML = `
      <article class="feature-card">
        <div class="eyebrow">Windows</div>
        <h3>Serenut OS ${winVer}</h3>
        <p>${winNote}</p>
        <a class="btn btn-primary" href="/download/windows" download>İndir</a>
      </article>
      <article class="feature-card">
        <div class="eyebrow">Android APK</div>
        <h3>Serenut OS ${apkVer}</h3>
        <p>${apkNote}</p>
        <a class="btn btn-primary" href="/download/android" download>İndir</a>
      </article>
      <article class="feature-card">
        <div class="eyebrow">Aktivasyon</div>
        <h3>Aktivasyon Akışı</h3>
        <p>Kurulum sonrası lisans, cihaz ve tenant bağlantısı uygulama içindeki cihaz/lisans modülünden yapılır.</p>
        <a class="btn btn-secondary" href="/login">Uygulamaya Gir</a>
      </article>
    `;
  }

  function renderFallback() {
    renderCards(null, null);
  }

  // Primary: /api/v1/releases/history (full release metadata)
  try {
    const res = await fetch('/api/v1/releases/history');
    if (res.ok) {
      const all = await res.json();
      if (Array.isArray(all) && all.length > 0) {
        const seen = new Set();
        const rows = all.filter(r => {
          const p = String(r.platform).toLowerCase();
          if (seen.has(p)) return false;
          seen.add(p);
          return true;
        });
        const windows = rows.find(r => r.platform === 'windows') || null;
        const android = rows.find(r => r.platform === 'android') || null;
        renderCards(windows, android);
        return;
      }
    }
  } catch (_) {}

  // Secondary: /api/v1/updates/latest-metadata (lighter endpoint)
  try {
    const res2 = await fetch('/api/v1/updates/latest-metadata');
    if (res2.ok) {
      const meta = await res2.json();
      if (Array.isArray(meta) && meta.length > 0) {
        const windows = meta.find(r => r.platform === 'windows') || null;
        const android = meta.find(r => r.platform === 'android') || null;
        renderCards(windows, android);
        return;
      }
    }
  } catch (_) {}

  renderFallback();
});
