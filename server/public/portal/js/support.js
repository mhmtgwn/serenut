/* ==========================================================================
   SERENUT OS V2 - PORTAL CUSTOMER SUPPORT MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate, translateStatus } from '/shared/js/formatters.js';
import { showToast } from '/shared/js/ui.js';

let selectedTicketId = null;

export async function loadTickets() {
  const tbody = document.getElementById('tickets-table-body');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Destek talepleri yükleniyor...</td></tr>';

  try {
    const tickets = await apiFetch('/portal/tickets');
    tbody.innerHTML = '';

    if (tickets.length === 0) {
      tbody.innerHTML = '<tr><td colspan="6" class="text-center text-muted">Açık destek talebiniz bulunmamaktadır.</td></tr>';
      return;
    }

    tickets.forEach(ticket => {
      const tr = document.createElement('tr');
      const updated = formatDate(ticket.updated_at);
      
      const priorityEmoji = ticket.priority === 'urgent' ? '🔴 Acil' : ticket.priority === 'high' ? '🟠 Yüksek' : ticket.priority === 'normal' ? '🟡 Normal' : '🟢 Düşük';
      const statusBadgeClass = ticket.status === 'open' ? 'badge-active' : (ticket.status === 'resolved' || ticket.status === 'closed') ? 'badge-danger' : 'badge-trial';

      tr.innerHTML = `
        <td><strong>#${ticket.id.substring(0, 8)}</strong></td>
        <td>${ticket.title}</td>
        <td><span class="badge badge-trial">${priorityEmoji}</span></td>
        <td><span class="badge ${statusBadgeClass}">${translateStatus(ticket.status)}</span></td>
        <td>${updated}</td>
        <td>
          <button class="btn btn-secondary btn-sm btn-open-chat" data-id="${ticket.id}" data-title="${ticket.title}" data-status="${ticket.status}">Yanıtlar / Oku</button>
        </td>
      `;
      tbody.appendChild(tr);
    });

    tbody.querySelectorAll('.btn-open-chat').forEach(btn => {
      btn.onclick = () => {
        openTicketChat(btn.getAttribute('data-id'), btn.getAttribute('data-title'), btn.getAttribute('data-status'));
      };
    });

  } catch (err) {
    console.error('Failed to load tickets:', err);
    tbody.innerHTML = '<tr><td colspan="6" class="text-center text-danger">Talepler yüklenemedi.</td></tr>';
  }
}

export async function submitCreateTicket() {
  const title = document.getElementById('tkt-title').value.trim();
  const priority = document.getElementById('tkt-priority').value;
  const description = document.getElementById('tkt-desc').value.trim();

  if (!title || !description) {
    alert('Lütfen destek konusu ve açıklamayı doldurun.');
    return false;
  }

  try {
    await apiFetch('/portal/tickets', {
      method: 'POST',
      body: { title, priority, description }
    });
    showToast('Destek talebi başarıyla iletildi.', 'success');
    loadTickets();
    return true;
  } catch (err) {
    alert(err.message || 'Talep oluşturulamadı.');
    return false;
  }
}

async function openTicketChat(id, title, status) {
  selectedTicketId = id;
  document.getElementById('ticket-chat-title').innerText = title;
  
  const badge = document.getElementById('ticket-status-badge');
  badge.innerText = translateStatus(status);
  badge.className = `badge ${status === 'open' ? 'badge-active' : (status === 'resolved' || status === 'closed') ? 'badge-danger' : 'badge-trial'}`;

  await loadTicketChatMessages();
  document.getElementById('modal-ticket-chat').classList.add('active');
}

export async function loadTicketChatMessages() {
  if (!selectedTicketId) return;
  const container = document.getElementById('ticket-chat-messages');
  container.innerHTML = '<p class="text-muted">Mesajlar yükleniyor...</p>';

  try {
    const messages = await apiFetch(`/portal/tickets/${selectedTicketId}/messages`);
    container.innerHTML = '';

    messages.forEach(msg => {
      const isAdmin = msg.sender_name === 'Serenut Destek';
      const div = document.createElement('div');
      div.className = `chat-msg ${isAdmin ? 'chat-msg-admin' : 'chat-msg-user'}`;
      
      const time = new Date(msg.created_at).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });

      div.innerHTML = `
        <strong style="display:block; font-size:0.75rem; color: var(--primary-400); margin-bottom: 2px;">${msg.sender_name}</strong>
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
  const input = document.getElementById('ticket-reply-text');
  const message = input.value.trim();
  if (!message || !selectedTicketId) return;

  try {
    await apiFetch(`/portal/tickets/${selectedTicketId}/reply`, {
      method: 'POST',
      body: { message }
    });
    input.value = '';
    await loadTicketChatMessages();
    loadTickets(); // Refresh table view status
  } catch (err) {
    showToast(err.message || 'Mesaj gönderilemedi.', 'error');
  }
}
