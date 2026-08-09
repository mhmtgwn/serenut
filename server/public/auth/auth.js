import { clearAuthSession, getAuthToken, setAuthToken, setRefreshToken } from '/shared/js/api-client.js';
import { setUserProfile } from '/shared/js/auth.js';

const page = document.body.dataset.authPage;
const status = document.getElementById('status');

validateExistingSession();

async function validateExistingSession() {
  const token = getAuthToken();
  if (!token || page === 'reset-password') return;
  try {
    const response = await fetch('/api/v1/users/me', {
      headers: { 'Accept': 'application/json', 'Authorization': `Bearer ${token}` }
    });
    if (response.ok) {
      window.location.replace('/app/?flow=panel');
      return;
    }
  } catch (_) {}
  clearAuthSession();
}

const message = (text, success = false) => {
  status.className = `auth-status text-sm ${success ? 'text-green' : 'text-red'}`;
  status.textContent = text;
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

function showRecoveryCodes(codes, destination = '/app/?flow=panel') {
  const form = document.querySelector('form');
  if (form) form.hidden = true;
  const panel = document.createElement('section');
  panel.setAttribute('aria-labelledby', 'recovery-codes-title');
  panel.innerHTML = `
    <h2 id="recovery-codes-title">Kurtarma kodlarınızı saklayın</h2>
    <p>Bu kodlar yalnızca şimdi gösterilir. Her kod tek kullanımlıktır.</p>
    <pre id="recovery-code-list" class="simple-field" style="white-space:pre-wrap;user-select:all"></pre>
    <button type="button" class="btn btn-primary w-full" id="download-recovery-codes">Kodları İndir</button>
    <a class="btn w-full" id="continue-after-codes" href="${destination}">Kodları Kaydettim, Devam Et</a>`;
  panel.querySelector('#recovery-code-list').textContent = codes.join('\n');
  panel.querySelector('#download-recovery-codes').addEventListener('click', () => {
    const blob = new Blob([`Serenut OS kurtarma kodları\n\n${codes.join('\n')}\n`], { type: 'text/plain;charset=utf-8' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'serenut-kurtarma-kodlari.txt';
    link.click();
    URL.revokeObjectURL(link.href);
  });
  status.after(panel);
  message('Hesabınız oluşturuldu. Devam etmeden önce kurtarma kodlarını kaydedin.', true);
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
      const resend = document.createElement('button');
      resend.type = 'button';
      resend.className = 'ghost-link';
      resend.textContent = 'Doğrulama bağlantısını yeniden gönder';
      resend.addEventListener('click', () => resendVerification(resend));
      status.append(' ', resend);
    }
  } finally {
    button.disabled = false;
  }
});

async function resendVerification(button) {
  button.disabled = true;
  try {
    const data = await post('resend-verification', { email: document.getElementById('email').value.trim() });
    button.textContent = data.message || 'Bağlantı gönderildi';
  } catch (error) {
    button.textContent = error.message;
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

    if (data.access_token) {
      setAuthToken(data.access_token);
      setRefreshToken(data.refresh_token);
      if (data.user) setUserProfile(data.user);
      if (Array.isArray(data.recovery_codes) && data.recovery_codes.length) {
        showRecoveryCodes(data.recovery_codes);
        return;
      }
      window.location.replace('/app/?flow=panel');
      return;
    }

    if (Array.isArray(data.recovery_codes) && data.recovery_codes.length) {
      showRecoveryCodes(data.recovery_codes, '/login');
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
  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('recovery/authorize-code', {
      identifier: document.getElementById('identifier').value.trim(),
      company_name: document.getElementById('company-name').value.trim(),
      tax_number: document.getElementById('tax-number').value.replace(/\D/g, ''),
      recovery_code: document.getElementById('recovery-code').value.trim()
    });
    sessionStorage.setItem('serenut_password_reset_token', data.reset_token);
    window.location.replace('/reset-password');
  } catch (error) {
    message(error.message);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('recovery-claim-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
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
    message(error.message);
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
