/* ==========================================================================
   SERENUT OS V2 - PORTAL USERS MODULE
   ========================================================================== */

import { apiFetch } from '/shared/js/api-client.js';
import { formatDate } from '/shared/js/formatters.js';
import { showToast, showConfirm } from '/shared/js/ui.js';

let availableRoles = [];
let resetTargetUserId = null;

/**
 * Loads available roles
 * @returns {Promise<Array>}
 */
export async function loadRoles() {
  if (availableRoles.length > 0) return availableRoles;
  try {
    availableRoles = await apiFetch('/portal/roles');
  } catch (err) {
    console.error('Failed to load user roles:', err);
  }
  return availableRoles;
}

/**
 * Loads company user cards
 */
export async function loadUsers() {
  const grid = document.getElementById('users-card-grid');
  if (!grid) return;

  grid.innerHTML = '<p class="text-muted">Kullanıcılar yükleniyor...</p>';

  try {
    const [users, roles] = await Promise.all([
      apiFetch('/portal/users'),
      loadRoles()
    ]);

    grid.innerHTML = '';

    if (!Array.isArray(users) || users.length === 0) {
      grid.innerHTML = '<p class="text-muted" style="grid-column: 1 / -1; text-align: center; padding: 20px;">Henüz personel hesabı tanımlanmamış.</p>';
      return;
    }

    users.forEach(u => {
      const roleObj = roles.find(r => r.id === u.role_id);
      let roleLabel = u.role_name || '🧾 Kasiyer';
      if (roleObj) {
        roleLabel = roleObj.name === 'owner' ? '👑 Firma Sahibi' : roleObj.name === 'manager' ? '🏪 Yönetici' : '🧾 Kasiyer';
      }

      const isActive = u.is_active !== false;
      const created = formatDate(u.created_at);

      const card = document.createElement('div');
      card.className = 'glass-panel';
      card.style.display = 'flex';
      card.style.flexDirection = 'column';
      card.style.gap = 'var(--space-4)';
      card.style.border = '1px solid var(--neutral-800)';

      card.innerHTML = `
        <div class="flex items-center justify-between gap-4">
          <div class="flex items-center gap-3">
            <div style="width:40px; height:40px; border-radius:50%; background:rgba(16,185,129,0.1); color:var(--primary-400); display:flex; align-items:center; justify-content:center; font-size:1.2rem;">
              ${roleLabel.split(' ')[0]}
            </div>
            <div>
              <div class="font-semibold text-light">${u.name}</div>
              <div class="text-muted text-xs">${u.email}</div>
            </div>
          </div>
          <span class="badge ${isActive ? 'badge-active' : 'badge-danger'}" style="font-size:0.68rem;">
            ${isActive ? 'Aktif' : 'Pasif'}
          </span>
        </div>

        <div class="flex justify-between items-center text-xs text-muted">
          <span>${roleLabel.substring(2)}</span>
          <span>Kayıt: ${created}</span>
        </div>

        <div class="flex gap-2 mt-2">
          <button class="btn btn-secondary btn-sm flex-1 btn-reset-pw" data-id="${u.id}" data-name="${u.name}">🔑 Şifre</button>
          <button class="btn btn-secondary btn-sm flex-1 btn-toggle-state" data-id="${u.id}" data-active="${isActive}">
            ${isActive ? '⏸ Pasif' : '▶ Aktif'}
          </button>
          <button class="btn btn-danger btn-sm btn-delete-user" data-id="${u.id}" data-name="${u.name}">🗑 Sil</button>
        </div>
      `;

      grid.appendChild(card);
    });

    // Bind event handlers dynamically
    grid.querySelectorAll('.btn-reset-pw').forEach(btn => {
      btn.onclick = () => openResetPasswordModal(btn.getAttribute('data-id'), btn.getAttribute('data-name'));
    });
    grid.querySelectorAll('.btn-toggle-state').forEach(btn => {
      btn.onclick = () => toggleUserActive(btn.getAttribute('data-id'), btn.getAttribute('data-active') === 'true');
    });
    grid.querySelectorAll('.btn-delete-user').forEach(btn => {
      btn.onclick = () => deleteUser(btn.getAttribute('data-id'), btn.getAttribute('data-name'));
    });

  } catch (err) {
    console.error('Failed to load users:', err);
    grid.innerHTML = '<p class="text-danger">Kullanıcılar listesi yüklenemedi.</p>';
  }
}

/**
 * Submits post add new user form
 */
export async function submitCreateUser() {
  const name = document.getElementById('usr-name').value.trim();
  const email = document.getElementById('usr-email').value.trim();
  const password = document.getElementById('usr-password').value;
  const role_id = document.getElementById('usr-role').value;
  const errEl = document.getElementById('usr-error');

  errEl.innerText = '';
  if (!name || !email || !password || !role_id) {
    errEl.innerText = 'Lütfen tüm alanları doldurun.';
    return false;
  }

  try {
    await apiFetch('/portal/users', {
      method: 'POST',
      body: { name, email, password, role_id }
    });
    showToast('Kullanıcı hesabı oluşturuldu.', 'success');
    loadUsers();
    return true;
  } catch (err) {
    errEl.innerText = err.message || 'Kullanıcı oluşturulamadı.';
    return false;
  }
}

function openResetPasswordModal(id, name) {
  resetTargetUserId = id;
  document.getElementById('reset-pw-user-name').innerText = `Kullanıcı: ${name}`;
  document.getElementById('reset-new-password').value = '';
  document.getElementById('reset-pw-error').innerText = '';
  document.getElementById('modal-reset-password').classList.add('active');
}

/**
 * Handles reset password form submission
 */
export async function submitResetPassword() {
  const password = document.getElementById('reset-new-password').value;
  const errEl = document.getElementById('reset-pw-error');

  errEl.innerText = '';
  if (!password || password.length < 8) {
    errEl.innerText = 'Yeni şifre en az 8 karakter olmalıdır.';
    return false;
  }

  try {
    await apiFetch(`/portal/users/${resetTargetUserId}`, {
      method: 'PATCH',
      body: { new_password: password }
    });
    showToast('Kullanıcı şifresi sıfırlandı.', 'success');
    document.getElementById('modal-reset-password').classList.remove('active');
    return true;
  } catch (err) {
    errEl.innerText = err.message || 'Şifre güncellenemedi.';
    return false;
  }
}

async function toggleUserActive(userId, currentlyActive) {
  try {
    await apiFetch(`/portal/users/${userId}`, {
      method: 'PATCH',
      body: { is_active: !currentlyActive }
    });
    showToast('Kullanıcı aktiflik durumu güncellendi.', 'success');
    loadUsers();
  } catch (err) {
    showToast(err.message || 'Hata oluştu.', 'error');
  }
}

async function deleteUser(userId, name) {
  const confirmed = await showConfirm(
    'Kullanıcı Silme Onayı',
    `"${name}" isimli personeli kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.`
  );
  if (!confirmed) return;

  try {
    await apiFetch(`/portal/users/${userId}`, { method: 'DELETE' });
    showToast('Kullanıcı başarıyla silindi.', 'success');
    loadUsers();
  } catch (err) {
    showToast(err.message || 'Kullanıcı silinemedi.', 'error');
  }
}
