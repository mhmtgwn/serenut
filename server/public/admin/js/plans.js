/* ==========================================================================
   SERENUT OS V2 - ADMIN PLANS MANAGEMENT MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

let cachedPlans = [];

export async function loadPlans() {
  const tbody = document.getElementById('plans-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Planlar yükleniyor...</td></tr>';

  try {
    // Admin billing plans route is /billing/plans
    cachedPlans = await apiFetch('/billing/plans');
    tbody.innerHTML = '';

    if (cachedPlans.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Kayıtlı plan bulunamadı.</td></tr>';
      return;
    }

    cachedPlans.forEach(plan => {
      let devicesLimit = 'Sınırsız';
      try {
        const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
        if (feats && feats.devices !== undefined) {
          devicesLimit = feats.devices > 90 ? 'Sınırsız' : `${feats.devices} Cihaz`;
        }
      } catch (_) {}

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${plan.id}</strong></td>
        <td>${plan.name}</td>
        <td>${formatCurrency(plan.price, plan.currency || 'TRY')}</td>
        <td>${plan.currency || 'TRY'}</td>
        <td>${devicesLimit}</td>
        <td class="text-right">
          <button class="btn btn-secondary btn-sm btn-edit-plan" data-id="${plan.id}">Düzenle</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-edit-plan').forEach(btn => {
      btn.onclick = () => {
        openEditPlanModal(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error('Failed to load plans:', err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Planlar listelenemedi.</td></tr>';
  }
}

function openEditPlanModal(planId) {
  const plan = cachedPlans.find(p => p.id === planId);
  if (!plan) return;

  document.getElementById('edit-plan-id').value = plan.id;
  document.getElementById('edit-plan-name').value = plan.name;
  document.getElementById('edit-plan-price').value = plan.price;
  document.getElementById('edit-plan-currency').value = plan.currency || 'TRY';
  document.getElementById('edit-plan-interval').value = plan.billing_interval || 'monthly';
  
  let devices = 1;
  let stores = 1;
  let sync = 'realtime';
  let analytics = 'standard';
  let featureList = [];

  try {
    const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
    if (feats) {
      if (feats.devices !== undefined) devices = feats.devices;
      if (feats.stores !== undefined) stores = feats.stores;
      if (feats.sync !== undefined) sync = feats.sync;
      if (feats.analytics !== undefined) analytics = feats.analytics;
      if (feats.feature_list !== undefined) featureList = feats.feature_list;
    }
  } catch (_) {}

  document.getElementById('edit-plan-devices').value = devices;
  document.getElementById('edit-plan-stores').value = stores;
  document.getElementById('edit-plan-sync').value = sync;
  document.getElementById('edit-plan-analytics').value = analytics;
  document.getElementById('edit-plan-features-list').value = Array.isArray(featureList) ? featureList.join('\n') : '';

  document.getElementById('modal-plan').classList.add('active');
}

export async function savePlanDetails() {
  const id = document.getElementById('edit-plan-id').value;
  const name = document.getElementById('edit-plan-name').value.trim();
  const price = parseFloat(document.getElementById('edit-plan-price').value);
  const currency = document.getElementById('edit-plan-currency').value;
  const billing_interval = document.getElementById('edit-plan-interval').value;
  const devices = parseInt(document.getElementById('edit-plan-devices').value, 10);
  const stores = parseInt(document.getElementById('edit-plan-stores').value, 10);
  const sync = document.getElementById('edit-plan-sync').value;
  const analytics = document.getElementById('edit-plan-analytics').value;
  const featuresText = document.getElementById('edit-plan-features-list').value;

  if (!name || isNaN(price) || isNaN(devices) || isNaN(stores) || !sync || !analytics) {
    alert('Lütfen tüm zorunlu alanları doğru şekilde doldurun.');
    return;
  }

  const feature_list = featuresText
    .split('\n')
    .map(line => line.trim())
    .filter(line => line.length > 0);

  const features = {
    devices,
    stores,
    sync,
    analytics,
    feature_list
  };

  try {
    await apiFetch(`/billing/plans/${id}`, {
      method: 'PUT',
      body: {
        name,
        price,
        currency,
        billing_interval,
        features
      }
    });

    document.getElementById('modal-plan').classList.remove('active');
    showToast('Plan detayları başarıyla kaydedildi.', 'success');
    loadPlans();
  } catch (err) {
    alert(err.message || 'Plan güncellenemedi.');
  }
}
