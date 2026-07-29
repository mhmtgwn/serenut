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
      password: document.getElementById('password').value,
      accept_terms: document.getElementById('accept-terms').checked,
      accept_privacy: document.getElementById('accept-privacy').checked,
      accept_kvkk: document.getElementById('accept-kvkk').checked,
      accept_marketing: document.getElementById('accept-marketing').checked
    });

    if (data.access_token) {
      setAuthToken(data.access_token);
      setRefreshToken(data.refresh_token);
      if (data.user) setUserProfile(data.user);
      window.location.replace('/app/?flow=panel');
      return;
    }

    message(data.message || 'Hesabınız oluşturuldu. E-postanızı doğruladıktan sonra giriş yapabilirsiniz.', true);
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
    const data = await post('forgot-password', { email: document.getElementById('email').value.trim() });
    message(data.message || 'Şifre sıfırlama bağlantısı gönderildi.', true);
  } catch (error) {
    message(error.message);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('reset-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const token = new URLSearchParams(window.location.search).get('token');
  const password = document.getElementById('password').value;
  if (!token) return message('Şifre sıfırlama bağlantısı geçersiz.');
  if (password !== document.getElementById('password-confirm').value) return message('Şifreler eşleşmiyor.');

  const button = event.submitter;
  button.disabled = true;
  try {
    const data = await post('reset-password', { token, newPassword: password });
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
if (params.get('verified') === '1') message('E-posta adresiniz doğrulandı. Giriş yapabilirsiniz.', true);
if (params.get('error') === 'portal_access_denied') message('Bu hesabın web yönetim paneline erişim yetkisi yok.');
if (params.get('error') === 'session_expired') message('Oturumunuz sona erdi. Lütfen yeniden giriş yapın.');
