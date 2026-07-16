document.addEventListener('DOMContentLoaded', () => {
  const toggle = document.getElementById('menu-toggle');
  const panel = document.getElementById('mobile-panel');
  const header = document.getElementById('site-header');

  toggle?.addEventListener('click', () => {
    panel?.classList.toggle('app-hidden');
    toggle.setAttribute('aria-expanded', String(!panel?.classList.contains('app-hidden')));
  });

  panel?.querySelectorAll('a').forEach((link) => {
    link.addEventListener('click', () => panel.classList.add('app-hidden'));
  });

  const syncHeader = () => {
    header?.classList.toggle('scrolled', window.scrollY > 12);
  };

  window.addEventListener('scroll', syncHeader, { passive: true });
  syncHeader();
});

document.getElementById('contact-form')?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector('button[type="submit"]');
  const status = document.getElementById('contact-status');
  button.disabled = true; button.textContent = 'Gönderiliyor…'; status.textContent = '';
  try {
    const response = await fetch('/api/v1/support/public-contact', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: document.getElementById('contact-name').value.trim(), email: document.getElementById('contact-email').value.trim(), phone: document.getElementById('contact-phone').value.trim(), subject: document.getElementById('contact-subject').value, message: document.getElementById('contact-message').value.trim() }) });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.message || 'Mesaj gönderilemedi.');
    status.className = 'form-status full success'; status.textContent = data.message || 'Mesajınız iletildi.'; form.reset();
  } catch (error) { status.className = 'form-status full error'; status.textContent = error.message; }
  finally { button.disabled = false; button.textContent = 'Mesajı Gönder'; }
});
