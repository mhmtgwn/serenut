/* ==========================================================================
   SERENUT OS V2 - PORTAL SUBSCRIPTION MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency, formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';
import { loadPlansList } from './billing.js';

export async function loadSubscription() {
  const container = document.getElementById('sub-active-details');
  const cancelBtn = document.getElementById('btn-sub-cancel');
  const reactivateBtn = document.getElementById('btn-sub-reactivate');

  if (!container) return;

  container.innerHTML = '<div class="spinner"></div>';
  if (cancelBtn) cancelBtn.style.display = 'none';
  if (reactivateBtn) reactivateBtn.style.display = 'none';

  try {
    const sub = await apiFetch('/billing/subscription');

    if (sub.status === 'no_subscription') {
      container.innerHTML = `
        <div class="alert alert-danger">
          <strong>Aktif Abonelik Bulunmuyor</strong><br>
          Hizmetleri kesintisiz kullanabilmek için lütfen aşağıdaki planlardan birini seçerek ödeme yapınız.
        </div>
      `;
      loadPlansList();
      return;
    }

    const price = Number(sub.plan_price || sub.price || 0);
    const currency = sub.plan_currency || sub.currency || 'TRY';
    const badgeClass = sub.status === 'active' ? 'badge-active' : 'badge-suspended';
    const renewalText = sub.cancel_at_period_end ? 'İptal Edilecek (Dönem Sonu)' : 'Otomatik Yenileniyor';

    container.innerHTML = `
      <div style="display: grid; grid-template-columns: 1fr 1fr; gap: var(--space-4); font-size: 0.95rem;">
        <div><strong>Aktif Plan:</strong> <span class="badge badge-trial">${sub.plan_name}</span></div>
        <div><strong>Abonelik Durumu:</strong> <span class="badge ${badgeClass}">${translateStatus(sub.status)} (${renewalText})</span></div>
        <div><strong>Fiyat Tutar:</strong> ${formatCurrency(price, currency)} / ay</div>
        <div><strong>Dönem Sonu / Yenileme:</strong> ${formatDate(sub.current_period_end)}</div>
        ${sub.cancel_at_period_end ? `<div style="grid-column: span 2; color: var(--warning-500); font-weight: 600; font-size:0.85rem;">⚠️ Aboneliğiniz dönem sonunda sonlanacaktır. İptal kararından vazgeçmek için "Yeniden Etkinleştir" butonunu kullanabilirsiniz.</div>` : ''}
      </div>
    `;

    // Toggle cancellation button states
    if (sub.status === 'active' && !sub.cancel_at_period_end) {
      if (cancelBtn) cancelBtn.style.display = 'inline-flex';
    } else if (sub.cancel_at_period_end || sub.status === 'suspended') {
      if (reactivateBtn) reactivateBtn.style.display = 'inline-flex';
    }

    loadPlansList();
  } catch (err) {
    console.error('Failed to load subscription data:', err);
    container.innerHTML = '<div class="alert alert-danger">Abonelik verileri sunucudan yüklenemedi.</div>';
    loadPlansList();
  }
}

/**
 * Submits post cancel command
 */
export async function submitCancelSubscription(reason, note) {
  try {
    await apiFetch('/billing/cancel', {
      method: 'POST',
      body: { reason: `${reason}: ${note}` }
    });
    showToast('Abonelik iptal talebi iletildi. Dönem sonuna kadar aktif kalacaktır.', 'success');
    loadSubscription();
    return true;
  } catch (err) {
    showToast(err.message || 'Abonelik iptal edilemedi.', 'error');
    return false;
  }
}

/**
 * Submits reactivation command
 */
export async function submitReactivateSubscription() {
  const confirmed = await showConfirm(
    'Abonelik Yeniden Aktifleştirme',
    'Aboneliğinizi tekrar otomatik yenilenen konuma döndürmek istediğinize emin misiniz?'
  );
  if (!confirmed) return;

  try {
    await apiFetch('/billing/reactivate', { method: 'POST' });
    showToast('Aboneliğiniz başarıyla yeniden aktifleştirildi.', 'success');
    loadSubscription();
  } catch (err) {
    showToast(err.message || 'İşlem gerçekleştirilemedi.', 'error');
  }
}
