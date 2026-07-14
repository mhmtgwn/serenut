/* ==========================================================================
   SERENUT OS V2 - PORTAL STORES MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

export async function loadStores() {
  const tbody = document.getElementById('stores-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Şubeler yükleniyor...</td></tr>';

  try {
    const stores = await apiFetch('/portal/stores');
    tbody.innerHTML = '';

    if (stores.length === 0) {
      tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted">Kayıtlı şube bulunamadı.</td></tr>';
      return;
    }

    stores.forEach(store => {
      const tr = document.createElement('tr');
      const badgeClass = store.status === 'inactive' ? 'badge-danger' : 'badge-active';

      tr.innerHTML = `
        <td><strong>${store.name}</strong></td>
        <td>${store.address || '—'}</td>
        <td><span class="badge ${badgeClass}">${translateStatus(store.status || 'active')}</span></td>
        <td>${formatDate(store.created_at)}</td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load stores:', err);
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-danger">Şubeler listelenemedi.</td></tr>';
  }
}

export async function submitCreateStore() {
  const name = document.getElementById('store-name').value.trim();
  const address = document.getElementById('store-address').value.trim();

  if (!name) {
    alert('Şube adı zorunludur.');
    return false;
  }

  try {
    await apiFetch('/portal/stores', {
      method: 'POST',
      body: { name, address }
    });
    showToast('Yeni şube başarıyla kaydedildi.', 'success');
    loadStores();
    return true;
  } catch (err) {
    alert(err.message || 'Şube kaydedilemedi.');
    return false;
  }
}
