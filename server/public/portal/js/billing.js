/* ==========================================================================
   SERENUT OS V2 - PORTAL BILLING MODULE
   ========================================================================== */

import { apiFetch, getAuthToken } from '/shared/js/api-client.js';
import { formatCurrency, formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

let loadedBankAccounts = [];

/**
 * Loads and displays payment invoices lists
 */
export async function loadInvoices() {
  const tbody = document.getElementById('invoices-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Faturalar yükleniyor...</td></tr>';

  try {
    const invoices = await apiFetch('/portal/invoices');
    tbody.innerHTML = '';

    if (invoices.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" class="text-center text-muted">Kayıtlı fatura bulunmamaktadır.</td></tr>';
      return;
    }

    invoices.forEach(inv => {
      const tr = document.createElement('tr');
      const badgeClass = inv.status === 'paid' ? 'badge-active' : 'badge-danger';
      
      tr.innerHTML = `
        <td><strong>${inv.invoice_number || inv.id}</strong></td>
        <td>${formatCurrency(inv.amount)}</td>
        <td>${formatDate(inv.due_at)}</td>
        <td><span class="badge ${badgeClass}">${translateStatus(inv.status)}</span></td>
        <td>
          <button class="btn btn-secondary btn-sm btn-dl-pdf" data-id="${inv.id}" data-num="${inv.invoice_number}">📄 PDF İndir</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    // Bind event listeners for PDF downloads
    tbody.querySelectorAll('.btn-dl-pdf').forEach(btn => {
      btn.onclick = () => {
        downloadInvoicePdf(btn.getAttribute('data-id'), btn.getAttribute('data-num'));
      };
    });

  } catch (err) {
    console.error('Failed to load invoices:', err);
    tbody.innerHTML = '<tr><td colspan="5" class="text-center text-danger">Faturalar yüklenemedi.</td></tr>';
  }
}

/**
 * Initiates file download request for invoice PDF
 */
export async function downloadInvoicePdf(invoiceId, invoiceNumber) {
  try {
    const res = await apiFetch(`/billing/invoices/${invoiceId}/pdf`);
    const blob = await res.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${invoiceNumber || invoiceId}.pdf`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.URL.revokeObjectURL(url);
    showToast('Fatura PDF dosyası indirildi.', 'success');
  } catch (err) {
    console.error(err);
    showToast('Fatura PDF dosyası indirilemedi.', 'error');
  }
}

/**
 * Loads the upgrade plans list dynamically in current subscription panel
 */
export async function loadPlansList() {
  const container = document.getElementById('portal-plans-container');
  if (!container) return;

  container.innerHTML = '<p class="text-muted">Planlar yükleniyor...</p>';

  try {
    const plans = await apiFetch('/billing/plans');
    container.innerHTML = '';

    plans.forEach(p => {
      // Exclude free tier upgrade from portal view
      if (p.id === 'plan-free') return;

      const isPro = p.id === 'plan-pro';
      const card = document.createElement('div');
      card.className = `card ${isPro ? 'border-teal' : ''}`;
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = 'var(--space-3)';
      card.style.position = 'relative';

      const popularBadge = isPro ? '<span class="badge badge-trial" style="position:absolute; top:12px; right:12px;">En Çok Tercih Edilen</span>' : '';

      card.innerHTML = `
        ${popularBadge}
        <h4 class="font-bold">${p.name}</h4>
        <p class="text-muted text-sm" style="flex:1;">${p.description || 'Bulut POS lisans planı.'}</p>
        <div class="font-bold text-light" style="font-size: 1.5rem; margin-block:var(--space-2);">
          ${formatCurrency(p.price)} <span style="font-size:0.8rem; font-weight:normal; color:var(--neutral-400)">/ ay</span>
        </div>
        <button class="btn ${isPro ? 'btn-primary' : 'btn-secondary'} w-full btn-select-plan" data-id="${p.id}">
          Bu Planı Seç
        </button>
      `;
      container.appendChild(card);
    });

    container.querySelectorAll('.btn-select-plan').forEach(btn => {
      btn.onclick = () => {
        initiatePlanPurchase(btn.getAttribute('data-id'));
      };
    });

  } catch (err) {
    console.error(err);
    container.innerHTML = '<p class="text-danger">Planlar yüklenirken hata oluştu.</p>';
  }
}

/**
 * Opens bank transfer modal and loads available accounts targets
 */
export async function initiatePlanPurchase(planId) {
  try {
    const methods = await apiFetch('/billing/payment-methods');
    if (!methods || methods.length === 0) {
      showToast('Aktif ödeme yöntemi bulunmamaktadır.', 'error');
      return;
    }

    if (methods.length === 1 && methods[0].id === 'bank_transfer') {
      // Only bank transfer available, skip selection modal
      openBankTransferModal(planId);
      return;
    }

    // Show selection modal
    const modal = document.getElementById('modal-payment-method');
    const container = document.getElementById('payment-methods-container');
    
    // Bind close
    document.getElementById('btn-payment-method-cancel').onclick = () => {
      modal.classList.remove('active');
    };

    container.innerHTML = '';
    methods.forEach(m => {
      const btn = document.createElement('button');
      btn.className = 'btn btn-secondary w-full';
      btn.style.padding = '15px';
      btn.style.textAlign = 'left';
      btn.innerText = m.display_name;
      btn.onclick = () => {
        modal.classList.remove('active');
        if (m.id === 'bank_transfer') {
          openBankTransferModal(planId);
        } else if (m.id === 'iyzico') {
          initiateIyzicoCheckout(planId);
        }
      };
      container.appendChild(btn);
    });

    modal.classList.add('active');

  } catch (err) {
    console.error('Failed to fetch payment methods', err);
    showToast('Ödeme yöntemleri yüklenemedi.', 'error');
  }
}

async function initiateIyzicoCheckout(planId) {
  const billingPeriod = sessionStorage.getItem('selected_billing_period') || 'monthly';
  try {
    // 1. Backend'den Iyzico HTML checkout formu iste (bunu da ekleyeceğiz veya frontend'de iyzico'ya yonlendiricez)
    const res = await apiFetch('/billing/checkout', {
      method: 'POST',
      body: { plan_id: planId, billing_period: billingPeriod, payment_method: 'iyzico' }
    });
    
    if (res.checkoutContent) {
      // Create a temporary div to render Iyzico script
      const div = document.createElement('div');
      div.innerHTML = res.checkoutContent + '<div id="iyzipay-checkout-form" class="responsive"></div>';
      document.body.appendChild(div);
    } else {
      showToast('Iyzico başlatılamadı.', 'error');
    }
  } catch (err) {
    showToast('Ödeme sistemi hatası', 'error');
  }
}

async function openBankTransferModal(planId) {
  const modal = document.getElementById('modal-bank-transfer');
  if (!modal) return;

  document.getElementById('transfer-plan-id').value = planId;
  document.getElementById('transfer-sender-name').value = '';
  document.getElementById('transfer-sender-bank').value = '';
  document.getElementById('transfer-description').value = '';
  document.getElementById('transfer-error-msg').innerText = '';

  modal.classList.add('active');

  const select = document.getElementById('transfer-bank-account');
  const detailsPreview = document.getElementById('selected-bank-details-preview');

  select.innerHTML = '<option value="">Yükleniyor...</option>';
  detailsPreview.innerHTML = '<div class="spinner"></div>';

  try {
    loadedBankAccounts = await apiFetch('/billing/bank-accounts');
    
    if (loadedBankAccounts.length === 0) {
      select.innerHTML = '<option value="">Aktif banka hesabı bulunamadı</option>';
      detailsPreview.innerText = 'Lütfen daha sonra tekrar deneyiniz.';
      return;
    }

    select.innerHTML = loadedBankAccounts.map(b => `<option value="${b.id}">${b.bank_name} - ${b.account_holder}</option>`).join('');
    updateBankDetailsPreview(loadedBankAccounts[0]);

    select.onchange = () => {
      const selected = loadedBankAccounts.find(b => b.id === select.value);
      if (selected) updateBankDetailsPreview(selected);
    };

  } catch (err) {
    select.innerHTML = '<option value="">Yükleme hatası</option>';
    detailsPreview.innerText = 'Banka hesapları yüklenemedi.';
  }
}

function updateBankDetailsPreview(bank) {
  const preview = document.getElementById('selected-bank-details-preview');
  if (!preview || !bank) return;

  preview.innerHTML = `
    <strong>Alıcı:</strong> ${bank.account_holder}<br>
    <strong>Banka:</strong> ${bank.bank_name}<br>
    <strong>Şube:</strong> ${bank.branch_name || 'Belirtilmedi'}<br>
    <strong>IBAN:</strong> <span style="font-family: monospace; font-weight: bold; color: var(--primary-400);">${bank.iban}</span><br>
    ${bank.instructions ? `<strong>Talimatlar:</strong> ${bank.instructions}` : ''}
  `;
}

/**
 * Handles payment verification notification trigger
 */
export async function submitBankTransferNotification() {
  const planId = document.getElementById('transfer-plan-id').value;
  const bankAccountId = document.getElementById('transfer-bank-account').value;
  const senderName = document.getElementById('transfer-sender-name').value.trim();
  const senderBank = document.getElementById('transfer-sender-bank').value.trim();
  const transferDesc = document.getElementById('transfer-description').value.trim();
  const errorMsg = document.getElementById('transfer-error-msg');
  const submitBtn = document.getElementById('btn-transfer-submit');

  errorMsg.innerText = '';
  if (!bankAccountId) {
    errorMsg.innerText = 'Lütfen alıcı banka hesabını seçin.';
    return;
  }
  if (!senderName || !senderBank) {
    errorMsg.innerText = 'Lütfen yıldızlı (*) zorunlu alanları doldurun.';
    return;
  }

  submitBtn.disabled = true;
  submitBtn.innerText = 'İşleniyor...';

  try {
    // Step 1: Create request bank transfer invoice
    const billingPeriod = sessionStorage.getItem('selected_billing_period') || 'monthly';
    const reqData = await apiFetch('/billing/request-bank-transfer', {
      method: 'POST',
      body: { plan_id: planId, bank_account_id: bankAccountId, billing_period: billingPeriod }
    });

    // Step 2: Notify bank transfer reference to review
    await apiFetch('/billing/notify-transfer', {
      method: 'POST',
      body: {
        invoice_id: reqData.invoice_id,
        sender_name: senderName,
        sender_bank: senderBank,
        transfer_description: transferDesc
      }
    });

    // Close checkout modal
    document.getElementById('modal-bank-transfer').classList.remove('active');

    // Clear session variables after successful request
    sessionStorage.removeItem('selected_plan_id');
    sessionStorage.removeItem('selected_billing_period');

    // Show approval result modal
    document.getElementById('success-reference-code').innerText = reqData.reference_code;
    document.getElementById('success-amount-display').innerText = formatCurrency(reqData.amount, reqData.currency);
    
    const bankObj = reqData.bank || {};
    document.getElementById('success-bank-details').innerHTML = `
      <strong>Banka:</strong> ${bankObj.bank_name}<br>
      <strong>Hesap Sahibi:</strong> ${bankObj.account_holder}<br>
      <strong>IBAN:</strong> <span style="font-family: monospace; font-weight: bold; color: var(--primary-400);">${bankObj.iban}</span><br>
      ${bankObj.instructions ? `<strong>Açıklama:</strong> ${bankObj.instructions}` : ''}
    `;

    document.getElementById('modal-transfer-success').classList.add('active');

    // Refresh views
    loadInvoices();

  } catch (err) {
    errorMsg.innerText = err.message || 'Ödeme talebi oluşturulamadı.';
  } finally {
    submitBtn.disabled = false;
    submitBtn.innerText = 'Talebi Oluştur & Bildir';
  }
}
