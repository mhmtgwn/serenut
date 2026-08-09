import { apiFetch, getAuthToken } from '/shared/js/api-client.js';
import { escapeHtml as esc, formatCurrency as money, formatDate as date, translateStatus as tr } from '/shared/js/formatters.js';

const badge = v => `<span class="status-badge status-${esc(String(v || 'unknown').toLowerCase())}">${esc(v || '—')}</span>`;
const metric = (label, value) => `<article class="metric-card"><span>${esc(label)}</span><strong>${esc(value)}</strong></article>`;
const fileSize = value => {
  const amount = Number(value || 0);
  if (!Number.isFinite(amount) || amount <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const unit = Math.min(Math.floor(Math.log(amount) / Math.log(1024)), units.length - 1);
  return `${(amount / (1024 ** unit)).toFixed(unit > 1 ? 1 : 0)} ${units[unit]}`;
};
const jsonObject = value => {
  if (!value) return {};
  if (typeof value === 'object') return value;
  try { return JSON.parse(value); } catch (_) { return {}; }
};

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

async function showSupportTicket(ticketId, isAdmin) {
  const detail=await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}`);
  const ticket=detail.ticket;const messages=detail.messages||[];
  const transitions={open:['in_progress','closed'],in_progress:['pending_customer','resolved'],pending_customer:['in_progress','closed'],resolved:['closed','in_progress'],closed:[]};
  const statuses=transitions[ticket.status]||[];
  set(`<button class="btn btn-secondary btn-sm" id="ticket-back">← Listeye dön</button>
    <div class="ticket-detail-head"><div><span class="ticket-number">${esc(ticket.id)}</span><h3>${esc(ticket.subject)}</h3><p>${esc(ticket.company_name||'')}</p></div><div>${badge(ticket.priority)} ${badge(ticket.status)}</div></div>
    <div class="ticket-meta-grid"><div><span>Kategori</span><strong>${esc(tr(ticket.category||'technical'))}</strong></div><div><span>Oluşturma</span><strong>${esc(date(ticket.created_at))}</strong></div><div><span>SLA</span><strong>${esc(date(ticket.sla_deadline_at))}</strong></div><div><span>Atanan</span><strong>${esc(ticket.assigned_to||'Atanmadı')}</strong></div></div>
    <div class="ticket-thread">${messages.map(m=>`<article class="ticket-message ${m.sender_name==='Serenut Destek'?'from-support':'from-customer'}"><header><strong>${esc(m.sender_name)}</strong><time>${esc(date(m.created_at))}</time></header><p>${esc(m.message)}</p></article>`).join('')||'<div class="state-panel">Henüz mesaj yok.</div>'}</div>
    ${ticket.status==='closed'?'<div class="attention-strip"><span>Bu talep kapatılmıştır.</span></div>':`<form class="ticket-reply-form" id="ticket-reply"><label>Yanıt<textarea id="ticket-reply-message" required maxlength="10000" placeholder="Yanıtınızı yazın"></textarea></label><button class="btn btn-primary">Yanıtı Gönder</button></form>`}
    ${isAdmin&&statuses.length?`<form class="ticket-status-form" id="ticket-status"><label>Yeni durum<select id="ticket-status-value">${statuses.map(s=>`<option value="${s}">${esc(tr(s))}</option>`).join('')}</select></label><button class="btn btn-secondary">Durumu Güncelle</button></form>`:''}`);
  document.getElementById('ticket-back').onclick=()=>loaders[isAdmin?'platform-support':'support-center']();
  const reply=document.getElementById('ticket-reply');
  if(reply)reply.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}/messages`,{method:'POST',body:{message:document.getElementById('ticket-reply-message').value.trim()}});await showSupportTicket(ticketId,isAdmin);}catch(x){notice(x.message);b.disabled=false}};
  const status=document.getElementById('ticket-status');
  if(status)status.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}/status`,{method:'PATCH',body:{status:document.getElementById('ticket-status-value').value}});await showSupportTicket(ticketId,true);}catch(x){notice(x.message);b.disabled=false}};
}

function diagnosticFingerprint(event) {
  const normalizedMessage = String(event.message || '')
    .toLowerCase()
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi, '<uuid>')
    .replace(/\b(?:ord|trans|sale|item|sync)-[a-z0-9-]+\b/gi, '<entity-id>')
    .replace(/\b\d{13,}\b/g, '<long-id>')
    .replace(/\d{4}-\d{2}-\d{2}t\d{2}:\d{2}:\d{2}(?:\.\d+)?z?/gi, '<timestamp>');
  return [
    event.source,
    event.severity,
    event.title,
    event.error_type,
    event.context,
    event.company_id,
    event.user_id,
    event.device_id,
    normalizedMessage,
  ].map(value => String(value || '').trim().toLowerCase()).join('|');
}

const mailAddresses = value => Array.isArray(value) ? value.join(', ') : String(value || '');
const mailWhen = message => date(message.received_at || message.sent_at || message.created_at);

function mailShell(content, activeFolder = 'inbox', unread = 0) {
  return `<div class="mail-layout">
    <aside class="mail-sidebar">
      <button class="btn btn-primary mail-compose-open" type="button">＋ Yeni e-posta</button>
      <button class="mail-folder ${activeFolder==='inbox'?'active':''}" data-folder="inbox">Gelen Kutusu ${unread?`<b>${esc(unread)}</b>`:''}</button>
      <button class="mail-folder ${activeFolder==='sent'?'active':''}" data-folder="sent">Gönderilenler</button>
      <button class="mail-folder ${activeFolder==='archive'?'active':''}" data-folder="archive">Arşiv</button>
    </aside><section class="mail-main">${content}</section>
  </div>`;
}

function bindMailNavigation() {
  document.querySelectorAll('.mail-folder').forEach(button=>button.onclick=()=>{window._mailFolder=button.dataset.folder;loaders['platform-mail']();});
  document.querySelectorAll('.mail-compose-open').forEach(button=>button.onclick=()=>showMailComposer());
}

async function showMailComposer(reply) {
  const to=reply?.sender_email||'';
  const subject=reply?(/^re:/i.test(reply.subject)?reply.subject:`Re: ${reply.subject}`):'';
  const quote=reply?`\n\n--- ${mailWhen(reply)} tarihinde ${reply.sender_email} yazdı ---\n${reply.text_body||''}`:'';
  set(mailShell(`<div class="mail-toolbar"><button class="btn btn-secondary btn-sm" id="mail-compose-back">← Posta kutusu</button><strong>Yeni e-posta</strong></div>
    <form class="mail-compose" id="mail-compose-form">
      <label>Kimden<input value="Serenut Destek &lt;destek@serenut.com&gt;" disabled></label>
      <label>Kime<input id="mail-to" type="email" value="${esc(to)}" required placeholder="ornek@firma.com"></label>
      <details><summary>Bilgi / Gizli bilgi</summary><div class="mail-copy-fields"><label>Bilgi (CC)<input id="mail-cc" type="text" placeholder="virgülle ayırabilirsiniz"></label><label>Gizli bilgi (BCC)<input id="mail-bcc" type="text" placeholder="virgülle ayırabilirsiniz"></label></div></details>
      <label>Konu<input id="mail-subject" value="${esc(subject)}" maxlength="500" required></label>
      <label>Mesaj<textarea id="mail-text" maxlength="50000" required rows="14" placeholder="Mesajınızı yazın">${esc(quote)}</textarea></label>
      <div class="mail-compose-actions"><button class="btn btn-primary" type="submit">Gönder</button><span id="mail-send-state"></span></div>
    </form>`,window._mailFolder||'inbox'));
  bindMailNavigation();
  document.getElementById('mail-compose-back').onclick=()=>loaders['platform-mail']();
  document.getElementById('mail-compose-form').onsubmit=async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;document.getElementById('mail-send-state').textContent='Gönderiliyor…';try{const split=id=>document.getElementById(id).value.split(',').map(x=>x.trim()).filter(Boolean);await apiFetch('/mail/send',{method:'POST',body:{to:split('mail-to'),cc:split('mail-cc'),bcc:split('mail-bcc'),subject:document.getElementById('mail-subject').value.trim(),text:document.getElementById('mail-text').value.trim(),reply_to_id:reply?.id}});notice('E-posta gönderildi.');window._mailFolder='sent';await loaders['platform-mail']();}catch(error){notice(error.message||'E-posta gönderilemedi.');button.disabled=false;document.getElementById('mail-send-state').textContent='';}};
}

async function showMailMessage(id) {
  const result=await apiFetch(`/mail/${encodeURIComponent(id)}`);const message=result.message;const thread=result.thread||[];
  const inbound=message.direction==='inbound';
  set(mailShell(`<div class="mail-toolbar"><button class="btn btn-secondary btn-sm" id="mail-message-back">← Listeye dön</button><div class="mail-toolbar-actions">${inbound?'<button class="btn btn-primary btn-sm" id="mail-reply">Yanıtla</button>':''}<button class="btn btn-secondary btn-sm" id="mail-archive">${message.is_archived?'Arşivden çıkar':'Arşivle'}</button></div></div>
    <article class="mail-detail"><header><h3>${esc(message.subject)}</h3><div><strong>${esc(message.sender_name||message.sender_email)}</strong> &lt;${esc(message.sender_email)}&gt;</div><small>Kime: ${esc(mailAddresses(message.recipients))} · ${esc(mailWhen(message))}</small></header>
      <div class="mail-thread">${thread.map(item=>`<article class="mail-thread-message ${item.direction}"><header><strong>${esc(item.direction==='outbound'?'Serenut Destek':item.sender_name||item.sender_email)}</strong><time>${esc(mailWhen(item))}</time></header><div>${esc(item.text_body||'').replace(/\n/g,'<br>')}</div></article>`).join('')}</div>
      ${Array.isArray(message.attachment_metadata)&&message.attachment_metadata.length?`<div class="mail-attachments"><strong>Ekler</strong>${message.attachment_metadata.map(a=>`<button class="mail-attachment-download" data-message="${esc(message.id)}" data-attachment="${esc(a.id)}" data-filename="${esc(a.filename||'ek')}">${esc(a.filename||'Dosya')} <small>${esc(fileSize(a.size))}</small></button>`).join('')}</div>`:''}
    </article>`,window._mailFolder||'inbox'));
  bindMailNavigation();
  document.getElementById('mail-message-back').onclick=()=>loaders['platform-mail']();
  const reply=document.getElementById('mail-reply');if(reply)reply.onclick=()=>showMailComposer(message);
  document.getElementById('mail-archive').onclick=async()=>{await apiFetch(`/mail/${encodeURIComponent(id)}`,{method:'PATCH',body:{is_archived:!message.is_archived}});await loaders['platform-mail']();};
  document.querySelectorAll('.mail-attachment-download').forEach(button=>button.onclick=async()=>{button.disabled=true;try{const response=await fetch(`/api/v1/mail/${encodeURIComponent(button.dataset.message)}/attachments/${encodeURIComponent(button.dataset.attachment)}`,{headers:{Authorization:`Bearer ${getAuthToken()}`}});if(!response.ok)throw new Error('Ek indirilemedi.');const blob=await response.blob();const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download=button.dataset.filename||'ek';link.click();setTimeout(()=>URL.revokeObjectURL(link.href),1000);}catch(error){notice(error.message);}finally{button.disabled=false;}});
}

function groupDiagnosticEvents(events) {
  const groups = new Map();
  for (const event of events) {
    const key = diagnosticFingerprint(event);
    const existing = groups.get(key);
    if (!existing) {
      groups.set(key, {
        ...event,
        occurrence_count: 1,
        first_seen_at: event.occurred_at,
        last_seen_at: event.occurred_at,
      });
      continue;
    }
    existing.occurrence_count += 1;
    const occurredAt = Date.parse(event.occurred_at || '');
    const firstSeenAt = Date.parse(existing.first_seen_at || '');
    const lastSeenAt = Date.parse(existing.last_seen_at || '');
    if (Number.isFinite(occurredAt) && (!Number.isFinite(firstSeenAt) || occurredAt < firstSeenAt)) {
      existing.first_seen_at = event.occurred_at;
    }
    if (Number.isFinite(occurredAt) && (!Number.isFinite(lastSeenAt) || occurredAt > lastSeenAt)) {
      existing.last_seen_at = event.occurred_at;
    }
  }
  return [...groups.values()];
}

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
  const occurrenceCount = Number(event.occurrence_count || 1);
  const occurrence = occurrenceCount > 1
    ? `<span class="diagnostic-count">${occurrenceCount} tekrar</span>`
    : '';
  const seenRange = occurrenceCount > 1
    ? `<p class="diagnostic-context"><strong>Görülme:</strong> İlk ${esc(date(event.first_seen_at))} · Son ${esc(date(event.last_seen_at))}</p>`
    : '';
  return `<article class="diagnostic-event diagnostic-${esc(severity)}">
    <div class="diagnostic-head">
      <div class="diagnostic-badges">${badge(severity)}${badge(event.source || 'unknown')}${occurrence}</div>
      <time>${esc(date(event.last_seen_at || event.occurred_at))}</time>
    </div>
    <h4>${esc(event.title || 'Tanılama kaydı')}</h4>
    <p class="diagnostic-explanation">${esc(event.explanation || event.message || 'Açıklama bulunamadı.')}</p>
    ${identity ? `<p class="diagnostic-context"><strong>Hesap:</strong> ${esc(identity)}</p>` : ''}
    ${environment ? `<p class="diagnostic-context"><strong>Ortam:</strong> ${esc(environment)}</p>` : ''}
    ${trace ? `<p class="diagnostic-context"><strong>İz:</strong> ${esc(trace)}</p>` : ''}
    ${seenRange}
    <details class="diagnostic-details">
      <summary>Teknik ayrıntı ve çözüm önerisi</summary>
      <div class="diagnostic-action"><strong>Önerilen işlem</strong><p>${esc(event.suggested_action || 'Kaydın bağlamını ve ilişkili işlemleri inceleyin.')}</p></div>
      <div><strong>Ham mesaj</strong><pre>${esc(event.message || '—')}</pre></div>
      ${event.stack_trace ? `<div><strong>Stack trace</strong><pre>${esc(event.stack_trace)}</pre></div>` : ''}
      ${metadata ? `<div><strong>Maskelenmiş ek veri</strong><pre>${esc(metadata)}</pre></div>` : ''}
    </details>
  </article>`;
}

function companyDetailView(d, plans) {
  const c = d.company || {},
    subscription = d.subscriptions?.[0],
    override = d.package_override;
  const from = (override?.valid_from || new Date().toISOString()).slice(0, 10);
  const until = (
    override?.valid_until || new Date(Date.now() + 365 * 86400000).toISOString()
  ).slice(0, 10);
  const companyEmail = c.email || d.users?.[0]?.email || "";
  return `<button class="btn btn-secondary" id="back-companies">← Firmalara dön</button><div class="company-detail-head"><div><span>FİRMA DETAYI</span><h3>${esc(c.name)}</h3><p>${esc(c.email || "E-posta yok")} · ${esc(c.phone || "Telefon yok")}</p></div><div style="display:flex;align-items:center;gap:10px">${badge(c.status)}<button class="btn btn-secondary btn-sm" id="send-reset-pw-btn" data-email="${esc(companyEmail)}">🔒 Kurtarma Talebi Oluştur</button></div></div><div class="company-tabs"><button class="btn btn-secondary btn-sm company-tab active" data-tab="summary">Firma Özeti</button><button class="btn btn-secondary btn-sm company-tab" data-tab="subscription">Abonelik</button><button class="btn btn-secondary btn-sm company-tab" data-tab="licenses">Lisans ve Cihazlar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="users">Kullanıcılar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="branches">Şubeler</button><button class="btn btn-secondary btn-sm company-tab" data-tab="payments">Ödemeler</button></div><section class="company-tab-panel" data-panel="summary"><div class="metrics-grid">${metric("Kullanıcı", d.users?.length || 0)}${metric("Cihaz", d.devices?.length || 0)}${metric("Şube", d.stores?.length || 0)}${metric("Abonelik", subscription?.plan_name || "Yok")}</div><div class="section-heading spaced"><div><h3>Firma Bilgileri</h3><p>Firma kaydına ait temel bilgiler.</p></div></div><div class="admin-form-grid" style="pointer-events:none;opacity:.7">${c.tax_number ? `<label>Vergi No<input value="${esc(c.tax_number)}" readonly></label>` : ""}<label>E-posta<input value="${esc(c.email || "")}" readonly></label><label>Telefon<input value="${esc(c.phone || "")}" readonly></label>${c.tax_office ? `<label>Vergi Dairesi<input value="${esc(c.tax_office)}" readonly></label>` : ""}</div></section><section class="company-tab-panel app-hidden" data-panel="subscription"><div class="section-heading"><div><h3>Abonelik ve Özel Paket</h3><p>Bu firmaya ait ticari ve kullanım limitlerini yönetin. Plan seçimi yapmadan sadece limitleri ve tarihleri düzenlemeniz yeterlidir.</p></div>${badge(subscription?.status || "subscription_yok")}</div>${
    subscription
      ? table(
          [
            { label: "Plan", key: "plan_name" },
            {
              label: "Başlangıç",
              render: (r) => esc(date(r.current_period_start)),
            },
            { label: "Bitiş", render: (r) => esc(date(r.current_period_end)) },
            { label: "Durum", render: (r) => badge(r.status) },
          ],
          [subscription],
        )
      : '<div class="state-panel">Aktif abonelik kaydı bulunamadı.</div>'
  }<form class="admin-form-grid" id="company-package-form"><label>Özel fiyat <small>(İsteğe bağlı)</small><input id="package-price" type="number" min="0" step="0.01" value="${esc(override?.custom_price || "")}" placeholder="Boş bırakırsanız plan fiyatı uygulanır"></label><label>Dönem<select id="package-period"><option value="monthly" ${override?.billing_interval === "monthly" ? "selected" : ""}>Aylık</option><option value="yearly" ${override?.billing_interval === "yearly" ? "selected" : ""}>Yıllık</option></select></label><label>Kullanıcı limiti<input id="package-users" type="number" min="1" value="${esc(override?.user_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Şube limiti<input id="package-stores" type="number" min="1" value="${esc(override?.store_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Cihaz limiti<input id="package-devices" type="number" min="1" value="${esc(override?.device_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Başlangıç<input id="package-from" type="date" value="${esc(from)}" required></label><label>Bitiş<input id="package-until" type="date" value="${esc(until)}" required></label><label><input id="package-renew" type="checkbox" ${override?.auto_renew ? "checked" : ""}> Otomatik yenile</label><label style="grid-column:1/-1">Gerekçe<input id="package-reason" value="${esc(override?.reason || "")}" required placeholder="Sözleşme / kampanya gerekçesi"></label><input id="package-plan" type="hidden" value="${esc(override?.base_plan_id || subscription?.plan_id || plans[0]?.id || "")}"><button class="btn btn-primary" type="submit">Özel Paketi Kaydet</button></form></section><section class="company-tab-panel app-hidden" data-panel="licenses">${table(
    [
      { label: "Anahtar", key: "license_key" },
      { label: "Plan", render: (r) => esc(r.plan_name || r.plan_id) },
      { label: "Cihaz limiti", key: "device_limit" },
      { label: "Şube limiti", key: "store_limit" },
      { label: "Bitiş", render: (r) => esc(date(r.valid_until)) },
      { label: "Durum", render: (r) => badge(r.status) },
    ],
    d.licenses,
  )}<h3 class="content-title">Cihazlar</h3>${table(
    [
      { label: "Cihaz", render: (r) => esc(r.name || r.id) },
      { label: "Platform", key: "platform" },
      { label: "Son Aktivite", render: (r) => esc(date(r.last_active_at)) },
      { label: "Durum", render: (r) => badge(r.status) },
    ],
    d.devices,
  )}</section><section class="company-tab-panel app-hidden" data-panel="users">${table(
    [
      { label: "Ad Soyad", key: "name" },
      { label: "E-posta", key: "email" },
      { label: "Kayıt", render: (r) => esc(date(r.created_at)) },
      {
        label: "Durum",
        render: (r) => badge(r.is_active === false ? "Pasif" : "Aktif"),
      },
      {
        label: "İşlem",
        render: (r) =>
          `<button class="btn btn-secondary btn-sm user-detail-reset-pw" data-email="${esc(r.email)}">Şifre Sıfırla</button>`,
      },
    ],
    d.users,
  )}</section><section class="company-tab-panel app-hidden" data-panel="branches">${table(
    [
      { label: "Şube", key: "name" },
      { label: "Adres", key: "address" },
      { label: "Telefon", key: "phone" },
      { label: "Durum", render: (r) => badge(r.status) },
    ],
    d.stores,
  )}</section><section class="company-tab-panel app-hidden" data-panel="payments">${table(
    [
      { label: "Fatura", render: (r) => esc(r.invoice_number || r.id) },
      { label: "Tutar", render: (r) => esc(money(r.amount)) },
      { label: "Vade", render: (r) => esc(date(r.due_at)) },
      { label: "Ödeme", render: (r) => esc(date(r.paid_at)) },
      { label: "Durum", render: (r) => badge(r.status) },
    ],
    d.invoices,
  )}</section>`;
}

async function beginCheckout(planId) {
  const billingPeriod = document.querySelector('input[name="billing-period"]:checked')?.value || 'monthly';
  const [accounts, plans, paymentMethods, quote] = await Promise.all([apiFetch('/billing/bank-accounts'), apiFetch('/billing/effective-plans'), apiFetch('/billing/payment-methods'),apiFetch('/billing/quotes',{method:'POST',body:{plan_id:planId,billing_period:billingPeriod}})]);
  const plan = plans.find(p=>String(p.id)===String(planId)) || {};
  const amount = Number(quote.amount || 0);
  const accountCards = accounts.map((a,index)=>`<label class="bank-choice"><input type="radio" name="bank-account" value="${esc(a.id)}" ${index===0?'checked':''}><span><b>${esc(a.bank_name)}</b><small>Alıcı: ${esc(a.account_holder||'Serenut')}</small><code>${esc(a.iban)}</code>${a.branch_name?`<small>Şube: ${esc(a.branch_name)}</small>`:''}</span></label>`).join('');
  const cardEnabled = paymentMethods.some(method=>method.id==='iyzico');
  const cardAction = cardEnabled ? '<button class="btn btn-primary" id="start-card-checkout" type="button">Kredi / Banka Kartıyla Öde</button>' : '';
  const transferContent = accounts.length ? `<form id="bank-transfer-form"><div class="bank-choice-grid">${accountCards}</div><div class="transfer-steps"><b>Nasıl ödeyeceksiniz?</b><ol><li>Banka hesabını seçin.</li><li>Ödeme talebini oluşturun.</li><li>Üretilen referansı havale açıklamasına yazın.</li><li>Ödemeyi yaptığınızı bildirin.</li><li>Onaydan sonra aboneliğiniz etkinleşir.</li></ol></div><button class="btn btn-secondary" type="submit">Havale Referansı Oluştur</button></form>` : '<div class="state-panel">Aktif havale hesabı bulunamadı.</div>';
  const quotedPeriod=quote.billing_period;
  set(`<button class="btn btn-secondary back-button" id="back-to-billing">← Planlara dön</button><div class="payment-layout"><section class="payment-summary"><span>SEÇİLEN PLAN</span><h3>${esc(plan.name||'Abonelik')}</h3><strong>${esc(money(amount,quote.currency||plan.currency||'TRY'))}</strong><p>${quotedPeriod==='yearly'?'Yıllık ödeme':'Aylık ödeme'}</p>${cardAction}</section><section class="transfer-panel"><div class="section-heading"><div><h3>Havale / EFT</h3><p>Aşağıdaki hesaba ödeme yapın. Talep oluşturunca açıklamaya yazacağınız referans kodu üretilir.</p></div></div>${transferContent}</section></div><label class="billing-legal-consent"><input id="billing-legal-acceptance" type="checkbox" required><span><a href="/terms" target="_blank" rel="noopener noreferrer">Ön Bilgilendirme Formu ve Mesafeli Satış Sözleşmesi</a>'ni okudum; plan, dönem ve tutarı kabul ediyorum.</span></label><div id="payment-result"></div>`);
    document.getElementById('back-to-billing').onclick = () => loaders['billing-center']();
    const cardButton = document.getElementById('start-card-checkout');
    if (cardButton) cardButton.onclick = async () => {
      if (!document.getElementById('billing-legal-acceptance').checked) return notice('Ön bilgilendirme ve mesafeli satış koşullarını onaylayın.');
      cardButton.disabled = true;
      try {
        const checkout = await apiFetch('/billing/subscribe',{method:'POST',body:{quote_id:quote.quote_id,legal_acceptance:true,pre_information_version:'2026-08-09',distance_sales_version:'2026-08-09'}});
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
        if (!document.getElementById('billing-legal-acceptance').checked) throw new Error('Ön bilgilendirme ve mesafeli satış koşullarını onaylayın.');
        const selected=document.querySelector('input[name="bank-account"]:checked');
        const result=await apiFetch('/billing/request-bank-transfer',{method:'POST',body:{quote_id:quote.quote_id,bank_account_id:selected.value,legal_acceptance:true,pre_information_version:'2026-08-09',distance_sales_version:'2026-08-09'}});
        document.getElementById('payment-result').innerHTML=`<div class="payment-result transfer-result"><span>${result.billing_period==='yearly'?'YILLIK':'AYLIK'} ÖDEME AÇIKLAMASI</span><strong>${esc(result.reference_code)}</strong><p><b>${esc(result.bank.bank_name)}</b><br>${esc(result.bank.iban)}</p><p>Havale açıklamasına yalnızca bu referans kodunu yazın.</p><p class="result-amount">${esc(money(result.amount,result.currency||'TRY'))}</p><p>Seçilen ödeme dönemi: ${result.billing_period==='yearly'?'1 yıl':'1 ay'}</p><form id="transfer-notification-form" class="payment-form"><h3>Ödemeyi yaptıysanız bildirin</h3><label>Gönderen adı<input id="transfer-sender-name" required placeholder="Hesap sahibinin adı"></label><label>Gönderen banka<input id="transfer-sender-bank" placeholder="Banka adı"></label><label>Transfer tarihi<input id="transfer-date" type="date" required></label><label>Açıklama<textarea id="transfer-description" rows="2" placeholder="İsteğe bağlı not"></textarea></label><button class="btn btn-primary" type="submit">Ödemeyi Yaptım</button></form><div id="transfer-notification-status"></div></div>`;
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
  'company-stores': async () => {
    const stores=await apiFetch('/portal/stores');
    set(`<div class="section-heading"><div><h3>Şubeler</h3><p>Satış noktalarınızı ve cihazların bağlı olduğu iş yerlerini yönetin.</p></div></div><form class="customer-form-grid" id="create-store-form"><label>Şube adı<input id="store-name" required placeholder="Örn. Merkez Şube"></label><label class="wide-field">Adres<input id="store-address" placeholder="Açık adres"></label><button class="btn btn-primary" type="submit">Şube Ekle</button></form><div class="section-heading spaced"><div><h3>Kayıtlı Şubeler</h3><p>${stores.length} şube bulundu.</p></div></div>${table([{label:'Şube',key:'name'},{label:'Adres',render:r=>esc(r.address||'—')},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(tr(r.status||'active'))}],stores)}`);
    document.getElementById('create-store-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/portal/stores',{method:'POST',body:{name:document.getElementById('store-name').value.trim(),address:document.getElementById('store-address').value.trim()}});notice('Şube oluşturuldu.');await loaders['company-stores']();}catch(x){notice(x.message||'Şube oluşturulamadı.');b.disabled=false}};
  },
  'company-devices': async () => {
    const devices=await apiFetch('/portal/devices');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Çevrimdışı',devices.filter(d=>!d.is_online).length)}${metric('Engelli',devices.filter(d=>['revoked','blocked','inactive'].includes(d.status)).length)}</div><div class="section-heading"><div><h3>Bağlı Terminaller</h3><p>Cihaz kimliği, şube, son bağlantı ve lisans durumunu birlikte izleyin.</p></div></div>${table([{label:'Cihaz',render:r=>`${esc(r.name||'Terminal')}<small>${esc(r.id||'—')}</small>`},{label:'Platform',render:r=>esc(r.platform||'—')},{label:'Şube',render:r=>esc(r.store_name||'Tanımsız')},{label:'Donanım Kimliği',render:r=>`<code>${esc(r.device_hash?`${r.device_hash.slice(0,18)}…`:'—')}</code>`},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(tr(r.status))}],devices)}`);
  },
  'team-management': async () => {
    const [users,roles,permissions] = await Promise.all([apiFetch('/portal/users'),apiFetch('/portal/roles'),apiFetch('/portal/permissions')]);
    const friendly={"sales:view":'Satışları görüntüle',"sales:create":'Satış oluştur',"inventory:view":'Ürünleri görüntüle',"inventory:manage":'Ürünleri yönet',"devices:view":'Cihazları görüntüle',"devices:manage":'Cihazları yönet',"reports:view":'Raporları görüntüle',"notifications:history:read":'SMS geçmişini görüntüle',"notifications:templates:manage":'SMS şablonlarını yönet',"billing:view":'Abonelik ve faturaları görüntüle',"settings:view":'Firma ayarlarını görüntüle'};
    const permissionOptions=permissions.filter(p=>friendly[p.code]).map(p=>`<label class="permission-option"><input type="checkbox" name="role-permission" value="${esc(p.code)}"><span>${esc(friendly[p.code])}</span></label>`).join('');
    set(`<div class="section-heading"><div><h3>Ekip</h3><p>Çalışanınızı ekleyin; ne yapabileceğini görevi belirlesin.</p></div></div><details class="customer-create-panel" open><summary>Yeni kullanıcı ekle</summary><form class="customer-form-grid user-create-form" id="create-user-form"><label>Ad soyad<input id="new-user-name" required placeholder="Örn. Ayşe Yılmaz"></label><label>E-posta<input id="new-user-email" type="email" required placeholder="ayse@firma.com"></label><label>Görevi<select id="new-user-role" required><option value="">Görev seçin</option>${roles.map(r=>`<option value="${esc(r.id)}">${esc(tr(r.name))}</option>`).join('')}</select></label><button class="btn btn-primary" type="submit">Kullanıcı Ekle</button></form></details><h3 class="content-title">Kullanıcılar</h3>${table([{label:'Ad Soyad',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Görev',render:r=>badge(tr(r.role_name||'Atanmadı'))},{label:'Kayıt Tarihi',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.is_active===false?'Pasif':'Aktif')},{label:'İşlem',render:r=>`<div style="display:flex;gap:6px;"><button class="btn btn-secondary btn-sm user-toggle" data-id="${esc(r.id)}" data-active="${r.is_active!==false}">${r.is_active===false?'Aktifleştir':'Devre Dışı Bırak'}</button><button class="btn btn-secondary btn-sm user-reset-pw" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Kurtarma Talebi Oluştur</button></div>`}],users)}<details class="customer-create-panel role-panel"><summary>Gelişmiş: özel görev rolü oluştur</summary><form id="create-role-form"><div class="customer-form-grid role-name-grid"><label>Rol adı<input id="new-role-name" required placeholder="Örn. Mağaza sorumlusu"></label><label>Açıklama<input id="new-role-description" placeholder="Bu rolün kısa açıklaması"></label><button class="btn btn-secondary" type="submit">Rolü Oluştur</button></div><div class="permission-grid">${permissionOptions}</div></form></details>`);
    document.getElementById('create-user-form').onsubmit = async e => { e.preventDefault(); const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/portal/users',{method:'POST',body:{name:document.getElementById('new-user-name').value.trim(),email:document.getElementById('new-user-email').value.trim(),role_id:document.getElementById('new-user-role').value}});alert(`Kullanıcı oluşturuldu.\nTalep: ${result.recovery_request_id}\nTek kullanımlık kod: ${result.claim_code}\n\nKullanıcı bu bilgilerle kendi şifresini belirlemelidir.`);await loaders['team-management']();}catch(x){alert(x.message)}finally{b.disabled=false}};
    document.getElementById('create-role-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const selected=[...document.querySelectorAll('input[name="role-permission"]:checked')].map(x=>x.value);b.disabled=true;try{await apiFetch('/portal/roles',{method:'POST',body:{name:document.getElementById('new-role-name').value.trim(),description:document.getElementById('new-role-description').value.trim(),permissions:selected}});await loaders['team-management']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.user-toggle').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/portal/users/${encodeURIComponent(b.dataset.id)}`,{method:'PATCH',body:{is_active:b.dataset.active!=='true'}});await loaders['team-management']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.user-reset-pw').forEach(b=>b.onclick=async()=>{const reason=prompt(`"${b.dataset.email}" kullanıcısı için kurtarma gerekçesi (en az 10 karakter):`);if(!reason||reason.trim().length<10){notice('Geçerli bir gerekçe zorunludur.');return;}b.disabled=true;try{const r=await apiFetch('/auth/recovery/admin-assist',{method:'POST',body:{target_user_id:b.dataset.id,reason:reason.trim()}});alert(`Tek kullanımlık kurtarma bilgisi\nTalep: ${r.request_id}\nKod: ${r.claim_code}\n\nKullanıcı /forgot-password ekranındaki yönetici destekli kurtarma bölümünden devam etmelidir.`);}catch(x){alert(x.message||'Kurtarma talebi oluşturulamadı.');}finally{b.disabled=false}});
  },
  'billing-center': async () => {
    const [sub,invoices,plans] = await Promise.all([apiFetch('/billing/subscription'),apiFetch('/portal/invoices'),apiFetch('/billing/effective-plans')]);

    function planPrice(plan, period) {
      const locked=plan.locked_billing_period||'';
      const effectivePeriod=locked||period;
      const raw=effectivePeriod==='yearly'?plan.yearly_price:plan.monthly_price;
      const base = Number(raw ?? 0);
      const cur  = plan.currency || 'TRY';
      if (effectivePeriod === 'yearly') {
        const discount=locked?'':' <span class="plan-price-badge">%15 indirim</span>';
        return `<span class="plan-price-amount">${money(base, cur)}</span> <small class="plan-price-label">/ yıl${discount}</small>`;
      }
      return `<span class="plan-price-amount">${money(base, cur)}</span> <small class="plan-price-label">/ ay</small>`;
    }

    set(`<div class="metrics-grid">${metric('Mevcut Plan',sub.plan_name||'Plan yok')}${metric('Abonelik',tr(sub.status))}${metric('Geçerlilik',date(sub.current_period_end))}</div><div class="toolbar billing-toolbar"><div><h3 class="content-title">Planlar</h3><p>Deneme süreniz bitince istediğiniz planı seçebilirsiniz.</p></div><div class="billing-toggle" role="radiogroup" aria-label="Ödeme dönemi"><input id="billing-monthly" type="radio" name="billing-period" value="monthly" checked><label for="billing-monthly">Aylık</label><input id="billing-yearly" type="radio" name="billing-period" value="yearly"><label for="billing-yearly">Yıllık</label><span aria-hidden="true"></span></div></div><div class="plan-grid customer-plan-grid">${plans.map(p=>`<article class="module-card plan-card" data-plan-id="${esc(p.id)}"><h3>${esc(p.name)}</h3><strong class="plan-card-price">${planPrice(p,'monthly')}</strong><p>${esc(p.description||'')}</p>${p.locked_billing_period?`<small>Firmaya özel ${p.locked_billing_period==='yearly'?'yıllık':'aylık'} dönem</small>`:''}<button class="btn btn-primary buy-plan" data-plan="${esc(p.id)}">Havale / EFT ile Al</button></article>`).join('')}</div><div class="section-heading spaced"><div><h3>Ödeme Geçmişi</h3><p>Oluşturduğunuz ödeme talepleri ve faturalar.</p></div></div>${table([{label:'Fatura',key:'invoice_number'},{label:'Tutar',render:r=>esc(money(r.amount,r.currency||'TRY'))},{label:'Tarih',render:r=>esc(date(r.created_at||r.due_at))},{label:'Durum',render:r=>badge(tr(r.status))}],invoices)}`);

    const cancellableInvoices=invoices.filter(invoice=>invoice.status==='pending');
    if(cancellableInvoices.length){const panel=document.createElement('section');panel.className='state-panel';panel.innerHTML=`<strong>Bekleyen ödeme talepleri</strong><p>Ödeme yapmayacağınız talepleri iptal ederek listenizi temizleyebilirsiniz.</p>${cancellableInvoices.map(invoice=>`<button class="btn btn-secondary btn-sm cancel-transfer-request" data-invoice="${esc(invoice.id)}">${esc(invoice.invoice_number||invoice.id)} talebini iptal et</button>`).join(' ')}`;document.getElementById('embed-content').appendChild(panel);panel.querySelectorAll('.cancel-transfer-request').forEach(button=>button.onclick=async()=>{if(!confirm('Bu ödeme talebi iptal edilsin mi?'))return;button.disabled=true;try{await apiFetch(`/billing/transfer-requests/${encodeURIComponent(button.dataset.invoice)}/cancel`,{method:'POST'});await loaders['billing-center']();}catch(error){notice(error.message);button.disabled=false}});}
    document.querySelectorAll('input[name="billing-period"]').forEach(radio => {
      radio.addEventListener('change', () => {
        const period = document.querySelector('input[name="billing-period"]:checked')?.value || 'monthly';
        document.querySelectorAll('.plan-card').forEach(card => {
          const currentPlan=plans.find(p=>String(p.id)===String(card.dataset.planId));
          const priceEl = card.querySelector('.plan-card-price');
          if (priceEl&&currentPlan) priceEl.innerHTML = planPrice(currentPlan, period);
        });
      });
    });

    document.querySelectorAll('.buy-plan').forEach(button => {
      button.onclick = () => beginCheckout(button.dataset.plan);
    });
  },
  'company-licenses': async () => {
    const dashboard=await apiFetch('/portal/dashboard');const licenses=dashboard.licenses||[];
    set(`<div class="metrics-grid">${metric('Toplam Lisans',licenses.length)}${metric('Aktif',licenses.filter(x=>x.status==='active').length)}${metric('Deneme',licenses.filter(x=>x.status==='trial').length)}${metric('Toplam Cihaz Hakkı',licenses.reduce((sum,x)=>sum+Number(x.allowed_devices_count||1),0))}</div><div class="section-heading"><div><h3>Lisanslar</h3><p>Lisans anahtarları ve kullanım hakları salt okunur biçimde gösterilir.</p></div></div>${table([{label:'Lisans Anahtarı',render:r=>`<code>${esc(r.license_key||'—')}</code>`},{label:'Paket',render:r=>badge(tr(r.tier||'basic'))},{label:'Cihaz Hakkı',render:r=>esc(r.allowed_devices_count||1)},{label:'Geçerlilik',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(tr(r.status))}],licenses)}`);
  },
  'company-downloads': async () => {
    const releases=await apiFetch('/releases/history');
    set(`<div class="section-heading"><div><h3>Kurulum Paketleri</h3><p>Hesabınıza açık güncel Windows ve Android sürümleri.</p></div></div><div class="release-download-grid">${releases.length?releases.map(r=>`<article class="release-download-card"><div class="release-platform">${String(r.platform).toLowerCase()==='android'?'Android':'Windows'}</div><h3>Sürüm ${esc(r.version_code)}</h3><p>${esc(r.release_notes||'Kararlılık ve güvenlik güncellemeleri.')}</p><small>${esc(date(r.created_at))}</small><button class="btn btn-primary release-download" data-id="${esc(r.id)}">Güvenli İndir</button></article>`).join(''):'<div class="state-panel">Yayınlanmış kurulum paketi bulunamadı.</div>'}</div>`);
    document.querySelectorAll('.release-download').forEach(button=>button.onclick=async()=>{const original=button.textContent;button.disabled=true;button.textContent='İndiriliyor…';try{const response=await fetch(`/api/v1/releases/download/${encodeURIComponent(button.dataset.id)}`,{headers:{Authorization:`Bearer ${getAuthToken()}`}});if(!response.ok)throw new Error('Paket indirilemedi.');const blob=await response.blob();const url=URL.createObjectURL(blob);const anchor=document.createElement('a');anchor.href=url;const disposition=response.headers.get('content-disposition')||'';const match=disposition.match(/filename[^;=]*=(?:"([^"]+)"|([^;]+))/i);anchor.download=(match?.[1]||match?.[2]||`serenut-${button.dataset.id}`).trim();document.body.appendChild(anchor);anchor.click();anchor.remove();URL.revokeObjectURL(url);notice('İndirme başlatıldı.');}catch(x){notice(x.message);}finally{button.disabled=false;button.textContent=original;}});
  },
  'support-center': async () => {
    const result=await apiFetch('/support/tickets');const tickets=result.tickets||[];
    set(`<div class="section-heading"><div><h3>Yeni destek talebi</h3><p>Firma ve kullanıcı bilgileriniz talebe otomatik bağlanır.</p></div></div><form class="customer-form-grid support-form" id="create-ticket-form"><label>Kategori<select id="ticket-category"><option value="technical">Teknik</option><option value="license">Lisans</option><option value="billing">Ödeme</option><option value="account">Hesap ve giriş</option><option value="usage">Kullanım</option><option value="other">Diğer</option></select></label><label>Konu<input id="ticket-title" required maxlength="500" placeholder="Kısaca neyle ilgili?"></label><label>Öncelik<select id="ticket-priority"><option value="P3">Normal</option><option value="P2">Yüksek</option><option value="P1">Acil</option><option value="P4">Düşük</option></select></label><label class="wide-field">Açıklama<textarea id="ticket-description" required placeholder="Sorunu ve denediğiniz adımları yazın"></textarea></label><button class="btn btn-primary" type="submit">Talep Oluştur</button></form><h3 class="content-title">Taleplerim</h3>${table([{label:'No',render:r=>esc(r.id)},{label:'Kategori',render:r=>badge(r.category||'technical')},{label:'Konu',key:'subject'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm ticket-open" data-id="${esc(r.id)}">Görüntüle</button>`}],tickets)}`);
    document.getElementById('create-ticket-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const response=await apiFetch('/support/tickets',{method:'POST',body:{category:document.getElementById('ticket-category').value,subject:document.getElementById('ticket-title').value.trim(),priority:document.getElementById('ticket-priority').value,body:document.getElementById('ticket-description').value.trim()}});notice(`Destek talebiniz oluşturuldu: ${response.ticket.id}`);await loaders['support-center']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.ticket-open').forEach(b=>b.onclick=()=>showSupportTicket(b.dataset.id,false));
  },
  'system-diagnostics': async () => {
    const d = await apiFetch('/portal/diagnostics');
    const s = d.summary || {};
    const crashes=(d.crashes||[]).map(r=>({severity:'error',source:'crash',title:r.error_message||'Uygulama hatası',explanation:r.error_message||'İstemci uygulamasında hata kaydedildi.',occurred_at:r.created_at,device_id:r.device_id,environment:r.app_version?`Uygulama ${r.app_version}`:'',raw_detail:r.stack_trace,suggested_action:'Yığın izini, cihazı ve aynı zamandaki senkronizasyon kayıtlarını karşılaştırın.'}));
    const conflicts=(d.sync_conflicts||[]).map(r=>({severity:'warning',source:'sync',title:`${r.entity_type||'Kayıt'} senkronizasyon çakışması`,explanation:`Yerel sürüm ${r.base_revision??'—'} ile sunucu sürümü ${r.server_revision??'—'} uyuşmuyor.`,occurred_at:r.created_at,entity_id:r.entity_id,raw_detail:r,suggested_action:'İki sürümü inceleyip doğru kaydı seçin; kayıt otomatik silinmemiştir.'}));
    const audit=(d.audit||[]).map(r=>({severity:'info',source:'audit',title:r.action||'Firma işlemi',explanation:`${r.entity||'Varlık'} kaydı üzerinde işlem yapıldı.`,occurred_at:r.created_at,user_name:r.user_name,entity_id:r.entity_id,ip_address:r.ip_address,raw_detail:r,suggested_action:'Beklenmeyen bir işlemse kullanıcıyı ve IP adresini doğrulayın.'}));
    const events=[...crashes,...conflicts,...audit].sort((a,b)=>new Date(b.occurred_at||0)-new Date(a.occurred_at||0));
    set(`<div class="metrics-grid">${metric('Kayıtlı cihaz',s.devices||0)}${metric('Çevrimiçi cihaz',s.online_devices||0)}${metric('Senkron çakışması',s.sync_conflicts||0)}${metric('Uygulama hatası',s.crashes||0)}</div><section class="diagnostic-panel"><div class="section-heading"><div><h3>Hata Ayıklama ve İşlem Akışı</h3><p>Hata, senkronizasyon ve firma işlemlerini tek zaman çizelgesinde inceleyin.</p></div><button class="btn btn-secondary btn-sm" id="portal-diagnostic-refresh">Yenile</button></div><form class="diagnostic-filters portal-diagnostic-filters" id="portal-diagnostic-filters"><label>Kaynak<select id="portal-diagnostic-source"><option value="all">Tümü</option><option value="crash">Uygulama hataları</option><option value="sync">Senkronizasyon</option><option value="audit">İşlemler</option></select></label><label>Önem<select id="portal-diagnostic-severity"><option value="all">Tümü</option><option value="error">Hata</option><option value="warning">Uyarı</option><option value="info">Bilgi</option></select></label><label class="diagnostic-search">Ara<input id="portal-diagnostic-search" placeholder="Hata, işlem, cihaz veya kayıt…"></label><button class="btn btn-primary" type="submit">Filtrele</button></form><p class="diagnostic-result-note" id="portal-diagnostic-count"></p><div class="diagnostic-list" id="portal-diagnostic-list"></div></section>`);
    const render=()=>{const source=document.getElementById('portal-diagnostic-source').value;const severity=document.getElementById('portal-diagnostic-severity').value;const query=document.getElementById('portal-diagnostic-search').value.trim().toLocaleLowerCase('tr-TR');const filtered=events.filter(event=>(source==='all'||event.source===source)&&(severity==='all'||event.severity===severity)&&(!query||JSON.stringify(event).toLocaleLowerCase('tr-TR').includes(query)));document.getElementById('portal-diagnostic-count').textContent=`${filtered.length} / ${events.length} kayıt gösteriliyor.`;document.getElementById('portal-diagnostic-list').innerHTML=filtered.length?filtered.map(diagnosticEvent).join(''):'<div class="state-panel">Bu filtrelerde kayıt bulunamadı.</div>';};
    document.getElementById('portal-diagnostic-filters').onsubmit=e=>{e.preventDefault();render();};
    document.getElementById('portal-diagnostic-refresh').onclick=()=>loaders['system-diagnostics']();
    render();
  },
  'platform-overview': async () => {
    const [d,companies,transfers]=await Promise.all([apiFetch('/admin/dashboard/commercial'),apiFetch('/admin/companies'),apiFetch('/billing/admin/pending-transfers')]);const s=d.summary||{};const subs=d.subscriptions||{};
    const recent=[...companies].sort((a,b)=>new Date(b.created_at||0)-new Date(a.created_at||0)).slice(0,6);
    set(`<div class="admin-welcome"><div><span>CANLI DURUM</span><h3>Bugün kontrol etmeniz gerekenler</h3><p>Bekleyen ödemeler ve yaklaşan lisans süreleri tek bakışta.</p></div><button class="btn btn-primary admin-jump" data-target="platform-billing">${esc(s.pendingTransfers||0)} havaleyi incele</button></div><div class="metrics-grid admin-primary-metrics">${metric('Toplam Firma',s.totalCustomers||0)}${metric('Aktif Abonelik',subs.active||0)}${metric('Denemedeki Firma',s.trialUsers||0)}${metric('30 Günlük Tahsilat',money(s.monthlyRevenue||0))}</div><div class="admin-columns"><section><div class="section-heading"><h3>Bekleyen Havaleler</h3><button class="text-action admin-jump" data-target="platform-billing">Tümünü gör</button></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))}],transfers.slice(0,5))}</section><section><div class="section-heading"><h3>Son Firmalar</h3><button class="text-action admin-jump" data-target="platform-companies">Tümünü gör</button></div>${table([{label:'Firma',key:'name'},{label:'Durum',render:r=>badge(r.status)},{label:'Kayıt',render:r=>esc(date(r.created_at))}],recent)}</section></div><div class="attention-strip"><strong>${esc(s.noLicense||0)}</strong><span>lisansı olmayan firma</span><strong>${esc(s.expiringLicenses||0)}</strong><span>7 gün içinde bitecek lisans</span></div>`);
    document.querySelectorAll('.admin-jump').forEach(b=>b.onclick=()=>document.querySelector(`[data-module-id="${CSS.escape(b.dataset.target)}"]`)?.click());
  },
  'platform-companies': async () => {
    const rows=await apiFetch('/admin/companies');set(`<div class="metrics-grid">${metric('Toplam Firma',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Askıda',rows.filter(x=>x.status==='suspended').length)}</div><details class="admin-create-panel"><summary>Yeni firma oluştur</summary><form class="admin-form-grid" id="create-company"><label>Firma ünvanı<input id="company-name" required placeholder="Örn. Serenut Gıda"></label><label>TC / VKN<input id="company-tax" required placeholder="10 veya 11 hane"></label><label>E-posta<input id="company-email" type="email" placeholder="firma@ornek.com"></label><label>Telefon<input id="company-phone" placeholder="05xx xxx xx xx"></label><label>Vergi Dairesi<input id="company-tax-office" placeholder="İsteğe bağlı"></label><hr style="grid-column:1/-1;border:0;border-top:1px solid #dfe6e1;margin:4px 0"><label style="grid-column:1/-1;color:#0b714d;font-size:.72rem;letter-spacing:.06em">ADMİN KULLANICI (İsteğe bağlı)</label><label>Yönetici Ad Soyad<input id="company-admin-name" placeholder="Ahmet Yılmaz"></label><label>Yönetici E-posta<input id="company-admin-email" type="email" placeholder="ahmet@firma.com"></label><button class="btn btn-primary">Firmayı Oluştur</button></form></details>${table([{label:'Firma',key:'name'},{label:'TC / VKN',key:'tax_number'},{label:'İletişim',render:r=>esc(r.email||r.phone||'—')},{label:'Şube',key:'store_count'},{label:'Cihaz',key:'device_count'},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm company-detail" data-id="${esc(r.id)}">Detay</button> <button class="btn btn-secondary btn-sm company-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='active'?'Askıya Al':'Aktifleştir'}</button>`}],rows)}`);
    document.getElementById('create-company').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;
      const adminEmail=document.getElementById('company-admin-email').value.trim();
      try{const result=await apiFetch('/admin/companies',{method:'POST',body:{name:document.getElementById('company-name').value.trim(),tax_number:document.getElementById('company-tax').value.trim(),tax_office:document.getElementById('company-tax-office').value.trim(),email:document.getElementById('company-email').value.trim(),phone:document.getElementById('company-phone').value.trim(),admin_name:document.getElementById('company-admin-name').value.trim()||undefined,admin_email:adminEmail||undefined}});let msg=`Şirket oluşturuldu. Deneme lisansı: ${result.license_key}`;if(result.user_id)msg+=`

Yönetici hesabı oluşturuldu: ${adminEmail}\nTalep: ${result.recovery_request_id}\nTek kullanımlık kod: ${result.claim_code}`;notice(msg);await loaders['platform-companies']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.company-toggle').forEach(b=>b.onclick=async()=>{const reason=prompt('Firma durum değişikliği gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{const suspend=b.dataset.status==='active';await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/${suspend?'suspend':'restore'}`,{method:'POST',body:suspend?{suspend:true,reason:reason.trim()}:{reason:reason.trim()}});await loaders['platform-companies']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.company-detail').forEach(b=>b.onclick=async()=>{b.disabled=true;try{const [d,plans]=await Promise.all([apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`),apiFetch('/billing/plans')]);set(companyDetailView(d,plans));
      document.getElementById('back-companies').onclick=()=>loaders['platform-companies']();
      document.querySelectorAll('.company-tab').forEach(tab=>tab.onclick=()=>{document.querySelectorAll('.company-tab').forEach(x=>x.classList.toggle('active',x===tab));document.querySelectorAll('.company-tab-panel').forEach(panel=>panel.classList.toggle('app-hidden',panel.dataset.panel!==tab.dataset.tab));});
      const resetBtn=document.getElementById('send-reset-pw-btn');
      const requestRecovery=async(button,email)=>{if(!email){notice('Hedef kullanıcı bulunamadı.');return;}const reason=prompt('Şifre kurtarma gerekçesi (en az 10 karakter):');if(!reason||reason.trim().length<10){notice('Geçerli bir gerekçe zorunludur.');return;}button.disabled=true;try{const r=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/password-recovery`,{method:'POST',body:{email,reason:reason.trim()}});if(r.requires_second_approval){notice(`Talep oluşturuldu: ${r.request_id}. İkinci sysadmin onayı gerekiyor.`);}else{notice(`Tek kullanımlık kurtarma bilgisi — Talep: ${r.request_id} Kod: ${r.claim_code}`);}}catch(x){notice(x.message||'Kurtarma talebi oluşturulamadı.');}finally{button.disabled=false;}};
      if(resetBtn)resetBtn.onclick=()=>requestRecovery(resetBtn,resetBtn.dataset.email);
      document.querySelectorAll('.user-detail-reset-pw').forEach(ub=>ub.onclick=()=>requestRecovery(ub,ub.dataset.email));
      document.getElementById('company-package-form').onsubmit=async e=>{e.preventDefault();const submit=e.submitter;submit.disabled=true;const numberOrNull=id=>{const value=document.getElementById(id).value;return value===''?null:Number(value)};const planInput=document.getElementById('package-plan');const planId=planInput?.value||plans[0]?.id;if(!planId){notice('Temel plan seçilemedi.');submit.disabled=false;return;}try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/package-override`,{method:'PUT',body:{base_plan_id:planId,custom_price:numberOrNull('package-price'),billing_interval:document.getElementById('package-period').value,user_limit:numberOrNull('package-users'),store_limit:numberOrNull('package-stores'),device_limit:numberOrNull('package-devices'),valid_from:document.getElementById('package-from').value,valid_until:document.getElementById('package-until').value,auto_renew:document.getElementById('package-renew').checked,reason:document.getElementById('package-reason').value.trim()||'Admin düzenlemesi',feature_overrides:{}}});notice('Firmaya özel paket kaydedildi. Ödeme onayında haklar otomatik uygulanacak.');await loaders['platform-companies']();}catch(x){notice(x.message);submit.disabled=false}};}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-subscriptions': async () => {
    const rows=await apiFetch('/admin/subscriptions');set(`<div class="metrics-grid">${metric('Toplam',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Deneme',rows.filter(x=>['trial','trialing'].includes(x.status)).length)}${metric('Sona Eren',rows.filter(x=>['expired','cancelled'].includes(x.status)).length)}</div>${table([{label:'Firma',key:'company_name'},{label:'Plan',key:'plan_name'},{label:'Tutar',render:r=>esc(money(r.price,r.currency||'TRY'))},{label:'Başlangıç',render:r=>esc(date(r.current_period_start))},{label:'Bitiş',render:r=>esc(date(r.current_period_end))},{label:'Durum',render:r=>badge(r.status)}],rows)}`);
  },
  'platform-billing': async () => {
    const [transfers,accounts,providers]=await Promise.all([apiFetch('/billing/admin/pending-transfers'),apiFetch('/billing/bank-accounts?all=true'),apiFetch('/admin/payment-methods')]);const iyzico=providers.find(p=>p.id==='iyzico')||{};set(`<div class="section-heading"><div><h3>Alıcı Banka Hesapları</h3><p>Müşteriye havale adımında gösterilecek hesapları yönetin.</p></div></div><form class="admin-form-grid bank-account-form" id="bank-account-form"><label>Banka adı<input id="bank-name" required placeholder="Örn. Ziraat Bankası"></label><label>Alıcı / hesap sahibi<input id="account-holder" required placeholder="Firma veya kişi ünvanı"></label><label>IBAN<input id="account-iban" required placeholder="TR00 0000 0000 0000 0000 0000 00"></label><label>Şube<input id="account-branch" placeholder="İsteğe bağlı"></label><label>Açıklama<input id="account-instructions" placeholder="Havale açıklamasına referans kodunu yazın"></label><button class="btn btn-primary">Hesabı Ekle</button></form>${table([{label:'Banka',key:'bank_name'},{label:'Alıcı',key:'account_holder'},{label:'IBAN',key:'iban'},{label:'Durum',render:r=>badge(r.is_active?'active':'inactive')},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm bank-toggle" data-id="${esc(r.id)}" data-active="${r.is_active}" data-account='${esc(JSON.stringify(r))}'>${r.is_active?'Pasifleştir':'Aktifleştir'}</button>`}],accounts)}<div class="section-heading spaced"><div><h3>iyzico</h3><p>Bilgileri kaydedin; bağlantı testi başarılı olursa etkinleştirilebilir.</p></div>${badge(iyzico.is_enabled?'active':(iyzico.is_configured?'configured':'not_configured'))}</div><form class="admin-form-grid provider-form" id="iyzico-form"><label>API adresi<input id="iyzico-base-url" value="${esc(iyzico.config?.iyzico_base_url||'https://sandbox-api.iyzipay.com')}"></label><label>API anahtarı<input id="iyzico-api-key" autocomplete="off" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'API anahtarı'}"></label><label>Gizli anahtar<input id="iyzico-secret" type="password" autocomplete="new-password" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'Gizli anahtar'}"></label><label class="switch-label"><input id="iyzico-enabled" type="checkbox" ${iyzico.is_enabled?'checked':''}> iyzico'yu etkinleştir</label><button class="btn btn-primary">Kaydet ve Test Et</button></form><div class="section-heading spaced"><div><h3>Bekleyen Havale / EFT Bildirimleri</h3><p>Banka hareketini doğruladıktan sonra aboneliği etkinleştirin.</p></div></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Gönderen',key:'sender_name'},{label:'Referans',key:'reference_code'},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-primary btn-sm approve-transfer" data-invoice="${esc(r.invoice_id)}">Ödemeyi Onayla</button>`}],transfers)}`);
    document.querySelectorAll('.approve-transfer').forEach(button=>{const transfer=transfers.find(item=>String(item.invoice_id)===String(button.dataset.invoice));const details=jsonObject(transfer?.billing_details);const period=document.createElement('small');period.textContent=details.billingPeriod==='yearly'?' · Yıllık':' · Aylık';button.parentElement?.insertBefore(period,button);const reject=document.createElement('button');reject.className='btn btn-danger btn-sm reject-transfer';reject.dataset.invoice=button.dataset.invoice;reject.textContent='Reddet';button.parentElement?.appendChild(reject);});
    document.getElementById('bank-account-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/billing/bank-accounts',{method:'POST',body:{bank_name:document.getElementById('bank-name').value.trim(),account_holder:document.getElementById('account-holder').value.trim(),iban:document.getElementById('account-iban').value.replace(/\s/g,'').toUpperCase(),currency:'TRY',branch_name:document.getElementById('account-branch').value.trim(),instructions:document.getElementById('account-instructions').value.trim()}});await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.bank-toggle').forEach(b=>b.onclick=async()=>{const account=JSON.parse(b.dataset.account);b.disabled=true;try{await apiFetch(`/billing/bank-accounts/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{...account,is_active:b.dataset.active!=='true'}});await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
    document.getElementById('iyzico-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const apiKey=document.getElementById('iyzico-api-key').value.trim();const secret=document.getElementById('iyzico-secret').value.trim();const secrets={};if(apiKey)secrets.iyzico_api_key=apiKey;if(secret)secrets.iyzico_secret_key=secret;await apiFetch('/admin/payment-methods/iyzico',{method:'PUT',body:{is_enabled:document.getElementById('iyzico-enabled').checked,config:{iyzico_base_url:document.getElementById('iyzico-base-url').value.trim()},secrets}});notice('iyzico ayarları kaydedildi.');await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.approve-transfer').forEach(b=>b.onclick=async()=>{if(!confirm('Ödeme banka hareketiyle doğrulandı mı? Bu işlem aboneliği aktifleştirir.'))return;b.disabled=true;try{const result=await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/approve-payment`,{method:'PUT'});notice(`Ödeme onaylandı. Lisans geçerlilik tarihi: ${date(result.license_valid_until)}`);await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.reject-transfer').forEach(b=>b.onclick=async()=>{const note=prompt('Havale red gerekçesi:');if(!note)return;b.disabled=true;try{await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/reject-payment`,{method:'PUT',body:{note}});notice('Havale bildirimi reddedildi.');await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-plans': async () => {
    const plans=await apiFetch('/billing/plans');set(`<div class="admin-plan-grid">${plans.map(p=>`<form class="admin-plan-card" data-plan="${esc(p.id)}"><span>SATIŞ PLANI</span><label>Plan adı<input name="name" value="${esc(p.name)}" required></label><label>Fiyat<div class="price-input"><input name="price" type="number" min="0" step="0.01" value="${esc(p.price)}" required><b>₺</b></div></label><label>Dönem<select name="billing_interval"><option value="monthly" ${p.billing_interval==='monthly'?'selected':''}>Aylık</option><option value="yearly" ${p.billing_interval==='yearly'?'selected':''}>Yıllık</option></select></label><button class="btn btn-primary" type="submit">Değişiklikleri Kaydet</button></form>`).join('')}</div>`);document.querySelectorAll('.admin-plan-card').forEach(f=>f.onsubmit=async e=>{e.preventDefault();const b=e.submitter;const plan=plans.find(p=>String(p.id)===f.dataset.plan);b.disabled=true;try{await apiFetch(`/billing/plans/${encodeURIComponent(f.dataset.plan)}`,{method:'PUT',body:{name:f.elements.name.value.trim(),price:Number(f.elements.price.value),currency:'TRY',billing_interval:f.elements.billing_interval.value,features:plan?.features||{}}});notice('Plan güncellendi.');}catch(x){notice(x.message)}finally{b.disabled=false}});
  },
  'platform-licenses': async () => {
    const [licenses,companies,devices]=await Promise.all([apiFetch('/admin/licenses'),apiFetch('/admin/companies'),apiFetch('/admin/devices')]);
    set(`<details class="admin-create-panel"><summary>Yeni lisans üret</summary><form class="admin-form-grid" id="create-license"><label>Firma<select id="license-company" required><option value="">Firma seçin</option>${companies.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('')}</select></label><label>Paket<select id="license-tier"><option value="trial">Deneme</option><option value="basic">Başlangıç</option><option value="pro">Pro</option><option value="pro_plus">Özel</option></select></label><label>Cihaz limiti<input id="license-devices" type="number" min="1" max="1000" value="1" required></label><label>Süre (gün)<input id="license-days" type="number" min="1" value="365" required></label><button class="btn btn-primary">Lisans Üret</button></form></details><h3 class="content-title">Lisanslar</h3>${table([{label:'Firma',key:'company_name'},{label:'Anahtar',key:'license_key'},{label:'Paket',render:r=>badge(r.tier)},{label:'Cihaz',key:'allowed_devices_count'},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm license-renew" data-id="${esc(r.id)}">1 Yıl Uzat</button> <button class="btn btn-secondary btn-sm license-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='suspended'?'Aktifleştir':'Askıya Al'}</button> ${r.status!=='revoked'?`<button class="btn btn-danger btn-sm license-revoke" data-id="${esc(r.id)}">İptal Et</button>`:''}`}],licenses)}<h3 class="content-title">Bağlı Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Firma',key:'company_name'},{label:'Platform',key:'platform'},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],devices)}`);
    document.getElementById('create-license').onsubmit=async e=>{e.preventDefault();const reason=prompt('Manuel lisans üretme gerekçesi:');if(!reason?.trim()){notice('Manuel lisans gerekçesi zorunludur.');return;}const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/admin/licenses',{method:'POST',body:{company_id:document.getElementById('license-company').value,tier:document.getElementById('license-tier').value,allowed_devices_count:document.getElementById('license-devices').value,expires_in_days:document.getElementById('license-days').value,reason:reason.trim()}});notice(`Lisans üretildi: ${result.license_key}`);await loaders['platform-licenses']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.license-renew').forEach(b=>b.onclick=async()=>{const reason=prompt('Manuel lisans uzatma gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/renew`,{method:'POST',body:{additional_days:365,reason:reason.trim()}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-toggle').forEach(b=>b.onclick=async()=>{const reason=prompt('Lisans durum değişikliği gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/suspend`,{method:'POST',body:{suspend:b.dataset.status!=='suspended',reason:reason.trim()}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-revoke').forEach(b=>b.onclick=async()=>{const reason=prompt('Kalıcı iptal gerekçesi:');if(!reason?.trim())return;if(!confirm('Bu lisans kalıcı olarak iptal edilecek ve bağlı cihazların erişimi kesilecek. Devam edilsin mi?'))return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/revoke`,{method:'POST',body:{reason:reason.trim()}});notice('Lisans iptal edildi.');await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-devices': async () => {
    const devices=await apiFetch('/admin/devices');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Çevrimdışı',devices.filter(d=>!d.is_online).length)}${metric('Engelli',devices.filter(d=>d.status!=='active').length)}</div><div class="section-heading"><div><h3>Tüm Cihazlar</h3><p>Firma, şube, donanım kimliği ve bağlantı durumuna göre terminalleri yönetin.</p></div></div>${table([{label:'Cihaz',render:r=>`${esc(r.name||'Terminal')}<small>${esc(r.id)}</small>`},{label:'Firma',render:r=>esc(r.company_name||'—')},{label:'Şube',render:r=>esc(r.store_name||'—')},{label:'Donanım',render:r=>`<code>${esc(r.device_hash?`${r.device_hash.slice(0,18)}…`:'—')}</code>`},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Durum',render:r=>badge(tr(r.status))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm device-toggle" data-id="${esc(r.id)}">${r.status==='active'?'Engelle':'Etkinleştir'}</button> <button class="btn btn-secondary btn-sm device-swap" data-id="${esc(r.id)}" data-company="${esc(r.company_id)}" data-name="${esc(r.name||'Terminal')}">Cihazı Değiştir</button>`}],devices)}`);
    document.querySelectorAll('.device-toggle').forEach(button=>button.onclick=async()=>{if(!confirm('Cihaz erişim durumunu değiştirmek istediğinize emin misiniz?'))return;button.disabled=true;try{await apiFetch(`/admin/devices/${encodeURIComponent(button.dataset.id)}/toggle`,{method:'POST'});await loaders['platform-devices']();}catch(x){notice(x.message);button.disabled=false}});
    document.querySelectorAll('.device-swap').forEach(button=>button.onclick=async()=>{const name=prompt('Yeni cihaz adı:',button.dataset.name||'Yeni Terminal');if(!name)return;const hash=prompt('Yeni cihaz UUID / donanım kimliği:');if(!hash)return;button.disabled=true;try{await apiFetch('/admin/devices/swap',{method:'POST',body:{company_id:button.dataset.company,old_device_id:button.dataset.id,new_device_name:name.trim(),new_device_hash:hash.trim()}});notice('Cihaz eşleşmesi güncellendi.');await loaders['platform-devices']();}catch(x){notice(x.message);button.disabled=false}});
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
  'platform-maintenance': async () => {
    const preview=await apiFetch('/admin/maintenance/preview');
    const tasks=preview.tasks||{};
    const taskDefinitions=[
      ['docker_build_cache','Docker Derleme Önbelleği','Kullanılmayan build katmanlarını kaldırır. Bir sonraki dağıtım daha uzun sürebilir.'],
      ['dangling_images','Sahipsiz Docker İmajları','Hiçbir etiketi ve çalışan konteyner bağlantısı olmayan imajları kaldırır.'],
      ['stopped_containers','Durdurulmuş Konteynerler','Çalışmayan eski konteynerleri kaldırır; aktif servisler ve veri volume’ları korunur.'],
      ['old_releases','Eski Uygulama Sürümleri','Android ve Windows için en yeni iki paketi korur, daha eski kararlı paketleri kaldırır.'],
      ['temporary_releases','Geçici Yayın Dosyaları','Yayın klasöründe en az iki saattir bekleyen APK ve EXE kopyalarını kaldırır.'],
      ['archived_logs','Arşivlenmiş Loglar','Yedi günden eski döndürülmüş logları kaldırır; aktif hata loglarına dokunmaz.'],
    ];
    const candidateFiles=[...(tasks.old_releases?.files||[]),...(tasks.temporary_releases?.files||[]),...(tasks.archived_logs?.files||[])];
    const history=Array.isArray(preview.history)?preview.history:[];
    set(`<div class="metrics-grid">${metric('Disk Kullanımı',`${preview.disk?.usedPercent||0}%`)}${metric('Boş Alan',fileSize(preview.disk?.freeBytes))}${metric('Temizlenebilir',fileSize(taskDefinitions.reduce((sum,[id])=>sum+Number(tasks[id]?.candidateBytes||0),0)))}${metric('Bakım Servisi',preview.running?'Çalışıyor':preview.releasePublishInProgress?'Yayın bekleniyor':'Hazır')}</div>
      <div class="maintenance-protection"><strong>Korunan veriler</strong><span>Veritabanı ve hesaplar</span><span>Satış, sipariş, ürün ve müşteriler</span><span>Aktif uygulama logları</span><span>Her platformun son iki sürümü</span></div>
      <section class="maintenance-panel">
        <div class="section-heading"><div><h3>Temizlik Önizlemesi</h3><p>Yalnızca aşağıdaki önceden tanımlı görevler çalıştırılabilir. Genel komut veya dosya yolu girilemez.</p></div><button class="btn btn-secondary btn-sm" id="maintenance-refresh">Yenile</button></div>
        <div class="maintenance-task-grid">${taskDefinitions.map(([id,label,description])=>`<label class="maintenance-task ${Number(tasks[id]?.candidateCount||0)===0?'maintenance-task-empty':''}"><input type="checkbox" name="maintenance-task" value="${id}" ${Number(tasks[id]?.candidateCount||0)>0?'checked':''}><span><strong>${esc(label)}</strong><small>${esc(description)}</small><b>${esc(tasks[id]?.candidateCount||0)} öğe · ${esc(fileSize(tasks[id]?.candidateBytes))}</b></span></label>`).join('')}</div>
        <details class="maintenance-files"><summary>Silinecek dosyaları göster (${candidateFiles.length})</summary>${candidateFiles.length?`<ul>${candidateFiles.slice(0,100).map(file=>`<li><code>${esc(file.path)}</code><span>${esc(fileSize(file.size))}</span></li>`).join('')}</ul>`:'<div class="state-panel">Silinecek yayın veya log dosyası bulunamadı.</div>'}</details>
        <div class="maintenance-confirm"><label>İşlemi onaylamak için <code>SUNUCUYU TEMIZLE</code> yazın<input id="maintenance-confirmation" autocomplete="off" placeholder="SUNUCUYU TEMIZLE"></label><button class="btn btn-primary" id="maintenance-run" disabled>Seçilenleri Temizle</button></div>
        <div id="maintenance-result"></div>
      </section>
      <div class="section-heading spaced"><div><h3>Bakım Geçmişi</h3><p>Başarılı ve başarısız işlemler denetim kaydında saklanır.</p></div></div>
      ${table([{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Yönetici',render:r=>esc(r.user_name||r.user_email||'Sistem')},{label:'Sonuç',render:r=>badge(r.action==='SERVER_MAINTENANCE_COMPLETED'?'Başarılı':'Başarısız')},{label:'Açılan Alan',render:r=>esc(fileSize(jsonObject(r.new_value).reclaimedBytes))},{label:'IP',render:r=>esc(r.ip_address||'—')}],history)}`);
    const confirmation=document.getElementById('maintenance-confirmation');
    const runButton=document.getElementById('maintenance-run');
    const updateButton=()=>{const selected=document.querySelectorAll('input[name="maintenance-task"]:checked').length;runButton.disabled=confirmation.value.trim()!=='SUNUCUYU TEMIZLE'||selected===0;};
    confirmation.oninput=updateButton;
    document.querySelectorAll('input[name="maintenance-task"]').forEach(input=>input.onchange=updateButton);
    document.getElementById('maintenance-refresh').onclick=()=>loaders['platform-maintenance']();
    runButton.onclick=async()=>{
      const selected=[...document.querySelectorAll('input[name="maintenance-task"]:checked')].map(input=>input.value);
      runButton.disabled=true;runButton.innerText='Temizleniyor…';
      document.getElementById('maintenance-result').innerHTML='<div class="attention-strip">Bakım görevi çalışıyor. Bu sayfayı kapatmayın.</div>';
      try{
        const result=await apiFetch('/admin/maintenance/cleanup',{method:'POST',body:{tasks:selected,confirmation:confirmation.value.trim()}});
        window._maintenanceLastResult=`Bakım tamamlandı. ${fileSize(result.reclaimedBytes)} alan açıldı.`;
        await loaders['platform-maintenance']();
        const resultBox=document.getElementById('maintenance-result');
        if(resultBox)resultBox.innerHTML=`<div class="state-panel"><strong>${esc(window._maintenanceLastResult)}</strong></div>`;
      }catch(error){
        document.getElementById('maintenance-result').innerHTML=`<div class="state-panel state-error"><strong>Bakım tamamlanamadı</strong><p>${esc(error.message)}</p></div>`;
        runButton.disabled=false;runButton.innerText='Seçilenleri Temizle';
      }
    };
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
    const [admins,auditLogs,companies,diagnostics,recoveryRequests]=await Promise.all([
      apiFetch('/admin/security/admin-users'),
      apiFetch('/admin/audit-logs'),
      apiFetch('/admin/companies'),
      apiFetch(`/admin/diagnostics?${params.toString()}`),
      apiFetch('/admin/security/password-recovery/pending')
    ]);
    const summary=diagnostics.summary||{};
    const companyOptions=companies.map(company=>`<option value="${esc(company.id)}" ${filters.company===String(company.id)?'selected':''}>${esc(company.name)}</option>`).join('');
    const rawEvents=Array.isArray(diagnostics.events)?diagnostics.events:[];
    const events=groupDiagnosticEvents(rawEvents);
    set(`<div class="metrics-grid">${metric('Kritik',summary.critical||0)}${metric('Hata',summary.error||0)}${metric('Toplam Olay',summary.total||0)}${metric('Hata Grubu',events.length)}</div>
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
        <p class="diagnostic-result-note">${summary.total||0} olay, ${events.length} benzer hata grubunda gösteriliyor. Tekrar sayıları ham kayıt toplamına dahildir.</p>
        <div class="diagnostic-list">${events.length?events.map(diagnosticEvent).join(''):'<div class="state-panel">Seçili filtrelerde tanılama kaydı bulunamadı.</div>'}</div>
      </section>
      <div class="section-heading spaced"><div><h3>Admin Hesapları</h3><p>Sistem sahibi rolüne sahip hesaplar.</p></div></div>
      ${table([{label:'Admin',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Son giriş',render:r=>esc(date(r.last_login_at))},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.is_active?'active':'inactive')}],admins)}
      <div class="section-heading spaced"><div><h3>Bekleyen Sysadmin Kurtarma Talepleri</h3><p>Talebi oluşturan veya hedef kullanıcı onay veremez.</p></div></div>
      ${table([{label:'Hedef',render:r=>`${esc(r.target_name)}<small>${esc(r.target_email)}</small>`},{label:'Başlatan',render:r=>esc(r.initiator_name||r.initiated_by)},{label:'Gerekçe',key:'reason'},{label:'Sona erme',render:r=>esc(date(r.expires_at))},{label:'İşlem',render:r=>`<button class="btn btn-primary btn-sm recovery-approve" data-id="${esc(r.id)}">İkinci Onayı Ver</button>`}],recoveryRequests)}
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
    document.querySelectorAll('.recovery-approve').forEach(button=>button.onclick=async()=>{if(!confirm('Bu sysadmin kurtarma talebini bağımsız ikinci onay olarak onaylıyor musunuz?'))return;button.disabled=true;try{const result=await apiFetch(`/admin/security/password-recovery/${encodeURIComponent(button.dataset.id)}/approve`,{method:'POST',body:{}});alert(`Tek kullanımlık kurtarma bilgisi\nTalep: ${button.dataset.id}\nKod: ${result.claim_code}`);await loaders['platform-security']();}catch(error){notice(error.message||'Talep onaylanamadı.');button.disabled=false;}});
  },
  'platform-support': async () => {
    const [result,guestResult]=await Promise.all([apiFetch('/support/tickets'),apiFetch('/support/guest-requests')]);const tickets=result.tickets||[];const guests=guestResult.requests||[];set(`<div class="metrics-grid">${metric('Kayıtlı Talep',tickets.length)}${metric('Açık',tickets.filter(x=>!['closed','resolved'].includes(x.status)).length)}${metric('Doğrulanmamış',guests.filter(x=>x.status==='unverified').length)}${metric('Acil',tickets.filter(x=>x.priority==='P1').length)}</div><div class="section-heading spaced"><div><h3>Kayıtlı Firma Talepleri</h3><p>Firma ve kullanıcı hesabına bağlı destek talepleri.</p></div></div>${table([{label:'No',render:r=>esc(r.id)},{label:'Firma',render:r=>esc(r.company_name||'—')},{label:'Kategori',render:r=>badge(r.category||'technical')},{label:'Konu',key:'subject'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm ticket-open" data-id="${esc(r.id)}">İncele</button>`}],tickets)}<div class="section-heading spaced"><div><h3>Doğrulanmamış Başvurular</h3><p>Hesapla eşleşmeyen kişilerden gelen ön destek başvuruları; müşteri talebi olarak kabul edilmeden önce doğrulanmalıdır.</p></div></div>${table([{label:'Takip No',key:'reference_code'},{label:'Başvuran',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Müşteri durumu',render:r=>badge(r.customer_claim)},{label:'Kategori',render:r=>badge(r.category)},{label:'Konu',key:'subject'},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)}],guests)}`);
    document.querySelectorAll('.ticket-open').forEach(b=>b.onclick=()=>showSupportTicket(b.dataset.id,true));
  },
  'platform-mail': async () => {
    const folder=window._mailFolder||'inbox';const search=window._mailSearch||'';
    const result=await apiFetch(`/mail?folder=${encodeURIComponent(folder)}&search=${encodeURIComponent(search)}`);const messages=result.messages||[];
    const content=`<div class="mail-toolbar"><form class="mail-search" id="mail-search-form"><input id="mail-search-input" value="${esc(search)}" placeholder="E-postalarda ara"><button class="btn btn-secondary btn-sm">Ara</button></form><button class="btn btn-secondary btn-sm" id="mail-refresh">Yenile</button></div>
      <div class="mail-list">${messages.length?messages.map(message=>`<button class="mail-row ${!message.is_read&&message.direction==='inbound'?'unread':''}" data-id="${esc(message.id)}"><span class="mail-row-sender">${esc(message.direction==='outbound'?mailAddresses(message.recipients):message.sender_name||message.sender_email)}</span><span class="mail-row-copy"><strong>${esc(message.subject)}</strong><small>${esc(message.preview||'')}</small></span><time>${esc(mailWhen(message))}</time></button>`).join(''):'<div class="state-panel">Bu klasörde e-posta bulunmuyor.</div>'}</div>`;
    set(mailShell(content,folder,result.unread||0));bindMailNavigation();
    document.getElementById('mail-refresh').onclick=()=>loaders['platform-mail']();
    document.getElementById('mail-search-form').onsubmit=async event=>{event.preventDefault();window._mailSearch=document.getElementById('mail-search-input').value.trim();await loaders['platform-mail']();};
    document.querySelectorAll('.mail-row').forEach(row=>row.onclick=()=>showMailMessage(row.dataset.id));
  },
  'account-settings': async () => {
    const [me,sessions,company]=await Promise.all([apiFetch('/users/me'),apiFetch('/users/sessions'),apiFetch('/company')]);
    const currentToken = sessionStorage.getItem('app_token') || localStorage.getItem('app_token');
    let currentSessionId = null;
    if (currentToken) { try { const p=JSON.parse(atob(currentToken.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))); currentSessionId=p.jti||p.session_id||null; } catch(_){} }
    if (!currentSessionId && sessions.length>0) { const sorted=[...sessions].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)); currentSessionId=sorted[0]?.id; }
    set(`<div class="metrics-grid">${metric('Ad Soyad',me.name)}${metric('E-posta',me.email)}${metric('Yetki',tr((me.roles||[])[0]))}</div><div class="section-heading spaced"><div><h3>Şifre Değiştir</h3><p>Şifre değiştiğinde güvenliğiniz için tüm aktif oturumlar kapatılır.</p></div></div><form class="customer-form-grid" id="change-password-form"><label>Mevcut şifre<input id="current-password" type="password" autocomplete="current-password" required></label><label>Yeni şifre<input id="new-password" type="password" autocomplete="new-password" minlength="10" required placeholder="En az 10 karakter; harf ve rakam"></label><label>Yeni şifre tekrar<input id="confirm-password" type="password" autocomplete="new-password" minlength="10" required></label><button class="btn btn-primary" type="submit">Şifreyi Değiştir</button></form><div class="section-heading spaced"><div><h3>Firma Bilgileri</h3><p>Uygulama ilk kurulumda bu bilgileri hazır olarak kullanır.</p></div></div><form class="customer-form-grid company-profile-form" id="company-profile-form"><label>Firma ünvanı<input id="profile-company-name" value="${esc(company.name||'')}" required></label><label>Yetkili kişi<input id="profile-owner-name" value="${esc(company.owner_name||'')}"></label><label>Telefon<input id="profile-phone" value="${esc(company.phone||'')}"></label><label>Vergi dairesi<input id="profile-tax-office" value="${esc(company.tax_office||'')}"></label><label>İl<input id="profile-city" value="${esc(company.city||'')}"></label><label>İlçe<input id="profile-district" value="${esc(company.district||'')}"></label><label class="wide-field">Adres<input id="profile-address" value="${esc(company.address||'')}"></label><label>Logo adresi <small>İsteğe bağlı</small><input id="profile-logo" value="${esc(company.logo_url||'')}"></label><button class="btn btn-primary" type="submit">Bilgileri Kaydet</button></form><div class="section-heading spaced"><div><h3>Aktif Oturumlar</h3><p>Hesabınıza giriş yapılmış oturumlar. Tanımadığınız bir oturum varsa kapatın.</p></div></div>${table([{label:'Cihaz / Tarayıcı',render:r=>{const isCurrent=r.id===currentSessionId;return `${esc(parseUA(r.user_agent))}${isCurrent?'<span class="status-badge status-active" style="margin-left:8px">✓ Bu oturum</span>':''}`;}},{label:'IP Adresi',render:r=>esc(r.ip_address||'—')},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm revoke-session" data-id="${esc(r.id)}" ${r.id===currentSessionId?'title="Bu mevcut oturumunuzdur"':''}>Oturumu Kapat</button>`}],sessions)}`);
    const companyForm=document.getElementById('company-profile-form');
    companyForm.insertAdjacentHTML('beforebegin','<div class="section-heading spaced"><div><h3>Kurtarma Kodları</h3><p>Yeni set oluşturulduğunda eski kullanılmamış kodlar iptal edilir.</p></div></div><form class="customer-form-grid" id="recovery-codes-form"><label>Mevcut şifre<input id="recovery-current-password" type="password" autocomplete="current-password" required></label><button class="btn btn-secondary" type="submit">Yeni Kurtarma Kodları Oluştur</button></form>');
    document.getElementById('recovery-codes-form').onsubmit=async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;try{const result=await apiFetch('/auth/recovery/codes/regenerate',{method:'POST',body:{current_password:document.getElementById('recovery-current-password').value}});const text=`Serenut OS kurtarma kodları\n\n${result.recovery_codes.join('\n')}\n`;const blob=new Blob([text],{type:'text/plain;charset=utf-8'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='serenut-kurtarma-kodlari.txt';link.click();URL.revokeObjectURL(link.href);alert(`Yeni kodlar oluşturuldu ve indirildi.\n\n${result.recovery_codes.join('\n')}`);}catch(error){notice(error.message||'Kodlar oluşturulamadı.');button.disabled=false;}};
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
