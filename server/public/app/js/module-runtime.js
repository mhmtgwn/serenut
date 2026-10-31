import { apiFetch, getAuthToken } from '/shared/js/api-client.js';
import { escapeHtml as esc, formatCurrency as money, formatDate as date, translateStatus as tr } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

const statusSlug = v => {
  const raw = String(v || 'unknown').toLowerCase().trim();
  const map = {
    'aktif': 'active', 'active': 'active', 'paid': 'active', 'ödendi': 'active', 'completed': 'active', 'tamamlandı': 'active',
    'resolved': 'active', 'çözüldü': 'active', 'online': 'online', 'çevrimiçi': 'online', 'up': 'active', 'çalışıyor': 'active',
    'configured': 'active', 'yapılandırıldı': 'active', 'başarılı': 'active',
    'trial': 'trial', 'trialing': 'trial', 'deneme süresi': 'trial', 'in_progress': 'trial', 'işlemde': 'trial', 'under_review': 'trial', 'inceleniyor': 'trial',
    'pending': 'pending', 'beklemede': 'pending', 'pending_review': 'pending', 'onay bekliyor': 'pending',
    'verification_pending': 'pending', 'doğrulama bekliyor': 'pending', 'pending_customer': 'pending', 'müşteri yanıtı bekleniyor': 'pending',
    'unverified': 'pending', 'yeni başvuru': 'pending', 'grace_period': 'pending', 'ödeme bekliyor': 'pending', 'warning': 'pending', 'uyarı': 'pending',
    'inactive': 'inactive', 'pasif': 'inactive', 'offline': 'offline', 'çevrimdışı': 'offline', 'closed': 'closed', 'kapalı': 'closed',
    'suspended': 'suspended', 'askıya alındı': 'suspended', 'expired': 'expired', 'süresi doldu': 'expired',
    'revoked': 'revoked', 'iptal edildi': 'revoked', 'cancelled': 'revoked', 'canceled': 'revoked',
    'failed': 'failed', 'başarısız': 'failed', 'rejected': 'failed', 'reddedildi': 'failed', 'error': 'failed', 'hata': 'failed', 'critical': 'failed', 'kritik': 'failed'
  };
  return map[raw] || raw.replace(/[^a-z0-9_-]/g, '-');
};
const badge = v => `<span class="status-badge status-${esc(statusSlug(v))}">${esc(tr(v || '—'))}</span>`;
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

function formatDevicePlatform(platform, osVersion) {
  const p = String(platform || '').toLowerCase();
  let icon = '💻';
  let title = 'Bilinmiyor';
  if (p.includes('windows')) {
    icon = '🪟';
    title = 'Windows';
  } else if (p.includes('android')) {
    icon = '📱';
    title = 'Android';
  } else if (p.includes('linux')) {
    icon = '🐧';
    title = 'Linux';
  } else if (p.includes('mac') || p.includes('ios')) {
    icon = '🍎';
    title = 'Apple';
  } else if (platform && platform !== 'unknown' && platform !== '—') {
    title = platform;
  }
  const osText = (osVersion && osVersion !== '—' && osVersion !== 'null') ? osVersion : (title !== 'Bilinmiyor' ? `${title} İşletim Sistemi` : 'İşletim sistemi bilgisi yok');
  return `<div style="display:flex;align-items:center;gap:6px;"><span style="font-size:16px;">${icon}</span><div><strong style="display:block;font-size:13px;">${esc(title)}</strong><small style="color:var(--text-muted, #94a3b8);display:block;font-size:11px;">${esc(osText)}</small></div></div>`;
}

function table(columns, rows) {
  if (!Array.isArray(rows) || !rows.length) return '<div class="state-panel">Kayıt bulunamadı.</div>';
  return `<div class="table-wrap"><table><thead><tr>${columns.map(c => `<th>${esc(c.label)}</th>`).join('')}</tr></thead><tbody>${rows.map(row => `<tr>${columns.map(c => `<td>${c.render ? c.render(row) : esc(row[c.key] ?? '—')}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}

function set(html) { document.getElementById('embed-content').innerHTML = html; }
function notice(message, type) {
  const text = String(message || '');
  const resolved = type || (/(hata|başarısız|olamaz|bulunamadı|reddedildi|zorunludur|eşleşmiyor|kaldırılamadı|silinemedi|oluşturulamadı|gönderilemedi|onaylanamadı|kesilemedi|indirilemedi)/i.test(text)
    ? 'error'
    : /(başarıyla|oluşturuldu|kaydedildi|güncellendi|onaylandı|aktifleştirildi|kopyalandı|indirildi|gönderildi|silindi|kaldırıldı|üretildi|kuruldu|alındı)/i.test(text)
      ? 'success'
      : 'info');
  try { showToast(text, resolved, 4500); } catch (_) { window.alert(text); }
}

function showRecoveryClaimBanner(title, requestId, claimCode, email = '', extraNote = '') {
  const container = document.getElementById('embed-content');
  if (!container) return;
  container.querySelector('.recovery-claim-banner')?.remove();
  const origin = window.location.origin;
  const recoveryUrl = `${origin}/forgot-password?request_id=${encodeURIComponent(requestId || '')}&claim_code=${encodeURIComponent(claimCode || '')}`;
  const summaryText = `${title}${email ? `\nHesap: ${email}` : ''}\nTalep No: ${requestId}\nTek Kullanımlık Kod: ${claimCode}\nDoğrudan Bağlantı: ${recoveryUrl}`;
  const banner = document.createElement('section');
  banner.className = 'state-panel recovery-claim-banner';
  banner.style.border = '2px solid #16a34a';
  banner.style.marginBottom = '16px';
  banner.innerHTML = `
    <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:12px;flex-wrap:wrap">
      <div>
        <strong style="color:#16a34a;font-size:15px">🔑 ${esc(title)}</strong>
        ${email ? `<p style="margin:4px 0"><strong>Kullanıcı:</strong> ${esc(email)}</p>` : ''}
        ${extraNote ? `<p style="margin:4px 0">${esc(extraNote)}</p>` : ''}
        <p style="margin:4px 0"><strong>Talep Numarası:</strong> <code style="user-select:all">${esc(requestId)}</code></p>
        <p style="margin:4px 0"><strong>Tek Kullanımlık Kod:</strong> <code style="user-select:all;font-weight:700">${esc(claimCode)}</code></p>
        <p style="margin:4px 0;font-size:12px;color:var(--text-muted,#64748b)">Kullanıcı bu bağlantı ile doğrudan yeni şifresini belirleyebilir: <code style="user-select:all">${esc(recoveryUrl)}</code></p>
      </div>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button type="button" class="btn btn-primary btn-sm copy-claim-all">Bilgileri Kopyala</button>
        <button type="button" class="btn btn-secondary btn-sm copy-claim-url">Kurtarma Linkini Kopyala</button>
        <button type="button" class="btn btn-secondary btn-sm close-claim-banner">Kapat</button>
      </div>
    </div>`;
  banner.querySelector('.copy-claim-all').onclick = async () => {
    try { await navigator.clipboard.writeText(summaryText); notice('Kurtarma bilgileri panoya kopyalandı.'); } catch (_) {}
  };
  banner.querySelector('.copy-claim-url').onclick = async () => {
    try { await navigator.clipboard.writeText(recoveryUrl); notice('Doğrudan kurtarma bağlantısı kopyalandı.'); } catch (_) {}
  };
  banner.querySelector('.close-claim-banner').onclick = () => banner.remove();
  container.prepend(banner);
}

function attachTableFilter(inputId) {
  const input = document.getElementById(inputId);
  if (!input) return;
  input.addEventListener('input', () => {
    const q = input.value.trim().toLocaleLowerCase('tr-TR');
    const wrap = input.closest('#embed-content')?.querySelector('.table-wrap');
    if (!wrap) return;
    wrap.querySelectorAll('tbody tr').forEach(trEl => {
      const match = !q || trEl.textContent.toLocaleLowerCase('tr-TR').includes(q);
      trEl.style.display = match ? '' : 'none';
    });
  });
}

function bindCopyButtons(root = document) {
  root.querySelectorAll('.copy-value-btn').forEach(btn => {
    btn.onclick = async () => {
      const val = btn.dataset.copy || '';
      if (!val) return;
      try {
        await navigator.clipboard.writeText(val);
        const prev = btn.textContent;
        btn.textContent = '✓ Kopyalandı';
        notice('Panoya kopyalandı.');
        setTimeout(() => { btn.textContent = prev; }, 2000);
      } catch (_) {}
    };
  });
}

async function showSupportTicket(ticketId, isAdmin) {
  const detail=await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}`);
  const ticket=detail.ticket;const messages=detail.messages||[];
  const transitions={open:['in_progress','closed'],in_progress:['pending_customer','resolved'],pending_customer:['in_progress','closed'],resolved:['closed','in_progress'],closed:[]};
  const statuses=transitions[ticket.status]||[];
  set(`<button class="btn btn-secondary btn-sm" id="ticket-back">← Listeye dön</button>
    <div class="ticket-detail-head"><div><span class="ticket-number">${esc(ticket.id)}</span><h3>${esc(ticket.subject)}</h3><p>${esc(ticket.company_name||'')}</p></div><div>${badge(ticket.priority)} ${badge(ticket.status)}</div></div>
    <div class="ticket-meta-grid"><div><span>Kategori</span><strong>${esc(tr(ticket.category||'technical'))}</strong></div><div><span>Oluşturma</span><strong>${esc(date(ticket.created_at))}</strong></div><div><span>SLA</span><strong>${esc(date(ticket.sla_deadline_at))}</strong></div><div><span>Atanan</span><strong>${esc(ticket.assigned_to||'Atanmadı')}</strong></div></div>
    <div class="ticket-thread">${messages.map(m=>`<article class="ticket-message ${m.sender_name==='Serenut Destek'?'from-support':'from-customer'}"><header><strong>${esc(m.sender_name)}</strong><time>${esc(date(m.created_at))}</time></header><p>${esc(m.message)}</p></article>`).join('')||'<div class="state-panel">Henüz mesaj yok.</div>'}</div>
    ${ticket.status==='closed'?'<div class="attention-strip"><span>Bu talep kapatılmıştır.</span></div>':`<form class="ticket-reply-form" id="ticket-reply"><label>Yanıt<textarea id="ticket-reply-message" required maxlength="10000" placeholder="Yanıtınızı yazın"></textarea></label><div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn btn-primary" type="submit">Yanıtı Gönder</button>${!isAdmin?'<button class="btn btn-secondary" type="button" id="customer-close-ticket">Talebi Kapat</button>':''}</div></form>`}
    ${isAdmin&&statuses.length?`<form class="ticket-status-form" id="ticket-status"><label>Yeni durum<select id="ticket-status-value">${statuses.map(s=>`<option value="${s}">${esc(tr(s))}</option>`).join('')}</select></label><button class="btn btn-secondary">Durumu Güncelle</button></form>`:''}`);
  document.getElementById('ticket-back').onclick=()=>loaders[isAdmin?'platform-support':'support-center']();
  const reply=document.getElementById('ticket-reply');
  if(reply)reply.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}/messages`,{method:'POST',body:{message:document.getElementById('ticket-reply-message').value.trim()}});await showSupportTicket(ticketId,isAdmin);}catch(x){notice(x.message);b.disabled=false}};
  const status=document.getElementById('ticket-status');
  if(status)status.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}/status`,{method:'PATCH',body:{status:document.getElementById('ticket-status-value').value}});await showSupportTicket(ticketId,true);}catch(x){notice(x.message);b.disabled=false}};
  const customerClose=document.getElementById('customer-close-ticket');
  if(customerClose)customerClose.onclick=async()=>{if(!confirm('Bu destek talebini çözüldü/kapalı olarak işaretlemek istiyor musunuz?'))return;customerClose.disabled=true;try{await apiFetch(`/support/tickets/${encodeURIComponent(ticketId)}/status`,{method:'PATCH',body:{status:'closed'}});notice('Destek talebiniz kapatıldı.');await showSupportTicket(ticketId,false);}catch(x){notice(x.message);customerClose.disabled=false}};
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

async function showGuestRequest(requestId, backTarget = 'platform-support') {
  const result=await apiFetch(`/support/guest-requests/${encodeURIComponent(requestId)}`);const request=result.request;
  const source=request.intake_source==='inbound_email'?'E-postadan yönlendirildi':'İletişim formu';
  set(`<button class="btn btn-secondary btn-sm" id="guest-back">← Başvurulara dön</button>
    <div class="ticket-detail-head"><div><span class="ticket-number">${esc(request.reference_code)}</span><h3>${esc(request.subject)}</h3><p>${esc(request.name)} · ${esc(request.email)}</p></div><div>${badge(tr(request.status))}</div></div>
    <div class="ticket-meta-grid"><div><span>Kaynak</span><strong>${esc(source)}</strong></div><div><span>Müşteri durumu</span><strong>${esc(tr(request.customer_claim))}</strong></div><div><span>Kategori</span><strong>${esc(tr(request.category))}</strong></div><div><span>Tarih</span><strong>${esc(date(request.created_at))}</strong></div></div>
    <article class="guest-request-message"><h4>Başvuru mesajı</h4><p>${esc(request.message)}</p></article>
    <div class="guest-request-actions">
      <button class="btn btn-primary btn-sm" id="guest-email-reply" type="button">E-posta ile Yanıtla</button>
      ${request.status!=='under_review'?'<button class="btn btn-secondary btn-sm guest-status" data-status="under_review">İncelemeye Al</button>':''}
      ${request.status!=='routed_to_sales'?'<button class="btn btn-secondary btn-sm guest-status" data-status="routed_to_sales">Satışa Yönlendir</button>':''}
      ${request.status!=='closed'?'<button class="btn btn-secondary btn-sm guest-status" data-status="closed">Kapat</button>':''}
    </div>`);
  document.getElementById('guest-back').onclick=()=>loaders[backTarget]();
  document.getElementById('guest-email-reply').onclick=()=>showMailComposer({sender_email:request.email,subject:request.subject,text_body:request.message});
  document.querySelectorAll('.guest-status').forEach(button=>button.onclick=async()=>{button.disabled=true;try{await apiFetch(`/support/guest-requests/${encodeURIComponent(requestId)}/status`,{method:'PATCH',body:{status:button.dataset.status}});await showGuestRequest(requestId);}catch(error){notice(error.message||'Başvuru güncellenemedi.');button.disabled=false;}});
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
      <button class="mail-folder ${activeFolder==='trash'?'active':''}" data-folder="trash">Çöp Kutusu</button>
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
  const inTrash=Boolean(message.deleted_at);
  set(mailShell(`<div class="mail-toolbar"><button class="btn btn-secondary btn-sm" id="mail-message-back">← Listeye dön</button><div class="mail-toolbar-actions">${!inTrash&&inbound?'<button class="btn btn-primary btn-sm" id="mail-reply">Yanıtla</button>':''}${!inTrash&&inbound&&!message.guest_request_id?'<button class="btn btn-secondary btn-sm" id="mail-to-support">Desteğe Yönlendir</button>':''}${message.guest_request_id?'<button class="btn btn-secondary btn-sm" id="mail-open-support">Destek Kaydını Aç</button>':''}${!inTrash?`<button class="btn btn-secondary btn-sm" id="mail-archive">${message.is_archived?'Arşivden çıkar':'Arşivle'}</button><button class="btn btn-danger btn-sm" id="mail-delete">Sil</button>`:'<button class="btn btn-primary btn-sm" id="mail-restore">Geri Yükle</button>'}</div></div>
    <article class="mail-detail"><header><h3>${esc(message.subject)}</h3><div><strong>${esc(message.sender_name||message.sender_email)}</strong> &lt;${esc(message.sender_email)}&gt;</div><small>Kime: ${esc(mailAddresses(message.recipients))} · ${esc(mailWhen(message))}</small></header>
      <div class="mail-thread">${thread.map(item=>`<article class="mail-thread-message ${item.direction}"><header><strong>${esc(item.direction==='outbound'?'Serenut Destek':item.sender_name||item.sender_email)}</strong><time>${esc(mailWhen(item))}</time></header><div>${esc(item.text_body||'').replace(/\n/g,'<br>')}</div></article>`).join('')}</div>
      ${Array.isArray(message.attachment_metadata)&&message.attachment_metadata.length?`<div class="mail-attachments"><strong>Ekler</strong>${message.attachment_metadata.map(a=>`<button class="mail-attachment-download" data-message="${esc(message.id)}" data-attachment="${esc(a.id)}" data-filename="${esc(a.filename||'ek')}">${esc(a.filename||'Dosya')} <small>${esc(fileSize(a.size))}</small></button>`).join('')}</div>`:''}
    </article>`,window._mailFolder||'inbox'));
  bindMailNavigation();
  document.getElementById('mail-message-back').onclick=()=>loaders['platform-mail']();
  const reply=document.getElementById('mail-reply');if(reply)reply.onclick=()=>showMailComposer(message);
  const toSupport=document.getElementById('mail-to-support');if(toSupport)toSupport.onclick=async()=>{toSupport.disabled=true;try{const routed=await apiFetch(`/mail/${encodeURIComponent(id)}/route-to-support`,{method:'POST',body:{}});notice(`Destek başvurusu oluşturuldu: ${routed.request.reference_code}`);await showGuestRequest(routed.request.id,'platform-mail');}catch(error){notice(error.message||'E-posta desteğe yönlendirilemedi.');toSupport.disabled=false;}};
  const openSupport=document.getElementById('mail-open-support');if(openSupport)openSupport.onclick=()=>showGuestRequest(message.guest_request_id,'platform-mail');
  const archive=document.getElementById('mail-archive');if(archive)archive.onclick=async()=>{await apiFetch(`/mail/${encodeURIComponent(id)}`,{method:'PATCH',body:{is_archived:!message.is_archived}});await loaders['platform-mail']();};
  const remove=document.getElementById('mail-delete');if(remove)remove.onclick=async()=>{if(!confirm('Bu e-posta Çöp Kutusu’na taşınacak. Devam edilsin mi?'))return;remove.disabled=true;try{await apiFetch(`/mail/${encodeURIComponent(id)}`,{method:'DELETE'});window._mailFolder='trash';await loaders['platform-mail']();}catch(error){notice(error.message||'E-posta silinemedi.');remove.disabled=false;}};
  const restore=document.getElementById('mail-restore');if(restore)restore.onclick=async()=>{restore.disabled=true;try{await apiFetch(`/mail/${encodeURIComponent(id)}`,{method:'PATCH',body:{restore:true}});window._mailFolder=message.direction==='outbound'?'sent':'inbox';await loaders['platform-mail']();}catch(error){notice(error.message||'E-posta geri yüklenemedi.');restore.disabled=false;}};
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
  const companyEmail = (d.users?.find(u => u.is_active !== false) || d.users?.[0])?.email || c.email || "";
  const selectedPlanId = override?.base_plan_id || subscription?.plan_id || plans[0]?.id || "";
  const planOptions = plans.map(plan => `<option value="${esc(plan.id)}" ${String(plan.id) === String(selectedPlanId) ? "selected" : ""}>${esc(plan.name)} · ${esc(money(plan.price, plan.currency || "TRY"))} / ${plan.billing_interval === "yearly" ? "yıl" : "ay"}</option>`).join("");
  const cs = d.cloud_stats || {}; const cleanTax = c.tax_number && !String(c.tax_number).startsWith("PENDING-") ? c.tax_number : ""; return `<button class="btn btn-secondary" id="back-companies">← Firmalara dön</button><div class="company-detail-head"><div><span>FİRMA DETAYI · KOD: ${esc(c.business_code || '—')}</span><h3>${esc(c.name)}</h3><p>${esc(c.email || "E-posta yok")} · ${esc(c.phone || "Telefon yok")}</p></div><div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">${badge(c.status)}<button class="btn btn-secondary btn-sm" id="send-reset-pw-btn" data-email="${esc(companyEmail)}">🔒 Kurtarma Talebi Oluştur</button><button class="btn btn-danger btn-sm" id="archive-company-btn" data-id="${esc(c.id)}" data-name="${esc(c.name)}">🗑️ Firmayı Arşivle</button></div></div><div class="company-tabs"><button class="btn btn-secondary btn-sm company-tab active" data-tab="summary">Firma Özeti</button><button class="btn btn-secondary btn-sm company-tab" data-tab="subscription">Abonelik & Süre Uzat</button><button class="btn btn-secondary btn-sm company-tab" data-tab="licenses">Lisans ve Cihazlar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="users">Kullanıcılar</button><button class="btn btn-secondary btn-sm company-tab" data-tab="branches">Şubeler</button><button class="btn btn-secondary btn-sm company-tab" data-tab="payments">Ödemeler</button></div><section class="company-tab-panel" data-panel="summary"><div class="metrics-grid">${metric("Kullanıcı", d.users?.length || 0)}${metric("Cihaz", d.devices?.length || 0)}${metric("Şube", d.stores?.length || 0)}${metric("Abonelik", subscription?.plan_name || "Yok")}${metric("Bulut Ürün / Satış", `${cs.products_count || 0} Ürün · ${cs.sales_count || 0} Satış`)}${metric("Son Sync v4", cs.last_sync_at ? date(cs.last_sync_at) : "Henüz yok")}</div><div class="section-heading spaced"><div><h3>Firma Bilgilerini Düzenle</h3><p>Firma ünvanı, iletişim ve vergi bilgilerini doğrudan güncelleyebilirsiniz.</p></div></div><form class="admin-form-grid" id="edit-company-form"><label>Firma Ünvanı<input id="edit-company-name" value="${esc(c.name || "")}" required></label><label>TC / Vergi No<input id="edit-company-tax" value="${esc(cleanTax)}" placeholder="Belirtilmedi"></label><label>Vergi Dairesi<input id="edit-company-tax-office" value="${esc(c.tax_office || "")}"></label><label>E-posta<input id="edit-company-email" type="email" value="${esc(c.email || "")}"></label><label>Telefon<input id="edit-company-phone" value="${esc(c.phone || "")}"></label><label class="wide-field">Adres<input id="edit-company-address" value="${esc(c.address || "")}"></label><button class="btn btn-primary" type="submit">Bilgileri Güncelle</button></form></section><section class="company-tab-panel app-hidden" data-panel="subscription"><div class="section-heading"><div><h3>Abonelik ve Özel Paket</h3><p>Bu firmaya ait ticari ve kullanım limitlerini yönetin. Hızlı süre tanımlama veya özel fiyat teklifi oluşturabilirsiniz.</p></div>${badge(subscription?.status || "subscription_yok")}</div>${
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
  }<div class="section-heading spaced"><div><h3>Hızlı Süre Uzatma / Manuel Abonelik Tanımlama</h3><p>Havale veya kart ödemesi beklemeden aboneliği ve lisans haklarını hemen başlatır veya uzatır.</p></div><div style="display:flex;gap:6px;flex-wrap:wrap"><button type="button" class="btn btn-secondary btn-sm quick-grant-days" data-days="30" data-reason="Yönetici tarafından +30 gün süre uzatımı">+30 Gün</button><button type="button" class="btn btn-secondary btn-sm quick-grant-days" data-days="90" data-reason="Yönetici tarafından +90 gün süre uzatımı">+90 Gün</button><button type="button" class="btn btn-secondary btn-sm quick-grant-days" data-days="365" data-reason="Yönetici tarafından +1 yıl yıllık sözleşme tanımlaması">+1 Yıl (365 Gün)</button></div></div><form class="admin-form-grid" id="manual-subscription-form"><label>Uygulanacak plan<select id="manual-plan" required>${planOptions}</select></label><label>Süre (gün)<input id="manual-days" type="number" min="1" max="3660" value="365" required></label><label>Cihaz limiti <small>(İsteğe bağlı)</small><input id="manual-devices" type="number" min="1" max="1000" placeholder="Plan/özel teklif limiti"></label><label>Şube limiti <small>(İsteğe bağlı)</small><input id="manual-stores" type="number" min="1" max="1000" placeholder="Plan/özel teklif limiti"></label><label style="grid-column:1/-1">Gerekçe<input id="manual-reason" minlength="10" required placeholder="Örn. imzalı yıllık sözleşme, ücretsiz tanımlama veya kampanya"></label><button class="btn btn-primary" type="submit">Aboneliği Hemen Aktifleştir</button></form><details class="admin-create-panel" style="margin-top:18px"><summary>Gelişmiş: Firmaya Özel Fiyat ve Limit Teklifi Tanımla (Ödeme Bekleyen)</summary><form class="admin-form-grid" id="company-package-form"><label>Temel plan<select id="package-plan" required>${planOptions}</select></label><label>Özel fiyat <small>(İsteğe bağlı)</small><input id="package-price" type="number" min="0" step="0.01" value="${esc(override?.custom_price || "")}" placeholder="Boş bırakırsanız plan fiyatı uygulanır"></label><label>Dönem<select id="package-period"><option value="monthly" ${override?.billing_interval === "monthly" ? "selected" : ""}>Aylık</option><option value="yearly" ${override?.billing_interval === "yearly" ? "selected" : ""}>Yıllık</option></select></label><label>Kullanıcı limiti<input id="package-users" type="number" min="1" value="${esc(override?.user_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Şube limiti<input id="package-stores" type="number" min="1" value="${esc(override?.store_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Cihaz limiti<input id="package-devices" type="number" min="1" value="${esc(override?.device_limit || "")}" placeholder="Plan limiti geçerli"></label><label>Başlangıç<input id="package-from" type="date" value="${esc(from)}" required></label><label>Bitiş<input id="package-until" type="date" value="${esc(until)}" required></label><label><input id="package-renew" type="checkbox" ${override?.auto_renew ? "checked" : ""}> Otomatik yenile</label><label style="grid-column:1/-1">Gerekçe<input id="package-reason" value="${esc(override?.reason || "")}" required placeholder="Sözleşme / kampanya gerekçesi"></label><button class="btn btn-secondary" type="submit">Özel Teklifi Kaydet</button></form></details></section><section class="company-tab-panel app-hidden" data-panel="licenses">${table(
    [
      { label: "Anahtar", render: (r) => r.license_key ? `<code>${esc(r.license_key)}</code> <button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(r.license_key)}">Kopyala</button>` : "—" },
      { label: "Plan", render: (r) => esc(r.plan_name || r.plan_id) },
      { label: "Cihaz limiti", key: "device_limit" },
      { label: "Şube limiti", key: "store_limit" },
      { label: "Bitiş", render: (r) => esc(date(r.valid_until)) },
      { label: "Durum", render: (r) => badge(r.status) },

    ],
    d.licenses,
  )}<h3 class="content-title">Cihazlar</h3>${table(
    [
      { label: "Cihaz", render: (r) => `<strong>${esc(r.name || 'Terminal')}</strong><small>${esc(r.id ? r.id.slice(0, 16) : '—')}</small>` },
      { label: "İşletim Sistemi", render: (r) => formatDevicePlatform(r.platform, r.os_version) },
      { label: "Son Aktivite", render: (r) => esc(date(r.last_active_at)) },
      { label: "İşlem", render: (r) => `<div style="display:flex;gap:6px;flex-wrap:wrap"><button type="button" class="btn btn-secondary btn-sm company-device-toggle" data-id="${esc(r.id)}">${r.status === 'active' ? 'Engelle' : 'Etkinleştir'}</button><button type="button" class="btn btn-danger btn-sm company-device-delete" data-id="${esc(r.id)}" data-name="${esc(r.name || 'Terminal')}">🗑️ Cihazı Kaldır</button></div>` },
      { label: "Durum", render: (r) => badge(r.status) },

    ],
    d.devices,
  )}</section><section class="company-tab-panel app-hidden" data-panel="users"><details class="admin-create-panel" style="margin-bottom:12px"><summary>+ Bu Firmaya Yeni Kullanıcı Ekle</summary><form class="admin-form-grid" id="admin-add-company-user-form"><label>Ad Soyad<input id="admin-user-name" required placeholder="Örn. Ayşe Demir"></label><label>E-posta<input id="admin-user-email" type="email" required placeholder="ayse@firma.com"></label><label>Rol<select id="admin-user-role"><option value="owner">Firma Yöneticisi (Owner)</option><option value="cashier">Kasiyer</option></select></label><button class="btn btn-primary" type="submit">Kullanıcıyı Ekle ve Aktivasyon Kodu Üret</button></form></details>${table(
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
          `<div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn btn-secondary btn-sm user-detail-reset-pw" data-email="${esc(r.email)}">Kurtarma Talebi Oluştur</button><button class="btn btn-secondary btn-sm user-force-logout" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Oturumları Kapat</button></div>`,
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
  const [accounts, plans, paymentMethods, quote, company] = await Promise.all([apiFetch('/billing/bank-accounts'), apiFetch('/billing/effective-plans'), apiFetch('/billing/payment-methods'),apiFetch('/billing/quotes',{method:'POST',body:{plan_id:planId,billing_period:billingPeriod}}),apiFetch('/company').catch(()=>({}))]); const needsBillingInfo = !company?.tax_number || String(company.tax_number).startsWith('PENDING-') || !company?.address; const billingInfoForm = `<div class="customer-create-panel" style="margin-bottom:14px;padding:14px"><h4 style="margin:0 0 6px">Fatura Bilgileri ${needsBillingInfo?'<span class="status-badge status-warning">Fatura için gerekli</span>':''}</h4><p style="margin:0 0 10px;font-size:13px;color:var(--text-muted)">Ödeme sonrası resmi faturanızın kesilebilmesi için vergi/TC numaranızı ve adresinizi kontrol edin.</p><div class="customer-form-grid"><label>TC Kimlik veya Vergi No (10-11 hane)<input id="checkout-tax-number" maxlength="11" required value="${esc(company?.tax_number && !String(company.tax_number).startsWith('PENDING-') ? company.tax_number : '')}" placeholder="10 veya 11 haneli numara"></label><label>Vergi Dairesi<input id="checkout-tax-office" value="${esc(company?.tax_office||'')}" placeholder="Örn: Kadıköy VD"></label><label class="wide-field">Fatura Adresi<input id="checkout-address" required value="${esc(company?.address||'')}" placeholder="Açık fatura adresi"></label></div></div>`; const ensureBillingProfile = async () => { const tax = document.getElementById('checkout-tax-number')?.value.replace(/\D/g,'')||''; const addr = document.getElementById('checkout-address')?.value.trim()||''; const office = document.getElementById('checkout-tax-office')?.value.trim()||''; if (![10,11].includes(tax.length)) throw new Error('Fatura için lütfen 10 haneli VKN veya 11 haneli TC Kimlik No girin.'); if (!addr) throw new Error('Fatura adresi zorunludur.'); if (needsBillingInfo || tax !== company?.tax_number || addr !== company?.address) { await apiFetch('/company', { method: 'PATCH', body: { tax_number: tax, tax_office: office, address: addr } }); } };
  const plan = plans.find(p=>String(p.id)===String(planId)) || {};
  const amount = Number(quote.amount || 0);
  const accountCards = accounts.map((a,index)=>`<label class="bank-choice"><input type="radio" name="bank-account" value="${esc(a.id)}" ${index===0?'checked':''}><span><b>${esc(a.bank_name)}</b><small>Alıcı: ${esc(a.account_holder||'Serenut')}</small><code>${esc(a.iban)}</code>${a.branch_name?`<small>Şube: ${esc(a.branch_name)}</small>`:''}</span></label>`).join('');
  const cardEnabled = paymentMethods.some(method=>method.id==='iyzico');
  const cardAction = cardEnabled ? '<button class="btn btn-primary" id="start-card-checkout" type="button">Kredi / Banka Kartıyla Öde</button>' : '';
  const transferContent = accounts.length ? `<form id="bank-transfer-form"><div class="bank-choice-grid">${accountCards}</div><div class="transfer-steps"><b>Nasıl ödeyeceksiniz?</b><ol><li>Banka hesabını seçin.</li><li>Ödeme talebini oluşturun.</li><li>Üretilen referansı havale açıklamasına yazın.</li><li>Ödemeyi yaptığınızı bildirin.</li><li>Onaydan sonra aboneliğiniz etkinleşir.</li></ol></div><button class="btn btn-secondary" type="submit">Havale Referansı Oluştur</button></form>` : '<div class="state-panel">Aktif havale hesabı bulunamadı.</div>';
  const quotedPeriod=quote.billing_period;
  set(`<button class="btn btn-secondary back-button" id="back-to-billing">← Planlara dön</button>${billingInfoForm}<div class="payment-layout"><section class="payment-summary"><span>SEÇİLEN PLAN</span><h3>${esc(plan.name||'Abonelik')}</h3><strong>${esc(money(amount,quote.currency||plan.currency||'TRY'))}</strong><p>${quotedPeriod==='yearly'?'Yıllık ödeme':'Aylık ödeme'}</p>${cardAction}</section><section class="transfer-panel"><div class="section-heading"><div><h3>Havale / EFT</h3><p>Aşağıdaki hesaba ödeme yapın. Talep oluşturunca açıklamaya yazacağınız referans kodu üretilir.</p></div></div>${transferContent}</section></div><label class="billing-legal-consent"><input id="billing-legal-acceptance" type="checkbox" required><span><a href="/terms" target="_blank" rel="noopener noreferrer">Ön Bilgilendirme Formu ve Mesafeli Satış Sözleşmesi</a>'ni okudum; plan, dönem ve tutarı kabul ediyorum.</span></label><div id="payment-result"></div>`);
    document.getElementById('back-to-billing').onclick = () => loaders['billing-center']();
    const cardButton = document.getElementById('start-card-checkout');
    if (cardButton) cardButton.onclick = async () => {
      if (!document.getElementById('billing-legal-acceptance').checked) return notice('Ön bilgilendirme ve mesafeli satış koşullarını onaylayın.');
      cardButton.disabled = true;
      try {
        await ensureBillingProfile(); const checkout = await apiFetch('/billing/subscribe',{method:'POST',body:{quote_id:quote.quote_id,legal_acceptance:true,pre_information_version:'2026-08-09',distance_sales_version:'2026-08-09'}});
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
        await ensureBillingProfile(); const selected=document.querySelector('input[name="bank-account"]:checked');
        const result=await apiFetch('/billing/request-bank-transfer',{method:'POST',body:{quote_id:quote.quote_id,bank_account_id:selected.value,legal_acceptance:true,pre_information_version:'2026-08-09',distance_sales_version:'2026-08-09'}});
        document.getElementById('payment-result').innerHTML=`<div class="payment-result transfer-result"><span>${result.billing_period==='yearly'?'YILLIK':'AYLIK'} ÖDEME AÇIKLAMASI</span><div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap"><strong>${esc(result.reference_code)}</strong><button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(result.reference_code)}">Referansı Kopyala</button></div><p><b>${esc(result.bank.bank_name)}</b><br><code style="user-select:all">${esc(result.bank.iban)}</code> <button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(result.bank.iban)}">IBAN Kopyala</button></p><p>Havale açıklamasına yalnızca bu referans kodunu yazın.</p><p class="result-amount">${esc(money(result.amount,result.currency||'TRY'))}</p><p>Seçilen ödeme dönemi: ${result.billing_period==='yearly'?'1 yıl':'1 ay'}</p><form id="transfer-notification-form" class="payment-form"><h3>Ödemeyi yaptıysanız bildirin</h3><label>Gönderen adı<input id="transfer-sender-name" required placeholder="Hesap sahibinin adı"></label><label>Gönderen banka<input id="transfer-sender-bank" placeholder="Banka adı"></label><label>Transfer tarihi<input id="transfer-date" type="date" required></label><label>Açıklama<textarea id="transfer-description" rows="2" placeholder="İsteğe bağlı not"></textarea></label><button class="btn btn-primary" type="submit">Ödemeyi Yaptım</button></form><div id="transfer-notification-status"></div></div>`;
        bindCopyButtons(document.getElementById('payment-result'));
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

let whatsappConnectionPollTimer;
function stopWhatsAppConnectionPoll() {
  if (whatsappConnectionPollTimer) {
    clearInterval(whatsappConnectionPollTimer);
    whatsappConnectionPollTimer = null;
  }
}

const loaders = {
  'company-dashboard': async () => {
    const d = await apiFetch('/portal/dashboard'); const s = d.summary || {};
    const firstLicense = (d.licenses || [])[0];
    const onboardingHtml = Number(s.devices || 0) === 0 ? `<section class="customer-create-panel onboarding-checklist" style="padding:20px;margin-bottom:18px;border-left:4px solid #16a34a">
      <div class="section-heading"><div><h3>🚀 Hızlı Kurulum Rehberi</h3><p>7 günlük ücretsiz deneme süreniz ilk POS cihazınızı bağladığınızda otomatik başlar.</p></div></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin-top:12px">
        <div class="state-panel" style="text-align:left"><strong>1. Uygulamayı İndirin</strong><p style="font-size:13px;margin:6px 0">Windows veya Android POS kurulum paketini indirin.</p><button type="button" class="btn btn-primary btn-sm portal-jump" data-target="company-downloads">Kurulum Paketlerine Git</button></div>
        <div class="state-panel" style="text-align:left"><strong>2. İlk Cihazınızı Bağlayın</strong><p style="font-size:13px;margin:6px 0">Uygulamaya e-posta ve şifrenizle giriş yapın${firstLicense?.license_key ? ` veya lisans anahtarınızı kullanın: <code>${esc(firstLicense.license_key)}</code>` : '.'}</p>${firstLicense?.license_key ? `<button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(firstLicense.license_key)}">Lisans Anahtarını Kopyala</button>` : ''}</div>
        <div class="state-panel" style="text-align:left"><strong>3. Şube ve Ekibinizi Ekleyin</strong><p style="font-size:13px;margin:6px 0">Mağaza şubelerinizi ve kasiyer/personel hesaplarını tanımlayın.</p><div style="display:flex;gap:6px;flex-wrap:wrap"><button type="button" class="btn btn-secondary btn-sm portal-jump" data-target="company-stores">Şubeler</button><button type="button" class="btn btn-secondary btn-sm portal-jump" data-target="team-management">Ekip</button></div></div>
      </div>
    </section>` : '';
    set(`${onboardingHtml}<div class="metrics-grid">${metric('Şube',s.stores||0)}${metric('Bağlı Cihaz',s.devices||0)}${metric('Ödenmemiş Fatura',s.unpaidInvoices||0)}${metric('Son 30 Gün Satış',money(s.monthlyRevenue))}</div><div class="section-heading spaced"><div><h3>Lisans Durumu</h3><p>Uygulamalarınızın kullanım hakkı ve cihaz sınırı.</p></div></div>${table([{label:'Paket',render:r=>esc(tr(r.tier))},{label:'Lisans Anahtarı',render:r=>r.license_key?`<code>${esc(r.license_key)}</code> <button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(r.license_key)}">Kopyala</button>`:'—'},{label:'Cihaz Hakkı',render:r=>esc(r.allowed_devices_count||1)},{label:'Geçerlilik',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(tr(r.status))}],d.licenses||[])}`);
    bindCopyButtons(document.getElementById('embed-content'));
    document.querySelectorAll('.portal-jump').forEach(b=>b.onclick=()=>window.selectAppModule?window.selectAppModule(b.dataset.target):document.querySelector(`[data-module-id="${CSS.escape(b.dataset.target)}"]`)?.click());
  },
  'sales-operations': async () => {
    const [devices,stores,gateway] = await Promise.all([apiFetch('/portal/devices'),apiFetch('/portal/stores'),apiFetch('/notifications/sms-gateway')]);
    const androidDevices=devices.filter(d=>String(d.platform||'').toLowerCase()==='android');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Şube',stores.length)}${metric('SMS Ana Cihaz',gateway?.device_name||'Seçilmedi')}</div><h3 class="content-title">SMS Ana Cihazı</h3><form class="payment-form" id="sms-gateway-form"><select id="sms-gateway-device"><option value="">Android cihaz seçin</option>${androidDevices.map(d=>`<option value="${esc(d.id)}" ${gateway?.device_activation_id===d.id?'selected':''}>${esc(d.name||d.id)}</option>`).join('')}</select><button class="btn btn-primary" type="submit">Ana Cihaz Yap</button></form><p>${gateway?`Son bağlantı: ${esc(date(gateway.last_poll_at))} — ${gateway.is_online?'Çevrimiçi':'Çevrimdışı'}`:'SMS işlemleri seçilen SIM kartlı Android cihazdan gönderilir.'}</p><h3 class="content-title">Cihazlar</h3>${table([{label:'Cihaz',render:r=>esc(r.name||r.id)},{label:'Platform',key:'platform'},{label:'Şube',key:'store_name'},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Durum',render:r=>badge(r.status)}],devices)}<h3 class="content-title">Şubeler</h3>${table([{label:'Şube',key:'name'},{label:'Adres',key:'address'},{label:'Durum',render:r=>badge(r.status||'active')}],stores)}`);
    document.getElementById('sms-gateway-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/notifications/sms-gateway',{method:'PUT',body:{device_id:document.getElementById('sms-gateway-device').value}});await loaders['sales-operations']();}catch(x){notice(x.message)}finally{b.disabled=false}};
  },
  'notification-channels': async () => {
    stopWhatsAppConnectionPoll();
    const [status, credits, queue, devices, gateway] = await Promise.all([apiFetch('/whatsapp/evolution/status'), apiFetch('/notifications/credits').catch(()=>({sms_credits:0,whatsapp_credits:0,email_credits:0})), apiFetch('/notifications/queue').catch(()=>[]), apiFetch('/portal/devices').catch(()=>[]), apiFetch('/notifications/sms-gateway').catch(()=>null)]);
    const androidDevices = (Array.isArray(devices) ? devices : []).filter(d => String(d.platform || '').toLowerCase() === 'android');
    const active = status.status === 'open';
    const phone = status.phone || status.name || '—';
    set(`<div class="section-heading"><div><h3>Bildirim Kanalları</h3><p>SMS, Android ana cihazın SIM kartından; WhatsApp bildirimleri bağlı Evolution API hesabından gönderilir.</p></div></div>
      <div class="metrics-grid">${metric('WhatsApp API',active?'Bağlı':status.status==='connecting'?'Bağlanıyor':'Bağlı değil')}${metric('Bağlı Numara',active?esc(phone):'—')}${metric('SMS Ana Cihazı',gateway?.device_name||'Seçilmedi')}${metric('E-posta Kredisi',credits?.email_credits??'—')}</div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px;margin-bottom:16px">
      <section class="customer-create-panel" style="padding:20px;margin:0"><h3>💬 Evolution API — WhatsApp Bağlantısı</h3>
        <p>${active?`${esc(phone)} WhatsApp bildirim kanalına bağlı.`:'Firma WhatsApp hesabını QR kod ile bağlayın. Telefonunuzdaki WhatsApp → Bağlı Cihazlar bölümünü kullanın.'}</p>
        <div style="display:flex;gap:10px;flex-wrap:wrap">
          <button class="btn btn-primary" id="whatsapp-connect" type="button">${active?'Bağlantıyı Yenile':'QR Kod ile Bağlan'}</button>
          ${active?'<button class="btn btn-secondary" id="whatsapp-disconnect" type="button">Bağlantıyı Kes</button>':''}
        </div>
        <p id="whatsapp-connect-state" class="diagnostic-result-note"></p>
        <div id="whatsapp-qr" style="margin-top:12px"></div>
      </section>
      <section class="customer-create-panel" style="padding:20px;margin:0"><h3>📱 Android SMS Ana Cihazı</h3>
        <p>${gateway?`Seçili cihaz: <b>${esc(gateway.device_name||'Android Terminal')}</b> (${gateway.is_online?'Çevrimiçi':'Çevrimdışı'} · Son kontrol: ${esc(date(gateway.last_poll_at,true))})`:'SMS bildirimleri işletmenizde seçtiğiniz SIM kartlı Android cihaz üzerinden gönderilir.'}</p>
        <form class="payment-form" id="sms-gateway-channel-form" style="display:flex;gap:10px;flex-wrap:wrap;align-items:center"><select id="sms-gateway-channel-device" style="flex:1;min-width:200px"><option value="">Android cihaz seçin (${androidDevices.length} kayıtlı)</option>${androidDevices.map(d=>`<option value="${esc(d.id)}" ${gateway?.device_activation_id===d.id?'selected':''}>${esc(d.name||d.id)}</option>`).join('')}</select><button class="btn btn-secondary" type="submit">Ana Cihaz Yap</button></form>
      </section>
      </div>
      ${active?'<section class="customer-create-panel" style="padding:20px"><h3>WhatsApp Test Mesajı</h3><form class="customer-form-grid" id="whatsapp-test-form"><label>Alıcı telefonu<input id="whatsapp-test-recipient" required placeholder="905551112233"></label><label class="wide-field">Mesaj<textarea id="whatsapp-test-body" required rows="3" maxlength="4096" placeholder="Serenut WhatsApp test mesajı"></textarea></label><button class="btn btn-primary" type="submit">Test Mesajını Kuyruğa Al</button></form></section>':''}<div class="section-heading spaced"><div><h3>Son Gönderimler</h3><p>Kuyruğa alınan ve gönderilen bildirimlerin teslimat durumu.</p></div></div>${table([{label:'Kanal',render:r=>badge(r.channel)},{label:'Alıcı',key:'recipient'},{label:'İçerik',render:r=>esc(String(r.title||r.body||'—').slice(0,80))},{label:'Tarih',render:r=>esc(date(r.created_at,true))},{label:'Durum',render:r=>badge(tr(r.status))}],Array.isArray(queue)?queue.slice(0,25):[])}`);

    const smsGwForm = document.getElementById('sms-gateway-channel-form');
    if (smsGwForm) smsGwForm.onsubmit = async e => { e.preventDefault(); const b = e.submitter; b.disabled = true; try { await apiFetch('/notifications/sms-gateway', { method: 'PUT', body: { device_id: document.getElementById('sms-gateway-channel-device').value } }); notice('SMS ana cihazı güncellendi.'); await loaders['notification-channels'](); } catch (x) { notice(x.message || 'SMS ana cihazı güncellenemedi.'); } finally { b.disabled = false; } };
    const connect = document.getElementById('whatsapp-connect');
    if (connect) connect.onclick = async () => {
      connect.disabled = true;
      const state = document.getElementById('whatsapp-connect-state');
      const qrPanel = document.getElementById('whatsapp-qr');
      state.textContent = 'Evolution API bağlantısı hazırlanıyor…';
      try {
        const result = await apiFetch('/whatsapp/evolution/qr');
        if (result.already_connected || result.status === 'open') {
          notice('WhatsApp zaten bağlı.');
          await loaders['notification-channels']();
          return;
        }
        if (!result.qrcode) throw new Error('Evolution API QR kodu döndürmedi.');
        qrPanel.innerHTML = `<img src="${esc(result.qrcode)}" alt="WhatsApp bağlantı QR kodu" style="display:block;width:min(280px,100%);height:auto;margin:auto"><p>QR kodu WhatsApp uygulamasındaki Bağlı Cihazlar ekranından tarayın.</p>`;
        state.textContent = 'WhatsApp bağlantısı bekleniyor…';
        whatsappConnectionPollTimer = setInterval(async () => {
          try {
            const current = await apiFetch('/whatsapp/evolution/status');
            if (current.status === 'open') {
              stopWhatsAppConnectionPoll();
              notice('WhatsApp API bağlantısı kuruldu.');
              await loaders['notification-channels']();
            }
          } catch (error) {
            state.textContent = error.message || 'Bağlantı durumu kontrol edilemedi.';
          }
        }, 2500);
      } catch (error) {
        state.textContent = error.message || 'Evolution API bağlantısı başlatılamadı.';
        connect.disabled = false;
      }
    };

    const disconnect = document.getElementById('whatsapp-disconnect');
    if (disconnect) disconnect.onclick = async () => {
      if (!confirm('WhatsApp API bağlantısı kesilecek. Devam edilsin mi?')) return;
      disconnect.disabled = true;
      try {
        await apiFetch('/whatsapp/evolution/disconnect', {method:'POST',body:{}});
        await loaders['notification-channels']();
      } catch (error) {
        notice(error.message || 'WhatsApp bağlantısı kesilemedi.');
        disconnect.disabled = false;
      }
    };

    const testForm = document.getElementById('whatsapp-test-form');
    if (testForm) testForm.onsubmit = async event => {
      event.preventDefault();
      const button = event.submitter;
      button.disabled = true;
      try {
        const queued = await apiFetch('/notifications/send-direct', {method:'POST',body:{
          channel:'whatsapp',
          recipient:document.getElementById('whatsapp-test-recipient').value.trim(),
          title:'Serenut WhatsApp testi',
          body:document.getElementById('whatsapp-test-body').value.trim(),
        }});
        notice(`Test mesajı kuyruğa alındı: ${queued.queue_id}`);
      } catch (error) {
        notice(error.message || 'Test mesajı kuyruğa alınamadı.');
      } finally {
        button.disabled = false;
      }
    };
  },
  'company-stores': async () => {
    const stores=await apiFetch('/portal/stores');
    set(`<div class="section-heading"><div><h3>Şubeler</h3><p>Satış noktalarınızı ve cihazların bağlı olduğu iş yerlerini yönetin.</p></div></div><form class="customer-form-grid" id="create-store-form"><label>Şube adı<input id="store-name" required placeholder="Örn. Merkez Şube"></label><label class="wide-field">Adres<input id="store-address" placeholder="Açık adres"></label><button class="btn btn-primary" type="submit">Şube Ekle</button></form><div class="section-heading spaced"><div><h3>Kayıtlı Şubeler</h3><p>${stores.length} şube bulundu.</p></div></div>${table([{label:'Şube',key:'name'},{label:'Adres',render:r=>esc(r.address||'—')},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(tr(r.status||'active'))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm store-edit-btn" data-id="${esc(r.id)}" data-name="${esc(r.name||'')}" data-address="${esc(r.address||'')}">Düzenle</button>`}],stores)}`);
    document.querySelectorAll('.store-edit-btn').forEach(btn=>btn.onclick=async()=>{const nextName=prompt('Şube adı:',btn.dataset.name||'');if(!nextName||!nextName.trim())return;const nextAddress=prompt('Şube adresi:',btn.dataset.address||'');if(nextAddress===null)return;btn.disabled=true;try{await apiFetch(`/portal/stores/${encodeURIComponent(btn.dataset.id)}`,{method:'PATCH',body:{name:nextName.trim(),address:nextAddress.trim()}});notice('Şube bilgileri güncellendi.');await loaders['company-stores']();}catch(err){notice(err.message||'Şube güncellenemedi.');btn.disabled=false;}});
    document.getElementById('create-store-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/portal/stores',{method:'POST',body:{name:document.getElementById('store-name').value.trim(),address:document.getElementById('store-address').value.trim()}});notice('Şube oluşturuldu.');await loaders['company-stores']();}catch(x){notice(x.message||'Şube oluşturulamadı.');b.disabled=false}};
  },
  'company-devices': async () => {
    const devices=await apiFetch('/portal/devices');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Çevrimdışı',devices.filter(d=>!d.is_online&&d.status==='active').length)}${metric('Kaldırılan / Pasif',devices.filter(d=>['revoked','blocked','inactive'].includes(d.status)).length)}</div><div class="section-heading spaced"><div><h3>Bağlı Terminaller ve Cihazlar</h3><p>İşletmenize bağlı tüm cihazları, işletim sistemi sürümlerini ve bağlantı durumlarını buradan yönetebilirsiniz.</p></div></div>${table([{label:'Cihaz Adı',render:r=>`<div style="line-height:1.3;"><strong style="font-size:13px;color:var(--text-primary,#f8fafc);">${esc(r.name||'Terminal')}</strong><div style="font-size:11px;color:var(--text-muted,#94a3b8);margin-top:2px;"><span>ID: ${esc(r.id?r.id.slice(0,16):'—')}</span>${r.app_version&&r.app_version!=='—'?` · <span style="background:rgba(255,255,255,0.08);padding:1px 5px;border-radius:3px;color:#93c5fd;">v${esc(r.app_version)}</span>`:''}</div></div>`},{label:'İşletim Sistemi',render:r=>formatDevicePlatform(r.platform,r.os_version)},{label:'Şube',render:r=>esc(r.store_name||'Tanımsız / Merkez')},{label:'Donanım Kimliği',render:r=>`<code>${esc(r.device_hash?`${r.device_hash.slice(0,14)}…`:'—')}</code>`},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at,true))},{label:'Durum',render:r=>badge(tr(r.status))},{label:'İşlem',render:r=>`<button class="btn btn-danger btn-sm device-remove" data-id="${esc(r.id)}" data-name="${esc(r.name||'Terminal')}">🗑️ Cihazı Kaldır</button>`}],devices)}`);
    document.querySelectorAll('.device-remove').forEach(button=>button.onclick=async()=>{
      const name=button.dataset.name||'Bu cihazı';
      if(!confirm(`"${name}" adlı cihazı hesabınızdan kaldırmak istediğinize emin misiniz?\n\nBu işlem cihazın oturumunu ve lisans yetkisini sonlandıracak, lisans kotanız boşa çıkacaktır.`)) return;
      button.disabled=true;
      button.textContent='Kaldırılıyor…';
      try{
        await apiFetch(`/portal/devices/${encodeURIComponent(button.dataset.id)}`,{method:'DELETE'});
        notice('Cihaz başarıyla kaldırıldı.');
        await loaders['company-devices']();
      }catch(err){
        notice(err.message||'Cihaz kaldırılamadı.');
        button.disabled=false;
        button.textContent='🗑️ Cihazı Kaldır';
      }
    });
  },
  'team-management': async () => {
    const [users,roles,permissions] = await Promise.all([apiFetch('/portal/users'),apiFetch('/portal/roles'),apiFetch('/portal/permissions')]);
    const friendly={"portal:access":'Web yönetim portalına erişim',"sales:view":'Satışları görüntüle',"sales:create":'Satış oluştur',"inventory:view":'Ürünleri görüntüle',"inventory:manage":'Ürünleri yönet',"devices:view":'Cihazları görüntüle',"devices:manage":'Cihazları yönet',"users:view":'Kullanıcıları görüntüle',"users:manage":'Kullanıcıları yönet',"reports:view":'Raporları görüntüle',"notifications.history.read":'SMS geçmişini görüntüle',"notifications.templates.manage":'SMS şablonlarını yönet',"billing:view":'Abonelik ve faturaları görüntüle',"settings:view":'Firma ayarlarını görüntüle',"settings:update":'Firma profilini güncelle',"settings:manage":'Firma ve şube ayarlarını yönet'};
    const permissionOptions=permissions.filter(p=>friendly[p.code]).map(p=>`<label class="permission-option"><input type="checkbox" name="role-permission" value="${esc(p.code)}"><span>${esc(friendly[p.code])}</span></label>`).join('');
    set(`<div class="section-heading"><div><h3>Ekip</h3><p>Çalışanınızı ekleyin; ne yapabileceğini görevi belirlesin.</p></div></div><details class="customer-create-panel" open><summary>Yeni kullanıcı ekle</summary><form class="customer-form-grid user-create-form" id="create-user-form"><label>Ad soyad<input id="new-user-name" required placeholder="Örn. Ayşe Yılmaz"></label><label>E-posta<input id="new-user-email" type="email" required placeholder="ayse@firma.com"></label><label>Görevi<select id="new-user-role" required><option value="">Görev seçin</option>${roles.map(r=>`<option value="${esc(r.id)}">${esc(tr(r.name))}</option>`).join('')}</select></label><button class="btn btn-primary" type="submit">Kullanıcı Ekle</button></form></details><h3 class="content-title">Kullanıcılar</h3>${table([{label:'Ad Soyad',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Görev',render:r=>`<select class="user-role-select" data-id="${esc(r.id)}" style="max-width:170px">${roles.map(ro=>`<option value="${esc(ro.id)}" ${ro.id===r.role_id||ro.name===r.role_name?'selected':''}>${esc(tr(ro.name))}</option>`).join('')}</select>`},{label:'Kayıt Tarihi',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.is_active===false?'Pasif':'Aktif')},{label:'İşlem',render:r=>`<div style="display:flex;gap:6px;"><button class="btn btn-secondary btn-sm user-toggle" data-id="${esc(r.id)}" data-active="${r.is_active!==false}">${r.is_active===false?'Aktifleştir':'Devre Dışı Bırak'}</button><button class="btn btn-secondary btn-sm user-reset-pw" data-id="${esc(r.id)}" data-email="${esc(r.email)}">Kurtarma Talebi Oluştur</button></div>`}],users)}<details class="customer-create-panel role-panel"><summary>Gelişmiş: özel görev rolü oluştur</summary><form id="create-role-form"><div class="customer-form-grid role-name-grid"><label>Rol adı<input id="new-role-name" required placeholder="Örn. Mağaza sorumlusu"></label><label>Açıklama<input id="new-role-description" placeholder="Bu rolün kısa açıklaması"></label><button class="btn btn-secondary" type="submit">Rolü Oluştur</button></form><div class="permission-grid">${permissionOptions}</div></form></details>`);
    document.querySelectorAll('.user-role-select').forEach(sel=>sel.onchange=async()=>{sel.disabled=true;try{await apiFetch(`/portal/users/${encodeURIComponent(sel.dataset.id)}`,{method:'PATCH',body:{role_id:sel.value}});notice('Kullanıcı görevi güncellendi.');await loaders['team-management']();}catch(err){notice(err.message||'Görev güncellenemedi.');sel.disabled=false;}});
    document.getElementById('create-user-form').onsubmit = async e => { e.preventDefault(); const b=e.submitter;const newEmail=document.getElementById('new-user-email').value.trim();b.disabled=true;try{const result=await apiFetch('/portal/users',{method:'POST',body:{name:document.getElementById('new-user-name').value.trim(),email:newEmail,role_id:document.getElementById('new-user-role').value}});notice('Kullanıcı oluşturuldu. Tek kullanımlık aktivasyon kodunu kopyalayıp kullanıcıya iletin.');await loaders['team-management']();showRecoveryClaimBanner('Yeni Kullanıcı Aktivasyon Bilgisi',result.recovery_request_id,result.claim_code,newEmail,'Kullanıcı bu bilgilerle kendi şifresini belirlemelidir.');}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.getElementById('create-role-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const selected=[...document.querySelectorAll('input[name="role-permission"]:checked')].map(x=>x.value);b.disabled=true;try{await apiFetch('/portal/roles',{method:'POST',body:{name:document.getElementById('new-role-name').value.trim(),description:document.getElementById('new-role-description').value.trim(),permissions:selected}});await loaders['team-management']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.user-toggle').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/portal/users/${encodeURIComponent(b.dataset.id)}`,{method:'PATCH',body:{is_active:b.dataset.active!=='true'}});await loaders['team-management']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.user-reset-pw').forEach(b=>b.onclick=async()=>{const reason=prompt(`"${b.dataset.email}" kullanıcısı için kurtarma gerekçesi (en az 10 karakter):`);if(!reason||reason.trim().length<10){notice('Geçerli bir gerekçe zorunludur.');return;}b.disabled=true;try{const r=await apiFetch('/auth/recovery/admin-assist',{method:'POST',body:{target_user_id:b.dataset.id,reason:reason.trim()}});notice('Tek kullanımlık kurtarma kodu oluşturuldu.');showRecoveryClaimBanner('Yönetici Destekli Kurtarma Bilgisi',r.request_id,r.claim_code,b.dataset.email);}catch(x){notice(x.message||'Kurtarma talebi oluşturulamadı.');}finally{b.disabled=false}});
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

    const preselectedPlan = sessionStorage.getItem('selected_plan_id') || '';
    const renewalBanner = sub.status === 'active' ? `<div class="attention-strip" style="justify-content:space-between;align-items:center"><span>${sub.cancel_at_period_end ? `Otomatik yenileme kapalı. Aboneliğiniz <b>${esc(date(sub.current_period_end))}</b> tarihinde sona erecektir.` : `Otomatik yenileme açık. Dönem bitişi: <b>${esc(date(sub.current_period_end))}</b>`}</span><button type="button" class="btn btn-secondary btn-sm" id="toggle-auto-renewal-btn">${sub.cancel_at_period_end ? 'Yenilemeyi Tekrar Aç' : 'Dönem Sonunda İptal Et'}</button></div>` : '';
    set(`<div class="metrics-grid">${metric('Mevcut Plan',sub.plan_name||'Plan yok')}${metric('Abonelik',tr(sub.status))}${metric(sub.status==='trialing'&&sub.trial_ends_at?'Deneme Bitişi':'Geçerlilik',date(sub.status==='trialing'&&sub.trial_ends_at?sub.trial_ends_at:sub.current_period_end))}</div>${renewalBanner}<div class="toolbar billing-toolbar"><div><h3 class="content-title">Planlar</h3><p>Deneme süreniz bitince istediğiniz planı seçebilirsiniz.</p></div><div class="billing-toggle" role="radiogroup" aria-label="Ödeme dönemi"><input id="billing-monthly" type="radio" name="billing-period" value="monthly" checked><label for="billing-monthly">Aylık</label><input id="billing-yearly" type="radio" name="billing-period" value="yearly"><label for="billing-yearly">Yıllık</label><span aria-hidden="true"></span></div></div><div class="plan-grid customer-plan-grid">${plans.map(p=>`<article class="module-card plan-card" data-plan-id="${esc(p.id)}" ${String(p.id)===String(preselectedPlan)?'style="border:2px solid #16a34a"':''}>${String(p.id)===String(preselectedPlan)?'<span class="status-badge status-active" style="margin-bottom:6px">Seçtiğiniz Paket</span>':''}<h3>${esc(p.name)}</h3><strong class="plan-card-price">${planPrice(p,'monthly')}</strong><p>${esc(p.description||'')}</p>${p.locked_billing_period?`<small>Firmaya özel ${p.locked_billing_period==='yearly'?'yıllık':'aylık'} dönem</small>`:''}<button class="btn btn-primary buy-plan" data-plan="${esc(p.id)}">Planı Seç</button></article>`).join('')}</div><div class="section-heading spaced"><div><h3>Ödeme Geçmişi</h3><p>Oluşturduğunuz ödeme talepleri ve faturalar.</p></div></div>${table([{label:'Fatura',key:'invoice_number'},{label:'Tutar',render:r=>esc(money(r.amount,r.currency||'TRY'))},{label:'Tarih',render:r=>esc(date(r.created_at||r.due_at))},{label:'Durum',render:r=>badge(tr(r.status))},{label:'Belge',render:r=>r.id?`<button type="button" class="btn btn-secondary btn-sm invoice-pdf-download" data-id="${esc(r.id)}" data-num="${esc(r.invoice_number||r.id)}">PDF İndir</button>`:'—'}],invoices)}`);
    const autoRenewBtn = document.getElementById('toggle-auto-renewal-btn');
    if (autoRenewBtn) autoRenewBtn.onclick = async () => {
      autoRenewBtn.disabled = true;
      try {
        const endpoint = sub.cancel_at_period_end ? '/billing/reactivate' : '/billing/cancel';
        const res = await apiFetch(endpoint, { method: 'POST', body: {} });
        notice(res.message || 'Abonelik yenileme tercihi güncellendi.');
        await loaders['billing-center']();
      } catch (err) {
        notice(err.message || 'İşlem gerçekleştirilemedi.');
        autoRenewBtn.disabled = false;
      }
    };
    document.querySelectorAll('.invoice-pdf-download').forEach(btn => {
      btn.onclick = async () => {
        const orig = btn.textContent;
        btn.disabled = true;
        btn.textContent = 'Hazırlanıyor…';
        try {
          const res = await fetch(`/api/v1/billing/invoices/${encodeURIComponent(btn.dataset.id)}/pdf`, { headers: { Authorization: `Bearer ${getAuthToken()}` } });
          if (!res.ok) throw new Error('Fatura PDF dosyası indirilemedi.');
          const blob = await res.blob();
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = `Fatura-${btn.dataset.num || btn.dataset.id}.pdf`;
          document.body.appendChild(a);
          a.click();
          a.remove();
          URL.revokeObjectURL(url);
          notice('Fatura PDF indirildi.');
        } catch (err) {
          notice(err.message || 'Fatura indirilemedi.');
        } finally {
          btn.disabled = false;
          btn.textContent = orig;
        }
      };
    });

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
    set(`<div class="metrics-grid">${metric('Toplam Lisans',licenses.length)}${metric('Aktif',licenses.filter(x=>x.status==='active').length)}${metric('Deneme',licenses.filter(x=>x.status==='trial').length)}${metric('Toplam Cihaz Hakkı',licenses.reduce((sum,x)=>sum+Number(x.allowed_devices_count||1),0))}</div><div class="section-heading"><div><h3>Lisanslar</h3><p>Lisans anahtarları ve kullanım hakları salt okunur biçimde gösterilir.</p></div></div>${table([{label:'Lisans Anahtarı',render:r=>r.license_key?`<code>${esc(r.license_key)}</code> <button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(r.license_key)}">Kopyala</button>`:'—'},{label:'Paket',render:r=>badge(tr(r.tier||'basic'))},{label:'Cihaz Hakkı',render:r=>esc(r.allowed_devices_count||1)},{label:'Geçerlilik',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(tr(r.status))}],licenses)}`);
    bindCopyButtons(document.getElementById('embed-content'));
  },
  'company-downloads': async () => {
    const releases=await apiFetch('/releases/history');
    const filteredReleases = releases.filter(r => r.is_available !== false);
    const cleanVer = v => String(v || '').split('+')[0].trim();
    set(`<div class="section-heading"><div><h3>Kurulum Paketleri</h3><p>Hesabınıza açık güncel Windows ve Android sürümleri.</p></div></div><div class="release-download-grid">${filteredReleases.length?filteredReleases.map(r=>`<article class="release-download-card"><div class="release-platform">${String(r.platform).toLowerCase()==='android'?'Android':'Windows'}</div><h3>Sürüm ${esc(cleanVer(r.version_code))}</h3><p>${esc(r.release_notes||'Kararlılık ve güvenlik güncellemeleri.')}</p><small>${esc(date(r.created_at))}</small><button class="btn btn-primary release-download" data-id="${esc(r.id)}">Güvenli İndir</button></article>`).join(''):'<div class="state-panel">Yayınlanmış kurulum paketi bulunamadı.</div>'}</div>`);
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
    const [d,companies,transfers,sysHealth,intel,traffic]=await Promise.all([apiFetch('/admin/dashboard/commercial'),apiFetch('/admin/companies'),apiFetch('/billing/admin/pending-transfers'),apiFetch('/admin/dashboard').catch(()=>({})),apiFetch('/admin/billing/intel').catch(()=>({})),apiFetch('/admin/traffic-funnel').catch(()=>({}))]);const s=d.summary||{};const subs=d.subscriptions||{};const sys=sysHealth?.system||{};const expiring=d.expiringCompanies||[];const tf=traffic.summary||{};const tfSources=(traffic.sources||[]).map(x=>`${esc(x.source)}: <b>${esc(x.visitors)}</b>`).join(' · ')||'Henüz veri toplanıyor';const tfDevices=(traffic.devices||[]).map(x=>`${esc(x.device_type)}: <b>${esc(x.visitors)}</b>`).join(' · ')||'—';
    const recent=[...companies].sort((a,b)=>new Date(b.created_at||0)-new Date(a.created_at||0)).slice(0,6);
    set(`<div class="admin-welcome"><div><span>CANLI OPERASYON MERKEZİ · BUGÜN ${esc(s.todaySignups||0)} YENİ KAYIT · ${esc(tf.visitors_today||0)} SİTE ZİYARETÇİSİ</span><h3>Bugün kontrol etmeniz gerekenler</h3><p>Bekleyen havaleler, süresi yaklaşan abonelikler, site ziyaretçi hunisi ve sunucu durumu tek ekranda.</p></div><div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn btn-primary admin-jump" data-target="platform-billing">${esc(s.pendingTransfers||0)} havaleyi incele</button><button class="btn btn-secondary admin-jump" data-target="platform-traffic">🌐 Web Trafiği (${esc(tf.visitors_today||0)} Ziyaretçi)</button><button class="btn btn-secondary admin-jump" data-target="platform-maintenance" style="background:rgba(255,255,255,.15)!important;color:#fff!important;border-color:rgba(255,255,255,.3)!important">Sunucu: Disk %${esc(sys.diskUsage||0)} · RAM %${esc(sys.ramUsage||0)}</button></div></div><div class="metrics-grid admin-primary-metrics">${metric('Toplam Firma',s.totalCustomers||0)}${metric('Aktif Abonelik',subs.active||0)}${metric('Denemedeki Firma',s.trialUsers||0)}${metric('Aylık Sabit Gelir (MRR)',money(intel.mrr||0))}${metric('30 Günlük Tahsilat',money(s.monthlyRevenue||0))}${metric('Riskli / Geciken',money(intel.at_risk_revenue||0))}</div><div class="customer-create-panel" style="padding:14px 16px;margin-bottom:16px"><div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;margin-bottom:10px"><div><h4 style="margin:0">🌐 Site Ziyaretçi & Müşteri Dönüşüm Hunisi (Son 30 Gün)</h4><small style="color:var(--text-muted)">Kaynaklar: ${tfSources} &nbsp;|&nbsp; Cihazlar: ${tfDevices}</small></div><div style="display:flex;gap:8px;align-items:center"><span class="status-badge status-active">Bugün: ${esc(tf.visitors_today||0)} Tekil Ziyaretçi (${esc(tf.pageviews_today||0)} sayfa)</span><button class="btn btn-secondary btn-sm admin-jump" data-target="platform-traffic">Detaylı Trafik Analitiği →</button></div></div><div class="metrics-grid" style="margin:0">${metric('1. Site Ziyaretçisi (30G)',`${tf.visitors_30d||0} kişi (${tf.pageviews_30d||0} görüntüleme)`)}${metric('2. Plan / İndirme İnceleyen',`${tf.interested_30d||0} kişi`)}${metric('3. Kayıt Sayfası → Kayıt Olan',`${tf.register_views_30d||0} görüntüleme → ${tf.signups_30d||0} firma`)}${metric('4. Uygulama İndiren & Cihaz Açan',`Win: ${tf.windows_downloads_30d||0} · And: ${tf.android_downloads_30d||0} → ${tf.activated_companies_30d||0} aktif firma`)}</div></div><div class="admin-columns"><section><div class="section-heading"><h3>Bekleyen Havale Bildirimleri</h3><button class="text-action admin-jump" data-target="platform-billing">Tümünü gör →</button></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Hızlı İşlem',render:r=>`<div style="display:flex;gap:6px"><button class="btn btn-primary btn-sm overview-approve-transfer" data-invoice="${esc(r.invoice_id)}">Onayla</button><button class="btn btn-danger btn-sm overview-reject-transfer" data-invoice="${esc(r.invoice_id)}">Reddet</button></div>`}],transfers.slice(0,5))}</section><section><div class="section-heading"><h3>Süresi Yaklaşan / Biten Firmalar (14 Gün)</h3><button class="text-action admin-jump" data-target="platform-companies">Tümünü gör →</button></div>${table([{label:'Firma',render:r=>`<strong>${esc(r.name)}</strong><small>${esc(r.plan_name||'Paket')}</small>`},{label:'Bitiş',render:r=>{const diff=Math.ceil((new Date(r.valid_until).getTime()-Date.now())/86400000);return `${esc(date(r.valid_until))} <small>(${diff<0?'Süresi doldu':`${diff} gün`})</small>`;}},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm overview-open-company" data-id="${esc(r.id)}">Süre Uzat / Yönet</button>`}],expiring)}</section></div><div class="section-heading spaced"><h3>Son Kayıt Olan Firmalar</h3><button class="text-action admin-jump" data-target="platform-companies">Tümünü gör →</button></div>${table([{label:'Firma',key:'name'},{label:'Paket',render:r=>esc(r.plan_name||'Deneme')},{label:'İletişim',render:r=>esc(r.email||r.phone||'—')},{label:'Durum',render:r=>badge(r.status)},{label:'Kayıt',render:r=>esc(date(r.created_at))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm overview-open-company" data-id="${esc(r.id)}">Yönet</button>`}],recent)}<div class="attention-strip" style="justify-content:space-between;flex-wrap:wrap;margin-top:14px"><div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap"><strong>${esc(s.noLicense||0)}</strong><span>lisansı olmayan firma</span><strong>${esc(s.expiringLicenses||0)}</strong><span>14 gün içinde süresi bitecek firma</span></div><div style="font-size:12px;color:#52615a">PostgreSQL: <b>${esc(sys.database||'aktif')}</b> · Redis: <b>${esc(sys.redis||'aktif')}</b> · CPU: <b>%${esc(sys.cpuUsage||0)}</b></div></div>`);
    document.querySelectorAll('.admin-jump').forEach(b=>b.onclick=()=>window.selectAppModule?window.selectAppModule(b.dataset.target):document.querySelector(`[data-module-id="${CSS.escape(b.dataset.target)}"]`)?.click());
    document.querySelectorAll('.overview-open-company').forEach(b=>b.onclick=()=>{window._openCompanyDetailId=b.dataset.id;if(window.selectAppModule)window.selectAppModule('platform-companies');});
    document.querySelectorAll('.overview-approve-transfer').forEach(b=>b.onclick=async()=>{if(!confirm('Ödeme banka hareketiyle doğrulandı mı? Bu işlem aboneliği hemen aktifleştirir.'))return;b.disabled=true;try{const result=await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/approve-payment`,{method:'PUT'});notice(`Ödeme onaylandı. Lisans geçerlilik tarihi: ${date(result.license_valid_until)}`);await loaders['platform-overview']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.overview-reject-transfer').forEach(b=>b.onclick=async()=>{const note=prompt('Havale red gerekçesi:');if(!note)return;b.disabled=true;try{await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/reject-payment`,{method:'PUT',body:{note}});notice('Havale bildirimi reddedildi.');await loaders['platform-overview']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-traffic': async () => {
    const traffic = await apiFetch('/admin/traffic-funnel').catch(() => ({}));
    const s = traffic.summary || {};
    const sources = traffic.sources || [];
    const devices = traffic.devices || [];
    const topPages = traffic.top_pages || [];
    const events = traffic.events || [];
    const campaigns = traffic.campaigns || [];
    const recent = traffic.recent_activity || [];

    const totalDownloads = Number(s.windows_downloads_30d || 0) + Number(s.android_downloads_30d || 0);
    const visitors30d = Number(s.visitors_30d || 0);
    const interested30d = Number(s.interested_30d || 0);
    const signups30d = Number(s.signups_30d || 0);
    const activated30d = Number(s.activated_companies_30d || 0);

    const pct = (num, denom) => denom > 0 ? Math.round((num / denom) * 100) : 0;

    const funnelSteps = [
      { step: '1. Web Ziyaretçisi', count: visitors30d, pct: 100, desc: 'Son 30 günde serenut.com gelen tekil kişi' },
      { step: '2. Plan / İndirme İnceleyen', count: interested30d, pct: pct(interested30d, visitors30d), desc: 'Fiyat planlarını ve indirme sayfasını gezenler' },
      { step: '3. Uygulama İndiren', count: totalDownloads, pct: pct(totalDownloads, visitors30d), desc: `Win: ${s.windows_downloads_30d || 0} · And: ${s.android_downloads_30d || 0}` },
      { step: '4. Kayıt Olan Firma', count: signups30d, pct: pct(signups30d, visitors30d), desc: 'Sisteme yeni kayıt açan işletmeler' },
      { step: '5. Cihazını Açan Aktif Firma', count: activated30d, pct: pct(activated30d, visitors30d), desc: 'En az bir POS cihazı aktifleştiren firma' }
    ];

    set(`
      <div class="section-heading">
        <div>
          <h3>🌐 Web Trafik & Ziyaretçi Analitiği</h3>
          <p>serenut.com ziyaretçi akışı, pazarlama kaynakları, okuma süreleri ve indirme dönüşüm hunisi.</p>
        </div>
        <div style="display:flex;gap:8px;align-items:center">
          <span class="status-badge status-active">● Canlı Telemetri Aktif</span>
          <button class="btn btn-secondary btn-sm" id="traffic-refresh-btn">Yenile</button>
        </div>
      </div>

      <div class="metrics-grid">
        ${metric('Bugün Tekil Ziyaretçi', `${s.visitors_today || 0} kişi`)}
        ${metric('Bugün Sayfa Gösterimi', `${s.pageviews_today || 0} sayfa`)}
        ${metric('Son 30 Gün Ziyaretçi', `${s.visitors_30d || 0} tekil (${s.pageviews_30d || 0} sayfa)`)}
        ${metric('Ort. Sayfada Kalma', `${s.avg_dwell_seconds || 0} saniye`)}
        ${metric('Ort. Okuma / Kaydırma', `%${s.avg_scroll_pct || 0}`)}
        ${metric('Toplam İndirme (30G)', `Win: ${s.windows_downloads_30d || 0} · And: ${s.android_downloads_30d || 0}`)}
      </div>

      <!-- DÖNÜŞÜM HUNİSİ (FUNNEL) -->
      <section class="customer-create-panel" style="padding:18px 20px;margin-bottom:18px">
        <h4 style="margin:0 0 14px 0">🎯 Web Ziyaretçi → Müşteri Dönüşüm Hunisi</h4>
        <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px">
          ${funnelSteps.map(f => `
            <div style="background:#f8faf9;border:1px solid #e2e8e4;border-radius:8px;padding:12px">
              <span style="font-size:11px;font-weight:700;color:#52615a">${esc(f.step)}</span>
              <div style="font-size:20px;font-weight:800;color:#151b18;margin:4px 0">${esc(f.count)} <small style="font-size:12px;color:#0b714d">(%${f.pct})</small></div>
              <div style="background:#e5e7eb;border-radius:4px;height:6px;overflow:hidden;margin-bottom:6px">
                <div style="background:#10b981;height:100%;width:${Math.min(f.pct, 100)}%"></div>
              </div>
              <small style="color:#718078;font-size:11px">${esc(f.desc)}</small>
            </div>
          `).join('')}
        </div>
      </section>

      <!-- TRAFİK KAYNAKLARI & CİHAZ TÜRÜ -->
      <div class="admin-columns" style="margin-bottom:18px">
        <section>
          <div class="section-heading">
            <h3>Trafik Kaynakları (Son 30 Gün)</h3>
          </div>
          ${table([
            { label: 'Kaynak', render: r => `<strong>${esc(r.source || 'Bilinmiyor')}</strong>` },
            { label: 'Tekil Ziyaretçi', render: r => esc(r.visitors || 0) },
            { label: 'Sayfa Görüntüleme', render: r => esc(r.views || 0) },
            { label: 'Payı', render: r => `%${pct(r.visitors, visitors30d)}` }
          ], sources)}
        </section>

        <section>
          <div class="section-heading">
            <h3>Cihaz ve Platform Dağılımı</h3>
          </div>
          <div style="display:grid;gap:12px;margin-top:8px">
            ${devices.map(d => {
              const dPct = pct(d.visitors, visitors30d);
              const icon = String(d.device_type).toLowerCase().includes('mobil') ? '📱' : '💻';
              return `
                <div style="background:#fff;border:1px solid #e2e8e4;border-radius:8px;padding:14px">
                  <div style="display:flex;justify-content:space-between;margin-bottom:6px">
                    <strong>${icon} ${esc(d.device_type || 'Bilinmiyor')}</strong>
                    <span><b>${esc(d.visitors || 0)}</b> ziyaretçi (%${dPct})</span>
                  </div>
                  <div style="background:#e5e7eb;border-radius:4px;height:8px;overflow:hidden">
                    <div style="background:#3b82f6;height:100%;width:${Math.min(dPct, 100)}%"></div>
                  </div>
                </div>
              `;
            }).join('') || '<div class="state-panel">Henüz cihaz verisi toplanmadı.</div>'}
          </div>
        </section>
      </div>

      <!-- EN ÇOK GEZİLEN SAYFALAR & BUTON TIKLAMALARI -->
      <div class="admin-columns" style="margin-bottom:18px">
        <section>
          <div class="section-heading">
            <h3>En Çok Okunan / Gezilen Sayfalar</h3>
          </div>
          ${table([
            { label: 'Sayfa', render: r => `<code>${esc(r.page_path)}</code>` },
            { label: 'Ziyaretçi', render: r => esc(r.visitors || 0) },
            { label: 'Görüntüleme', render: r => esc(r.views || 0) },
            { label: 'Ort. Süre', render: r => `${esc(r.avg_seconds || 0)} sn` },
            { label: 'Kaydırma', render: r => `%${esc(r.avg_scroll || 0)}` }
          ], topPages)}
        </section>

        <section>
          <div class="section-heading">
            <h3>Kritik Buton & Etkileşim Olayları</h3>
          </div>
          ${table([
            { label: 'Olay', render: r => `<strong>${esc(r.event_name)}</strong><small>${esc(r.event_category || 'etkileşim')}</small>` },
            { label: 'Toplam Tıklama', render: r => esc(r.total_events || 0) },
            { label: 'Tekil Kişi', render: r => esc(r.unique_visitors || 0) }
          ], events)}
        </section>
      </div>

      <!-- PAZARLAMA KAMPANYALARI (UTM) -->
      ${campaigns.length ? `
        <section style="margin-bottom:18px">
          <div class="section-heading">
            <h3>Pazarlama Kampanyaları (UTM Parametreleri)</h3>
          </div>
          ${table([
            { label: 'Kaynak (utm_source)', render: r => `<strong>${esc(r.utm_source)}</strong>` },
            { label: 'Mecra (utm_medium)', render: r => esc(r.utm_medium) },
            { label: 'Kampanya Adı (utm_campaign)', render: r => esc(r.utm_campaign) },
            { label: 'Ziyaretçi', render: r => esc(r.visitors || 0) },
            { label: 'Görüntüleme', render: r => esc(r.views || 0) }
          ], campaigns)}
        </section>
      ` : ''}

      <!-- CANLI SON ZİYARETÇİ AKIŞI -->
      <section>
        <div class="section-heading">
          <h3>Canlı Ziyaretçi Akışı (Son 20 İşlem)</h3>
        </div>
        ${table([
          { label: 'Sayfa', render: r => `<code>${esc(r.page_path)}</code>` },
          { label: 'Kaynak', render: r => esc(r.traffic_source || 'Direkt') },
          { label: 'Cihaz', render: r => esc(r.device_type || 'Masaüstü') },
          { label: 'Süre / Kaydırma', render: r => `${esc(r.duration_seconds || 0)} sn · %${esc(r.max_scroll_pct || 0)}` },
          { label: 'Zaman', render: r => esc(date(r.created_at, true)) }
        ], recent)}
      </section>
    `);

    const refreshBtn = document.getElementById('traffic-refresh-btn');
    if (refreshBtn) refreshBtn.onclick = () => loaders['platform-traffic']();
  },
  'platform-companies': async () => {
    const rows=await apiFetch('/admin/companies');const activeFilter=window._companySegmentFilter||'all';const isExpiring=r=>{if(!r.valid_until)return false;const diff=(new Date(r.valid_until).getTime()-Date.now())/86400000;return diff<=14;};const filteredRows=rows.filter(r=>activeFilter==='all'?true:activeFilter==='active'?r.status==='active'&&r.subscription_status==='active':activeFilter==='trial'?['trial','trialing'].includes(r.subscription_status):activeFilter==='expiring'?isExpiring(r):r.status==='suspended');set(`<div class="metrics-grid">${metric('Toplam Firma',rows.length)}${metric('Aktif Firma',rows.filter(x=>x.status==='active').length)}${metric('Denemede',rows.filter(x=>['trial','trialing'].includes(x.subscription_status)).length)}${metric('Süresi Yaklaşan / Biten',rows.filter(isExpiring).length)}</div><details class="admin-create-panel"><summary>+ Yeni Firma ve Yönetici Hesabı Oluştur</summary><form class="admin-form-grid" id="create-company"><label>Firma ünvanı<input id="company-name" required placeholder="Örn. Serenut Gıda"></label><label>TC / VKN<input id="company-tax" required placeholder="10 veya 11 hane"></label><label>E-posta<input id="company-email" type="email" placeholder="firma@ornek.com"></label><label>Telefon<input id="company-phone" placeholder="05xx xxx xx xx"></label><label>Vergi Dairesi<input id="company-tax-office" placeholder="İsteğe bağlı"></label><hr style="grid-column:1/-1;border:0;border-top:1px solid #dfe6e1;margin:4px 0"><label style="grid-column:1/-1;color:#0b714d;font-size:.72rem;letter-spacing:.06em">ADMİN KULLANICI (İsteğe bağlı)</label><label>Yönetici Ad Soyad<input id="company-admin-name" placeholder="Ahmet Yılmaz"></label><label>Yönetici E-posta<input id="company-admin-email" type="email" placeholder="ahmet@firma.com"></label><button class="btn btn-primary">Firmayı Oluştur</button></form></details><div class="toolbar" style="margin:12px 0;display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap"><div style="display:flex;gap:6px;flex-wrap:wrap">${[['all','Tümü'],['active','Aktif Abonelik'],['trial','Denemede'],['expiring','Süresi Yaklaşan/Biten'],['suspended','Askıda']].map(([id,label])=>`<button type="button" class="btn btn-secondary btn-sm company-segment-btn ${activeFilter===id?'active':''}" data-segment="${id}">${label}</button>`).join('')}</div><input id="filter-platform-companies" data-table-filter placeholder="Firma adı, VKN, e-posta veya telefon ile filtrele…" style="max-width:340px"></div>${table([{label:'Firma',render:r=>`<strong>${esc(r.name)}</strong><small>VKN: ${esc(r.tax_number&&!String(r.tax_number).startsWith('PENDING-')?r.tax_number:'Belirtilmedi')}</small>`},{label:'İletişim',render:r=>esc(r.email||r.phone||'—')},{label:'Paket & Abonelik',render:r=>`<div><strong>${esc(r.plan_name||'Deneme')}</strong><div>${badge(tr(r.subscription_status||'none'))}</div></div>`},{label:'Bitiş / Kalan Süre',render:r=>{if(!r.valid_until)return '—';const diff=Math.ceil((new Date(r.valid_until).getTime()-Date.now())/86400000);return `<div>${esc(date(r.valid_until))}<small>${diff<0?'Süresi doldu':`${diff} gün kaldı`}</small></div>`;}},{label:'Şube / Cihaz Kotası',render:r=>`<span>${esc(r.store_count||0)}/${esc(r.store_limit||1)} Şube · ${esc(r.device_count||0)}/${esc(r.device_limit||1)} Cihaz</span>`},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<div style="display:flex;gap:6px;flex-wrap:wrap"><button class="btn btn-primary btn-sm company-detail" data-id="${esc(r.id)}">Yönet</button><button class="btn btn-secondary btn-sm company-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='active'?'Askıya Al':'Aktifleştir'}</button></div>`}],filteredRows)}`);document.querySelectorAll('.company-segment-btn').forEach(btn=>btn.onclick=()=>{window._companySegmentFilter=btn.dataset.segment;loaders['platform-companies']();});
    attachTableFilter('filter-platform-companies');
    document.getElementById('create-company').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;
      const adminEmail=document.getElementById('company-admin-email').value.trim();
      try{const result=await apiFetch('/admin/companies',{method:'POST',body:{name:document.getElementById('company-name').value.trim(),tax_number:document.getElementById('company-tax').value.trim(),tax_office:document.getElementById('company-tax-office').value.trim(),email:document.getElementById('company-email').value.trim(),phone:document.getElementById('company-phone').value.trim(),admin_name:document.getElementById('company-admin-name').value.trim()||undefined,admin_email:adminEmail||undefined}});let msg=`Şirket oluşturuldu. Deneme lisansı: ${result.license_key}`;if(result.user_id)msg+=`

Yönetici hesabı oluşturuldu: ${adminEmail}\nTalep: ${result.recovery_request_id}\nTek kullanımlık kod: ${result.claim_code}`;notice(msg);await loaders['platform-companies']();if(result.user_id)showRecoveryClaimBanner('Yeni Firma Yöneticisi Aktivasyon Bilgisi',result.recovery_request_id,result.claim_code,adminEmail,`Deneme lisansı: ${result.license_key}`);}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.company-toggle').forEach(b=>b.onclick=async()=>{const reason=prompt('Firma durum değişikliği gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{const suspend=b.dataset.status==='active';await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/${suspend?'suspend':'restore'}`,{method:'POST',body:suspend?{suspend:true,reason:reason.trim()}:{reason:reason.trim()}});await loaders['platform-companies']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.company-detail').forEach(b=>b.onclick=async()=>{b.disabled=true;try{const [d,plans]=await Promise.all([apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`),apiFetch('/billing/plans')]);set(companyDetailView(d,plans));
      document.getElementById('back-companies').onclick=()=>loaders['platform-companies']();
      bindCopyButtons(document.getElementById('embed-content'));
      const editCompanyForm=document.getElementById('edit-company-form');if(editCompanyForm)editCompanyForm.onsubmit=async e=>{e.preventDefault();const subBtn=e.submitter;subBtn.disabled=true;try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{name:document.getElementById('edit-company-name').value.trim(),tax_number:document.getElementById('edit-company-tax').value.trim(),tax_office:document.getElementById('edit-company-tax-office').value.trim(),email:document.getElementById('edit-company-email').value.trim(),phone:document.getElementById('edit-company-phone').value.trim(),address:document.getElementById('edit-company-address').value.trim()}});notice('Firma bilgileri güncellendi.');await b.onclick();}catch(x){notice(x.message);subBtn.disabled=false;}};
      const archiveBtn=document.getElementById('archive-company-btn');if(archiveBtn)archiveBtn.onclick=async()=>{if(!confirm(`"${archiveBtn.dataset.name}" firmasını arşivlemek istediğinize emin misiniz?\n\nArşivlenen firmanın lisansları iptal edilir ve kullanıcı oturumları kapatılır.`))return;archiveBtn.disabled=true;try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}`,{method:'DELETE'});notice('Firma arşivlendi.');await loaders['platform-companies']();}catch(x){notice(x.message);archiveBtn.disabled=false;}};
      document.querySelectorAll('.quick-grant-days').forEach(qbtn=>qbtn.onclick=()=>{const daysInput=document.getElementById('manual-days');const reasonInput=document.getElementById('manual-reason');if(daysInput)daysInput.value=qbtn.dataset.days;if(reasonInput&&!reasonInput.value.trim())reasonInput.value=qbtn.dataset.reason;notice(`Süre ${qbtn.dataset.days} gün olarak seçildi. "Aboneliği Hemen Aktifleştir" butonuna basarak onaylayın.`);});
      const addUserForm=document.getElementById('admin-add-company-user-form');if(addUserForm)addUserForm.onsubmit=async e=>{e.preventDefault();const subBtn=e.submitter;subBtn.disabled=true;try{const uEmail=document.getElementById('admin-user-email').value.trim();const r=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/users`,{method:'POST',body:{name:document.getElementById('admin-user-name').value.trim(),email:uEmail,role_name:document.getElementById('admin-user-role').value}});notice(`Kullanıcı eklendi. Aktivasyon talebi: ${r.recovery_request_id} · Kod: ${r.claim_code}`);await b.onclick();showRecoveryClaimBanner('Yeni Kullanıcı Aktivasyon Bilgisi',r.recovery_request_id,r.claim_code,uEmail);}catch(x){notice(x.message);subBtn.disabled=false;}};
      document.querySelectorAll('.user-force-logout').forEach(ubtn=>ubtn.onclick=async()=>{if(!confirm(`"${ubtn.dataset.email}" kullanıcısının tüm aktif oturumlarını sonlandırmak istediğinize emin misiniz?`))return;ubtn.disabled=true;try{await apiFetch(`/admin/security/users/${encodeURIComponent(ubtn.dataset.id)}/force-logout`,{method:'POST',body:{}});notice('Kullanıcının tüm oturumları sonlandırıldı.');}catch(x){notice(x.message);}finally{ubtn.disabled=false;}});
      document.querySelectorAll('.company-device-toggle').forEach(dbtn=>dbtn.onclick=async()=>{if(!confirm('Cihaz erişim durumunu değiştirmek istediğinize emin misiniz?'))return;dbtn.disabled=true;try{await apiFetch(`/admin/devices/${encodeURIComponent(dbtn.dataset.id)}/toggle`,{method:'POST'});notice('Cihaz durumu güncellendi.');await b.onclick();}catch(x){notice(x.message);dbtn.disabled=false}});
      document.querySelectorAll('.company-device-delete').forEach(dbtn=>dbtn.onclick=async()=>{if(!confirm(`"${dbtn.dataset.name||'Terminal'}" cihazını bu firmadan kaldırmak istediğinize emin misiniz?`))return;dbtn.disabled=true;try{await apiFetch(`/admin/devices/${encodeURIComponent(dbtn.dataset.id)}`,{method:'DELETE'});notice('Cihaz kaldırıldı.');await b.onclick();}catch(x){notice(x.message);dbtn.disabled=false}});
      document.querySelectorAll('.company-tab').forEach(tab=>tab.onclick=()=>{document.querySelectorAll('.company-tab').forEach(x=>x.classList.toggle('active',x===tab));document.querySelectorAll('.company-tab-panel').forEach(panel=>panel.classList.toggle('app-hidden',panel.dataset.panel!==tab.dataset.tab));});
      const resetBtn=document.getElementById('send-reset-pw-btn');
      const requestRecovery=async(button,email)=>{if(!email){notice('Hedef kullanıcı bulunamadı.');return;}const reason=prompt('Şifre kurtarma gerekçesi (en az 10 karakter):');if(!reason||reason.trim().length<10){notice('Geçerli bir gerekçe zorunludur.');return;}button.disabled=true;try{const r=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/password-recovery`,{method:'POST',body:{email,reason:reason.trim()}});if(r.requires_second_approval){notice(`Talep oluşturuldu: ${r.request_id}. İkinci sysadmin onayı gerekiyor.`);}else{notice(`Tek kullanımlık kurtarma bilgisi — Talep: ${r.request_id} Kod: ${r.claim_code}`);showRecoveryClaimBanner('Firma Kullanıcısı Kurtarma Bilgisi',r.request_id,r.claim_code,email);}}catch(x){notice(x.message||'Kurtarma talebi oluşturulamadı.');}finally{button.disabled=false;}};
      if(resetBtn)resetBtn.onclick=()=>requestRecovery(resetBtn,resetBtn.dataset.email);
      document.querySelectorAll('.user-detail-reset-pw').forEach(ub=>ub.onclick=()=>requestRecovery(ub,ub.dataset.email));
      document.getElementById('company-package-form').onsubmit=async e=>{e.preventDefault();const submit=e.submitter;submit.disabled=true;const numberOrNull=id=>{const value=document.getElementById(id).value;return value===''?null:Number(value)};const planInput=document.getElementById('package-plan');const planId=planInput?.value||plans[0]?.id;if(!planId){notice('Temel plan seçilemedi.');submit.disabled=false;return;}try{await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/package-override`,{method:'PUT',body:{base_plan_id:planId,custom_price:numberOrNull('package-price'),billing_interval:document.getElementById('package-period').value,user_limit:numberOrNull('package-users'),store_limit:numberOrNull('package-stores'),device_limit:numberOrNull('package-devices'),valid_from:document.getElementById('package-from').value,valid_until:document.getElementById('package-until').value,auto_renew:document.getElementById('package-renew').checked,reason:document.getElementById('package-reason').value.trim()||'Admin düzenlemesi',feature_overrides:{}}});notice('Firmaya özel paket kaydedildi. Ödeme onayında haklar otomatik uygulanacak.');await b.onclick();}catch(x){notice(x.message);submit.disabled=false}};
      document.getElementById('manual-subscription-form').onsubmit=async e=>{e.preventDefault();const submit=e.submitter;const reason=document.getElementById('manual-reason').value.trim();if(reason.length<10){notice('Manuel abonelik için en az 10 karakterlik gerekçe zorunludur.');return;}if(!confirm('Bu işlem ödeme kaydı olmadan aboneliği ve lisans haklarını hemen aktifleştirecek. Devam edilsin mi?'))return;submit.disabled=true;const optionalNumber=id=>{const value=document.getElementById(id).value;return value===''?null:Number(value)};try{const result=await apiFetch(`/admin/companies/${encodeURIComponent(b.dataset.id)}/manual-subscription`,{method:'POST',body:{plan_id:document.getElementById('manual-plan').value,grant_days:Number(document.getElementById('manual-days').value),device_limit:optionalNumber('manual-devices'),store_limit:optionalNumber('manual-stores'),reason}});notice(`Abonelik aktifleştirildi. Geçerlilik: ${date(result.valid_until)}`);await b.onclick();}catch(x){notice(x.message);submit.disabled=false}};
    }catch(x){notice(x.message);b.disabled=false}});
    if(window._openCompanyDetailId){const targetBtn=document.querySelector(`.company-detail[data-id="${CSS.escape(String(window._openCompanyDetailId))}"]`);window._openCompanyDetailId=null;if(targetBtn)targetBtn.click();}
  },
  'platform-subscriptions': async () => {
    const rows=await apiFetch('/admin/subscriptions');set(`<div class="metrics-grid">${metric('Toplam',rows.length)}${metric('Aktif',rows.filter(x=>x.status==='active').length)}${metric('Deneme',rows.filter(x=>['trial','trialing'].includes(x.status)).length)}${metric('Sona Eren',rows.filter(x=>['expired','cancelled'].includes(x.status)).length)}</div><div class="toolbar" style="margin:12px 0"><input id="filter-platform-subscriptions" data-table-filter placeholder="Firma, plan veya durum ile filtrele…" style="max-width:360px"></div>${table([{label:'Firma',key:'company_name'},{label:'Plan',key:'plan_name'},{label:'Tutar',render:r=>esc(money(r.price,r.currency||'TRY'))},{label:'Başlangıç',render:r=>esc(date(r.current_period_start))},{label:'Bitiş',render:r=>esc(date(r.current_period_end))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>r.company_id?`<button class="btn btn-secondary btn-sm sub-open-company" data-id="${esc(r.company_id)}">Firmayı Yönet</button>`:'—'}],rows)}`);
    attachTableFilter('filter-platform-subscriptions');
    document.querySelectorAll('.sub-open-company').forEach(b=>b.onclick=()=>{window._openCompanyDetailId=b.dataset.id;if(window.selectAppModule)window.selectAppModule('platform-companies');});
  },
  'platform-billing': async () => {
    const [transfers,accounts,providers,intel]=await Promise.all([apiFetch('/billing/admin/pending-transfers'),apiFetch('/billing/bank-accounts?all=true'),apiFetch('/admin/payment-methods'),apiFetch('/admin/billing/intel').catch(()=>({}))]);const iyzico=providers.find(p=>p.id==='iyzico')||{};const overdue=intel.overdue_invoices||[];const billingSubView=window._billingSubView||'transfers';set(`<div class="metrics-grid">${metric('Bekleyen Havale',transfers.length)}${metric('Aylık Sabit Gelir (MRR)',money(intel.mrr||0))}${metric('Yıllık Projeksiyon (ARR)',money(intel.arr||0))}${metric('Riskli / Geciken Tahsilat',money(intel.at_risk_revenue||0))}</div><div class="company-tabs" style="margin-bottom:14px"><button type="button" class="btn btn-secondary btn-sm billing-subtab-btn ${billingSubView==='transfers'?'active':''}" data-view="transfers">Bekleyen Havaleler & Riskli Tahsilatlar (${transfers.length})</button><button type="button" class="btn btn-secondary btn-sm billing-subtab-btn ${billingSubView==='settings'?'active':''}" data-view="settings">Tahsilat Ayarları (Banka IBAN & iyzico POS)</button></div><section class="${billingSubView==='transfers'?'':'app-hidden'}" id="billing-panel-transfers"><div class="section-heading spaced"><div><h3>Bekleyen Havale / EFT Bildirimleri</h3><p>Müşterilerin gönderdiği ödeme bildirimlerini banka hareketiyle doğruladıktan sonra tek tıkla aboneliği başlatın.</p></div></div>${table([{label:'Firma',render:r=>esc(r.company_name||r.company_id)},{label:'Gönderen',key:'sender_name'},{label:'Referans',key:'reference_code'},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-primary btn-sm approve-transfer" data-invoice="${esc(r.invoice_id)}">Ödemeyi Onayla</button>`}],transfers)}${overdue.length?`<div class="section-heading spaced"><div><h3>Gecikmiş / Ödenmemiş Faturalar (Tahsilat Riski)</h3><p>Vadesi geçmiş veya ödeme bekleyen faturalar.</p></div></div>${table([{label:'Firma',key:'company_name'},{label:'Tutar',render:r=>esc(money(r.amount))},{label:'Vade Tarihi',render:r=>esc(date(r.due_at))},{label:'Durum',render:r=>badge(r.status)}],overdue)}`:''}</section><section class="${billingSubView==='settings'?'':'app-hidden'}" id="billing-panel-settings"><div class="section-heading spaced"><div><h3>Alıcı Banka Hesapları (IBAN)</h3><p>Müşteriye havale adımında gösterilen banka hesapları.</p></div></div><details class="admin-create-panel"><summary>+ Yeni Banka Hesabı (IBAN) Ekle</summary><form class="admin-form-grid bank-account-form" id="bank-account-form"><label>Banka adı<input id="bank-name" required placeholder="Örn. Ziraat Bankası"></label><label>Alıcı / hesap sahibi<input id="account-holder" required placeholder="Firma veya kişi ünvanı"></label><label>IBAN<input id="account-iban" required placeholder="TR00 0000 0000 0000 0000 0000 00"></label><label>Şube<input id="account-branch" placeholder="İsteğe bağlı"></label><label>Açıklama<input id="account-instructions" placeholder="Havale açıklamasına referans kodunu yazın"></label><button class="btn btn-primary">Hesabı Ekle</button></form></details>${table([{label:'Banka',key:'bank_name'},{label:'Alıcı',key:'account_holder'},{label:'IBAN',key:'iban'},{label:'Durum',render:r=>badge(r.is_active?'active':'inactive')},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm bank-toggle" data-id="${esc(r.id)}" data-active="${r.is_active}" data-account='${esc(JSON.stringify(r))}'>${r.is_active?'Pasifleştir':'Aktifleştir'}</button>`}],accounts)}<div class="section-heading spaced"><div><h3>Sanal POS — iyzico Ayarları</h3><p>Kredi kartı ile online tahsilat için iyzico API anahtarlarını yapılandırın.</p></div>${badge(iyzico.is_enabled?'active':(iyzico.is_configured?'configured':'not_configured'))}</div><form class="admin-form-grid provider-form" id="iyzico-form"><label>API adresi<input id="iyzico-base-url" value="${esc(iyzico.config?.iyzico_base_url||'https://sandbox-api.iyzipay.com')}"></label><label>API anahtarı<input id="iyzico-api-key" autocomplete="off" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'API anahtarı'}"></label><label>Gizli anahtar<input id="iyzico-secret" type="password" autocomplete="new-password" placeholder="${iyzico.is_configured?'Kayıtlı — değiştirmek için yazın':'Gizli anahtar'}"></label><label class="switch-label"><input id="iyzico-enabled" type="checkbox" ${iyzico.is_enabled?'checked':''}> iyzico'yu etkinleştir</label><button class="btn btn-primary">Kaydet ve Test Et</button></form></section>`);document.querySelectorAll('.billing-subtab-btn').forEach(btn=>btn.onclick=()=>{window._billingSubView=btn.dataset.view;loaders['platform-billing']();});
    document.querySelectorAll('.approve-transfer').forEach(button=>{const transfer=transfers.find(item=>String(item.invoice_id)===String(button.dataset.invoice));const details=jsonObject(transfer?.billing_details);const period=document.createElement('small');period.textContent=details.billingPeriod==='yearly'?' · Yıllık':' · Aylık';button.parentElement?.insertBefore(period,button);const reject=document.createElement('button');reject.className='btn btn-danger btn-sm reject-transfer';reject.dataset.invoice=button.dataset.invoice;reject.textContent='Reddet';button.parentElement?.appendChild(reject);});
    document.getElementById('bank-account-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/billing/bank-accounts',{method:'POST',body:{bank_name:document.getElementById('bank-name').value.trim(),account_holder:document.getElementById('account-holder').value.trim(),iban:document.getElementById('account-iban').value.replace(/\s/g,'').toUpperCase(),currency:'TRY',branch_name:document.getElementById('account-branch').value.trim(),instructions:document.getElementById('account-instructions').value.trim()}});await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.bank-toggle').forEach(b=>b.onclick=async()=>{const account=JSON.parse(b.dataset.account);b.disabled=true;try{await apiFetch(`/billing/bank-accounts/${encodeURIComponent(b.dataset.id)}`,{method:'PUT',body:{...account,is_active:b.dataset.active!=='true'}});await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
    document.getElementById('iyzico-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const apiKey=document.getElementById('iyzico-api-key').value.trim();const secret=document.getElementById('iyzico-secret').value.trim();const secrets={};if(apiKey)secrets.iyzico_api_key=apiKey;if(secret)secrets.iyzico_secret_key=secret;await apiFetch('/admin/payment-methods/iyzico',{method:'PUT',body:{is_enabled:document.getElementById('iyzico-enabled').checked,config:{iyzico_base_url:document.getElementById('iyzico-base-url').value.trim()},secrets}});notice('iyzico ayarları kaydedildi.');await loaders['platform-billing']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.approve-transfer').forEach(b=>b.onclick=async()=>{if(!confirm('Ödeme banka hareketiyle doğrulandı mı? Bu işlem aboneliği aktifleştirir.'))return;b.disabled=true;try{const result=await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/approve-payment`,{method:'PUT'});notice(`Ödeme onaylandı. Lisans geçerlilik tarihi: ${date(result.license_valid_until)}`);await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.reject-transfer').forEach(b=>b.onclick=async()=>{const note=prompt('Havale red gerekçesi:');if(!note)return;b.disabled=true;try{await apiFetch(`/billing/admin/invoices/${encodeURIComponent(b.dataset.invoice)}/reject-payment`,{method:'PUT',body:{note}});notice('Havale bildirimi reddedildi.');await loaders['platform-billing']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-plans': async () => {
    const plans=await apiFetch('/billing/plans');
    const fields=(p={})=>`<label>Plan adı<input name="name" value="${esc(p.name||'')}" required></label><label>Fiyat<div class="price-input"><input name="price" type="number" min="0" step="0.01" value="${esc(p.price??'')}" required><b>₺</b></div></label><label>Fiyat dönemi<select name="billing_interval"><option value="monthly" ${p.billing_interval!=='yearly'?'selected':''}>Aylık</option><option value="yearly" ${p.billing_interval==='yearly'?'selected':''}>Yıllık</option></select></label><label>Kullanıcı limiti<input name="user_limit" type="number" min="1" max="1000" value="${esc(p.user_limit||1)}" required></label><label>Şube limiti<input name="store_limit" type="number" min="1" max="1000" value="${esc(p.store_limit||1)}" required></label><label>Cihaz limiti<input name="device_limit" type="number" min="1" max="1000" value="${esc(p.device_limit||1)}" required></label><label>Deneme günü<input name="trial_days" type="number" min="0" max="365" value="${esc(p.trial_days||0)}"></label>`;
    set(`<div class="attention-strip"><strong>Plan ve özel paket farkı</strong><span>Burada herkese sunulan ana planları oluşturun. Firmaya özel fiyat/limit için Firmalar → Firma Detayı → Abonelik ekranını kullanın.</span></div><details class="admin-create-panel"><summary>Yeni satış planı oluştur</summary><form class="admin-form-grid" id="create-plan-form">${fields()}<button class="btn btn-primary" type="submit">Planı Oluştur</button></form></details><div class="admin-plan-grid">${plans.map(p=>`<form class="admin-plan-card" data-plan="${esc(p.id)}"><span>SATIŞ PLANI</span>${fields(p)}<button class="btn btn-primary" type="submit">Değişiklikleri Kaydet</button></form>`).join('')}</div>`);
    document.getElementById('create-plan-form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget;const b=e.submitter;b.disabled=true;try{await apiFetch('/billing/plans',{method:'POST',body:{name:f.elements.name.value.trim(),price:Number(f.elements.price.value),currency:'TRY',billing_interval:f.elements.billing_interval.value,user_limit:Number(f.elements.user_limit.value),store_limit:Number(f.elements.store_limit.value),device_limit:Number(f.elements.device_limit.value),trial_days:Number(f.elements.trial_days.value||0),features:{}}});notice('Yeni plan oluşturuldu.');await loaders['platform-plans']();}catch(x){notice(x.message);b.disabled=false}};
    document.querySelectorAll('.admin-plan-card').forEach(f=>f.onsubmit=async e=>{e.preventDefault();const b=e.submitter;const plan=plans.find(p=>String(p.id)===f.dataset.plan);b.disabled=true;try{await apiFetch(`/billing/plans/${encodeURIComponent(f.dataset.plan)}`,{method:'PUT',body:{name:f.elements.name.value.trim(),price:Number(f.elements.price.value),currency:'TRY',billing_interval:f.elements.billing_interval.value,user_limit:Number(f.elements.user_limit.value),store_limit:Number(f.elements.store_limit.value),device_limit:Number(f.elements.device_limit.value),trial_days:Number(f.elements.trial_days.value||0),features:plan?.features||{}}});notice('Plan güncellendi.');}catch(x){notice(x.message)}finally{b.disabled=false}});
  },
  'platform-licenses': async () => {
    const [licenses,companies]=await Promise.all([apiFetch('/admin/licenses'),apiFetch('/admin/companies')]);
    set(`<details class="admin-create-panel"><summary>Yeni lisans üret</summary><form class="admin-form-grid" id="create-license"><label>Firma<select id="license-company" required><option value="">Firma seçin</option>${companies.map(c=>`<option value="${esc(c.id)}">${esc(c.name)}</option>`).join('')}</select></label><label>Paket<select id="license-tier"><option value="trial">Deneme</option><option value="basic">Başlangıç</option><option value="pro">Pro</option><option value="pro_plus">Özel</option></select></label><label>Cihaz limiti<input id="license-devices" type="number" min="1" max="1000" value="1" required></label><label>Süre (gün)<input id="license-days" type="number" min="1" value="365" required></label><button class="btn btn-primary">Lisans Üret</button></form></details><div class="toolbar" style="margin:12px 0"><input id="filter-platform-licenses" data-table-filter placeholder="Firma adı veya lisans anahtarı ile filtrele…" style="max-width:360px"></div><h3 class="content-title">Lisans Anahtarları</h3>${table([{label:'Firma',key:'company_name'},{label:'Anahtar',render:r=>r.license_key?`<code>${esc(r.license_key)}</code> <button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(r.license_key)}">Kopyala</button>`:'—'},{label:'Paket',render:r=>badge(r.tier)},{label:'Cihaz',key:'allowed_devices_count'},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm license-renew" data-id="${esc(r.id)}">1 Yıl Uzat</button> <button class="btn btn-secondary btn-sm license-toggle" data-id="${esc(r.id)}" data-status="${esc(r.status)}">${r.status==='suspended'?'Aktifleştir':'Askıya Al'}</button> ${r.status!=='revoked'?`<button class="btn btn-danger btn-sm license-revoke" data-id="${esc(r.id)}">İptal Et</button>`:''}`}],licenses)}`);
    bindCopyButtons(document.getElementById('embed-content'));
    attachTableFilter('filter-platform-licenses');
    document.getElementById('create-license').onsubmit=async e=>{e.preventDefault();const reason=prompt('Manuel lisans üretme gerekçesi:');if(!reason?.trim()){notice('Manuel lisans gerekçesi zorunludur.');return;}const b=e.submitter;b.disabled=true;try{const result=await apiFetch('/admin/licenses',{method:'POST',body:{company_id:document.getElementById('license-company').value,tier:document.getElementById('license-tier').value,allowed_devices_count:document.getElementById('license-devices').value,expires_in_days:document.getElementById('license-days').value,reason:reason.trim()}});notice(`Lisans üretildi: ${result.license_key}`);await loaders['platform-licenses']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.license-renew').forEach(b=>b.onclick=async()=>{const reason=prompt('Manuel lisans uzatma gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/renew`,{method:'POST',body:{additional_days:365,reason:reason.trim()}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-toggle').forEach(b=>b.onclick=async()=>{const reason=prompt('Lisans durum değişikliği gerekçesi:');if(!reason?.trim())return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/suspend`,{method:'POST',body:{suspend:b.dataset.status!=='suspended',reason:reason.trim()}});await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
    document.querySelectorAll('.license-revoke').forEach(b=>b.onclick=async()=>{const reason=prompt('Kalıcı iptal gerekçesi:');if(!reason?.trim())return;if(!confirm('Bu lisans kalıcı olarak iptal edilecek ve bağlı cihazların erişimi kesilecek. Devam edilsin mi?'))return;b.disabled=true;try{await apiFetch(`/admin/licenses/${encodeURIComponent(b.dataset.id)}/revoke`,{method:'POST',body:{reason:reason.trim()}});notice('Lisans iptal edildi.');await loaders['platform-licenses']();}catch(x){notice(x.message);b.disabled=false}});
  },
  'platform-devices': async () => {
    const devices=await apiFetch('/admin/devices');
    set(`<div class="metrics-grid">${metric('Toplam Cihaz',devices.length)}${metric('Çevrimiçi',devices.filter(d=>d.is_online).length)}${metric('Çevrimdışı',devices.filter(d=>!d.is_online).length)}${metric('Engelli',devices.filter(d=>d.status!=='active').length)}</div><div class="section-heading"><div><h3>Tüm Cihazlar</h3><p>Firma, şube, donanım kimliği ve bağlantı durumuna göre terminalleri yönetin.</p></div></div><div class="toolbar" style="margin:12px 0"><input id="filter-platform-devices" data-table-filter placeholder="Cihaz adı, firma, platform veya donanım kimliği ile filtrele…" style="max-width:380px"></div>${table([{label:'Cihaz',render:r=>`<div style="line-height:1.3;"><strong style="font-size:13px;">${esc(r.name||'Terminal')}</strong><div style="font-size:11px;color:var(--text-muted,#94a3b8);"><span>ID: ${esc(r.id)}</span>${r.app_version&&r.app_version!=='—'?` · <span>v${esc(r.app_version)}</span>`:''}</div></div>`},{label:'Firma',render:r=>esc(r.company_name||'—')},{label:'İşletim Sistemi',render:r=>formatDevicePlatform(r.platform,r.os_version)},{label:'Donanım',render:r=>`<code>${esc(r.device_hash?`${r.device_hash.slice(0,14)}…`:'—')}</code>`},{label:'Son Aktivite',render:r=>esc(date(r.last_active_at))},{label:'Bağlantı',render:r=>badge(r.is_online?'online':'offline')},{label:'Durum',render:r=>badge(tr(r.status))},{label:'İşlem',render:r=>`<div style="display:flex;gap:4px;flex-wrap:wrap;"><button class="btn btn-secondary btn-sm device-toggle" data-id="${esc(r.id)}">${r.status==='active'?'Engelle':'Etkinleştir'}</button> <button class="btn btn-secondary btn-sm device-swap" data-id="${esc(r.id)}" data-company="${esc(r.company_id)}" data-name="${esc(r.name||'Terminal')}">Değiştir</button> <button class="btn btn-danger btn-sm device-remove-admin" data-id="${esc(r.id)}" data-name="${esc(r.name||'Terminal')}">Sil</button></div>`}],devices)}`);
    attachTableFilter('filter-platform-devices');
    document.querySelectorAll('.device-toggle').forEach(button=>button.onclick=async()=>{if(!confirm('Cihaz erişim durumunu değiştirmek istediğinize emin misiniz?'))return;button.disabled=true;try{await apiFetch(`/admin/devices/${encodeURIComponent(button.dataset.id)}/toggle`,{method:'POST'});await loaders['platform-devices']();}catch(x){notice(x.message);button.disabled=false}});
    document.querySelectorAll('.device-swap').forEach(button=>button.onclick=async()=>{const name=prompt('Yeni cihaz adı:',button.dataset.name||'Yeni Terminal');if(!name)return;const hash=prompt('Yeni cihaz UUID / donanım kimliği:');if(!hash)return;button.disabled=true;try{await apiFetch('/admin/devices/swap',{method:'POST',body:{company_id:button.dataset.company,old_device_id:button.dataset.id,new_device_name:name.trim(),new_device_hash:hash.trim()}});notice('Cihaz eşleşmesi güncellendi.');await loaders['platform-devices']();}catch(x){notice(x.message);button.disabled=false}});
    document.querySelectorAll('.device-remove-admin').forEach(button=>button.onclick=async()=>{
      const name=button.dataset.name||'Bu cihazı';
      if(!confirm(`"${name}" adlı cihazı kalıcı olarak silmek istediğinize emin misiniz?`)) return;
      button.disabled=true;
      try{
        await apiFetch(`/admin/devices/${encodeURIComponent(button.dataset.id)}`,{method:'DELETE'});
        notice('Cihaz silindi.');
        await loaders['platform-devices']();
      }catch(x){notice(x.message);button.disabled=false}
    });
  },
  'platform-releases': async () => {
    const releases=await apiFetch('/releases/list');
    set(`<h3 class="content-title">Yeni Sürüm Yayınla</h3><form class="inline-form" id="release-upload-form"><input id="release-version" required placeholder="Sürüm (örn. 1.2.0)"><select id="release-platform"><option value="android">Android</option><option value="windows">Windows</option></select><select id="release-channel"><option value="stable">Kararlı</option><option value="beta">Beta</option></select><input id="release-min-version" placeholder="Asgari sürüm (isteğe bağlı)"><label><input id="release-mandatory" type="checkbox"> Zorunlu güncelleme</label><input id="release-file" type="file" required><textarea id="release-notes" required placeholder="Sürüm notları"></textarea><button class="btn btn-primary" type="submit" id="btn-release-submit">Sürümü İmzala ve Yayınla</button></form><div id="release-upload-status" class="release-status-box" style="display:none"></div><h3 class="content-title">Yayın Geçmişi</h3>${table([{label:'Sürüm',render:r=>`${esc(String(r.version_code||'').split('+')[0])}<small>${esc(r.platform)} / ${esc(r.channel)}</small>`},{label:'Dağıtım',render:r=>`<input class="release-rollout" data-id="${esc(r.id)}" type="number" min="0" max="100" value="${esc(r.rollout_percentage)}" style="width:5rem"> %`},{label:'İndirme',key:'total_downloads'},{label:'Kurulum',key:'verified_installs'},{label:'Yayın',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(r.status)},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm save-rollout" data-id="${esc(r.id)}">Kaydet</button> ${r.status!=='yanked'?`<button class="btn btn-secondary btn-sm yank-release" data-id="${esc(r.id)}">Geri Çek</button>`:''} <button class="btn btn-secondary btn-sm delete-release" data-id="${esc(r.id)}" data-version="${esc(String(r.version_code||'').split('+')[0])}" style="color:#e11d48;border-color:#fecdd3">Sil</button>`}],releases)}`);
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
    const [preview,live,dash,syncMon,smsStats]=await Promise.all([apiFetch('/admin/maintenance/preview'),apiFetch('/admin/monitoring/live').catch(()=>({})),apiFetch('/admin/dashboard').catch(()=>({})),apiFetch('/admin/sync/monitor').catch(()=>({})),apiFetch('/admin/sms/stats').catch(()=>({}))]);const sys=dash.system||{};const qNotif=live.queues?.notifications||{};const qBill=live.queues?.billing||{};const syncOv=syncMon.overview||{};const smsSummary=smsStats.summary||{};
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
    set(`<div class="metrics-grid">${metric('PostgreSQL',`${live.services?.database?.latency_ms??0} ms (${sys.database||'aktif'})`)}${metric('Redis & Kuyruk',`${sys.redis||'aktif'} · ${qNotif.waiting||0} bekleyen`)}${metric('Aktif Terminal (WS)',`${live.metrics?.active_websockets??0} bağlı`)}${metric('Sync v4 (Son 24s)',`${syncOv.changes_last_24h??0} işlem · ${syncOv.unresolved_conflicts??0} çakışma`)}${metric('Bildirim / SMS (30G)',`${smsSummary.sent_count??0} başarılı · ${smsSummary.failed_count??0} hatalı`)}${metric('Disk Kullanımı',`${preview.disk?.usedPercent||0}% (${fileSize(preview.disk?.freeBytes)} boş)`)}</div><div class="attention-strip" style="justify-content:space-between;flex-wrap:wrap"><div><strong>Canlı Kuyruk & Senkronizasyon:</strong> <span>Bildirim Kuyruğu: <b>${esc(qNotif.waiting||0)}</b> bekleyen / <b>${esc(qNotif.failed||0)}</b> hatalı · Faturalama: <b>${esc(qBill.waiting||0)}</b> bekleyen · Aktif Sync Firması (24s): <b>${esc(syncOv.active_companies_24h||0)}</b></span></div><div><span>CPU: <b>%${esc(sys.cpuUsage||0)}</b> · RAM: <b>%${esc(sys.ramUsage||0)}</b> · Bakım: <b>${preview.running?'Çalışıyor':preview.releasePublishInProgress?'Yayın bekleniyor':'Hazır'}</b></span></div></div>
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
    const [admins,auditLogs,companies,diagnostics,blacklist]=await Promise.all([
      apiFetch('/admin/security/admin-users'),
      apiFetch('/admin/audit-logs'),
      apiFetch('/admin/companies'),
      apiFetch(`/admin/diagnostics?${params.toString()}`),
      apiFetch('/admin/security/blacklist').catch(()=>[])
    ]);
    const summary=diagnostics.summary||{};
    const companyOptions=companies.map(company=>`<option value="${esc(company.id)}" ${filters.company===String(company.id)?'selected':''}>${esc(company.name)}</option>`).join('');
    const rawEvents=Array.isArray(diagnostics.events)?diagnostics.events:[];
    const events=groupDiagnosticEvents(rawEvents);
    const activeAdmins=admins.filter(admin=>admin.is_active);
    const recoveryReady=activeAdmins.filter(admin=>Number(admin.unused_recovery_codes)>0);
    set(`<div class="metrics-grid">${metric('Kritik Olay',summary.critical||0)}${metric('Hata Kaydı',summary.error||0)}${metric('Engelli IP',Array.isArray(blacklist)?blacklist.length:0)}${metric('Kurtarma Kodu',recoveryReady.length>0?'Hazır':'Üretilmeli')}</div>
      <div class="section-heading spaced" style="margin-top:8px"><div><h3>Yönetici Hesap Güvenliği ve Acil Kurtarma Kodları</h3><p>Şifrenizi unuttuğunuzda <code>/forgot-password</code> sayfasından güvenli giriş yapabilmek için 10 adet tek kullanımlık <code>SRNT-…</code> kurtarma kodu üretin ve saklayın.</p></div></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;margin-bottom:20px">
        <form class="customer-create-panel" id="sysadmin-recovery-codes-form" style="padding:16px;margin:0"><h4 style="margin-top:0">Acil Kurtarma Kodları Üret (.txt)</h4><p style="font-size:13px;color:var(--text-muted)">Yeni 10 kod üretildiğinde eski kullanılmamış kodlar iptal edilir.</p><label>Mevcut şifreniz<input id="sysadmin-recovery-current-pw" type="password" autocomplete="current-password" required></label><button class="btn btn-primary" type="submit" style="margin-top:8px">10 Yeni Kurtarma Kodu Üret ve İndir</button><div id="sysadmin-regenerated-codes-box"></div></form>
        <form class="customer-create-panel" id="sysadmin-change-pw-form" style="padding:16px;margin:0"><h4 style="margin-top:0">Yönetici Şifresini Değiştir</h4><label>Mevcut şifre<input id="sysadmin-old-pw" type="password" autocomplete="current-password" required></label><label>Yeni şifre (en az 10 karakter, harf + rakam)<input id="sysadmin-new-pw" type="password" autocomplete="new-password" minlength="10" required></label><label>Yeni şifre tekrar<input id="sysadmin-confirm-pw" type="password" autocomplete="new-password" minlength="10" required></label><button class="btn btn-secondary" type="submit" style="margin-top:8px">Şifreyi Güncelle</button></form>
      </div>
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
      <div class="section-heading spaced"><div><h3>Güvenlik Duvarı & IP Engelleme (Blacklist)</h3><p>Şüpheli IP adreslerini Redis güvenlik duvarı üzerinden anında engelleyin veya engeli kaldırın.</p></div></div><form class="admin-form-grid" id="ban-ip-form" style="margin-bottom:12px"><label>IP Adresi<input id="ban-ip-input" required placeholder="Örn. 185.220.101.1"></label><label>Süre (Saat)<input id="ban-ip-hours" type="number" min="1" max="8760" value="24" required></label><label class="wide-field">Engelleme Gerekçesi<input id="ban-ip-reason" required placeholder="Örn. Brute-force giriş denemesi"></label><button class="btn btn-danger" type="submit">IP Adresini Engelle</button></form>${table([{label:'IP Adresi',render:r=>`<code>${esc(r.ip)}</code>`},{label:'Gerekçe',render:r=>esc(r.reason||'—')},{label:'Kalan Süre',render:r=>`${Math.ceil(Number(r.ttl_seconds||0)/60)} dk`},{label:'İşlem',render:r=>`<button type="button" class="btn btn-secondary btn-sm unban-ip-btn" data-ip="${esc(r.ip)}">Engeli Kaldır</button>`}],Array.isArray(blacklist)?blacklist:[])}
      ${''}
      ${''}
      ${''}
      <div class="section-heading spaced"><div><h3>Denetim Kayıtları (Audit Logs)</h3><p>Sistem üzerinde yapılan tüm kritik yönetim işlemleri.</p></div><button type="button" class="btn btn-secondary btn-sm" id="export-audit-csv-btn">📥 CSV Olarak İndir</button></div>
      ${''}
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
    const sysRecForm=document.getElementById('sysadmin-recovery-codes-form');if(sysRecForm)sysRecForm.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const res=await apiFetch('/auth/recovery/codes/regenerate',{method:'POST',body:{current_password:document.getElementById('sysadmin-recovery-current-pw').value}});const codesText=res.recovery_codes.join('\n');const blob=new Blob([`Serenut OS Sysadmin Acil Kurtarma Kodları\n\n${codesText}\n`],{type:'text/plain;charset=utf-8'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='serenut-sysadmin-kurtarma-kodlari.txt';link.click();URL.revokeObjectURL(link.href);const box=document.getElementById('sysadmin-regenerated-codes-box');if(box){box.innerHTML=`<div class="state-panel" style="margin-top:12px;border:2px solid #16a34a"><strong>10 yeni kurtarma kodunuz üretildi ve indirildi:</strong><pre style="white-space:pre-wrap;user-select:all;margin:8px 0">${esc(codesText)}</pre><button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(codesText)}">Kodları Kopyala</button></div>`;bindCopyButtons(box);}notice('Yeni kurtarma kodları oluşturuldu ve indirildi.');}catch(err){notice(err.message||'Kurtarma kodları üretilemedi.');}finally{b.disabled=false;}};
    const sysPwForm=document.getElementById('sysadmin-change-pw-form');if(sysPwForm)sysPwForm.onsubmit=async e=>{e.preventDefault();const b=e.submitter;const next=document.getElementById('sysadmin-new-pw').value;const conf=document.getElementById('sysadmin-confirm-pw').value;if(next!==conf){notice('Yeni şifreler eşleşmiyor.');return;}b.disabled=true;try{await apiFetch('/auth/change-password',{method:'POST',body:{old_password:document.getElementById('sysadmin-old-pw').value,new_password:next}});notice('Şifreniz güncellendi. Yeni şifrenizle tekrar giriş yapın.');window.location.reload();}catch(err){notice(err.message||'Şifre güncellenemedi.');b.disabled=false;}};
    const banIpForm=document.getElementById('ban-ip-form');if(banIpForm)banIpForm.onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{await apiFetch('/admin/security/ban-ip',{method:'POST',body:{ip:document.getElementById('ban-ip-input').value.trim(),duration_hours:Number(document.getElementById('ban-ip-hours').value||24),reason:document.getElementById('ban-ip-reason').value.trim()}});notice('IP adresi güvenlik duvarında engellendi.');await loaders['platform-security']();}catch(err){notice(err.message||'IP engellenemedi.');b.disabled=false;}};
    document.querySelectorAll('.unban-ip-btn').forEach(btn=>btn.onclick=async()=>{btn.disabled=true;try{await apiFetch(`/admin/security/ban-ip/${encodeURIComponent(btn.dataset.ip)}`,{method:'DELETE'});notice('IP engeli kaldırıldı.');await loaders['platform-security']();}catch(err){notice(err.message||'IP engeli kaldırılamadı.');btn.disabled=false;}});
    const exportCsvBtn=document.getElementById('export-audit-csv-btn');if(exportCsvBtn)exportCsvBtn.onclick=async()=>{exportCsvBtn.disabled=true;try{const res=await fetch('/api/v1/admin/audit-logs/export',{headers:{Authorization:`Bearer ${getAuthToken()}`}});if(!res.ok)throw new Error('CSV indirilemedi.');const blob=await res.blob();const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`serenut-audit-logs-${new Date().toISOString().slice(0,10)}.csv`;a.click();URL.revokeObjectURL(url);notice('Denetim kayıtları CSV olarak indirildi.');}catch(err){notice(err.message);}finally{exportCsvBtn.disabled=false;}};
  },
  'platform-support': async () => {
    const [result,guestResult]=await Promise.all([apiFetch('/support/tickets'),apiFetch('/support/guest-requests')]);const tickets=result.tickets||[];const guests=guestResult.requests||[];set(`<div class="metrics-grid">${metric('Firma Talebi',result.total??tickets.length)}${metric('Açık',tickets.filter(x=>!['closed','resolved'].includes(x.status)).length)}${metric('Yeni Ön Başvuru',guests.filter(x=>x.status==='unverified').length)}${metric('Acil',tickets.filter(x=>x.priority==='P1').length)}</div><div class="section-heading spaced"><div><h3>Firma Destek Talepleri</h3><p>Panelden açılan ve firma hesabına bağlı talepler.</p></div></div>${table([{label:'No',render:r=>esc(r.id)},{label:'Firma',render:r=>esc(r.company_name||'—')},{label:'Kategori',render:r=>badge(tr(r.category||'technical'))},{label:'Konu',key:'subject'},{label:'Öncelik',render:r=>badge(r.priority)},{label:'Güncelleme',render:r=>esc(date(r.updated_at))},{label:'Durum',render:r=>badge(tr(r.status))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm ticket-open" data-id="${esc(r.id)}">İncele</button>`}],tickets)}<div class="section-heading spaced"><div><h3>Ön Destek Başvuruları</h3><p>İletişim formundan gelen veya posta kutusundan özellikle desteğe yönlendirdiğiniz başvurular.</p></div></div>${table([{label:'Takip No',key:'reference_code'},{label:'Başvuran',render:r=>`${esc(r.name)}<small>${esc(r.email)}</small>`},{label:'Kaynak',render:r=>esc(r.intake_source==='inbound_email'?'E-posta':'İletişim formu')},{label:'Kategori',render:r=>badge(tr(r.category))},{label:'Konu',key:'subject'},{label:'Tarih',render:r=>esc(date(r.created_at))},{label:'Durum',render:r=>badge(tr(r.status))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm guest-open" data-id="${esc(r.id)}">İncele</button>`}],guests)}`);
    document.querySelectorAll('.ticket-open').forEach(b=>b.onclick=()=>showSupportTicket(b.dataset.id,true));
    document.querySelectorAll('.guest-open').forEach(b=>b.onclick=()=>showGuestRequest(b.dataset.id));
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
    if (currentToken) { try { const p=JSON.parse(atob(currentToken.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))); currentSessionId=p.session_id||p.jti||null; } catch(_){} }
    if (!currentSessionId && sessions.length>0) { const sorted=[...sessions].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at)); currentSessionId=sorted[0]?.id; }
    set(`<div class="metrics-grid">${metric('Ad Soyad',me.name)}${metric('E-posta',me.email)}${metric('Yetki',tr((me.roles||[])[0]))}</div><div class="section-heading spaced"><div><h3>Şifre Değiştir</h3><p>Şifre değiştiğinde güvenliğiniz için tüm aktif oturumlar kapatılır.</p></div></div><form class="customer-form-grid" id="change-password-form"><label>Mevcut şifre<input id="current-password" type="password" autocomplete="current-password" required></label><label>Yeni şifre<input id="new-password" type="password" autocomplete="new-password" minlength="10" required placeholder="En az 10 karakter; harf ve rakam"></label><label>Yeni şifre tekrar<input id="confirm-password" type="password" autocomplete="new-password" minlength="10" required></label><button class="btn btn-primary" type="submit">Şifreyi Değiştir</button></form><div class="section-heading spaced"><div><h3>Firma Bilgileri</h3><p>Uygulama ilk kurulumda bu bilgileri hazır olarak kullanır.</p></div></div><form class="customer-form-grid company-profile-form" id="company-profile-form"><label>Firma ünvanı<input id="profile-company-name" value="${esc(company.name||'')}" required></label><label>Yetkili kişi<input id="profile-owner-name" value="${esc(company.owner_name||'')}"></label><label>TC veya Vergi No<input id="profile-tax-number" maxlength="11" value="${esc(company.tax_number&&!String(company.tax_number).startsWith('PENDING-')?company.tax_number:'')}" placeholder="10 veya 11 haneli numara"></label><label>Telefon<input id="profile-phone" value="${esc(company.phone||'')}"></label><label>Vergi dairesi<input id="profile-tax-office" value="${esc(company.tax_office||'')}"></label><label>İl<input id="profile-city" value="${esc(company.city||'')}"></label><label>İlçe<input id="profile-district" value="${esc(company.district||'')}"></label><label class="wide-field">Adres<input id="profile-address" value="${esc(company.address||'')}"></label><button class="btn btn-primary" type="submit">Bilgileri Kaydet</button></form><div class="section-heading spaced"><div><h3>Aktif Oturumlar</h3><p>Hesabınıza giriş yapılmış oturumlar. Tanımadığınız bir oturum varsa kapatın.</p></div></div>${table([{label:'Cihaz / Tarayıcı',render:r=>{const isCurrent=r.id===currentSessionId;return `${esc(parseUA(r.user_agent))}${isCurrent?'<span class="status-badge status-active" style="margin-left:8px">✓ Bu oturum</span>':''}`;}},{label:'IP Adresi',render:r=>esc(r.ip_address||'—')},{label:'Oluşturma',render:r=>esc(date(r.created_at))},{label:'Bitiş',render:r=>esc(date(r.expires_at))},{label:'İşlem',render:r=>`<button class="btn btn-secondary btn-sm revoke-session" data-id="${esc(r.id)}" ${r.id===currentSessionId?'title="Bu mevcut oturumunuzdur"':''}>Oturumu Kapat</button>`}],sessions)}`);
    const companyForm=document.getElementById('company-profile-form');
    companyForm.insertAdjacentHTML('beforebegin','<div class="section-heading spaced"><div><h3>Kurtarma Kodları</h3><p>Yeni set oluşturulduğunda eski kullanılmamış kodlar iptal edilir.</p></div></div><form class="customer-form-grid" id="recovery-codes-form"><label>Mevcut şifre<input id="recovery-current-password" type="password" autocomplete="current-password" required></label><button class="btn btn-secondary" type="submit">Yeni Kurtarma Kodları Oluştur</button></form><div id="regenerated-codes-box"></div>');
    companyForm.insertAdjacentHTML('afterend','<form class="customer-form-grid" id="company-logo-upload-form" style="margin-top:12px"><label>Logo dosyası yükle (PNG, JPEG, WebP - maks. 2MB)<input id="company-logo-file" type="file" accept="image/png,image/jpeg,image/webp" required></label><button class="btn btn-secondary" type="submit">Logoyu Yükle</button></form>');
    document.getElementById('company-logo-upload-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const file=document.getElementById('company-logo-file').files?.[0];if(!file)return;b.disabled=true;try{const fd=new FormData();fd.append('logo',file);await apiFetch('/company/logo',{method:'POST',body:fd});notice('Firma logosu başarıyla yüklendi.');await loaders['account-settings']();}catch(err){notice(err.message||'Logo yüklenemedi.');b.disabled=false;}};
    document.getElementById('recovery-codes-form').onsubmit=async event=>{event.preventDefault();const button=event.submitter;button.disabled=true;try{const result=await apiFetch('/auth/recovery/codes/regenerate',{method:'POST',body:{current_password:document.getElementById('recovery-current-password').value}});const codesText=result.recovery_codes.join('\n');const text=`Serenut OS kurtarma kodları\n\n${codesText}\n`;const blob=new Blob([text],{type:'text/plain;charset=utf-8'});const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='serenut-kurtarma-kodlari.txt';link.click();URL.revokeObjectURL(link.href);const box=document.getElementById('regenerated-codes-box');if(box){box.innerHTML=`<div class="state-panel" style="margin:12px 0;border:2px solid #16a34a"><strong>Yeni kurtarma kodlarınız oluşturuldu ve indirildi</strong><pre style="white-space:pre-wrap;user-select:all;margin:8px 0">${esc(codesText)}</pre><button type="button" class="btn btn-secondary btn-sm copy-value-btn" data-copy="${esc(codesText)}">Kodları Kopyala</button></div>`;bindCopyButtons(box);}notice('Yeni kurtarma kodları oluşturuldu ve indirildi.');}catch(error){notice(error.message||'Kodlar oluşturulamadı.');}finally{button.disabled=false;}};
    document.getElementById('change-password-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;const next=document.getElementById('new-password').value;const confirmation=document.getElementById('confirm-password').value;if(next!==confirmation){notice('Yeni şifreler eşleşmiyor.');return;}b.disabled=true;try{await apiFetch('/auth/change-password',{method:'POST',body:{old_password:document.getElementById('current-password').value,new_password:next}});notice('Şifreniz değiştirildi. Lütfen yeni şifrenizle tekrar giriş yapın.');window.location.reload();}catch(x){notice(x.message||'Şifre değiştirilemedi.');b.disabled=false}};
    document.getElementById('company-profile-form').onsubmit=async e=>{e.preventDefault();const b=e.submitter;b.disabled=true;try{const taxVal=document.getElementById('profile-tax-number')?.value.replace(/\D/g,'').trim();const payload={expected_version:company.version,name:document.getElementById('profile-company-name').value.trim(),owner_name:document.getElementById('profile-owner-name').value.trim(),phone:document.getElementById('profile-phone').value.trim(),tax_office:document.getElementById('profile-tax-office').value.trim(),city:document.getElementById('profile-city').value.trim(),district:document.getElementById('profile-district').value.trim(),address:document.getElementById('profile-address').value.trim()};if(taxVal&&/^\d{10,11}$/.test(taxVal)){payload.tax_number=taxVal;}await apiFetch('/company',{method:'PATCH',body:payload});notice('Firma bilgileri kaydedildi.');await loaders['account-settings']();}catch(x){notice(x.message)}finally{b.disabled=false}};
    document.querySelectorAll('.revoke-session').forEach(b=>b.onclick=async()=>{b.disabled=true;try{await apiFetch(`/users/sessions/${encodeURIComponent(b.dataset.id)}`,{method:'DELETE'});await loaders['account-settings']();}catch(x){notice(x.message);b.disabled=false}});
  }
};

export async function loadModule(item) {
  stopWhatsAppConnectionPoll();
  const loader=loaders[item.id]; if(!loader) throw new Error('Bu modül için ekran tanımı bulunamadı.');
  document.getElementById('embed-content').innerHTML='<div class="module-loading">Veriler yükleniyor…</div>';
  try{await loader()}catch(error){errorView(error,()=>loadModule(item))}
}
