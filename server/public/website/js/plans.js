/* ==========================================================================
   SERENUT OS V2 - PLANS & PRICING BINDER
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency } from '/shared/js/formatters.js';

let allPlans = [];
let billingCycle = 'monthly'; // 'monthly' | 'yearly'

document.addEventListener('DOMContentLoaded', () => {
  initPlansPage();
});

async function initPlansPage() {
  const container = document.getElementById('plans-container');
  if (!container) return;

  try {
    container.innerHTML = `
      <div class="loading-container" style="grid-column: 1 / -1;">
        <div class="spinner"></div>
        <p style="color: var(--neutral-400);">Fiyat planları yüklüyor...</p>
      </div>
    `;

    // Fetch dynamic plans list
    allPlans = await apiFetch('/billing/plans');
    
    setupBillingToggle();
    renderPlans();
  } catch (err) {
    console.error('Failed to load plans:', err);
    container.innerHTML = `
      <div class="alert alert-danger" style="grid-column: 1 / -1; width: 100%;">
        Bilinmeyen bir hata nedeniyle planlar yüklenemedi. Lütfen daha sonra tekrar deneyiniz.
      </div>
    `;
  }
}

function setupBillingToggle() {
  const toggle = document.getElementById('billing-toggle');
  const lblMonthly = document.getElementById('lbl-monthly');
  const lblYearly = document.getElementById('lbl-yearly');

  if (!toggle) return;

  const handleToggle = () => {
    billingCycle = toggle.checked ? 'yearly' : 'monthly';
    if (billingCycle === 'yearly') {
      lblYearly.classList.add('active');
      lblMonthly.classList.remove('active');
    } else {
      lblMonthly.classList.add('active');
      lblYearly.classList.remove('active');
    }
    renderPlans();
  };

  toggle.addEventListener('change', handleToggle);
  
  // Label clicks
  lblMonthly.addEventListener('click', () => {
    toggle.checked = false;
    handleToggle();
  });
  lblYearly.addEventListener('click', () => {
    toggle.checked = true;
    handleToggle();
  });
}

function renderPlans() {
  const container = document.getElementById('plans-container');
  if (!container) return;

  container.innerHTML = '';

  allPlans.forEach(plan => {
    // Skip free tier in plans comparison if required, or display all. 
    // Usually, SaaS features display Free, Starter/Basic, Pro/Enterprise.
    const isPro = plan.id.includes('pro');
    let price = Number(plan.price);
    
    // Apply 15% discount for yearly billing cycle
    if (billingCycle === 'yearly') {
      price = price * 12 * 0.85;
    }

    let devicesLimit = '1 Cihaz';
    let storesLimit = '1 Şube';
    let syncOption = 'Senkronizasyon Yok';
    let featureList = [];

    try {
      const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
      if (feats) {
        if (feats.devices !== undefined) {
          devicesLimit = feats.devices > 90 ? 'Sınırsız POS Terminali' : `${feats.devices} POS Terminali`;
        }
        if (feats.stores !== undefined) {
          storesLimit = feats.stores > 90 ? 'Sınırsız Şube' : `${feats.stores} Şube`;
        }
        if (feats.sync === 'realtime') {
          syncOption = 'Anlık Canlı Senkronizasyon';
        } else if (feats.sync === 'delta') {
          syncOption = 'Arka Plan Delta Eşitleme';
        } else {
          syncOption = 'Manuel Aktarım';
        }
        featureList = feats.feature_list || [];
      }
    } catch (_) {}

    const card = document.createElement('div');
    card.className = `card plan-card ${isPro ? 'border-teal' : ''}`;
    
    // Custom highlights
    const proBadge = isPro ? '<div class="badge badge-trial mb-4" style="display:inline-flex; width:auto; font-size:0.75rem; font-weight:700; align-self:flex-start;">En Popüler Seçenek</div>' : '';
    
    card.innerHTML = `
      ${proBadge}
      <h3 class="font-bold mb-1">${plan.name}</h3>
      <p class="text-muted text-sm mb-4" style="min-height: 48px;">${plan.description || 'İşletmenizin dijital otomasyon süreçleri için ideal plan.'}</p>
      
      <div class="plan-price-block">
        ${formatCurrency(price, plan.currency || 'TRY')}
        <span>/ ${billingCycle === 'yearly' ? 'yıl' : 'ay'}</span>
      </div>

      <ul class="plan-features-list">
        <li class="plan-feature-item">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
          <span>${devicesLimit}</span>
        </li>
        <li class="plan-feature-item">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
          <span>${storesLimit}</span>
        </li>
        <li class="plan-feature-item">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
          <span>${syncOption}</span>
        </li>
        ${featureList.map(feat => `
          <li class="plan-feature-item">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>
            <span>${feat}</span>
          </li>
        `).join('')}
      </ul>

      <button class="btn ${isPro ? 'btn-primary' : 'btn-secondary'} w-full mt-6" onclick="selectPlan('${plan.id}')">
        Hemen Başla
      </button>
    `;

    container.appendChild(card);
  });
}

// Attach to window scope for HTML onclick access
window.selectPlan = function(planId) {
  // Store selected plan ID and billing period in session or storage, then redirect to registration
  sessionStorage.setItem('selected_plan_id', planId);
  sessionStorage.setItem('selected_billing_period', billingCycle);
  window.location.href = `/portal/#register`;
};
