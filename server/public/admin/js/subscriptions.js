/* ==========================================================================
   SERENUT OS V2 - ADMIN SUBSCRIPTIONS & INTEL MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency, formatDate, translateStatus } from '/shared/js/formatters.js';
import { loadPendingTransfers } from './transfers.js';

export async function loadSubscriptionsIntel() {
  try {
    // 1. Load pending bank transfers checklist
    await loadPendingTransfers();

    // 2. Fetch MRR, ARR, and Churn Intel
    const intel = await apiFetch('/admin/billing/intel');

    document.getElementById('mrr-val').innerText = formatCurrency(intel.mrr || 0);
    document.getElementById('arr-val').innerText = formatCurrency(intel.arr || 0);
    document.getElementById('churn-val').innerText = `% ${intel.churnRate || '0.0'}`;
    document.getElementById('risk-val').innerText = (intel.riskList || []).length || 0;

    // 3. Render Churn Risk companies list
    const tbody = document.getElementById('risk-table-body');
    if (tbody) {
      tbody.innerHTML = '';
      const list = intel.riskList || [];

      if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Ödeme riski taşıyan şirket bulunmamaktadır.</td></tr>';
        return;
      }

      list.forEach(comp => {
        const tr = document.createElement('tr');
        const badgeClass = comp.subscription_status === 'suspended' ? 'badge-danger' : 'badge-warning';

        tr.innerHTML = `
          <td><strong>${comp.id}</strong></td>
          <td>${comp.name}</td>
          <td>${comp.email || '—'}</td>
          <td><span class="badge ${badgeClass}">${translateStatus(comp.subscription_status)}</span></td>
          <td>${formatDate(comp.grace_period_until)}</td>
          <td>${comp.unpaid_invoices_count || 1} Adet</td>
          <td class="text-red font-bold">${formatCurrency(comp.unpaid_amount || 0)}</td>
        `;
        tbody.appendChild(tr);
      });
    }

  } catch (err) {
    console.error('Failed to load subscriptions commercial intelligence:', err);
  }
}

// Register global refresh event listener to break circular dependency
document.addEventListener('admin-subscription-refresh', () => {
  loadSubscriptionsIntel().catch(err => console.error('Refresh event failed:', err));
});
