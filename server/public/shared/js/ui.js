/* ==========================================================================
   SERENUT OS V2 - DYNAMIC UI ACTIONS (TOASTS, MODALS, LOADER)
   ========================================================================== */

/**
 * Escapes HTML characters to prevent XSS injections
 * @param {string} str 
 * @returns {string}
 */
export function escapeHTML(str) {
  if (str === null || str === undefined) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Pushes a dynamic animated toast notification
 * @param {string} message 
 * @param {'success'|'warning'|'error'} type 
 * @param {number} duration 
 */
export function showToast(message, type = 'success', duration = 3500) {
  let container = document.querySelector('.toast-container');
  if (!container) {
    container = document.createElement('div');
    container.className = 'toast-container';
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.className = `toast ${type === 'error' ? 'toast-error' : type === 'warning' ? 'toast-warning' : ''}`;
  
  let icon = '✓';
  if (type === 'error') icon = '🚨';
  if (type === 'warning') icon = '⚠️';

  toast.innerHTML = `
    <span class="toast-icon">${icon}</span>
    <span class="toast-msg">${escapeHTML(message)}</span>
  `;

  container.appendChild(toast);

  // Auto remove
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(16px) scale(0.95)';
    setTimeout(() => {
      toast.remove();
      if (container.children.length === 0) {
        container.remove();
      }
    }, 250);
  }, duration);
}

/**
 * Shows a premium styled confirm modal
 * @param {string} title 
 * @param {string} message 
 * @param {string} confirmLabel 
 * @returns {Promise<boolean>}
 */
export function showConfirm(title, message, confirmLabel = 'Evet, Devam Et') {
  return new Promise((resolve) => {
    let overlay = document.getElementById('dynamic-confirm-modal');
    if (overlay) overlay.remove();

    overlay = document.createElement('div');
    overlay.className = 'modal-overlay active';
    overlay.id = 'dynamic-confirm-modal';
    overlay.style.zIndex = '1500'; // Make sure it sits above standard modals

    overlay.innerHTML = `
      <div class="modal-card">
        <div class="modal-header">
          <h3>${escapeHTML(title)}</h3>
          <button class="modal-close" id="confirm-btn-close">&times;</button>
        </div>
        <div class="modal-body">
          <p style="color: var(--neutral-300); font-size: 0.95rem;">${escapeHTML(message)}</p>
        </div>
        <div class="modal-footer">
          <button class="btn btn-secondary" id="confirm-btn-cancel">İptal</button>
          <button class="btn btn-primary" id="confirm-btn-approve">${escapeHTML(confirmLabel)}</button>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    const cleanup = (value) => {
      overlay.classList.remove('active');
      setTimeout(() => overlay.remove(), 200);
      resolve(value);
    };

    document.getElementById('confirm-btn-close').onclick = () => cleanup(false);
    document.getElementById('confirm-btn-cancel').onclick = () => cleanup(false);
    document.getElementById('confirm-btn-approve').onclick = () => cleanup(true);
  });
}

/**
 * Injects a skeleton loading layout or progress spinner in a container
 * @param {HTMLElement} element 
 * @param {number} rowCount 
 */
export function renderSkeleton(element, rowCount = 4) {
  if (!element) return;
  let skeletons = '<div class="loading-container"><div class="spinner"></div><p>Yükleniyor...</p></div>';
  element.innerHTML = skeletons;
}
