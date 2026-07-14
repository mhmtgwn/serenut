/* ==========================================================================
   SERENUT OS V2 - ADMIN PENDING BANK TRANSFERS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatCurrency, formatDate } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadPendingTransfers() {
  const tbody = document.getElementById('transfers-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Bekleyen onaylar yükleniyor...</td></tr>';

  try {
    const list = await apiFetch('/billing/admin/pending-transfers');
    tbody.innerHTML = '';

    if (list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Bekleyen havale onay talebi bulunamadı.</td></tr>';
      return;
    }

    list.forEach(item => {
      const tr = document.createElement('tr');
      const created = formatDate(item.created_at, true);

      tr.innerHTML = `
        <td><strong class="text-cyan">${item.reference_code}</strong></td>
        <td>${item.company_name}</td>
        <td>${item.sender_name || '—'}</td>
        <td>${item.sender_bank || '—'}</td>
        <td>${item.invoice_number || item.invoice_id}</td>
        <td class="text-green font-bold">${formatCurrency(item.amount)}</td>
        <td>${created}</td>
        <td class="text-right">
          <button class="btn btn-primary btn-sm btn-approve-transfer" data-id="${item.invoice_id}">Onayla</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-approve-transfer').forEach(btn => {
      btn.onclick = () => {
        approveBankTransfer(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error('Failed to load pending bank wires:', err);
    tbody.innerHTML = '<tr><td colspan="8" class="text-center text-danger">Onay listesi yüklenemedi.</td></tr>';
  }
}

async function approveBankTransfer(invoiceId) {
  const confirmed = await showConfirm(
    'Havale Onaylama',
    'Bu havale ödemesini onaylamak ve ilişkili aboneliği aktifleştirmek istediğinize emin misiniz?'
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/billing/admin/invoices/${invoiceId}/approve-payment`, {
      method: 'PUT'
    });
    showToast('Havale onaylandı, ilgili abonelik aktif konuma getirildi.', 'success');
    
    // Dispatch refresh event to break circular dependency
    document.dispatchEvent(new CustomEvent('admin-subscription-refresh'));
  } catch (err) {
    showToast(err.message || 'Ödeme onaylanamadı.', 'error');
  }
}
