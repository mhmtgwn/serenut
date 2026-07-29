import { apiFetch } from '/shared/js/api-client.js';
import { escapeHtml as esc, formatCurrency as money, formatDate as date, translateStatus as tr } from '/shared/js/formatters.js';

const badge = v => `<span class="status-badge status-${esc(String(v || 'unknown').toLowerCase())}">${esc(v || '—')}</span>`;
const metric = (label, value) => `<article class="metric-card"><span>${esc(label)}</span><strong>${esc(value)}</strong></article>`;

// Tarayıcı ve işletim sistemi bilgisini user-agent string'inden çıkar
function parseUA(ua) {
  if (!ua) return '—';
  let browser = 'Tarayıcı';
  let os = '';
  if (/Edg\//.test(ua)) browser = 'Edge';
  else if (/OPR\/|Opera/.test(ua)) browser = 'Opera';
  else if (/Chrome\//.test(ua) && !/Chromium/.test(ua)) browser = 'Chrome';
  else if (/Firefox\//.test(ua)) browser = 'Firefox';
  else if (/Safari\//.test(ua) && !/Chrome/.test(ua)) browser = 'Safari';
  else if (/MSIE|Trident/.test(ua)) browser = 'Internet Explorer';
  else if (/PostmanRuntime/.test(ua)) browser = 'Postman';
  else if (/python-requests/.test(ua)) browser = 'Python';
  else if (/PowerShell/.test(ua)) browser = 'PowerShell';
  const vMatch = ua.match(/(Chrome|Firefox|Safari|Edg|OPR)\/([\ d.]+)/);
  if (vMatch) browser += ' ' + vMatch[2].split('.')[0];
  if (/Windows NT 10/.test(ua)) os = 'Windows 10/11';
  else if (/Windows NT 6/.test(ua)) os = 'Windows 7/8';
  else if (/Windows/.test(ua)) os = 'Windows';
  else if (/Macintosh|Mac OS X/.test(ua)) os = 'macOS';
  else if (/iPhone|iPad/.test(ua)) os = 'iOS';
  else if (/Android/.test(ua)) os = 'Android';
  else if (/Linux/.test(ua)) os = 'Linux';
  return os ? `${browser} / ${os}` : browser;
}

function table(columns, rows) {
  if (!Array.isArray(rows) || !rows.length) return '<div class="state-panel">Kayıt bulunamadı.</div>';
  return `<div class="table-wrap"><table><thead><tr>${columns.map(c => `<th>${esc(c.label)}</th>`).join('')}</tr></thead><tbody>${rows.map(row => `<tr>${columns.map(c => `<td>${c.render ? c.render(row) : esc(row[c.key] ?? '—')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function set(html) { document.getElementById('embed-content').innerHTML = html; }
function notice(message) { window.alert(message); }

function diagnosticEvent(event) {
  const severity = String(event.severity || 'error').toLowerCase();
  const metadata = event.metadata && Object.keys(event.metadata).length
    ? JSON.stringify(event.metadata, null, 2)
    : '';
  const identity = [
    event.company_name || event.company_id,
    event.user_name || event.user_id,
    event.device_name || event.device_id,
  ].filter(Boolean).join(' · ');
  const environment = [
    event.platform,
    event.app_version ? `v${event.app_version}` : '',
    event.ip_address,
  ].filter(Boolean).join(' · ');
  const trace = [
    event.context ? `Bağlam: ${event.context}` : '',
    event.correlation_id ? `İzleme: ${event.correlation_id}` : '',
  ].filter(Boolean).join(' · ');
  return `<article class="diagnostic-event diagnostic-${esc(severity)}">
    <div class="diagnostic-head">
      <div class="diagnostic-badges">${badge(severity)}${badge(event.source || 'unknown')}</div>
      <time>${esc(date(event.occurred_at))}</time>
    </div>
    <h4>${esc(event.title || 'Tanılama kaydı')}</h4>
    <p class="diagnostic-explanation">${esc(event.explanation || event.message || 'Açıklama bulunamadı.')}</p>
    ${identity ? `<p class="diagnostic-context"><strong>Hesap:</strong> ${esc(identity)}</p>` : ''}
    ${environment ? `<p class="diagnostic-context"><strong>Ortam:</strong> ${esc(environment)}</p>` : ''}
    ${trace ? `<p class="diagnostic-context"><strong>İz:</strong> ${esc(trace)}</p>` : ''}
    <details class="diagnostic-details">
      <summary>Teknik ayrıntı ve çözüm önerisi</summary>
      <div class="diagnostic-action"><strong>Önerilen işlem</strong><p>${esc(event.suggested_action || 'Kaydın bağlamını ve ilişkili işlemleri inceleyin.')}</p></div>
      <div><strong>Ham mesaj</strong><pre>${esc(event.message || '—')}</pre></div>
      ${event.stack_trace ? `<div><strong>Stack trace</strong><pre>${esc(event.stack_trace)}</pre></div>` : ''}
      ${metadata ? `<div><strong>Maskelenmiş ek veri</strong><pre>${esc(metadata)}</pre></div>` : ''}
    </details>
  </article>`;
}

function companyDetailView(d,plans) {
  const c=d.company||{}, subscription=d.subscriptions?.[0], override=d.package_override;
  const from=(override?.valid_from||new Date().toISOString()).slice(0,10);
  const until=(override?.valid_until||new Date(Date.now()+365*86400000).toISOString()).slice(0,10);
  const companyEmail = c.email || (d.users?.[0]?.email) || '';
  return `<button class="btn btn-secondary" id="back-companies">← Firmalara dön</button><div class="company-detail-head"><div><span>FİRMA DETAYI</span><h3>${esc(c.name)}</h3><p>${esc(c.email||'E-posta yok')} · ${esc(c.phone||'Telefon yok')}</p></div><div style="display:flex;align-items:center;gap:10px">${badge(c.status)}<button class="btn btn-secondary btn-sm" id="send-reset-pw-btn" data-email="${esc(companyEmail)}">🔒 Şifre Sıfırlama Linki Gönder</button></div></div><div class="company-tabs"><button class="btn btn-secondary btn-sm company-tab active" data-tab="summary">Firma Özeti</button><button class="btn btn-secondary btn-sm company-tab" data-tab="subscription">Abonelik</button><button class="btn btn-secondary btn-sm company-tab" data-tab="licenses">Lisans ve Cihazlar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="users">Kullanıcılar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="branches">Şubeler</button><button class="btn btn-secondary btn-sm company-tab" data-tab="payments">Ödemeler</button></div><section class="company-tab-panel" data-panel="summary"><div class="metrics-grid">${metric('Kullanıcı',d.users?.length||0)}${metric('Cihaz',d.devices?.length||0)}${metric('Şube',d.stores?.length||0)}${metric('Abonelik',subscription?.plan_name||'Yok')}</div><div class="section-heading spaced"><div><h3>Firma Bilgileri</h3><p>Firma kaydına ait temel bilgiler.</p></div></div><div class="admin-form-grid" style="pointer-events:none;opacity:.7">${c.tax_number?`<label>Vergi No<input value="${esc(c.tax_number)}" readonly></label>`:''}<label>E-posta<input value="${esc(c.email||'')}" readonly></label><label>Telefon<input value="${esc(c.phone||'')}" readonly></label>${c.tax_office?`<label>Vergi Dairesi<input value="${esc(c.tax_office)}" readonly></label>`:''}</div></section><section class="company-tab-panel app-hidden" data-panel="subscription"><div class="section-heading"><div><h3>Abonelik ve Özel Paket</h3><p>Bu firmaya ait ticari ve kullanım limitlerini yönetin. Plan seçimi yapmadan sadece limitleri ve tarihleri düzenlemeniz yeterlidir.</p></div>${badge(subscription?.status||'subscription_yok')}</div>${subscription?table([{label:'Plan',key:'plan_name'},{label:'Başlangıç',render:r=>esc(date(r.current_period_start))},{label:'Bitiş',render:r=>esc(date(r.current_period_end))},{label:'Durum',render:r=>badge(r.status)}],[subscription]):'<div class="state-panel">Aktif abonelik kaydı bulunamadı.</div>'}<form class="admin-form-grid" id="company-package-form"><label>Özel fiyat <small>(İsteğe bağlı)</small><input id="package-price" type="number" min="0" step="0.01" value="${esc(override?.custom_price||'')}" placeholder="Boş bırakırsanız plan fiyatı uygulanır"></label><label>Dönem<select id="package-period"><option value="monthly" ${override?.billing_interval==='monthly'?'selected':''}>Aylık</option><option value="yearly" ${override?.billing_interval==='yearly'?'selected':''}>Yıllık</option></select></label><label>Kullanıcı limiti<input id="package-users" type="number" min="1" value="${esc(override?.user_limit||'')}" placeholder="Plan limiti geçerli"></label><label>Şube limiti<input id="package-stores" type="number" min="1" value="${esc(override?.store_limit||'')}" placeholder="Plan limiti geçerli"></label><label>Cihaz limiti<input id="package-devices" type="number" min="1" value="${esc(override?.device_limit||'')}" placeholder="Plan limiti geçerli"></label><label>Başlangıç<input id="package-from" type="date" value="${esc(from)}" required></label><label>Bitiş<input id="package-until" type="date" value="${esc(until)}" required></label><label><input id="package-renew" type="checkbox" ${override?.auto_renew?'checked':''}> Otomatik yenile</label><label style="grid-column:1/-1">Gerekçe<input id="package-reason" value="${esc(override?.reason||'')}" required placeholder="Sözleşme / kampanya gerekçesi"></label><input id="package-plan" type="hidden" value="${esc(override?.base_plan_id||subscription?.plan_id||plans[0]?.id||'')}"><button class="btn btn-primary" type="submit">Özel Paketi Kaydet</button></form></section><section class="company-tab-panel app-hidden" data-panel="licenses">${table([{label:'Anahtar',key:'license_key'},{label:'Plan',render:r=>esc(r.plan_name||r.plan_id)},{label:'Cihaz limiti',key:'device_limit'},{label:'Şube limiti',key:'store_limit'},{label:'Bitiş',render:r=>esc(date(r.valid_until))},{label:'Durum',render:r=>badge(r.status)}],d.licenses)}<h3 class="content-title">Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Platform',key:'platform'},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],d.devices)}</section><section class="company-tab-panel app-hidden" data-panel="users">${table([{label:'Ad Soyad',key:'name'},{label:'E-posta',key:'email'},{label:'Kayıt',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.is_active===false?'Pasif':'Aktif')},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm user-detail-reset-pw" data-email="${esc(r.email)}">Şifre Sıfırla</button>`}],d.users)}</section><section class="company-tab-panel app-hidden" data-panel="branches">${table([{label:'Şube',key:'name'},{label:'Adres',key:'address'},{label:'Telefon',key:'phone'},{label:'Durum',render:r=>badge(r.status)}],d.stores)}</section><section class="company-tab-panel app-hidden" data-panel="payments">${table([{label:'Fatura',render:r=>esc(r.invoice_number||r.id)},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Vade',render:r=>esc(date(r.due_at))},{label:'Ödeme',render:r=>esc(date(r.paid_at))},{label:'Durum',render:r=>badge(r.status)}],d.invoices)}</section>`;
}

async function beginCheckout(planId) {
  const billingPeriod = document.querySelector('input[name="billing-period"]:checked')?.value || 'monthly';
  const [accounts, plans, paymentMethods] = await Promise.all([apiFetch('/billing/bank-accounts'), apiFetch('/billing/effective-plans'), apiFetch('/billing/payment-methods')]);
  const plan = plans.find(p=>String(p.id)===String(planId)) || {};
  const multiplier = billingPeriod === 'yearly' ? 12 * .85 : 1;
  const amount = Number(plan.price || 0) * multiplier;
  const accountCards = accounts.map((a,index)=>`<label class="bank-choice"><input type="radio" name="bank-account" value="${esc(a.id)}" ${index===0?'checked':''}><span><b>${esc(a.bank_name)}</b><small>Alıcı: ${esc(a.account_holder||'Serenut')}</small><code>${esc(a.iban)}</code>${a.branch_name?`<small>Şube: ${esc(a.branch_name)}</small>`:''}</span></label>`).join('');
  const cardEnabled = paymentMethods.some(method=>method.id==='iyzico' && method.is_enabled);
  const cardAction = cardEnabled ? '<button class="btn btn-primary" id="start-card-checkout" type="button">Kredi / Banka Kartıyla Öde</button>' : '';
  const transferContent = accounts.length ? `<form id="bank-transfer-form"><div class="bank-choice-grid">${accountCards}</div><div class="transfer-steps"><b>Nasıl ödeyeceksiniz?</b><ol><li>Banka hesabını seçin.</li><li>Ödeme talebini oluşturun.</li><li>Üretilen referansı havale açıklamasına yazın.</li><li>Ödemeyi yaptığınızı bildirin.</li><li>Onaydan sonra aboneliğiniz etkinleşir.</li></ol></div><button class="btn btn-secondary" type="submit">Havale Referansı Oluştur</button></form>` : '<div class="state-panel">Aktif havale hesabı bulunamadı.</div>';
  set(`<button class="btn btn-secondary back-button" id="back-to-billing">← Planlara dön</button><div class="payment-layout"><section class="payment-summary"><span>SEÇİLEN PLAN</span><h3>${esc(plan.name||'Abonelik')}</h3><strong>${esc(money(amount,plan.currency||'TRY'))}</strong><p>${billingPeriod==='yearly'?'Yıllık ödeme, %15 indirimli':'Aylık ödeme'}</p>${cardAction}</section><section class="transfer-panel"><div class="section-heading"><div><h3>Havale / EFT</h3><p>Aşağıdaki hesaba ödeme yapın. Talep oluşturunca açıklamaya yazacağınız referans kodu üretilir.</p></div></div>${transferContent}</section></div><div id="payment-result"></div>`);
    document.getElementById('back-to-billing').onclick = () => loaders['billing-center']();
    const cardButton = document.getElementById('start-card-checkout');
    if (cardButton) cardButton.onclick = async () => {
      cardButton.disabled = true;
      try {
        const checkout = await apiFetch('/billing/subscribe',{method:'POST',body:{plan_id:planId,billing_period:billingPeriod}});
        if (!checkout.checkoutFormContent) throw new Error('Kart ödeme formu oluşturulamadı.');
        const frame = document.createElement('iframe');
        frame.className = 'checkout-frame';
        frame.title = 'Güvenli kart ödeme formu';
        frame.srcdoc = checkout.checkoutFormContent;
        document.getElementById('payment-result').replaceChildren(frame);
      } catch (cardError) {
        notice(cardError.message);
        cardButton.disabled = false;
      }
    };
    const transferForm = document.getElementById('bank-transfer-form');
    if (transferForm) transferForm.onsubmit = async event => {
      event.preventDefault(); const button=event.submitter; button.disabled=true;
      try {
        const selected=document.querySelector('input[name="bank-account"]:checked');
        const result=await apiFetch('/billing/request-bank-transfer',{method:'POST',body:{plan_id:planId,bank_account_id:selected.value,billing_period:billingPeriod}});
        document.getElementById('payment-result').innerHTML=`<div class="payment-result transfer-result"><span>ÖDEME AÇIKLAMASI</span><strong>${esc(result.reference_code)}</strong><p><b>${esc(result.bank.bank_name)}</b><br>${esc(result.bank.iban)}</p><p>Havale açıklamasına yalnızca bu referans kodunu yazın.</p><p class="result-amount">${esc(money(result.amount,result.currency||'TRY'))}</p><form id="transfer-notification-form" class="payment-form"><h3>Ödemeyi yaptıysanız bildirin</h3><label>Gönderen adı<input id="transfer-sender-name" required placeholder="Hesap sahibinin adı"></label><label>Gönderen banka<input id="transfer-sender-bank" placeholder="Banka adı"></label><label>Transfer tarihi<input id="transfer-date" type="date" required></label><label>Açıklama<textarea id="transfer-description" rows="2" placeholder="İsteğe bağlı not"></textarea></label><button class="btn btn-primary" type="submit">Ödemeyi Yaptım</button></form><div id="transfer-notification-status"></div></div>`;
        document.getElementById('transfer-date').value = new Date().toISOString().slice(0,10);
        document.getElementById('transfer-notification-form').onsubmit = async notifyEvent => {
          notifyEvent.preventDefault();
          const formElement = notifyEvent.currentTarget || document.getElementById('transfer-notification-form');
          const notifyButton = notifyEvent.submitter;
          if (notifyButton) notifyButton.disabled = true;
          try {
            const notification = await apiFetch('/billing/notify-transfer',{method:'POST',body:{invoice_id:result.invoice_id,sender_name:document.getElementById('transfer-sender-name').value.trim(),sender_bank:document.getElementById('transfer-sender-bank').value.trim(),transfer_date:document.getElementById('transfer-date').value,transfer_description:document.getElementById('transfer-description').value.trim()}});
            document.getElementById('transfer-notification-status').innerHTML=`<div class="state-panel"><strong>Bildiriminiz alındı</strong><p>${esc(notification.message)}</p></div>`;
            if (formElement) formElement.remove();
          } catch (notifyError) {
            notice(notifyError.message);
            if (notifyButton) notifyButton.disabled = false;
          }
        };
      } catch(e) { notice(e.message); } finally { button.disabled=false; }
    };
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
    set(`<div class="metrics-grid">${metric('Şube',s.stores||0)}${metric('Bağlı Cihaz',s.devices||0)}${metric('Ödenmemiş Fatura',s.unpaidInvoices||0)}${metric('Son 30 Gün Satış',money(s.monthlyRevenue))}</div><div class="section-heading spaced"><div><h3>Lisans Durumu</h3><p>Uygulamalarınızın kullanım hakkı ve cihaz sınırı.</p></div></div>${table([{label:'Paket',render:r=>esc(tr(r.tier))},{label:'Cihaz Hakkı',render:r=>esc(r.allowed_devices_count||1)},{label:'Geçerlilik',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(tr(r.status))}],d.licenses||[])}`);
  },
  'sales-operations': async () => {
    const [devices,stores,gateway] = await Promise.all([apiFetch('/portal/devices'),apiFetch('/portal/stores'),apiFetch('/notifications/sms-gateway')]);
    const androidDevices=devices.filter(d=>String(d.platform||'').toLowerCase()==='android');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Şube',stores.length)}${metric('SMS Ana Cihaz',gateway?.device_name||'Seçilmedi')}</div><h3 class="content-title">SMS Ana Cihazı</h3><form class="payment-form" id="sms-gateway-form"><select id="sms-gateway-device"><option value="">Android cihaz seçin</option>${androidDevices.map(d=>`<option value="${esc(d.id)}" ${gateway?.device_activation_id===d.id?'selected':''}>${esc(d.name||d.id)}</option>`).join('')}</select><button class="btn btn-primary" type="submit">Ana Cihaz Yap</button></form><p>${gateway?`Son bağlantı: ${esc(date(gateway.last_poll_at))} — ${gateway.is_online?'Çevrimiçi':'Çevrimdışı'}`:'SMS işlemleri seçilen SIM kartlı Android cihazdan gönderilir.'}</p><h3 class="content-title">Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Platform',key:'platform'},{label:'Şube',key:'store_name'},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],devices)}<h3 class="content-title">Şubeler</h3>${table([{label:'Şube',key:'name'},{label:'Adres',key:'address'},{label:'Durum',render:r=>badge(r.status||'active')}],stores)}`);
    document.getElementById('sms-gateway-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/notifications/sms-gateway',{method:'PUT',body:{device_id:document.getElementById('sms-gateway-device').value}});await loaders['sales-operations']();}catch(x){notice(x.message)}finally{b.disabled=false}};
  },
  'team-management': async () => {
    const [users,roles,permissions] = await Promise.all([apiFetch('/portal/users'),apiFetch('/portal/roles'),apiFetch('/portal/permissions')]);
    const friendly={"sales:view":'Satışları görüntüle',"sales:create":'Satış oluştur',"inventory:view":'Ürünleri görüntüle',"inventory:manage":'Ürünleri yönet',"devices:view":'Cihazları görüntüle',"devices:manage":'Cihazları yönet',"reports:view":'Raporları görüntüle',"notifications:history:read":'SMS geçmişini görüntüle',"notifications:templates:manage":'SMS şablonlarını yönet',"billing:view":'Abonelik ve faturaları görüntüle',"settings:view":'Firma ayarlarını görüntüle'};
    const permissionOptions=permissions.filter(p=>friendly[p.code]).map(p=>`<label class="permission-option"><input type="checkbox" name="role-permission" value="${esc(p.code)}"><span>${esc(friendly[p.code])}</span></label>`).join('');
    set(`<div class="section-heading"><div><h3>Ekip</h3><p>Çalışanınızı ekleyin; ne yapabileceğini görevi belirlesin.</p></div></div><details class="customer-create-panel" open><summary>Yeni kullanıcı ekle</summary><form class="customer-form-grid user-create-form" id="create-user-form"><label>Ad soyad<input id="new-user-name" required placeholder="Örn. Ayşe Yılmaz"></label><label>E-posta<input id="new-user-email" type="email" required placeholder="ayse@firma.com"></label><label>Geçici şifre<input id="new-user-password" type="password" minlength="8" required placeholder="En az 8 karakter"></label><label>Görevi<select id="new-user-role" required><option value="">Görev seçin</option>${roles.map(r=>`<option value="${esc(r.id)}">${esc(tr(r.name))}</option>`).join('')}</select></label><button class="btn btn-primary" type="submit">Kullanıcı Ekle</button></form></details><h3 class="content-title">Kullanıcılar</h3>${table([{label:'Ad Soyad',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Görev',render:r=>badge(tr(r.role_name||'Atanmadı'))},{label:'Kayıt Tarihi',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.is_active===false?'Pasif':'Aktif')},{label:'İşlem',render:r=>`<div style="display:flex;gap:6px;"><button class="btn btn-secondary btn-sm user-toggle" data-id="${esc(r.id)}" data-active="${r.is_active!==false}">${r.is_active===false?'Aktifleştir':'Devre Dışı Bırak'}</button><button class="btn btn-secondary btn-sm user-reset-pw" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Şifre Sıfırla</button></div>`}],users)}<details class="customer-create-panel role-panel"><summary>Gelişmiş: özel görev rolü oluştur</summary><form id="create-role-form"><div class="customer-form-grid role-name-grid"><label>Rol adı<input id="new-role-name" required placeholder="Örn. Mağaza sorumlusu"></label><label>Açıklama<input id="new-role-description" placeholder="Bu rolün kısa açıklaması"></label><button class="btn btn-secondary" type="submit">Rolü Oluştur</button></div><div class="permission-grid">${permissionOptions}</div></form></details>`);
    document.getElementById('create-user-form').onsubmit = async e => { e.preventDefault(); const b=e.submitter;b.disabled=true;try{await apiFetch('/portal/users',{method:'POST',body:{name:document.getElementById('new-user-name').value.trim(),email:document.getElementById('new-user-email').value.trim(),password:document.getElementById('new-user-password').value,role_id:document.getElementById('new-user-role').value}});await loaders['team-management']();}catch(x){alert(x.message)}finally{b.disabled=false}};
    document.getElementById('create-role-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const selected=[...document.querySelectorAll('input[name="role-permission"]:checked')].map(x=>x.value);b.disabled=true;try{await apiFetch('/portal/roles',{method:'POST',body:{name:document.getElementById('new-role-name').value.trim(),description:document.getElementById('new-role-description').value.trim(),permissions:selected}});await loaders['team-management']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.user-toggle').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/portal/users/${encodeURIComponent(b.dataset.id)}`,{method:'PATCH',body:{is_active:b.dataset.active!=='true'}});await loaders['team-management']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.user-reset-pw').forEach(b=>b.onclick=async()=>{const newPw=prompt(`"${b.dataset.email}" kullanıcısı için yeni geçici şifre girin (en az 8 karakter):`,'Serenut2026!');if(!newPw)return;if(newPw.length<8){alert('Şifre en az 8 karakter olmalıdır.');return;}b.disabled=true;try{await apiFetch(`/portal/users/${encodeURIComponent(b.dataset.id)}`,{method:'PATCH',body:{new_password:newPw}});alert(`Şifre başarıyla güncellendi!\nKullanıcı: ${b.dataset.email}\nYeni Geçici Şifre: ${newPw}`);}catch(x){alert(x.message||'Şifre güncellenemedi.');}finally{b.disabled=false}});
  },
  'billing-center': async () => {
    const [sub,invoices,plans] = await Promise.all([apiFetch('/billing/subscription'),apiFetch('/portal/invoices'),apiFetch('/billing/effective-plans')]);

    function planPrice(plan, period) {
      const base = Number(plan.price || 0);
      const cur  = plan.currency || 'TRY';
      if (period === 'yearly') {
        const yearly = base * 12 * 0.85;
        return `<span class="plan-price-amount">${money(yearly, cur)}</span> <small class="plan-price-label">/ yıl <span class="plan-price-badge">%15 indirim</span></small>`;
      }
      return `<span class="plan-price-amount">${money(base, cur)}</span> <small class="plan-price-label">/ ay</small>`;
    }

    set(`<div class="metrics-grid">${metric('Mevcut Plan',sub.plan_name||'Plan yok')}${metric('Abonelik',tr(sub.status))}${metric('Geçerlilik',date(sub.current_period_end))}</div><div class="toolbar billing-toolbar"><div><h3 class="content-title">Planlar</h3><p>Deneme süreniz bitince istediğiniz planı seçebilirsiniz.</p></div><div class="billing-toggle" role="radiogroup" aria-label="Ödeme dönemi"><input id="billing-monthly" type="radio" name="billing-period" value="monthly" checked><label for="billing-monthly">Aylık</label><input id="billing-yearly" type="radio" name="billing-period" value="yearly"><label for="billing-yearly">Yıllık</label><span aria-hidden="true"></span></div></div><div class="plan-grid customer-plan-grid">${plans.map(p=>`<article class="module-card plan-card" data-plan-id="${esc(p.id)}" data-plan-price="${esc(String(p.price))}" data-plan-currency="${esc(p.currency||'TRY')}"><h3>${esc(p.name)}</h3><strong class="plan-card-price">${planPrice(p,'monthly')}</strong><p>${esc(p.description||'')}</p><button class="btn btn-primary buy-plan" data-plan="${esc(p.id)}">Havale / EFT ile Al</button></article>`).join('')}</div><div class="section-heading spaced"><div><h3>Ödeme Geçmişi</h3><p>Oluşturduğunuz ödeme talepleri ve faturalar.</p></div></div>${table([{label:'Fatura',key:'invoice_number'},{label:'Tutar',render:r=>esc(money(r.amount,r.currency||'TRY'))},{label:'Tarih',render:r=>esc(date(r.created_at||r.due_at))},{label:'Durum',render:r=>badge(tr(r.status))}],invoices)}`);

    document.querySelectorAll('input[name="billing-period"]').forEach(radio => {
      radio.addEventListener('change', () => {
        const period = document.querySelector('input[name="billing-period"]:checked')?.value || 'monthly';
        document.querySelectorAll('.plan-card').forEach(card => {
          const fakePlan = { price: card.dataset.planPrice, currency: card.dataset.planCurrency };
          const priceEl = card.querySelector('.plan-card-price');
          if (priceEl) priceEl.innerHTML = planPrice(fakePlan, period);
        });
      });
    });

    document.querySelectorAll('.buy-plan').forEach(button => {
      button.onclick = () => beginCheckout(button.dataset.plan);
    });
  },
  'support-center': async () => {
    const result=await apiFetch('/support/tickets');const tickets=result.tickets||[];
    set(`<div class="section-heading"><div><h3>Yeni destek talebi</h3><p>Firma ve kullanıcı bilgileriniz talebe otomatik bağlanır.</p></div></div><form class="customer-form-grid support-form" id="create-ticket-form"><label>Kategori<select id="ticket-category"><option value="technical">Teknik</option><option value="license">Lisans</option><option value="billing">Ödeme</option><option value="account">Hesap ve giriş</option><option value="usage">Kullanım</option><option value="other">Diğer</option></select></label><label>Konu<input id="ticket-title" required maxlength="500" placeholder="Kısaca neyle ilgili?"></label><label>Öncelik<select id="ticket-priority"><option value="P3">Normal</option><option value="P2">Yüksek</option><option value="P1">Acil</option><option value="P4">Düşük</option></select></label><label class="wide-field">Açıklama<textarea id="ticket-description" required placeholder="Sorunu ve denediğiniz adımları yazın"></textarea></label><button class="btn btn-primary" type="submit">Talep Oluştur</button></form><h3 class="content-title">Taleplerim</h3>${table([{label:'No',render:r=>esc(r.id)},{label:'Kategori',render:r=>badge(r.category||'technical')},{label:'Konu',key:'subject'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.status)}],tickets)}`);
    document.getElementById('create-ticket-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const response=await apiFetch('/support/tickets',{method:'POST',body:{category:document.getElementById('ticket-category').value,subject:document.getElementById('ticket-title').value.trim(),priority:document.getElementById('ticket-priority').value,body:document.getElementById('ticket-description').value.trim()}});notice(`Destek talebiniz oluşturuldu: ${response.ticket.id}`);await loaders['support-center']();}catch(x){notice(x.message)}finally{b.disabled=false}};
  },
  'system-diagnostics': async () => {
    const d = await apiFetch('/portal/diagnostics');
    const s = d.summary || {};
    set(`<div class="metrics-grid">${metric('Kayıtlı cihaz',s.devices||0)}${metric('Çevrimiçi cihaz',s.online_devices||0)}${metric('Senkron çakışması',s.sync_conflicts||0)}${metric('Uygulama hatası',s.crashes||0)}</div><div class="section-heading spaced"><div><h3>Senkronizasyon Çakışmaları</h3><p>Çakışan kayıtlar silinmez; destek incelemesi için burada görünür.</p></div></div>${table([{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Tür',key:'entity_type'},{label:'Kayıt',key:'entity_id'},{label:'Yerel sürüm',key:'base_revision'},{label:'Sunucu sürümü',key:'server_revision'}],d.sync_conflicts)}<div class="section-heading spaced"><div><h3>Uygulama Hataları</h3><p>Bu firmaya ait gönderilmiş çökme ve hata kayıtları.</p></div></div>${table([{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Cihaz',key:'device_id'},{label:'Sürüm',key:'app_version'},{label:'Hata',render:r=>`<details><summary>${esc(String(r.error_message||'Bilinmeyen hata').slice(0,160))}</summary><pre class="diagnostic-stack">${esc(r.stack_trace||'Ek iz bilgisi yok.')}</pre></details>`}],d.crashes)}<div class="section-heading spaced"><div><h3>Firma İşlem Kayıtları</h3><p>Kullanıcı, cihaz ve abonelikle ilgili son işlemler.</p></div></div>${table([{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'İşlem',key:'action'},{label:'Varlık',key:'entity'},{label:'Kayıt',key:'entity_id'},{label:'IP',key:'ip_address'}],d.audit)}`);
  },
  'platform-overview': async () => {
    const [d,companies,transfers]=await Promise.all([apiFetch('/admin/dashboard/commercial'),apiFetch('/admin/companies'),apiFetch('/billing/admin/pending-transfers')]);const s=d.summary||{};const subs=d.subscriptions||{};
    const recent=[...companies].sort((a,b)=>new Date(b.created_at||0)-new Date(a.created_at||0)).slice(0,6);
    set(`<div class="admin-welcome"><div><span>CANLI DURUM</span><h3>Bugün kontrol etmeniz gerekenler</h3><p>Bekleyen ödemeler ve yaklaşan lisans süreleri tek bakışta.</p></div><button class="btn btn-primary admin-jump" data-target="platform-billing">${esc(s.pendingTransfers||0)} havaleyi incele</button></div><div class="metrics-grid admin-primary-metrics">${metric('Toplam Firma',s.totalCustomers||0)}${metric('Aktif Abonelik',subs.active||0)}${metric('Denemedeki Firma',s.trialUsers||0)}${metric('30 Günlük Tahsilat',money(s.monthlyRevenue||0))}</div><div class="admin-columns"><section><div class="section-heading"><h3>Bekleyen Havaleler</h3><button class="text-action admin-jump" data-target="platform-billing">Tümünü gör</button></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))}],transfers.slice(0,5))}</section><section><div class="section-heading"><h3>Son Firmalar</h3><button class="text-action admin-jump" data-target="platform-companies">Tümünü gör</button></div>${table([{label:'Firma',key:'name'},{label:'Durum',render:r=>badge(r.status)},{label:'Kayıt',render:r=>esc(date(r.created_at))}],recent)}</section></div><div class="attention-strip"><strong>${esc(s.noLicense||0)}</strong><span>lisansı olmayan firma</span><strong>${esc(s.expiringLicenses||0)}</strong><span>7 gün içinde bitecek lisans</span></div>`);
    document.querySelectorAll('.admin-jump').forEach(b=>b.onclick=()=>document.querySelector(`[data-module-id="${CSS.escape(b.dataset.target)}"]`)?.click());
  },
  'platform-companies': async () => {
    const rows=await apiFetch('/admin/companies');set(`<div class="metrics-grid">${metric('Toplam Firma',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Askıda',rows.filter(x=>x.status==='suspended').length)}</div><details class="admin-create-panel"><summary>Yeni firma oluştur</summary><form class="admin-form-grid" id="create-company"><label>Firma ünvanı<input id="company-name" required placeholder="Örn. Serenut Gıda"></label><label>TC / VKN<input id="company-tax" required placeholder="10 veya 11 hane"></label><label>E-posta<input id="company-email" type="email" placeholder="firma@ornek.com"></label><label>Telefon<input id="company-phone" placeholder="05xx xxx xx xx"></label><label>Vergi Dairesi<input id="company-tax-office" placeholder="İsteğe bağlı"></label><hr style="grid-column:1/-1;border:0;border-top:1px solid #dfe6e1;margin:4px 0"><label style="grid-column:1/-1;color:#0b714d;font-size:.72rem;letter-spacing:.06em">ADMİN KULLANICI (İsteğe bağlı)</label><label>Yönetici Ad Soyad<input id="company-admin-name" placeholder="Ahmet Yılmaz"></label><label>Yönetici E-posta<input id="company-admin-email" type="email" placeholder="ahmet@firma.com"></label><label>Geçici Şifre<input id="company-admin-pw" type="password" minlength="8" placeholder="En az 8 karakter"></label><label>Geçici Şifre Tekrar<input id="company-admin-pw2" type="password" minlength="8" placeholder="Şifre tekrarı"></label><button class="btn btn-primary">Firmayı Oluştur</button></form></details>${table([{label:'Firma',key:'name'},{label:'TC / VKN',key:'tax_number'},{label:'İletişim',render:r=>esc(r.email||r.phone||'—')},{label:'Şube',key:'store_count'},{label:'Cihaz',key:'device_count'},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm company-detail" data-id="${esc(r.id)}">Detay</button> <button class="btn btn-secondary btn-sm company-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='active'?'Askıya Al':'Aktifleştir'}</button>`}],rows)}`);
    document.getElementById('create-company').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;
      const adminPw=document.getElementById('company-admin-pw').value;
      const adminPw2=document.getElementById('company-admin-pw2').value;
      const adminEmail=document.getElementById('company-admin-email').value.trim();
      if(adminEmail&&adminPw&&adminPw!==adminPw2){notice('Geçici şifreler eşleşmiyor.');b.disabled=false;return;}
      try{const result=await apiFetch('/admin/companies',{method:'POST',body:{name:document.getElementById('company-name').value.trim(),tax_number:document.getElementById('company-tax').value.trim(),tax_office:document.getElementById('company-tax-office').value.trim(),email:document.getElementById('company-email').value.trim(),phone:document.getElementById('company-phone').value.trim(),admin_name:document.getElementById('company-admin-name').value.trim()||undefined,admin_email:adminEmail||undefined,admin_password:adminPw||undefined}});let msg=`Şirket oluşturuldu. Deneme lisansı: ${result.license_key}`;if(result.user_id)msg+=`

Admin kullanıcı oluşturuldu: ${adminEmail}`;notice(msg);await loaders['platform-companies']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.company-toggle').forEach(b=>b.onclick=async()=>{if(!confirm('şirket durumunu değiştirmek istediğinize emin misiniz?'))return;b.disabled=true;try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{status:b.dataset.status==='active'?'suspended':'active'}});await loaders['platform-companies']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.company-detail').forEach(b=>b.onclick=async()=>{b.disabled=true;try{const [d,plans]=await Promise.all([apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`),apiFetch('/billing/plans')]);set(companyDetailView(d,plans));
      document.getElementById('back-companies').onclick=()=>loaders['platform-companies']();
      document.querySelectorAll('.company-tab').forEach(tab=>tab.onclick=()=>{document.querySelectorAll('.company-tab').forEach(x=>x.classList.toggle('active',x===tab));document.querySelectorAll('.company-tab-panel').forEach(panel=>panel.classList.toggle('app-hidden',panel.dataset.panel!==tab.dataset.tab));});
      const resetBtn=document.getElementById('send-reset-pw-btn');
      if(resetBtn)resetBtn.onclick=async()=>{const email=resetBtn.dataset.email;if(!email){notice('Firmaya ait e-posta bulunamadı.');return;}if(!confirm(`${email} adresine şifre sıfırlama linki gönderilsin mi?`))return;resetBtn.disabled=true;try{const r=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/send-reset-password`,{method:'POST',body:{email}});notice(r.message||'Link gönderildi.');}catch(x){notice(x.message||'Link gönderilemedi.');}finally{resetBtn.disabled=false;}};
      document.querySelectorAll('.user-detail-reset-pw').forEach(ub=>ub.onclick=async()=>{const email=ub.dataset.email;if(!email)return;if(!confirm(`${email} adresine şifre sıfırlama linki gönderilsin mi?`))return;ub.disabled=true;try{const r=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/send-reset-password`,{method:'POST',body:{email}});notice(r.message||'Link gönderildi.');}catch(x){notice(x.message||'Link gönderilemedi.');}finally{ub.disabled=false;}});
      document.getElementById('company-package-form').onsubmit=async e=>{e.preventDefault();const submit=e.submitter;submit.disabled=true;const numberOrNull=id=>{const value=document.getElementById(id).value;return value===''?null:Number(value)};const planInput=document.getElementById('package-plan');const planId=planInput?.value||plans[0]?.id;if(!planId){notice('Temel plan seçilemedi.');submit.disabled=false;return;}try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/package-override`,{method:'PUT',body:{base_plan_id:planId,custom_price:numberOrNull('package-price'),billing_interval:document.getElementById('package-period').value,user_limit:numberOrNull('package-users'),store_limit:numberOrNull('package-stores'),device_limit:numberOrNull('package-devices'),valid_from:document.getElementById('package-from').value,valid_until:document.getElementById('package-until').value,auto_renew:document.getElementById('package-renew').checked,reason:document.getElementById('package-reason').value.trim()||'Admin düzenlemesi',feature_overrides:{}}});notice('Firmaya özel paket kaydedildi. Ödeme onayında haklar otomatik uygulanacak.');await loaders['platform-companies']();}catch(x){notice(x.message);submit.disabled=false}};}catch(x){notice(x.message);b.disabled=false}});
  },
').value,auto_renew:document.getElementById('package-renew').checked,reason:document.getElementById('package-reason').value.trim(),feature_overrides:{}}});notice('Firmaya özel paket kaydedildi. Ödeme onayında haklar otomatik uygulanacak.');await loaders['platform-companies']();}catch(x){notice(x.message);submit.disabled=false}};}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-subscriptions': async () => {
    const rows=await apiFetch('/admin/subscriptions');set(`<div class="metrics-grid">${metric('Toplam',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Deneme',rows.filter(x=>['trial','trialing'].includes(x.status)).length)}${metric('Sona Eren',rows.filter(x=>['expired','cancelled'].includes(x.status)).length)}</div>${table([{label:'Firma',key:'company_name'},{label:'Plan',key:'plan_name'},{label:'Tutar',render:r=>esc(money(r.price,r.currency||'TRY'))},{label:'Başlangıç',render:r=>esc(date(r.current_period_start))},{label:'Bitiş',render:r=>esc(date(r.current_period_end))},{label:'Durum',render:r=>badge(r.status)}],rows)}`);
  },
  'platform-billing': async () => {
    const [transfers,accounts,providers]=await Promise.all([apiFetch('/billing/admin/pending-transfers'),apiFetch('/billing/bank-accounts?all=true'),apiFetch('/admin/payment-methods')]);const iyzico=providers.find(p=>p.id==='iyzico')||{};set(`<div class="section-heading"><div><h3>Alıcı Banka Hesapları</h3><p>Müşteriye havale adımında gösterilecek hesapları yönetin.</p></div></div><form class="admin-form-grid bank-account-form" id="bank-account-form"><label>Banka adı<input id="bank-name" required placeholder="Örn. Ziraat Bankası"></label><label>Alıcı / hesap sahibi<input id="account-holder" required placeholder="Firma veya kişi ünvanı"></label><label>IBAN<input id="account-iban" required placeholder="TR00 0000 0000 0000 0000 0000 00"></label><label>Şube<input id="account-branch" placeholder="İsteğe bağlı"></label><label>Açıklama<input id="account-instructions" placeholder="Havale açıklamasına referans kodunu yazın"></label><button class="btn btn-primary">Hesabı Ekle</button></form>${table([{label:'Banka',key:'bank_name'},{label:'Alıcı',key:'account_holder'},{label:'IBAN',key:'iban'},{label:'Durum',render:r=>badge(r.is_active?'active':'inactive')},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm bank-toggle" data-id="${esc(r.id)}" data-active="${r.is_active}" data-account='${esc(JSON.stringify(r))}'>${r.is_active?'Pasifleştir':'Aktifleştir'}</button>`}],accounts)}<div class="section-heading spaced"><div><h3>iyzico</h3><p>Bilgileri kaydedin; bağlantı testi başarılı olursa etkinleştirilebilir.</p></div>${badge(iyzico.is_enabled?'active':(iyzico.is_configured?'configured':'not_configured'))}</div><form class="admin-form-grid provider-form" id="iyzico-form"><label>API adresi<input id="iyzico-base-url" value="${esc(iyzico.config?.iyzico_base_url||'https://sandbox-api.iyzipay.com')}"></label><label>API anahtarı<input id="iyzico-api-key" autocomplete="off" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'API anahtarı'}"></label><label>Gizli anahtar<input id="iyzico-secret" type="password" autocomplete="new-password" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'Gizli anahtar'}"></label><label class="switch-label"><input id="iyzico-enabled" type="checkbox" ${iyzico.is_enabled?'checked':''}> iyzico'yu etkinleştir</label><button class="btn btn-primary">Kaydet ve Test Et</button></form><div class="section-heading spaced"><div><h3>Bekleyen Havale / EFT Bildirimleri</h3><p>Banka hareketini doğruladıktan sonra aboneliği etkinleştirin.</p></div></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Gönderen',key:'sender_name'},{label:'Referans',key:'reference_code'},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-primary btn-sm approve-transfer" data-invoice="${esc(r.invoice_id)}">Ödemeyi Onayla</button>`}],transfers)}`);
    document.getElementById('bank-account-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/billing/bank-accounts',{method:'POST',body:{bank_name:document.getElementById('bank-name').value.trim(),account_holder:document.getElementById('account-holder').value.trim(),iban:document.getElementById('account-iban').value.replace(/\s/g,'').toUpperCase(),currency:'TRY',branch_name:document.getElementById('account-branch').value.trim(),instructions:document.getElementById('account-instructions').value.trim()}});await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.bank-toggle').forEach(b=>b.onclick=async()=>{const account=JSON.parse(b.dataset.account);b.disabled=true;try{await apiFetch(`/billing/bank-accounts/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{...account,is_active:b.dataset.active!=='true'}});await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
    document.getElementById('iyzico-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const apiKey=document.getElementById('iyzico-api-key').value.trim();const secret=document.getElementById('iyzico-secret').value.trim();const secrets={};if(apiKey)secrets.iyzico_api_key=apiKey;if(secret)secrets.iyzico_secret_key=secret;await apiFetch('/admin/payment-methods/iyzico',{method:'PUT',body:{is_enabled:document.getElementById('iyzico-enabled').checked,config:{iyzico_base_url:document.getElementById('iyzico-base-url').value.trim()},secrets}});notice('iyzico ayarları kaydedildi.');await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.approve-transfer').forEach(b=>b.onclick=async()=>{if(!confirm('Ödeme banka hareketiyle doğrulandı mı? Bu işlem aboneliği aktifleştirir.'))return;b.disabled=true;try{await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/approve-payment`,{method:'PUT'});await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-plans': async () => {
    const plans=await apiFetch('/billing/plans');set(`<div class="admin-plan-grid">${plans.map(p=>`<form class="admin-plan-card" data-plan="${esc(p.id)}"><span>SATIŞ PLANI</span><label>Plan adı<input name="name" value="${esc(p.name)}" required></label><label>Fiyat<div class="price-input"><input name="price" type="number" min="0" step="0.01" value="${esc(p.price)}" required><b>₺</b></div></label><label>Dönem<select name="billing_interval"><option value="monthly" ${p.billing_interval==='monthly'?'selected':''}>Aylık</option><option value="yearly" ${p.billing_interval==='yearly'?'selected':''}>Yıllık</option></select></label><button class="btn btn-primary" type="submit">Değişiklikleri Kaydet</button></form>`).join('')}</div>`);document.querySelectorAll('.admin-plan-card').forEach(f=>f.onsubmit=async e=>{e.preventDefault();const b=e.submitter;const plan=plans.find(p=>String(p.id)===f.dataset.plan);b.disabled=true;try{await apiFetch(`/billing/plans/${encodeURIComponent(f.dataset.plan)}`,{method:'PUT',body:{name:f.elements.name.value.trim(),price:Number(f.elements.price.value),currency:'TRY',billing_interval:f.elements.billing_interval.value,features:plan?.features||{}}});notice('Plan güncellendi.');}catch(x){notice(x.message)}finally{b.disabled=false}});
  },
  'platform-licenses': async () => {
    const [licenses,companies,devices]=await Promise.all([apiFetch('/admin/licenses'),apiFetch('/admin/companies'),apiFetch('/admin/devices')]);
    set(`<details class="admin-create-panel"><summary>Yeni lisans üret</summary><form class="admin-form-grid" id="create-license"><label>Firma<select id="license-company" required><option value="">Firma seçin</option>${companies.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('')}</select></label><label>Paket<select id="license-tier"><option value="trial">Deneme</option><option value="basic">Başlangıç</option><option value="pro">Pro</option><option value="pro_plus">Özel</option></select></label><label>Cihaz limiti<input id="license-devices" type="number" min="1" max="1000" value="1" required></label><label>Süre (gün)<input id="license-days" type="number" min="1" value="365" required></label><button class="btn btn-primary">Lisans Üret</button></form></details><h3 class="content-title">Lisanslar</h3>${table([{label:'Firma',key:'company_name'},{label:'Anahtar',key:'license_key'},{label:'Paket',render:r=>badge(r.tier)},{label:'Cihaz',key:'allowed_devices_count'},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm license-renew" data-id="${esc(r.id)}">1 Yıl Uzat</button> <button class="btn btn-secondary btn-sm license-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='suspended'?'Aktifleştir':'Askıya Al'}</button>`}],licenses)}<h3 class="content-title">Bağlı Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Firma',key:'company_name'},{label:'Platform',key:'platform'},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],devices)}`);
    document.getElementById('create-license').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/admin/licenses',{method:'POST',body:{company_id:document.getElementById('license-company').value,tier:document.getElementById('license-tier').value,allowed_devices_count:document.getElementById('license-devices').value,expires_in_days:document.getElementById('license-days').value}});notice(`Lisans üretildi: ${result.license_key}`);await loaders['platform-licenses']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.license-renew').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/renew`,{method:'POST',body:{additional_days:365}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-toggle').forEach(b=>b.onclick=async()=>{if(!confirm('Lisans durumunu değiştirmek istediğinize emin misiniz?'))return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/suspend`,{method:'POST',body:{suspend:b.dataset.status!=='suspended'}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-releases': async () => {
    const releases=await apiFetch('/releases/list');
    set(`<h3 class="content-title">Yeni Sürüm Yayınla</h3><form class="inline-form" id="release-upload-form"><input id="release-version" required placeholder="Sürüm (örn. 1.2.0+42)"><select id="release-platform"><option value="android">Android</option><option value="windows">Windows</option></select><select id="release-channel"><option value="stable">Kararlı</option><option value="beta">Beta</option></select><input id="release-min-version" placeholder="Asgari sürüm (isteğe bağlı)"><label><input id="release-mandatory" type="checkbox"> Zorunlu güncelleme</label><input id="release-file" type="file" required><textarea id="release-notes" required placeholder="Sürüm notları"></textarea><button class="btn btn-primary" type="submit" id="btn-release-submit">Sürümü İmzala ve Yayınla</button></form><div id="release-upload-status" class="release-status-box" style="display:none"></div><h3 class="content-title">Yayın Geçmişi</h3>${table([{label:'Sürüm',render:r=>`${esc(r.version_code)}<small>${esc(r.platform)} / ${esc(r.channel)}</small>`},{label:'Dağıtım',render:r=>`<input class="release-rollout" data-id="${esc(r.id)}" type="number" min="0" max="100" value="${esc(r.rollout_percentage)}" style="width:5rem"> %`},{label:'İndirme',key:'total_downloads'},{label:'Kurulum',key:'verified_installs'},{label:'Yayın',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm save-rollout" data-id="${esc(r.id)}">Kaydet</button> ${r.status!=='yanked'?`<button class="btn btn-secondary btn-sm yank-release" data-id="${esc(r.id)}">Geri Çek</button>`:''} <button class="btn btn-secondary btn-sm delete-release" data-id="${esc(r.id)}" data-version="${esc(r.version_code)}" style="color:#e11d48;border-color:#fecdd3">Sil</button>`}],releases)}`);
    document.getElementById('release-upload-form').onsubmit=async e=>{
      e.preventDefault();
      const b=document.getElementById('btn-release-submit');
      const statusBox=document.getElementById('release-upload-status');
      const form=new FormData();
      form.append('version_code',document.getElementById('release-version').value.trim());
      form.append('platform',document.getElementById('release-platform').value);
      form.append('channel',document.getElementById('release-channel').value);
      form.append('min_required_version',document.getElementById('release-min-version').value.trim());
      form.append('is_mandatory',String(document.getElementById('release-mandatory').checked));
      form.append('release_notes',document.getElementById('release-notes').value.trim());
      form.append('file',document.getElementById('release-file').files[0]);
      
      b.disabled=true;
      b.innerText='Yükleniyor & İmzalanıyor…';
      if(statusBox){
        statusBox.style.display='block';
        statusBox.innerHTML='<div class="attention-strip"><strong>⏳ Yükleniyor:</strong> <span>Dosya sunucuya aktarılıyor ve RSA ile dijital olarak imzalanıyor. Lütfen sayfayı kapatmayın (50MB dosya için 30-90 sn sürebilir)…</span></div>';
      }
      try{
        await apiFetch('/releases/upload',{method:'POST',body:form});
        notice('✅ Sürüm başarıyla imzalandı ve yayınlandı!');
        await loaders['platform-releases']();
      }catch(x){
        notice('❌ Hata: ' + x.message);
        if(statusBox){
          statusBox.innerHTML=`<div class="attention-strip" style="background:#fee2e2;border-color:#fca5a5"><strong style="color:#991b1b">❌ Hata:</strong> <span style="color:#991b1b">${esc(x.message)}</span></div>`;
        }
      }finally{
        b.disabled=false;
        b.innerText='Sürümü İmzala ve Yayınla';
      }
    };
    document.querySelectorAll('.save-rollout').forEach(b=>b.onclick=async()=>{const input=document.querySelector(`.release-rollout[data-id="${CSS.escape(b.dataset.id)}"]`);b.disabled=true;try{await apiFetch(`/releases/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{rollout_percentage:Number(input.value)}});notice('Dağıtım oranı güncellendi.');}catch(x){notice(x.message)}finally{b.disabled=false}});
    document.querySelectorAll('.yank-release').forEach(b=>b.onclick=async()=>{const reason=prompt('Geri çekme nedeni:','Kritik sorun nedeniyle geri çekildi.');if(reason===null)return;b.disabled=true;try{await apiFetch(`/releases/${encodeURIComponent(b.dataset.id)}/yank`,{method:'POST',body:{reason}});await loaders['platform-releases']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.delete-release').forEach(b=>b.onclick=async()=>{if(!confirm(`"${b.dataset.version}" sürüm kaydını tamamen silmek istediğinize emin misiniz?`))return;b.disabled=true;try{await apiFetch(`/releases/${encodeURIComponent(b.dataset.id)}`,{method:'DELETE'});notice('Sürüm kaydı silindi.');await loaders['platform-releases']();}catch(x){notice(x.message);b.disabled=false}});
  },

  'platform-health': async () => {
    const [d,incidents]=await Promise.all([apiFetch('/admin/dashboard'),apiFetch('/admin/incidents')]);
    const s=d.system||{};
    set(`<div class="metrics-grid">${metric('PostgreSQL',s.database||'—')}${metric('Redis',s.redis||'—')}${metric('CPU',`${s.cpuUsage||0}%`)}${metric('RAM',`${s.ramUsage||0}%`)}${metric('Disk',`${s.diskUsage||0}%`)}</div><h3 class="content-title">Sistem Olayları</h3>${table([{label:'Önem',render:r=>badge(r.severity)},{label:'Başlık',key:'title'},{label:'Şirket',key:'company_name'},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)}],incidents)}`);
  },
  'platform-security': async () => {
    const filters={
      severity:window._diagnosticSeverity||'error',
      source:window._diagnosticSource||'all',
      hours:window._diagnosticHours||'168',
      company:window._diagnosticCompany||'',
      search:window._diagnosticSearch||''
    };
    const params=new URLSearchParams({severity:filters.severity,source:filters.source,hours:filters.hours,limit:'300'});
    if(filters.company)params.set('company_id',filters.company);
    if(filters.search)params.set('search',filters.search);
    const [admins,auditLogs,companies,diagnostics]=await Promise.all([
      apiFetch('/admin/security/admin-users'),
      apiFetch('/admin/audit-logs'),
      apiFetch('/admin/companies'),
      apiFetch(`/admin/diagnostics?${params.toString()}`)
    ]);
    const summary=diagnostics.summary||{};
    const companyOptions=companies.map(company=>`<option value="${esc(company.id)}" ${filters.company===String(company.id)?'selected':''}>${esc(company.name)}</option>`).join('');
    const events=Array.isArray(diagnostics.events)?diagnostics.events:[];
    set(`<div class="metrics-grid">${metric('Kritik',summary.critical||0)}${metric('Hata',summary.error||0)}${metric('Uyarı',summary.warning||0)}${metric('Gösterilen Kayıt',summary.total||0)}</div>
      <section class="diagnostic-panel">
        <div class="section-heading"><div><h3>Hata Ayıklama ve Tanılama</h3><p>Sunucu, Windows ve Android kayıtlarını tek zaman akışında gösterir. Hassas bilgiler otomatik maskelenir.</p></div><button class="btn btn-secondary btn-sm" id="diagnostic-refresh">Yenile</button></div>
        <form class="diagnostic-filters" id="diagnostic-filters">
          <label>Önem<select id="diagnostic-severity"><option value="error" ${filters.severity==='error'?'selected':''}>Hata + kritik</option><option value="critical" ${filters.severity==='critical'?'selected':''}>Yalnız kritik</option><option value="warning" ${filters.severity==='warning'?'selected':''}>Uyarı</option><option value="all" ${filters.severity==='all'?'selected':''}>Tümü</option></select></label>
          <label>Kaynak<select id="diagnostic-source"><option value="all" ${filters.source==='all'?'selected':''}>Tüm kaynaklar</option><option value="client" ${filters.source==='client'?'selected':''}>Windows / Android</option><option value="server" ${filters.source==='server'?'selected':''}>Sunucu</option><option value="crash" ${filters.source==='crash'?'selected':''}>Çökme kayıtları</option></select></label>
          <label>Dönem<select id="diagnostic-hours"><option value="24" ${filters.hours==='24'?'selected':''}>Son 24 saat</option><option value="168" ${filters.hours==='168'?'selected':''}>Son 7 gün</option><option value="720" ${filters.hours==='720'?'selected':''}>Son 30 gün</option><option value="2160" ${filters.hours==='2160'?'selected':''}>Son 90 gün</option></select></label>
          <label>Firma<select id="diagnostic-company"><option value="">Tüm firmalar</option>${companyOptions}</select></label>
          <label class="diagnostic-search">Ara<input id="diagnostic-search" value="${esc(filters.search)}" placeholder="Hata, kullanıcı, cihaz, correlation ID…"></label>
          <button class="btn btn-primary" type="submit">Uygula</button>
        </form>
        <p class="diagnostic-result-note">Bu sayaçlar seçili filtreye uyan ve ekranda gösterilen kayıtları ifade eder.</p>
        <div class="diagnostic-list">${events.length?events.map(diagnosticEvent).join(''):'<div class="state-panel">Seçili filtrelerde tanılama kaydı bulunamadı.</div>'}</div>
      </section>
      <div class="section-heading spaced"><div><h3>Admin Hesapları</h3><p>Sistem sahibi rolüne sahip hesaplar.</p></div></div>
      ${table([{label:'Admin',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Son giriş',render:r=>esc(date(r.last_login_at))},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.is_active?'active':'inactive')}],admins)}
      <div class="section-heading spaced"><div><h3>Denetim Kayıtları</h3><p>Kim, ne zaman, hangi yönetim işlemini yaptı?</p></div></div>
      ${table([{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Kullanıcı',render:r=>esc(r.user_name||r.user_id||'Sistem')},{label:'İşlem',key:'action'},{label:'Varlık',render:r=>esc(r.entity||r.entity_type||'—')},{label:'Kayıt',render:r=>esc(r.entity_id||'—')},{label:'IP',render:r=>esc(r.ip_address||'—')}],auditLogs)}`);
    const reload=async()=>{
      window._diagnosticSeverity=document.getElementById('diagnostic-severity').value;
      window._diagnosticSource=document.getElementById('diagnostic-source').value;
      window._diagnosticHours=document.getElementById('diagnostic-hours').value;
      window._diagnosticCompany=document.getElementById('diagnostic-company').value;
      window._diagnosticSearch=document.getElementById('diagnostic-search').value.trim();
      await loaders['platform-security']();
    };
    document.getElementById('diagnostic-filters').onsubmit=async event=>{event.preventDefault();await reload();};
    document.getElementById('diagnostic-refresh').onclick=async()=>await reload();
  },
  'platform-support': async () => {
    const [result,guestResult]=await Promise.all([apiFetch('/support/tickets'),apiFetch('/support/guest-requests')]);const tickets=result.tickets||[];const guests=guestResult.requests||[];set(`<div class="metrics-grid">${metric('Kayıtlı Talep',tickets.length)}${metric('Açık',tickets.filter(x=>!['closed','resolved'].includes(x.status)).length)}${metric('Doğrulanmamış',guests.filter(x=>x.status==='unverified').length)}${metric('Acil',tickets.filter(x=>x.priority==='P1').length)}</div><div class="section-heading spaced"><div><h3>Kayıtlı Firma Talepleri</h3><p>Firma ve kullanıcı hesabına bağlı destek talepleri.</p></div></div>${table([{label:'No',render:r=>esc(r.id)},{label:'Firma',render:r=>esc(r.company_name||'—')},{label:'Kategori',render:r=>badge(r.category||'technical')},{label:'Konu',key:'subject'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.status)}],tickets)}<div class="section-heading spaced"><div><h3>Doğrulanmamış Başvurular</h3><p>Hesapla eşleşmeyen kişilerden gelen ön destek başvuruları; müşteri talebi olarak kabul edilmeden önce doğrulanmalıdır.</p></div></div>${table([{label:'Takip No',key:'reference_code'},{label:'Başvuran',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Müşteri durumu',render:r=>badge(r.customer_claim)},{label:'Kategori',render:r=>badge(r.category)},{label:'Konu',key:'subject'},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)}],guests)}`);
  },
  'account-settings': async () => {
    const [me,sessions,company]=await Promise.all([apiFetch('/users/me'),apiFetch('/users/sessions'),apiFetch('/company')]);
    const currentToken = sessionStorage.getItem('app_token') || localStorage.getItem('app_token');
    let currentSessionId = null;
    if (currentToken) { try { const p=JSON.parse(atob(currentToken.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))); currentSessionId=p.jti||p.session_id||null; } catch(_){} }
    if (!currentSessionId && sessions.length>0) { const sorted=[...sessions].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)); currentSessionId=sorted[0]?.id; }
    set(`<div class="metrics-grid">${metric('Ad Soyad',me.name)}${metric('E-posta',me.email)}${metric('Yetki',tr((me.roles||[])[0]))}</div><div class="section-heading spaced"><div><h3>Şifre Değiştir</h3><p>Şifre değiştiğinde güvenliğiniz için tüm aktif oturumlar kapatılır.</p></div></div><form class="customer-form-grid" id="change-password-form"><label>Mevcut şifre<input id="current-password" type="password" autocomplete="current-password" required></label><label>Yeni şifre<input id="new-password" type="password" autocomplete="new-password" minlength="8" required></label><label>Yeni şifre tekrar<input id="confirm-password" type="password" autocomplete="new-password" minlength="8" required></label><button class="btn btn-primary" type="submit">Şifreyi Değiştir</button></form><div class="section-heading spaced"><div><h3>Firma Bilgileri</h3><p>Uygulama ilk kurulumda bu bilgileri hazır olarak kullanır.</p></div></div><form class="customer-form-grid company-profile-form" id="company-profile-form"><label>Firma ünvanı<input id="profile-company-name" value="${esc(company.name||'')}" required></label><label>Yetkili kişi<input id="profile-owner-name" value="${esc(company.owner_name||'')}"></label><label>Telefon<input id="profile-phone" value="${esc(company.phone||'')}"></label><label>Vergi dairesi<input id="profile-tax-office" value="${esc(company.tax_office||'')}"></label><label>İl<input id="profile-city" value="${esc(company.city||'')}"></label><label>İlçe<input id="profile-district" value="${esc(company.district||'')}"></label><label class="wide-field">Adres<input id="profile-address" value="${esc(company.address||'')}"></label><label>Logo adresi <small>İsteğe bağlı</small><input id="profile-logo" value="${esc(company.logo_url||'')}"></label><button class="btn btn-primary" type="submit">Bilgileri Kaydet</button></form><div class="section-heading spaced"><div><h3>Aktif Oturumlar</h3><p>Hesabınıza giriş yapılmış oturumlar. Tanımadığınız bir oturum varsa kapatın.</p></div></div>${table([{label:'Cihaz / Tarayıcı',render:r=>{const isCurrent=r.id===currentSessionId;return `${esc(parseUA(r.user_agent))}${isCurrent?'<span class="status-badge status-active" style="margin-left:8px">✓ Bu oturum</span>':''}`;}},{label:'IP Adresi',render:r=>esc(r.ip_address||'—')},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm revoke-session" data-id="${esc(r.id)}" ${r.id===currentSessionId?'title="Bu mevcut oturumunuzdur"':''}>Oturumu Kapat</button>`}],sessions)}`);
    document.getElementById('change-password-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const next=document.getElementById('new-password').value;const confirmation=document.getElementById('confirm-password').value;if(next!==confirmation){notice('Yeni şifreler eşleşmiyor.');return;}b.disabled=true;try{await apiFetch('/auth/change-password',{method:'POST',body:{old_password:document.getElementById('current-password').value,new_password:next}});notice('Şifreniz değiştirildi. Lütfen yeni şifrenizle tekrar giriş yapın.');window.location.reload();}catch(x){notice(x.message||'Şifre değiştirilemedi.');b.disabled=false}};
    document.getElementById('company-profile-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/company',{method:'PATCH',body:{expected_version:company.version,name:document.getElementById('profile-company-name').value.trim(),owner_name:document.getElementById('profile-owner-name').value.trim(),phone:document.getElementById('profile-phone').value.trim(),tax_office:document.getElementById('profile-tax-office').value.trim(),city:document.getElementById('profile-city').value.trim(),district:document.getElementById('profile-district').value.trim(),address:document.getElementById('profile-address').value.trim(),logo_url:document.getElementById('profile-logo').value.trim()}});notice('Firma bilgileri kaydedildi.');await loaders['account-settings']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.revoke-session').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/users/sessions/${encodeURIComponent(b.dataset.id)}`,{method:'DELETE'});await loaders['account-settings']();}catch(x){notice(x.message);b.disabled=false}});
  }
};

export async function loadModule(item) {
  const loader=loaders[item.id]; if(!loader) throw new Error('Bu modül için ekran tanımı bulunamadı.');
  document.getElementById('embed-content').innerHTML='<div class="module-loading">Veriler yükleniyor…</div>';
  try{await loader()}catch(error){errorView(error,()=>loadModule(item))}
}
