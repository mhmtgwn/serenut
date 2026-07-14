/* ==========================================================================
   SERENUT OS V2 - ADMIN COMPANIES MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus, formatCurrency } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

export async function loadCompanies() {
  const tbody = document.getElementById('company-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Şirketler yükleniyor...</td></tr>';

  try {
    const companies = await apiFetch('/admin/companies');
    tbody.innerHTML = '';

    if (companies.length === 0) {
      tbody.innerHTML = '<tr><td colspan="8" class="text-center text-muted">Kayıtlı şirket bulunmamaktadır.</td></tr>';
      return;
    }

    companies.forEach(comp => {
      const tr = document.createElement('tr');
      const badgeClass = comp.status === 'active' ? 'badge-active' : 'badge-danger';

      tr.innerHTML = `
        <td><strong>${comp.id}</strong></td>
        <td>${comp.name}</td>
        <td>${comp.tax_number} / ${comp.tax_office || "—"}</td>
        <td>${comp.phone || "—"} <br> <span style="font-size:0.8rem; color:var(--neutral-400);">${comp.email || "—"}</span></td>
        <td>${comp.store_count} Mağaza</td>
        <td>${comp.device_count} Terminal</td>
        <td><span class="badge ${badgeClass}">${translateStatus(comp.status)}</span></td>
        <td>
          <button class="btn btn-secondary btn-sm btn-comp-details" data-id="${comp.id}">Detay</button>
          <button class="btn btn-danger btn-sm btn-comp-toggle" data-id="${comp.id}" data-status="${comp.status}">
            ${comp.status === 'active' ? 'Askıya Al' : 'Aktifleştir'}
          </button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    // Bind event handlers dynamically
    tbody.querySelectorAll('.btn-comp-details').forEach(btn => {
      btn.onclick = () => viewCompanyDetails(btn.getAttribute('data-id'));
    });
    tbody.querySelectorAll('.btn-comp-toggle').forEach(btn => {
      btn.onclick = () => toggleCompanyStatus(btn.getAttribute('data-id'), btn.getAttribute('data-status'));
    });

  } catch (err) {
    console.error('Failed to load companies:', err);
    tbody.innerHTML = '<tr><td colspan="8" class="text-center text-danger">Şirketler listesi yüklenemedi.</td></tr>';
  }
}

async function viewCompanyDetails(companyId) {
  try {
    const details = await apiFetch(`/admin/companies/${companyId}`);
    
    const formatted = `
🏢 ŞİRKET BİLGİLERİ:
  ID: ${details.company.id}
  Ünvan: ${details.company.name}
  Vergi No / Dairesi: ${details.company.tax_number} / ${details.company.tax_office || '—'}
  Durum: ${translateStatus(details.company.status)}
  E-posta / Telefon: ${details.company.email || '—'} / ${details.company.phone || '—'}
  Oluşturulma Tarihi: ${formatDate(details.company.created_at)}

🏪 MAĞAZALAR (${details.stores.length}):
${details.stores.map(s => `  - [${s.id}] ${s.name} (${s.address || 'Adres belirtilmemiş'})`).join('\n')}

💻 AKTİF POS CİHAZLARI (${details.devices.length}):
${details.devices.map(d => `  - [${d.id}] ${d.name} (${translateStatus(d.status)}) - Son Görülme: ${formatDate(d.last_active_at, true)}`).join('\n')}

🔑 LİSANSLAR (${details.licenses.length}):
${details.licenses.map(l => `  - ${l.license_key} [Paket: ${String(l.tier).toUpperCase()}] - Durum: ${translateStatus(l.status)} - Geçerlilik: ${formatDate(l.expires_at)}`).join('\n')}

👥 KULLANICILAR (${details.users.length}):
${details.users.map(u => `  - ${u.name} (${u.email}) - Durum: ${u.is_active ? 'Aktif' : 'Pasif'}`).join('\n')}

🧾 FATURALAR (${details.invoices.length}):
${details.invoices.map(i => `  - No: ${i.id} - Tutar: ${formatCurrency(i.amount)} - Ödeme: ${translateStatus(i.status)}`).join('\n')}
    `;

    openTextViewer('Şirket Entegrasyon Detayları', formatted);
  } catch (err) {
    showToast('Şirket detayları yüklenemedi.', 'error');
  }
}

async function toggleCompanyStatus(companyId, currentStatus) {
  const isSuspending = currentStatus === 'active';
  const nextStatus = isSuspending ? 'suspended' : 'active';
  
  const confirmed = await showConfirm(
    isSuspending ? 'Şirketi Askıya Alma Onayı' : 'Şirketi Aktifleştirme Onayı',
    isSuspending 
      ? `[${companyId}] ID'li şirketi askıya almak istediğinize emin misiniz? Bu işlem şirkete bağlı tüm kullanıcıların girişini donduracak, senkronizasyonu durduracak ve POS terminallerini kilitleyecektir.`
      : `[${companyId}] ID'li şirketi yeniden aktifleştirmek istediğinize emin misiniz? Bu işlem terminal bağlantılarını ve oturum girişlerini normale döndürecektir.`
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/admin/companies/${companyId}`, {
      method: 'PUT',
      body: { status: nextStatus }
    });
    showToast(`Şirket durumu '${translateStatus(nextStatus)}' olarak güncellendi.`, 'success');
    loadCompanies();
  } catch (err) {
    showToast(err.message || 'Durum güncellenemedi.', 'error');
  }
}

export async function submitCreateCompany() {
  const name = document.getElementById('comp-name').value.trim();
  const tax_number = document.getElementById('comp-tax').value.trim();
  const tax_office = document.getElementById('comp-tax-office').value.trim();
  const phone = document.getElementById('comp-phone').value.trim();
  const email = document.getElementById('comp-email').value.trim();
  const address = document.getElementById('comp-address').value.trim();

  if (!name || !tax_number) {
    alert('Firma adı ve vergi numarası zorunludur.');
    return false;
  }

  try {
    const payload = await apiFetch('/admin/companies', {
      method: 'POST',
      body: { name, tax_number, tax_office, phone, email, address }
    });

    alert(`Firma başarıyla oluşturuldu!\nİlk POS Deneme Lisans Anahtarı: ${payload.license_key}`);
    loadCompanies();
    return true;
  } catch (err) {
    alert(err.message || 'Şirket kaydı başarısız.');
    return false;
  }
}

function openTextViewer(title, content) {
  document.getElementById('viewer-title').innerText = title;
  document.getElementById('viewer-content').innerText = content;
  document.getElementById('modal-viewer').classList.add('active');
}
