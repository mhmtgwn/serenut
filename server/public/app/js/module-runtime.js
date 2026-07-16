import { apiFetch } from '/shared/js/api-client.js';

const esc = (v = '') => String(v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date = v => v ? new Intl.DateTimeFormat('tr-TR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(v)) : '—';
const money = (v, c = 'TRY') => new Intl.NumberFormat('tr-TR', { style: 'currency', currency: c }).format(Number(v || 0));
const badge = v => `<span class="status-badge status-${esc(String(v || 'unknown').toLowerCase())}">${esc(v || '—')}</span>`;
const metric = (label, value) => `<article class="metric-card"><span>${esc(label)}</span><strong>${esc(value)}</strong></article>`;

function table(columns, rows) {
  if (!Array.isArray(rows) || !rows.length) return '<div class="state-panel">Kayıt bulunamadı.</div>';
  return `<div class="table-wrap"><table><thead><tr>${columns.map(c => `<th>${esc(c.label)}</th>`).join('')}</tr></thead><tbody>${rows.map(row => `<tr>${columns.map(c => `<td>${c.render ? c.render(row) : esc(row[c.key] ?? '—')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function set(html) { document.getElementById('embed-content').innerHTML = html; }
function notice(message) { window.alert(message); }

async function beginCheckout(planId) {
  const billingPeriod = document.getElementById('billing-period')?.value || 'monthly';
  try {
    const checkout = await apiFetch('/billing/subscribe', { method: 'POST', body: { plan_id: planId, billing_period: billingPeriod } });
    if (!checkout.checkoutFormContent) throw new Error('Ödeme formu alınamadı.');
    set(`<button class="btn btn-secondary" id="back-to-billing">← Aboneliklere dön</button><div class="checkout-host">${checkout.checkoutFormContent}</div>`);
    document.getElementById('back-to-billing').onclick = () => loaders['billing-center']();
  } catch (error) {
    if (error.status !== 501) throw error;
    const accounts = await apiFetch('/billing/bank-accounts');
    if (!accounts.length) throw new Error('Aktif ödeme kanalı bulunamadı. Lütfen destek ekibiyle iletişime geçin.');
    set(`<h3>Havale ile ödeme</h3><p>Kart tahsilatı şu anda kapalı. Güvenli havale talebi oluşturabilirsiniz.</p><form class="payment-form" id="bank-transfer-form"><select id="bank-account">${accounts.map(a=>`<option value="${esc(a.id)}">${esc(a.bank_name)} — ${esc(a.iban)}</option>`).join('')}</select><button class="btn btn-primary" type="submit">Ödeme Talebi Oluştur</button></form><div id="payment-result"></div>`);
    document.getElementById('bank-transfer-form').onsubmit = async event => {
      event.preventDefault(); const button=event.submitter; button.disabled=true;
      try {
        const result=await apiFetch('/billing/request-bank-transfer',{method:'POST',body:{plan_id:planId,bank_account_id:document.getElementById('bank-account').value,billing_period:billingPeriod}});
        document.getElementById('payment-result').innerHTML=`<div class="payment-result"><strong>Referans: ${esc(result.reference_code)}</strong><p>${esc(result.bank.bank_name)} — ${esc(result.bank.iban)}</p><p>${esc(result.message)}</p><p>Tutar: ${esc(money(result.amount,result.currency||'TRY'))}</p></div>`;
      } catch(e) { notice(e.message); } finally { button.disabled=false; }
    };
  }
}
function errorView(error, retry) {
  const box = document.createElement('div'); box.className = 'state-panel state-error';
  const title = document.createElement('h3'); title.textContent = 'Modül yüklenemedi';
  const message = document.createElement('p'); message.textContent = error.message || 'Sunucu yanıt vermedi.';
  const button = document.createElement('button'); button.className = 'btn btn-secondary'; button.textContent = 'Tekrar Dene'; button.onclick = retry;
  box.append(title, message, button); document.getElementById('embed-content').replaceChildren(box);
}

const loaders = {
  'company-dashboard': async () => {
    const d = await apiFetch('/portal/dashboard'); const s = d.summary || {};
    set(`<div class="metrics-grid">${metric('Şube',s.stores||0)}${metric('Cihaz',s.devices||0)}${metric('Ödenmemiş Fatura',s.unpaidInvoices||0)}${metric('Aylık Ciro',money(s.monthlyRevenue))}</div><h3 class="content-title">Aktif Lisanslar</h3>${table([{label:'Anahtar',key:'license_key'},{label:'Paket',key:'tier'},{label:'Cihaz',render:r=>esc(r.allowed_devices_count||r.device_limit||1)},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(r.status)}],d.licenses||[])}`);
  },
  'sales-operations': async () => {
    const [devices,stores] = await Promise.all([apiFetch('/portal/devices'),apiFetch('/portal/stores')]);
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Şube',stores.length)}</div><h3 class="content-title">Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Şube',key:'store_name'},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],devices)}<h3 class="content-title">Şubeler</h3>${table([{label:'Şube',key:'name'},{label:'Adres',key:'address'},{label:'Durum',render:r=>badge(r.status||'active')}],stores)}`);
  },
  'team-management': async () => {
    const [users,roles] = await Promise.all([apiFetch('/portal/users'),apiFetch('/portal/roles')]);
    set(`<form class="inline-form" id="create-user-form"><input id="new-user-name" required placeholder="Ad soyad"><input id="new-user-email" type="email" required placeholder="E-posta"><input id="new-user-password" type="password" minlength="8" required placeholder="Geçici şifre"><select id="new-user-role" required><option value="">Rol seçin</option>${roles.map(r=>`<option value="${esc(r.id)}">${esc(r.name)}</option>`).join('')}</select><button class="btn btn-primary" type="submit">Kullanıcı Ekle</button></form>${table([{label:'Kullanıcı',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Rol',render:r=>badge(r.role_name)},{label:'Kayıt',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.is_active===false?'inactive':'active')}],users)}`);
    document.getElementById('create-user-form').onsubmit = async e => { e.preventDefault(); const b=e.submitter;b.disabled=true;try{await apiFetch('/portal/users',{method:'POST',body:{name:document.getElementById('new-user-name').value.trim(),email:document.getElementById('new-user-email').value.trim(),password:document.getElementById('new-user-password').value,role_id:document.getElementById('new-user-role').value}});await loaders['team-management']();}catch(x){alert(x.message)}finally{b.disabled=false}};
  },
  'billing-center': async () => {
    const [sub,invoices,plans] = await Promise.all([apiFetch('/billing/subscription'),apiFetch('/portal/invoices'),apiFetch('/billing/plans')]);
    set(`<div class="metrics-grid">${metric('Aktif Plan',sub.plan_name||'Plan yok')}${metric('Durum',sub.status||'—')}${metric('Dönem Sonu',date(sub.current_period_end))}</div><div class="toolbar"><h3 class="content-title">Planlar</h3><select id="billing-period"><option value="monthly">Aylık ödeme</option><option value="yearly">Yıllık — %15 indirim</option></select></div><div class="plan-grid">${plans.map(p=>`<article class="module-card"><h3>${esc(p.name)}</h3><strong>${money(p.price,p.currency||'TRY')} / ay</strong><p>${esc(p.description||'')}</p><button class="btn btn-primary buy-plan" data-plan="${esc(p.id)}">Planı Satın Al</button></article>`).join('')}</div><h3 class="content-title">Faturalar</h3>${table([{label:'Fatura',key:'invoice_number'},{label:'Tutar',render:r=>esc(money(r.amount,r.currency||'TRY'))},{label:'Tarih',render:r=>esc(date(r.created_at||r.due_at))},{label:'Durum',render:r=>badge(r.status)}],invoices)}`);
    document.querySelectorAll('.buy-plan').forEach(button => button.onclick = async () => { button.disabled=true; try { await beginCheckout(button.dataset.plan); } catch(error) { notice(error.message); button.disabled=false; } });
  },
  'support-center': async () => {
    const tickets=await apiFetch('/portal/tickets');
    set(`<form class="inline-form support-form" id="create-ticket-form"><input id="ticket-title" required placeholder="Destek konusu"><select id="ticket-priority"><option value="normal">Normal</option><option value="high">Yüksek</option><option value="urgent">Acil</option></select><textarea id="ticket-description" required placeholder="Sorunu ayrıntılı açıklayın"></textarea><button class="btn btn-primary" type="submit">Talep Oluştur</button></form>${table([{label:'No',render:r=>esc(String(r.id).slice(0,8))},{label:'Konu',key:'title'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.status)}],tickets)}`);
    document.getElementById('create-ticket-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/portal/tickets',{method:'POST',body:{title:document.getElementById('ticket-title').value.trim(),priority:document.getElementById('ticket-priority').value,description:document.getElementById('ticket-description').value.trim()}});await loaders['support-center']();}catch(x){alert(x.message)}finally{b.disabled=false}};
  },
  'platform-companies': async () => {
    const rows=await apiFetch('/admin/companies');set(`<div class="metrics-grid">${metric('Toplam Şirket',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Askıda',rows.filter(x=>x.status==='suspended').length)}</div><form class="inline-form" id="create-company"><input id="company-name" required placeholder="Şirket ünvanı"><input id="company-tax" required placeholder="Vergi numarası"><input id="company-email" type="email" placeholder="E-posta"><input id="company-phone" placeholder="Telefon"><button class="btn btn-primary">Şirket Oluştur</button></form>${table([{label:'Şirket',key:'name'},{label:'Vergi No',key:'tax_number'},{label:'İletişim',render:r=>esc(r.email||r.phone||'—')},{label:'Şube',key:'store_count'},{label:'Cihaz',key:'device_count'},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm company-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='active'?'Askıya Al':'Aktifleştir'}</button>`}],rows)}`);
    document.getElementById('create-company').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/admin/companies',{method:'POST',body:{name:document.getElementById('company-name').value.trim(),tax_number:document.getElementById('company-tax').value.trim(),email:document.getElementById('company-email').value.trim(),phone:document.getElementById('company-phone').value.trim()}});notice(`Şirket oluşturuldu. Deneme lisansı: ${result.license_key}`);await loaders['platform-companies']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.company-toggle').forEach(b=>b.onclick=async()=>{if(!confirm('Şirket durumunu değiştirmek istediğinize emin misiniz?'))return;b.disabled=true;try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{status:b.dataset.status==='active'?'suspended':'active'}});await loaders['platform-companies']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-billing': async () => {
    const [transfers,methods]=await Promise.all([apiFetch('/billing/admin/pending-transfers'),apiFetch('/billing/payment-methods')]);set(`<h3 class="content-title">Bekleyen Havaleler</h3>${table([{label:'Şirket',render:r=>esc(r.company_name||r.company_id)},{label:'Referans',key:'reference_code'},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-primary btn-sm approve-transfer" data-invoice="${esc(r.invoice_id)}">Ödemeyi Onayla</button>`}],transfers)}<h3 class="content-title">Ödeme Yöntemleri</h3>${table([{label:'Yöntem',render:r=>esc(r.display_name||r.name)},{label:'Yapılandırma',render:r=>esc(JSON.stringify(r.config||{}))}],methods)}`);
    document.querySelectorAll('.approve-transfer').forEach(b=>b.onclick=async()=>{if(!confirm('Ödeme banka hareketiyle doğrulandı mı? Bu işlem aboneliği aktifleştirir.'))return;b.disabled=true;try{await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/approve-payment`,{method:'PUT'});await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-licenses': async () => {
    const [licenses,companies]=await Promise.all([apiFetch('/admin/licenses'),apiFetch('/admin/companies')]);
    set(`<form class="inline-form" id="create-license"><select id="license-company" required><option value="">Şirket seçin</option>${companies.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('')}</select><select id="license-tier"><option value="trial">Deneme</option><option value="basic">Basic</option><option value="pro">Pro</option><option value="pro_plus">Enterprise</option></select><input id="license-devices" type="number" min="1" max="1000" value="1" required><input id="license-days" type="number" min="1" value="365" required><button class="btn btn-primary">Lisans Üret</button></form>${table([{label:'Şirket',key:'company_name'},{label:'Anahtar',key:'license_key'},{label:'Paket',render:r=>badge(r.tier)},{label:'Cihaz',key:'allowed_devices_count'},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm license-renew" data-id="${esc(r.id)}">1 Yıl Uzat</button> <button class="btn btn-secondary btn-sm license-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='suspended'?'Aktifleştir':'Askıya Al'}</button>`}],licenses)}`);
    document.getElementById('create-license').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/admin/licenses',{method:'POST',body:{company_id:document.getElementById('license-company').value,tier:document.getElementById('license-tier').value,allowed_devices_count:document.getElementById('license-devices').value,expires_in_days:document.getElementById('license-days').value}});notice(`Lisans üretildi: ${result.license_key}`);await loaders['platform-licenses']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.license-renew').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/renew`,{method:'POST',body:{additional_days:365}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-toggle').forEach(b=>b.onclick=async()=>{if(!confirm('Lisans durumunu değiştirmek istediğinize emin misiniz?'))return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/suspend`,{method:'POST',body:{suspend:b.dataset.status!=='suspended'}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-health': async () => {
    const [d,incidents]=await Promise.all([apiFetch('/admin/dashboard'),apiFetch('/admin/incidents')]);const s=d.system||{};set(`<div class="metrics-grid">${metric('PostgreSQL',s.database||'—')}${metric('Redis',s.redis||'—')}${metric('CPU',`${s.cpuUsage||0}%`)}${metric('RAM',`${s.ramUsage||0}%`)}${metric('Disk',`${s.diskUsage||0}%`)}</div><h3 class="content-title">Sistem Olayları</h3>${table([{label:'Önem',render:r=>badge(r.severity)},{label:'Başlık',key:'title'},{label:'Şirket',key:'company_name'},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)}],incidents)}`);
  },
  'account-settings': async () => {
    const [me,sessions]=await Promise.all([apiFetch('/users/me'),apiFetch('/users/sessions')]);set(`<div class="metrics-grid">${metric('Ad Soyad',me.name)}${metric('E-posta',me.email)}${metric('Roller',(me.roles||[]).join(', '))}</div><h3 class="content-title">Aktif Oturumlar</h3>${table([{label:'Cihaz / Tarayıcı',key:'user_agent'},{label:'IP',key:'ip_address'},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Son Aktivite',render:r=>esc(date(r.updated_at))}],sessions)}`);
  }
};

export async function loadModule(item) {
  const loader=loaders[item.id]; if(!loader) throw new Error('Bu modül için ekran tanımı bulunamadı.');
  document.getElementById('embed-content').innerHTML='<div class="module-loading">Veriler yükleniyor…</div>';
  try{await loader()}catch(error){errorView(error,()=>loadModule(item))}
}
