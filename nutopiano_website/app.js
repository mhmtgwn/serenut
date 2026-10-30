/* app.js — Nutopia: ortak bileşenler, ürünler, sepet, hesaplayıcı, form */
(function () {
  'use strict';
  const D = window.NUTO;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const tl = (n) => '₺' + n.toLocaleString('tr-TR', { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 });
  const wa = (text) => 'https://wa.me/' + D.phone + '?text=' + encodeURIComponent(text);
  const page = document.body.dataset.page || '';

  /* ---------- Toast ---------- */
  let toastTimer;
  function toast(msg) {
    let t = $('.toast');
    if (!t) { t = document.createElement('div'); t.className = 'toast'; t.setAttribute('role', 'status'); document.body.appendChild(t); }
    t.textContent = msg; t.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
  }

  /* ---------- Header / Footer ---------- */
  const links = [['/', 'Ana Sayfa', 'home'], ['/degirmen', 'Değirmen Hizmetleri', 'degirmen'], ['/urunler', 'Nutopiano Ürünler', 'urunler'], ['/hakkimizda', 'Hakkımızda', 'hakkimizda'], ['/iletisim', 'İletişim', 'iletisim']];
  function mountLayout() {
    const h = $('#site-header');
    if (h) h.innerHTML = `
      <a class="skip" href="#main">İçeriğe geç</a>
      <div class="topbar"><div class="container">
        <span>🚚 ${tl(D.freeShipping)} üzeri siparişlerde kargo bedava · 🎖️ Şehit ailelerine ve gazilere %${D.gaziPct} indirim</span>
        <a href="tel:0${D.phone.slice(2)}">📞 ${esc(D.phoneDisplay)}</a>
      </div></div>
      <header class="site-header"><div class="container header-inner">
        <a class="brand" href="/" aria-label="Nutopia Fındık Değirmeni ana sayfa"><img src="/images/nutopia-logo.png" alt="" width="46" height="46"><div><b>Nutopia</b><span>Fındık Değirmeni</span></div></a>
        <nav class="nav" id="nav" aria-label="Ana menü">${links.map(([u, n, k]) => `<a href="${u}"${k === page ? ' aria-current="page"' : ''}>${n}</a>`).join('')}</nav>
        <div class="header-actions">
          <button class="icon-btn" id="openCart" type="button" aria-label="Sepeti aç">🛒 Sepet<span class="count" id="cartCount">0</span></button>
          <button class="icon-btn menu-btn" id="menuBtn" type="button" aria-label="Menü" aria-expanded="false" aria-controls="nav">☰</button>
        </div>
      </div></header>`;
    const f = $('#site-footer');
    if (f) f.innerHTML = `
      <footer class="site-footer"><div class="container">
        <div class="footer-grid">
          <div><h4>Nutopia Fındık Değirmeni</h4><p>Fındığınızı işleriz, Nutopiano ile sofranıza taşırız.<br>${esc(D.address)}</p></div>
          <div><h4>Sayfalar</h4><ul>${links.map(([u, n]) => `<li><a href="${u}">${n}</a></li>`).join('')}</ul></div>
          <div><h4>İletişim</h4><ul>
            <li><a href="tel:0${D.phone.slice(2)}">📞 ${esc(D.phoneDisplay)}</a></li>
            <li><a href="${wa('Merhaba, bilgi almak istiyorum.')}" target="_blank" rel="noopener">💬 WhatsApp</a></li>
            <li><a href="https://maps.google.com/?q=${encodeURIComponent('Hatipoğulları Alanı Ormanlı Kdz. Ereğli Zonguldak')}" target="_blank" rel="noopener">📍 Yol tarifi</a></li>
          </ul></div>
        </div>
        <p class="copy">© ${new Date().getFullYear()} Nutopia Fındık Değirmeni · Nutopiano</p>
      </div></footer>
      <a class="wa-float" href="${wa('Merhaba, bilgi almak istiyorum.')}" target="_blank" rel="noopener" aria-label="WhatsApp ile yazın">💬 WhatsApp</a>`;
    const mb = $('#menuBtn');
    if (mb) mb.addEventListener('click', () => { const o = $('#nav').classList.toggle('open'); mb.setAttribute('aria-expanded', o); });
  }

  /* ---------- Sepet durumu ---------- */
  const LS = 'nutopia_cart_v2';
  let cart = [];
  try { const raw = JSON.parse(localStorage.getItem(LS)); if (Array.isArray(raw)) cart = raw.filter((i) => D.products.some((p) => p.id === i.id) && Number.isInteger(i.qty) && i.qty > 0); } catch (e) { /* boş sepet */ }
  const save = () => { try { localStorage.setItem(LS, JSON.stringify(cart)); } catch (e) { /* özel mod */ } };
  let coupon = null, pay = 'havale', gazi = false;
  const prod = (id) => D.products.find((p) => p.id === id);
  const lines = () => cart.map((i) => { const p = prod(i.id); const v = p.variants[i.v] || p.variants[0]; return { p, v, qty: i.qty, key: i.id + ':' + i.v }; });

  function totals() {
    const sub = lines().reduce((s, l) => s + l.v.price * l.qty, 0);
    const cDisc = coupon ? Math.round(sub * coupon.pct) / 100 : 0;
    const after = sub - cDisc;
    const hDisc = pay === 'havale' ? Math.round(after * D.havalePct) / 100 : 0;
    return { sub, cDisc, after, hDisc, total: after - hDisc, free: after >= D.freeShipping };
  }
  function add(id, v) {
    const f = cart.find((i) => i.id === id && i.v === v);
    if (f) f.qty = Math.min(f.qty + 1, 99); else cart.push({ id, v, qty: 1 });
    save(); renderCart(); toast('Sepete eklendi');
  }
  function change(key, d) {
    const [id, v] = key.split(':'); const it = cart.find((i) => i.id === id && i.v === +v); if (!it) return;
    it.qty += d; if (it.qty <= 0) cart = cart.filter((i) => i !== it); save(); renderCart();
  }

  /* ---------- Sepet çekmecesi ---------- */
  function mountCart() {
    const ov = document.createElement('div'); ov.className = 'overlay'; ov.id = 'ov';
    const dr = document.createElement('aside'); dr.className = 'drawer'; dr.id = 'drawer'; dr.setAttribute('aria-label', 'Sepet'); dr.setAttribute('aria-hidden', 'true');
    dr.innerHTML = `
      <header><h3>Sepetiniz</h3><button class="x" type="button" id="closeCart" aria-label="Kapat">&times;</button></header>
      <div class="body" id="cartBody"></div>
      <footer id="cartFoot"></footer>`;
    document.body.append(ov, dr);
    const open = () => { dr.classList.add('open'); ov.classList.add('show'); dr.setAttribute('aria-hidden', 'false'); };
    const close = () => { dr.classList.remove('open'); ov.classList.remove('show'); dr.setAttribute('aria-hidden', 'true'); };
    $('#openCart').addEventListener('click', open); $('#closeCart').addEventListener('click', close); ov.addEventListener('click', close);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
    dr.addEventListener('click', (e) => {
      const b = e.target.closest('[data-q]'); if (b) change(b.dataset.key, +b.dataset.q);
      if (e.target.id === 'applyCoupon') applyCoupon();
      if (e.target.id === 'sendOrder') sendOrder();
    });
    dr.addEventListener('change', (e) => {
      if (e.target.name === 'pay') { pay = e.target.value; renderSummary(); }
      if (e.target.id === 'gazi') { gazi = e.target.checked; renderSummary(); }
    });
    window.NutoCart = { open };
    renderCart();
  }

  function renderCart() {
    const body = $('#cartBody'), foot = $('#cartFoot'); if (!body) return;
    $('#cartCount').textContent = cart.reduce((s, i) => s + i.qty, 0);
    const keep = {}; ['oName', 'oPhone', 'oAddr'].forEach((id) => { const e = $('#' + id); if (e) keep[id] = e.value; });
    const ls = lines();
    if (!ls.length) {
      body.innerHTML = '<div class="empty">Sepetiniz boş.<br><a href="/urunler">Ürünlere göz atın →</a></div>'; foot.innerHTML = ''; return;
    }
    body.innerHTML = ls.map((l) => `
      <div class="item"><img src="${esc(l.p.img)}" alt="" loading="lazy">
        <div><b>${esc(l.p.name)}</b><small>${esc(l.v.label)} · ${tl(l.v.price)}</small>
          <div class="qty"><button type="button" data-q="-1" data-key="${esc(l.key)}" aria-label="Azalt">−</button><span>${l.qty}</span><button type="button" data-q="1" data-key="${esc(l.key)}" aria-label="Artır">+</button></div></div>
        <b>${tl(l.v.price * l.qty)}</b></div>`).join('');
    foot.innerHTML = `
      <div class="small" id="shipTxt"></div><div class="progress"><i id="shipBar"></i></div>
      <div class="field" style="margin-top:10px"><div class="coupon"><input type="text" id="couponIn" placeholder="İndirim kodu" autocomplete="off" aria-label="İndirim kodu" value="${coupon ? esc(coupon.code) : ''}"><button class="btn btn-ghost" type="button" id="applyCoupon">Uygula</button></div><div class="msg" id="couponMsg">${coupon ? esc(coupon.label) + ' uygulandı' : ''}</div></div>
      <div class="field"><label for="oName">Ad Soyad *</label><input type="text" id="oName" autocomplete="name"></div>
      <div class="field"><label for="oPhone">Telefon *</label><input type="tel" id="oPhone" autocomplete="tel" placeholder="05XX XXX XX XX"></div>
      <div class="field"><label for="oAddr">Teslimat adresi *</label><textarea id="oAddr" autocomplete="street-address"></textarea></div>
      <div class="field"><label>Ödeme şekli</label><div class="pay">
        <label><input type="radio" name="pay" value="havale"${pay === 'havale' ? ' checked' : ''}>Havale / EFT <b>(%${D.havalePct} indirim)</b></label>
        <label><input type="radio" name="pay" value="kapida"${pay === 'kapida' ? ' checked' : ''}>Kapıda ödeme</label></div>
        <div class="small muted" style="margin-top:6px">Havale seçerseniz IBAN bilgisi sipariş onayında WhatsApp'tan iletilir.</div></div>
      <div class="field"><label class="check"><input type="checkbox" id="gazi"${gazi ? ' checked' : ''}> Şehit yakını / gaziyim (%${D.gaziPct} indirim; belge doğrulaması sonrası uygulanır)</label></div>
      <div class="sum" id="sum"></div>
      <div class="msg err" id="orderErr" role="alert"></div>
      <button class="btn btn-wa btn-block" type="button" id="sendOrder">WhatsApp ile siparişi gönder</button>`;
    Object.keys(keep).forEach((id) => { $('#' + id).value = keep[id]; });
    renderSummary();
  }

  function renderSummary() {
    const s = $('#sum'); if (!s) return; const t = totals();
    s.innerHTML = `<div class="row"><span>Ara toplam</span><span>${tl(t.sub)}</span></div>
      ${t.cDisc ? `<div class="row"><span>${esc(coupon.label)}</span><span>−${tl(t.cDisc)}</span></div>` : ''}
      ${t.hDisc ? `<div class="row"><span>Havale indirimi</span><span>−${tl(t.hDisc)}</span></div>` : ''}
      <div class="row"><span>Kargo</span><span>${t.free ? 'Ücretsiz' : 'Onayda bildirilir'}</span></div>
      <div class="row grand"><span>Toplam</span><span>${tl(t.total)}</span></div>
      ${gazi ? `<div class="small muted">Gazi/şehit yakını indirimi doğrulama sonrası ayrıca düşülür.</div>` : ''}`;
    const left = D.freeShipping - t.after;
    $('#shipTxt').textContent = left > 0 ? `Kargo bedava için ${tl(Math.ceil(left))} daha ekleyin` : '🎉 Kargo bedava!';
    $('#shipBar').style.width = Math.min(100, (t.after / D.freeShipping) * 100) + '%';
  }

  function applyCoupon() {
    const code = $('#couponIn').value.trim().toUpperCase(), m = $('#couponMsg');
    if (!code) { coupon = null; m.textContent = ''; renderSummary(); return; }
    const c = D.coupons[code];
    if (!c) { coupon = null; m.className = 'msg err'; m.textContent = 'Geçersiz kod.'; renderSummary(); return; }
    coupon = { code, ...c }; m.className = 'msg ok'; m.textContent = c.label + ' uygulandı'; renderSummary();
  }

  function sendOrder() {
    const name = $('#oName').value.trim(), phone = $('#oPhone').value.trim(), addr = $('#oAddr').value.trim(), err = $('#orderErr');
    if (name.length < 3 || phone.replace(/\D/g, '').length < 10 || addr.length < 10) { err.textContent = 'Lütfen ad, telefon ve adres bilgilerini eksiksiz girin.'; return; }
    err.textContent = '';
    const t = totals();
    const txt = ['*Yeni sipariş — Nutopiano*', '',
      ...lines().map((l) => `• ${l.qty} × ${l.p.name} (${l.v.label}) — ${tl(l.v.price * l.qty)}`), '',
      `Ara toplam: ${tl(t.sub)}`,
      t.cDisc ? `Kupon (${coupon.code}): −${tl(t.cDisc)}` : null,
      t.hDisc ? `Havale indirimi: −${tl(t.hDisc)}` : null,
      `Kargo: ${t.free ? 'Ücretsiz' : 'Hesaplanacak'}`,
      `*Toplam: ${tl(t.total)}*`,
      `Ödeme: ${pay === 'havale' ? 'Havale / EFT' : 'Kapıda ödeme'}`,
      gazi ? `Şehit yakını / gazi indirimi talebi var (%${D.gaziPct}) — belge doğrulanacak.` : null, '',
      `Ad Soyad: ${name}`, `Telefon: ${phone}`, `Adres: ${addr}`].filter((x) => x !== null).join('\n');
    window.open(wa(txt), '_blank', 'noopener');
  }

  /* ---------- Ürünler ---------- */
  function productCard(p) {
    const el = document.createElement('article'); el.className = 'card product'; el.dataset.cat = p.cat; el.dataset.id = p.id;
    el.dataset.search = (p.name + ' ' + p.desc + ' ' + p.tag).toLocaleLowerCase('tr');
    el.innerHTML = `
      <button class="pimg" type="button" data-detail="${esc(p.id)}" aria-label="${esc(p.name)} detayları"><img src="${esc(p.img)}" alt="${esc(p.name)}" loading="lazy" width="300" height="300"></button>
      <div class="card-body" style="display:flex;flex-direction:column;flex:1">
        <span class="tag">${esc(p.tag)}</span><h3>${esc(p.name)}</h3><p class="desc">${esc(p.desc)}</p>
        <div class="variants" role="group" aria-label="Boyut">${p.variants.map((v, i) => `<button type="button" class="variant${i === 0 ? ' active' : ''}" data-v="${i}">${esc(v.label)}</button>`).join('')}</div>
        <div class="prow"><span class="price">${tl(p.variants[0].price)}</span><button class="btn btn-gold" type="button" data-add>Sepete ekle</button></div>
        <button class="linkbtn" type="button" data-detail="${esc(p.id)}">İçindekiler ve besin değerleri</button>
      </div>`;
    return el;
  }
  function mountProducts() {
    const grid = $('#productGrid'); if (!grid) return;
    D.products.forEach((p) => grid.appendChild(productCard(p)));
    const fl = $('#filters');
    fl.innerHTML = `<button class="chip active" type="button" data-cat="all">Tümü (${D.products.length})</button>` + D.categories.map((c) => `<button class="chip" type="button" data-cat="${c.id}">${esc(c.name)}</button>`).join('');
    let cat = 'all', q = '';
    const apply = () => {
      let n = 0;
      $$('.product', grid).forEach((c) => { const ok = (cat === 'all' || c.dataset.cat === cat) && c.dataset.search.includes(q); c.hidden = !ok; if (ok) n++; });
      $('#noResult').hidden = n > 0;
    };
    fl.addEventListener('click', (e) => { const b = e.target.closest('.chip'); if (!b) return; cat = b.dataset.cat; $$('.chip', fl).forEach((x) => x.classList.toggle('active', x === b)); apply(); });
    $('#productSearch').addEventListener('input', (e) => { q = e.target.value.trim().toLocaleLowerCase('tr'); apply(); });
    grid.addEventListener('click', (e) => {
      const card = e.target.closest('.product'); if (!card) return; const p = prod(card.dataset.id);
      const vb = e.target.closest('.variant');
      if (vb) { $$('.variant', card).forEach((x) => x.classList.toggle('active', x === vb)); $('.price', card).textContent = tl(p.variants[+vb.dataset.v].price); }
      if (e.target.closest('[data-add]')) add(p.id, +($('.variant.active', card).dataset.v));
      if (e.target.closest('[data-detail]')) openDetail(p);
    });
  }
  function openDetail(p) {
    let dlg = $('#detail');
    if (!dlg) { dlg = document.createElement('dialog'); dlg.id = 'detail'; document.body.appendChild(dlg); dlg.addEventListener('click', (e) => { if (e.target === dlg || e.target.closest('[data-close]')) dlg.close(); }); }
    const n = p.nutrition;
    dlg.innerHTML = `<div class="dlg"><header><div><span class="eyebrow">${esc(p.tag)}</span><h3>${esc(p.name)}</h3></div><button class="x" type="button" data-close aria-label="Kapat">&times;</button></header>
      <p>${esc(p.desc)}</p>
      <div class="nutri"><div><b>${n.kcal}</b><span>kcal</span></div><div><b>${n.protein} g</b><span>Protein</span></div><div><b>${n.fat} g</b><span>Yağ</span></div><div><b>${n.carb} g</b><span>Karbonhidrat</span></div></div>
      <p class="small muted">100 g için yaklaşık değerler.</p>
      <p style="margin-top:10px"><b>İçindekiler:</b> ${esc(p.ingredients)}</p>
      <p style="margin-top:6px"><b>Alerjen:</b> ${esc(p.allergen)}</p>
      <div class="btn-row" style="margin-top:16px"><button class="btn btn-gold" type="button" data-close>Kapat</button>
      <a class="btn btn-wa" target="_blank" rel="noopener" href="${wa(p.name + ' hakkında bilgi almak istiyorum.')}">WhatsApp'tan sor</a></div></div>`;
    dlg.showModal();
  }
  function mountHomeProducts() {
    const g = $('#homeProducts'); if (!g) return;
    D.products.slice(0, 4).forEach((p) => g.appendChild(productCard(p)));
    g.addEventListener('click', (e) => {
      const card = e.target.closest('.product'); if (!card) return; const p = prod(card.dataset.id);
      const vb = e.target.closest('.variant');
      if (vb) { $$('.variant', card).forEach((x) => x.classList.toggle('active', x === vb)); $('.price', card).textContent = tl(p.variants[+vb.dataset.v].price); }
      if (e.target.closest('[data-add]')) add(p.id, +($('.variant.active', card).dataset.v));
      if (e.target.closest('[data-detail]')) openDetail(p);
    });
  }

  /* ---------- Değirmen hesaplayıcı ---------- */
  function mountCalc() {
    const sel = $('#calcService'); if (!sel) return;
    sel.innerHTML = D.services.map((s) => `<option value="${s.id}">${esc(s.name)} — ${s.price} ₺/kg</option>`).join('');
    const kg = $('#calcKg'), g = $('#calcGazi'), out = $('#calcOut');
    const run = () => {
      const k = Math.max(0, parseFloat(String(kg.value).replace(',', '.')) || 0); const s = D.services.find((x) => x.id === sel.value);
      const list = k * s.price, disc = g.checked ? list * D.gaziPct / 100 : 0;
      out.innerHTML = `<div class="row"><span>Tahmini iç fındık / ezme</span><span>~${(k * D.yieldPct / 100).toLocaleString('tr-TR', { maximumFractionDigits: 1 })} kg</span></div>
        <div class="row"><span>${k.toLocaleString('tr-TR')} kg × ${s.price} ₺</span><span>${tl(list)}</span></div>
        ${disc ? `<div class="row"><span>Şehit/gazi indirimi (%${D.gaziPct})</span><span>−${tl(disc)}</span></div>` : ''}
        <div class="row total"><span>Tahmini ücret</span><span>${tl(list - disc)}</span></div>`;
      $('#calcWa').href = wa(`Merhaba, ${k} kg kabuklu fındık için "${s.name}" hizmetini almak istiyorum. Tahmini ücret: ${tl(list - disc)}. Randevu alabilir miyim?`);
    };
    [kg, sel, g].forEach((el) => el.addEventListener('input', run)); run();
  }

  /* ---------- İletişim formu ---------- */
  function mountContact() {
    const f = $('#contactForm'); if (!f) return;
    f.addEventListener('submit', (e) => {
      e.preventDefault();
      const v = (id) => $('#' + id).value.trim();
      const txt = ['*Yeni talep — nutopiano.com*', `Konu: ${v('cSubject')}`, `Ad Soyad: ${v('cName')}`, `Telefon: ${v('cPhone')}`,
        v('cAmount') ? `Tahmini miktar: ${v('cAmount')}` : null, v('cMsg') ? `Mesaj: ${v('cMsg')}` : null].filter(Boolean).join('\n');
      window.open(wa(txt), '_blank', 'noopener');
    });
  }

  /* ---------- Başlat ---------- */
  mountLayout(); mountCart(); mountProducts(); mountHomeProducts(); mountCalc(); mountContact();
})();
