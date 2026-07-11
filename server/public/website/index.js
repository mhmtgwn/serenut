/* index.js — Corporate Landing Page JavaScript Engine (Fixed IDs) */

document.addEventListener('DOMContentLoaded', () => {
  setupBillingToggle();
  setupFaqAccordions();
  setupCookieConsent();
  trackPageView();
  loadDynamicPrices();
});

// Global state for plan prices retrieved from database
let planPrices = {
  basic: 499,
  pro: 899,
  enterprise: 1699
};

// ── 1. BILLING SWITCH TOGGLE (MONTHLY VS YEARLY) ────────────────────────────
function setupBillingToggle() {
  const toggleSwitch = document.getElementById('billing-cycle-toggle');
  const labelMonthly = document.getElementById('label-monthly');
  const labelYearly = document.getElementById('label-yearly');

  if (!toggleSwitch) return;

  toggleSwitch.addEventListener('change', (e) => {
    const isYearly = e.target.checked;

    if (isYearly) {
      labelYearly.classList.add('active');
      labelMonthly.classList.remove('active');
      
      // Update periods
      document.querySelectorAll('.pricing-card .period').forEach(el => {
        el.innerText = '/yıl (aylık faturalandırılır)';
      });
    } else {
      labelMonthly.classList.add('active');
      labelYearly.classList.remove('active');
      
      // Update periods
      document.querySelectorAll('.pricing-card .period').forEach(el => {
        el.innerText = '/ay';
      });
    }
    updatePriceUI();
  });
}

function updatePriceUI() {
  const toggleSwitch = document.getElementById('billing-cycle-toggle');
  const isYearly = toggleSwitch ? toggleSwitch.checked : false;

  const priceBasic = document.getElementById('price-basic');
  const pricePro = document.getElementById('price-pro');
  const priceEnterprise = document.getElementById('price-enterprise');

  if (priceBasic) {
    priceBasic.innerText = isYearly ? Math.round(planPrices.basic * 0.8) : Math.round(planPrices.basic);
  }
  if (pricePro) {
    pricePro.innerText = isYearly ? Math.round(planPrices.pro * 0.8) : Math.round(planPrices.pro);
  }
  if (priceEnterprise) {
    priceEnterprise.innerText = isYearly ? Math.round(planPrices.enterprise * 0.8) : Math.round(planPrices.enterprise);
  }
}

async function loadDynamicPrices() {
  try {
    const res = await fetch('/api/v1/billing/plans');
    const plans = await res.json();

    const basicPlan = plans.find(p => p.id === 'plan-basic');
    const proPlan = plans.find(p => p.id === 'plan-pro');
    const entPlan = plans.find(p => p.id === 'plan-enterprise');

    function renderFeatures(plan, ulId, defaultDevicesElementId, defaultDevicesText) {
      if (!plan) return;
      const ul = document.getElementById(ulId);
      if (!ul) return;

      const feats = typeof plan.features === 'string' ? JSON.parse(plan.features) : plan.features;
      if (feats && feats.feature_list && Array.isArray(feats.feature_list) && feats.feature_list.length > 0) {
        ul.innerHTML = '';
        feats.feature_list.forEach(feat => {
          const li = document.createElement('li');
          li.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="#10b981" stroke-width="3" style="display:inline-block; vertical-align:middle; margin-right:6px;"><path d="M20 6 9 17l-5-5"/></svg>${feat}`;
          ul.appendChild(li);
        });
      } else {
        const featDevices = document.getElementById(defaultDevicesElementId);
        if (featDevices && feats && feats.devices !== undefined) {
          const devLimitText = feats.devices > 90 ? 'Sınırsız' : feats.devices;
          featDevices.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="#10b981" stroke-width="3" style="display:inline-block; vertical-align:middle; margin-right:6px;"><path d="M20 6 9 17l-5-5"/></svg>${devLimitText} ${defaultDevicesText}`;
        }
      }
    }

    if (basicPlan) {
      planPrices.basic = parseFloat(basicPlan.price);
      renderFeatures(basicPlan, 'features-basic', 'feat-basic-devices', 'POS Terminal Lisansı');
    }
    if (proPlan) {
      planPrices.pro = parseFloat(proPlan.price);
      renderFeatures(proPlan, 'features-pro', 'feat-pro-devices', 'POS Terminal Lisansı');
    }
    if (entPlan) {
      planPrices.enterprise = parseFloat(entPlan.price);
      renderFeatures(entPlan, 'features-enterprise', 'feat-enterprise-devices', 'POS Terminali');
    }

    updatePriceUI();
  } catch (err) {
    console.error('Failed to load dynamic plan prices from server:', err);
  }
}

// ── 2. FAQ ACCORDION TRANSITIONS ─────────────────────────────────────────────
function setupFaqAccordions() {
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach(item => {
    const trigger = item.querySelector('.faq-question');
    if (trigger) {
      trigger.addEventListener('click', () => {
        const isActive = item.classList.contains('active');

        // Close other items
        faqItems.forEach(other => other.classList.remove('active'));

        if (!isActive) {
          item.classList.add('active');
        }
      });
    }
  });
}

// ── 3. COOKIE CONSENT BOX ────────────────────────────────────────────────────
function setupCookieConsent() {
  const consentBar = document.getElementById('cookie-banner');
  const btnAccept = document.getElementById('btn-accept-cookies');

  if (!consentBar || !btnAccept) return;

  const hasAccepted = localStorage.getItem('cookie_consent_accepted');
  if (!hasAccepted) {
    // Show cookie notice after a short delay
    setTimeout(() => {
      consentBar.style.display = 'block';
    }, 1500);
  }

  btnAccept.addEventListener('click', () => {
    localStorage.setItem('cookie_consent_accepted', 'true');
    consentBar.style.display = 'none';
  });
}

// ── 4. ANALYTICS & TELEMETRY MOCKS ──────────────────────────────────────────
function trackPageView() {
  console.log('Serenut OS Web Analytics: Page view tracked. Path=/');
}
