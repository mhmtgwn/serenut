/* ==========================================================================
   SERENUT OS V2 - ADMIN SUPPORT TICKETS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

let selectedTicketId = null;

export async function loadTickets() {
  const tbody = document.getElementById('tickets-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Destek biletleri yükleniyor...</td></tr>';

  try {
    const tickets = await apiFetch('/admin/tickets');
    tbody.innerHTML = '';

    if (tickets.length === 0) {
      tbody.innerHTML = '<tr><td colspan="7" class="text-center text-muted">Açık destek bileti bulunmamaktadır.</td></tr>';
      return;
    }

    tickets.forEach(t => {
      const created = formatDate(t.created_at);
      const tr = document.createElement('tr');
      
      const priorityLabel = t.priority === 'urgent' ? '🔴 Acil' : t.priority === 'high' ? '🟠 Yüksek' : t.priority === 'normal' ? '🟡 Normal' : '🟢 Düşük';
      const statusBadge = t.status === 'open' ? 'badge-active' : (t.status === 'resolved' || t.status === 'closed') ? 'badge-danger' : 'badge-trial';

      tr.innerHTML = `
        <td><strong>#${t.id.substring(0, 8)}</strong></td>
        <td>${t.company_name || 'Şirket Tanımsız'}</td>
        <td>${t.title}</td>
        <td><span class="badge badge-trial">${priorityLabel}</span></td>
        <td><span class="badge ${statusBadge}">${translateStatus(t.status)}</span></td>
        <td>${created}</td>
        <td>
          <button class="btn btn-secondary btn-sm btn-open-support-chat" data-id="${t.id}" data-title="${t.title}" data-status="${t.status}">Yanıtla / Detay</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-open-support-chat').forEach(btn => {
      btn.onclick = () => {
        openSupportChat(btn.getAttribute('data-id'), btn.getAttribute('data-title'), btn.getAttribute('data-status'));
      };
    });

  } catch (err) {
    console.error('Failed to load support tickets:', err);
    tbody.innerHTML = '<tr><td colspan="7" class="text-center text-danger">Biletler listesi yüklenemedi.</td></tr>';
  }
}

async function openSupportChat(id, title, status) {
  selectedTicketId = id;
  document.getElementById('ticket-title').innerText = `Talep Konusu: ${title}`;
  
  const badge = document.getElementById('ticket-status-badge');
  badge.innerText = translateStatus(status);
  badge.className = `badge ${status === 'open' ? 'badge-active' : (status === 'resolved' || status === 'closed') ? 'badge-danger' : 'badge-trial'}`;

  await Promise.all([
    loadTicketMessages(),
    loadTicketInternalNotes()
  ]);

  document.getElementById('modal-ticket').classList.add('active');
}

export async function loadTicketMessages() {
  if (!selectedTicketId) return;
  const container = document.getElementById('ticket-chat-messages');
  container.innerHTML = '<p class="text-muted">Mesajlar yükleniyor...</p>';

  try {
    const messages = await apiFetch(`/admin/tickets/${selectedTicketId}/messages`);
    container.innerHTML = '';

    messages.forEach(msg => {
      const isSystemAdmin = msg.sender_name === 'Serenut Destek';
      const div = document.createElement('div');
      div.className = `chat-msg ${isSystemAdmin ? 'chat-msg-admin' : 'chat-msg-user'}`;
      
      const time = new Date(msg.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });

      div.innerHTML = `
        <strong style="display:block; font-size:0.75rem; color: var(--secondary-400); margin-bottom: 2px;">${msg.sender_name}</strong>
        <p style="margin:0;">${msg.message}</p>
        <span class="chat-msg-time">${time}</span>
      `;
      container.appendChild(div);
    });

    container.scrollTop = container.scrollHeight;
  } catch (err) {
    container.innerHTML = '<p class="text-danger">Mesajlar yüklenemedi.</p>';
  }
}

export async function submitTicketReply() {
  const textInput = document.getElementById('ticket-reply-text');
  const message = textInput.value.trim();
  if (!message || !selectedTicketId) return;

  try {
    await apiFetch(`/admin/tickets/${selectedTicketId}/reply`, {
      method: 'POST',
      body: { message }
    });
    textInput.value = '';
    await loadTicketMessages();
    loadTickets(); // Refresh lists
  } catch (err) {
    showToast(err.message || 'Cevap gönderilemedi.', 'error');
  }
}

export async function loadTicketInternalNotes() {
  if (!selectedTicketId) return;
  const container = document.getElementById('ticket-internal-notes-list');
  container.innerHTML = 'İç notlar yükleniyor...';

  try {
    const notes = await apiFetch(`/admin/tickets/${selectedTicketId}/notes`);
    container.innerHTML = '';

    if (notes.length === 0) {
      container.innerHTML = '<div style="color: var(--neutral-400); text-align: center; font-size:0.85rem;">Kayıtlı iç not bulunmamaktadır.</div>';
      return;
    }

    notes.forEach(n => {
      const date = formatDate(n.created_at, true);
      const div = document.createElement('div');
      div.style.background = 'var(--neutral-950)';
      div.style.padding = 'var(--space-2) var(--space-3)';
      div.style.borderRadius = 'var(--radius-sm)';
      div.style.fontSize = '0.85rem';
      div.style.borderLeft = '3px solid var(--secondary-500)';

      div.innerHTML = `
        <div class="flex justify-between" style="font-weight: 700; margin-bottom: 4px; color: var(--secondary-400);">
          <span>${n.author_name}</span>
          <span style="font-size: 0.72rem; color: var(--neutral-500);">${date}</span>
        </div>
        <p style="margin: 0; color:var(--neutral-200);">${n.note}</p>
      `;
      container.appendChild(div);
    });
    container.scrollTop = container.scrollHeight;
  } catch (err) {
    container.innerHTML = '<div class="text-danger">Notlar yüklenemedi.</div>';
  }
}

export async function submitCreateInternalNote() {
  const input = document.getElementById('ticket-internal-note-input');
  const note = input.value.trim();
  if (!note || !selectedTicketId) return;

  try {
    await apiFetch(`/admin/tickets/${selectedTicketId}/notes`, {
      method: 'POST',
      body: { note }
    });
    input.value = '';
    await loadTicketInternalNotes();
  } catch (err) {
    showToast(err.message || 'Not kaydedilemedi.', 'error');
  }
}
