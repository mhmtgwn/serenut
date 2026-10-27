import { clearAuthSession, getAuthToken, refreshAccessToken, setAuthToken, setRefreshToken } from '/shared/js/api-client.js';
import { setUserProfile } from '/shared/js/auth.js';

const page = document.body.dataset.authPage;
const status = document.getElementById('status');

validateExistingSession();
setupPasswordEnhancements();
setupPagePrefills();

async function validateExistingSession() {
  const token = getAuthToken();
  if (!token || page === 'reset-password') return;
  try {
    let response = await fetch('/api/v1/users/me', {
      headers: { 'Accept': 'application/json', 'Authorization': `Bearer ${token}` }
    });
    if (response.status === 401 && await refreshAccessToken()) {
      const nextToken = getAuthToken();
      response = await fetch('/api/v1/users/me', {
        headers: { 'Accept': 'application/json', 'Authorization': `Bearer ${nextToken}` }
      });
    }
    if (response.ok) {
      window.location.replace('/app/?flow=panel');
      return;
    }
    if (response.status === 401 || response.status === 403) {
      clearAuthSession();
    }
  } catch (_) {
    // Do not clear auth session on temporary network failures
  }
}

const message = (text, success = false, targetForm = null) => {
  if (status) {
    status.className = `auth-status text-sm ${success ? 'text-green' : 'text-red'}`;
    status.textContent = text;
  }
  if (targetForm) {
    let inlineStatus = targetForm.querySelector('.inline-auth-status');
    if (!inlineStatus) {
      inlineStatus = document.createElement('div');
      inlineStatus.setAttribute('role', 'status');
      const submitBtn = targetForm.querySelector('button[type="submit"]');
      if (submitBtn) {
        submitBtn.before(inlineStatus);
      } else {
        targetForm.appendChild(inlineStatus);
      }
    }
    inlineStatus.className = `inline-auth-status auth-status text-sm ${success ? 'text-green' : 'text-red'}`;
    inlineStatus.textContent = text;
  }
};

const errorMessage = (data, fallback) =>
  data?.error?.message || (typeof data?.error === 'string' ? data.error : '') || data?.message || fallback;

async function post(endpoint, body) {
  const response = await fetch(`/api/v1/auth/${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(errorMessage(data, 'İşlem tamamlanamadı.'));
    error.data = data;
    throw error;
  }
  return data;
}

function setupPasswordEnhancements() {
  const passwordInputs = document.querySelectorAll('input[type="password"]');
  passwordInputs.forEach((input) => {
    const label = input.closest('label.simple-field');
    if (!label || label.querySelector('.pw-toggle-btn')) return;
    const span = label.querySelector('span');
    if (span) {
      span.style.display = 'flex';
      span.style.justifyContent = 'space-between';
      span.style.alignItems = 'center';
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = 'ghost-link pw-toggle-btn';
      toggle.style.fontSize = '12px';
      toggle.textContent = 'Göster';
      toggle.addEventListener('click', (e) => {
        e.preventDefault();
        const isPw = input.type === 'password';
        input.type = isPw ? 'text' : 'password';
        toggle.textContent = isPw ? 'Gizle' : 'Göster';
      });
      span.appendChild(toggle);
    }

    if ((page === 'register' || page === 'reset-password') && input.id === 'password') {
      const hint = document.createElement('small');
      hint.className = 'pw-strength-hint text-muted';
      hint.style.display = 'block';
      hint.style.fontSize = '12px';
      hint.style.marginTop = '4px';
      hint.textContent = 'En az 10 karakter, 1 harf ve 1 rakam gerekli.';
      label.appendChild(hint);
      input.addEventListener('input', () => {
        const val = input.value || '';
        const lenOk = val.length >= 10;
        const letterOk = /\p{L}/u.test(val);
        const digitOk = /\d/.test(val);
        if (!val) {
          hint.textContent = 'En az 10 karakter, 1 harf ve 1 rakam gerekli.';
          hint.className = 'pw-strength-hint text-muted';
          return;
        }
        hint.textContent = `${lenOk ? '✓' : '○'} 10+ karakter  ·  ${letterOk ? '✓' : '○'} Harf  ·  ${digitOk ? '✓' : '○'} Rakam`;
        hint.className = `pw-strength-hint ${lenOk && letterOk && digitOk ? 'text-green' : 'text-muted'}`;
      });
    }
  });
}

function setupPagePrefills() {
  const searchParams = new URLSearchParams(window.location.search);
  if (page === 'register') {
    const rawPlan = searchParams.get('plan');
    if (rawPlan) {
      const planMap = {
        basic: { id: 'plan-basic', label: 'Başlangıç (Starter)' },
        'plan-basic': { id: 'plan-basic', label: 'Başlangıç (Starter)' },
        pro: { id: 'plan-pro', label: 'Profesyonel (Pro)' },
        'plan-pro': { id: 'plan-pro', label: 'Profesyonel (Pro)' },
        enterprise: { id: 'plan-enterprise', label: 'Kurumsal (Pro Plus)' },
        'plan-enterprise': { id: 'plan-enterprise', label: 'Kurumsal (Pro Plus)' }
      };
      const matched = planMap[rawPlan.toLowerCase()];
      if (matched) {
        try { sessionStorage.setItem('selected_plan_id', matched.id); } catch (_) {}
        const heading = document.querySelector('.simple-auth-heading');
        if (heading && !document.getElementById('selected-plan-banner')) {
          const banner = document.createElement('div');
          banner.id = 'selected-plan-banner';
          banner.className = 'auth-status text-sm text-green';
          banner.style.marginTop = '8px';
          banner.textContent = `Seçilen paket: ${matched.label} — Hesabınız 30 gün ücretsiz deneme ile açılır, panelden paketinize geçebilirsiniz.`;
          heading.appendChild(banner);
        }
      }
    }
  }

  if (page === 'forgot-password') {
    const reqId = searchParams.get('request_id');
    const claimCode = searchParams.get('claim_code');
    if (reqId || claimCode) {
      const reqInput = document.getElementById('request-id');
      const codeInput = document.getElementById('claim-code');
      if (reqInput && reqId) reqInput.value = reqId;
      if (codeInput && claimCode) codeInput.value = claimCode;
      const details = document.getElementById('recovery-claim-form')?.closest('details');
      if (details) details.open = true;
    }
  }
}

function showRecoveryCodes(codes, destination = '/app/?flow=panel', extraNotice = '') {
  const form = document.querySelector('form');
  if (form) form.hidden = true;
  const panel = document.createElement('section');
  panel.setAttribute('aria-labelledby', 'recovery-codes-title');
  panel.innerHTML = `
    <h2 id="recovery-codes-title">Kurtarma kodlarınızı saklayın</h2>
    <p>Bu kodlar yalnızca şimdi gösterilir. Her kod tek kullanımlıktır.</p>
    ${extraNotice ? `<div class="auth-status text-sm text-green" style="margin-bottom:10px;font-weight:600">${extraNotice}</div>` : ''}
    <pre id="recovery-code-list" class="simple-field" style="white-space:pre-wrap;user-select:all"></pre>
    <div style="display:flex;gap:8px;flex-wrap:wrap;margin:10px 0">
      <button type="button" class="btn btn-primary" style="flex:1" id="download-recovery-codes">Kodları İndir (.txt)</button>
      <button type="button" class="btn btn-secondary" style="flex:1" id="copy-recovery-codes">Kodları Kopyala</button>
    </div>
    <label style="display:flex;align-items:center;gap:8px;margin:10px 0;font-size:13px;cursor:pointer">
      <input type="checkbox" id="confirm-codes-saved">
      <span>Kurtarma kodlarımı güvenli bir yere kaydettim</span>
    </label>
    <a class="btn w-full" id="continue-after-codes" href="${destination}">Kodları Kaydettim, Devam Et</a>`;
  panel.querySelector('#recovery-code-list').textContent = codes.join('\n');
  const confirmBox = panel.querySelector('#confirm-codes-saved');
  panel.querySelector('#download-recovery-codes').addEventListener('click', () => {
    const blob = new Blob([`Serenut OS kurtarma kodları\n\n${codes.join('\n')}\n`], { type: 'text/plain;charset=utf-8' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'serenut-kurtarma-kodlari.txt';
    link.click();
    URL.revokeObjectURL(link.href);
    if (confirmBox) confirmBox.checked = true;
  });
  panel.querySelector('#copy-recovery-codes')?.addEventListener('click', async (e) => {
    const btn = e.currentTarget;
    try {
      await navigator.clipboard.writeText(codes.join('\n'));
      btn.textContent = '✓ Kodlar Kopyalandı';
      if (confirmBox) confirmBox.checked = true;
    } catch (_) {
      btn.textContent = 'Kopyalanamadı, listeden seçin';
    }
  });
  panel.querySelector('#continue-after-codes')?.addEventListener('click', (e) => {
    if (confirmBox && !confirmBox.checked) {
      e.preventDefault();
      message('Devam etmeden önce kurtarma kodlarınızı indirin, kopyalayın veya kaydettiğinizi onaylayın.');
      confirmBox.focus();
    }
  });
  status.after(panel);
  message(
    extraNotice || 'Hesabınız oluşturuldu. Devam etmeden önce kurtarma kodlarını kaydedin.',
    true
  );
}

function appendResendVerificationButton() {
  if (status.querySelector('.resend-verification-btn')) return;
  const resend = document.createElement('button');
  resend.type = 'button';
  resend.className = 'ghost-link resend-verification-btn';
  resend.textContent = 'Doğrulama bağlantısını yeniden gönder';
  resend.addEventListener('click', () => resendVerification(resend));
  status.append(' ', resend);
}

document.getElementById('login-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('login', {
      email: document.getElementById('email').value.trim(),
      password: document.getElementById('password').value
    });
    setAuthToken(data.access_token);
    setRefreshToken(data.refresh_token);
    setUserProfile(data.user);
    const next = new URLSearchParams(window.location.search).get('next');
    window.location.replace(next?.startsWith('/app') ? next : '/app/?flow=panel');
  } catch (error) {
    message(error.message);
    if (error.data?.error?.code === 'EMAIL_NOT_VERIFIED') {
      appendResendVerificationButton();
    }
  } finally {
    button.disabled = false;
  }
});

async function resendVerification(button) {
  const emailVal = document.getElementById('email')?.value?.trim();
  if (!emailVal) {
    message('Yeni doğrulama bağlantısı için lütfen önce e-posta adresinizi girin.');
    document.getElementById('email')?.focus();
    return;
  }
  button.disabled = true;
  try {
    const data = await post('resend-verification', { email: emailVal });
    button.textContent = data.message || 'Bağlantı gönderildi';
  } catch (error) {
    button.textContent = `${error.message} (Tekrar dene)`;
    button.disabled = false;
  }
}

document.getElementById('register-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = event.submitter;
  const taxNumber = document.getElementById('tax-number').value.replace(/\D/g, '');
  if (![10, 11].includes(taxNumber.length)) {
    message('TC Kimlik No 11, Vergi Kimlik No 10 haneli olmalıdır.');
    return;
  }
  const password = document.getElementById('password').value;
  if (password.length < 10 || !/\p{L}/u.test(password) || !/\d/.test(password)) {
    message('Şifre en az 10 karakter olmalı ve harf ile rakam içermelidir.');
    return;
  }

  button.disabled = true;
  try {
    const data = await post('register', {
      company_name: document.getElementById('company').value.trim(),
      name: document.getElementById('name').value.trim(),
      email: document.getElementById('email').value.trim(),
      phone: document.getElementById('phone').value.trim(),
      tax_number: taxNumber,
      tax_office: document.getElementById('tax-office').value.trim(),
      city: document.getElementById('city').value.trim(),
      district: document.getElementById('district').value.trim(),
      address: document.getElementById('address').value.trim(),
      password,
      accept_terms: document.getElementById('accept-terms').checked,
      accept_privacy: document.getElementById('accept-privacy').checked,
      accept_kvkk: document.getElementById('accept-kvkk').checked,
      accept_marketing: document.getElementById('accept-marketing').checked
    });

    const selectedPlan = sessionStorage.getItem('selected_plan_id');
    const panelDest = selectedPlan ? '/app/#billing-center' : '/app/?flow=panel';

    if (data.access_token) {
      setAuthToken(data.access_token);
      setRefreshToken(data.refresh_token);
      if (data.user) setUserProfile(data.user);
      if (Array.isArray(data.recovery_codes) && data.recovery_codes.length) {
        showRecoveryCodes(data.recovery_codes, panelDest);
        return;
      }
      window.location.replace(panelDest);
      return;
    }

    const verifyNotice = data.email_verification_required
      ? (data.message || 'Hesabınız oluşturuldu. Giriş yapabilmek için e-posta adresinize gönderilen doğrulama bağlantısını onaylayın.')
      : '';
    if (Array.isArray(data.recovery_codes) && data.recovery_codes.length) {
      showRecoveryCodes(data.recovery_codes, '/login', verifyNotice);
      return;
    }
    message(data.message || 'Hesabınız oluşturuldu.', true);
    button.remove();
    const login = document.createElement('a');
    login.className = 'btn btn-primary w-full';
    login.href = '/login';
    login.textContent = 'Giriş Sayfasına Git';
    status.after(login);
  } catch (error) {
    message(error.message);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('forgot-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('recovery/authorize-code', {
      identifier: document.getElementById('identifier').value.trim(),
      company_name: document.getElementById('company-name')?.value?.trim() || '',
      tax_number: (document.getElementById('tax-number')?.value || '').replace(/\D/g, ''),
      recovery_code: document.getElementById('recovery-code').value.trim()
    });
    sessionStorage.setItem('serenut_password_reset_token', data.reset_token);
    window.location.replace('/reset-password');
  } catch (error) {
    message(error.message, false, form);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('recovery-claim-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('recovery/claim', {
      request_id: document.getElementById('request-id').value.trim(),
      claim_code: document.getElementById('claim-code').value.trim()
    });
    sessionStorage.setItem('serenut_password_reset_token', data.reset_token);
    window.location.replace('/reset-password');
  } catch (error) {
    message(error.message, false, form);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('email-recovery-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('forgot-password', { email: document.getElementById('recovery-email').value.trim() });
    message(data.message || 'Hesap varsa sıfırlama bağlantısı gönderildi.', true);
    form.reset();
  } catch (error) {
    message(error.message);
  } finally { button.disabled = false; }
});

document.getElementById('reset-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const token = sessionStorage.getItem('serenut_password_reset_token');
  const password = document.getElementById('password').value;
  if (!token) return message('Şifre sıfırlama bağlantısı geçersiz.');
  if (password !== document.getElementById('password-confirm').value) return message('Şifreler eşleşmiyor.');
  if (password.length < 10 || !/\p{L}/u.test(password) || !/\d/.test(password)) return message('Şifre en az 10 karakter olmalı ve harf ile rakam içermelidir.');

  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('reset-password', { token, newPassword: password });
    sessionStorage.removeItem('serenut_password_reset_token');
    if (data.access_token) {
      setAuthToken(data.access_token);
      setRefreshToken(data.refresh_token);
      if (data.user) setUserProfile(data.user);
      window.location.replace('/app/?flow=panel');
      return;
    }
    message(data.message || 'Şifreniz güncellendi.', true);
    button.remove();
    const login = document.createElement('a');
    login.className = 'btn btn-primary w-full';
    login.href = '/login';
    login.textContent = 'Giriş Yap';
    status.after(login);
  } catch (error) {
    message(error.message);
  } finally {
    button.disabled = false;
  }
});

const params = new URLSearchParams(window.location.search);
if (document.body.dataset.authPage === 'reset-password' && params.get('token')) {
  sessionStorage.setItem('serenut_password_reset_token', params.get('token'));
  window.history.replaceState({}, document.title, '/reset-password');
}
if (params.get('verified') === '1') message('E-posta adresiniz doğrulandı. Giriş yapabilirsiniz.', true);
if (params.get('error') === 'portal_access_denied') message('Bu hesabın web yönetim paneline erişim yetkisi yok.');
if (params.get('error') === 'session_expired') message('Oturumunuz sona erdi. Lütfen yeniden giriş yapın.');
if (params.get('error') === 'verification_expired' || params.get('error') === 'verification_invalid') {
  message('Doğrulama bağlantısının süresi dolmuş veya geçersiz. E-posta adresinizi girip yeni bağlantı gönderebilirsiniz.');
  appendResendVerificationButton();
}
