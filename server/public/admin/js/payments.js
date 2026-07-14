/* ==========================================================================
   SERENUT OS V2 - ADMIN PAYMENTS LOGS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency, formatDate, translateStatus } from '/shared/js/formatters.js';

export async function loadPaymentsLog() {
  const tbody = document.getElementById('payments-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Ödemeler yükleniyor...</td></tr>';

  try {
    const data = await apiFetch('/admin/billing/intel');
    const atRisk = data.riskList || [];
    tbody.innerHTML = '';

    if (atRisk.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Son ödeme kaydı bulunamadı.</td></tr>';
      return;
    }

    // Display invoices debt details
    atRisk.forEach(item => {
      const tr = document.createElement('tr');
      const badgeClass = item.unpaid_invoices_count > 0 ? 'badge-danger' : 'badge-active';

      tr.innerHTML = `
        <td><strong>${item.id}</strong></td>
        <td>${item.name}</td>
        <td>${item.email || '—'}</td>
        <td>${item.unpaid_invoices_count} Adet</td>
        <td class="font-bold text-red">${formatCurrency(item.unpaid_amount || 0)}</td>
        <td><span class="badge ${badgeClass}">${item.unpaid_invoices_count > 0 ? 'Borçlu' : 'Ödendi'}</span></td>
      `;
      tbody.appendChild(tr);
    });

  } catch (err) {
    console.error('Failed to load payments logs:', err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Ödemeler listesi yüklenemedi.</td></tr>';
  }
}
