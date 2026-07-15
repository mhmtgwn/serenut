/* ==========================================================================
   SERENUT OS V2 - PAYMENT METHODS ADMIN MODULE
   ========================================================================== */

import { apiFetch } from '/admin/js/api-client.js';
import { showToast } from '/shared/js/ui.js';

let providers = [];

export async function initPaymentMethods() {
  await loadPaymentMethods();
}

async function loadPaymentMethods() {
  const grid = document.getElementById('payment-methods-grid');
  if (!grid) return;
  
  grid.innerHTML = '<p class="text-muted">Yükleniyor...</p>';

  try {
    providers = await apiFetch('/admin/payment-methods');
    renderProviders(grid);
  } catch (err) {
    console.error(err);
    grid.innerHTML = '<p class="text-danger">Yüklenirken hata oluştu.</p>';
  }
}

function renderProviders(grid) {
  grid.innerHTML = '';
  providers.forEach(p => {
    const card = document.createElement('div');
    card.className = `card ${p.is_enabled ? 'border-teal' : 'border-red'}`;
    card.innerHTML = `
      <div class="flex justify-between items-center mb-2">
        <h4 class="font-bold">${p.display_name}</h4>
        <span class="badge ${p.is_enabled ? 'badge-active' : 'badge-danger'}">${p.is_enabled ? 'Aktif' : 'Pasif'}</span>
      </div>
      <p class="text-sm text-muted mb-4">Son Test: ${p.last_test_at ? new Date(p.last_test_at).toLocaleString() : 'Test Edilmedi'}</p>
      ${p.last_error ? `<p class="text-xs text-red mb-2">Hata: ${p.last_error}</p>` : ''}
      <div class="flex gap-2">
        <button class="btn btn-secondary btn-sm flex-1 btn-edit" data-id="${p.id}">Ayar & Test</button>
      </div>
    `;
    grid.appendChild(card);
  });

  grid.querySelectorAll('.btn-edit').forEach(btn => {
    btn.onclick = () => openProviderModal(btn.getAttribute('data-id'));
  });
}

function openProviderModal(id) {
  const p = providers.find(x => x.id === id);
  if (!p) return;

  // For simplicity, we just use sweetalert2 or standard prompt for now, 
  // since building a full modal dynamically without existing html is complex.
  // We can use sweetalert2 here.
  const isIyzico = id === 'iyzico';
  
  let html = `<div style="text-align: left; font-size: 0.9rem;">
    <div class="form-group mb-3">
      <label>Aktif Mi?</label>
      <select id="pm-enabled" class="swal2-select" style="display:flex; width:100%; margin:0;">
        <option value="true" ${p.is_enabled ? 'selected' : ''}>Aktif</option>
        <option value="false" ${!p.is_enabled ? 'selected' : ''}>Pasif</option>
      </select>
    </div>
  `;

  if (isIyzico) {
    html += `
      <div class="form-group mb-3">
        <label>API Key</label>
        <input type="text" id="pm-api-key" class="swal2-input" value="${p.secrets.iyzico_api_key || ''}" style="margin:0; width:100%; font-size:14px;">
      </div>
      <div class="form-group mb-3">
        <label>Secret Key</label>
        <input type="password" id="pm-secret-key" class="swal2-input" placeholder="Gizli (değiştirmek için yazın)" style="margin:0; width:100%; font-size:14px;">
      </div>
      <div class="form-group mb-3">
        <label>Base URL</label>
        <input type="text" id="pm-base-url" class="swal2-input" value="${p.config.iyzico_base_url || 'https://sandbox-api.iyzipay.com'}" style="margin:0; width:100%; font-size:14px;">
      </div>
    `;
  }

  html += `</div>`;

  Swal.fire({
    title: `${p.display_name} Ayarları`,
    html: html,
    showCancelButton: true,
    showDenyButton: true,
    confirmButtonText: 'Kaydet',
    denyButtonText: 'Bağlantı Testi Yap',
    cancelButtonText: 'İptal',
    preConfirm: () => {
      const isEnabled = document.getElementById('pm-enabled').value === 'true';
      const payload = { is_enabled: isEnabled, config: {}, secrets: {} };
      if (isIyzico) {
        payload.config.iyzico_base_url = document.getElementById('pm-base-url').value;
        const ak = document.getElementById('pm-api-key').value;
        const sk = document.getElementById('pm-secret-key').value;
        if (ak) payload.secrets.iyzico_api_key = ak;
        if (sk) payload.secrets.iyzico_secret_key = sk;
      }
      return apiFetch(`/admin/payment-methods/${id}`, { method: 'PUT', body: payload })
        .catch(error => {
          Swal.showValidationMessage(`Request failed: ${error}`);
        });
    }
  }).then((result) => {
    if (result.isConfirmed) {
      showToast('Ayarlar kaydedildi.', 'success');
      loadPaymentMethods();
    } else if (result.isDenied) {
      // Test Connection
      Swal.fire({
        title: 'Test Ediliyor...',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
      });
      apiFetch(`/admin/payment-methods/${id}/test`, { method: 'POST' })
        .then(res => {
          if (res.success) {
            Swal.fire('Başarılı!', 'Bağlantı testi başarılı.', 'success');
          } else {
            Swal.fire('Hata!', res.message || 'Bağlantı testi başarısız.', 'error');
          }
          loadPaymentMethods();
        }).catch(err => {
          Swal.fire('Hata!', 'Test işlemi sırasında sunucu hatası oluştu.', 'error');
          loadPaymentMethods();
        });
    }
  });
}
