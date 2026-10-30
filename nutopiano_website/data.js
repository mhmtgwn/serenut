/* data.js — Tek veri kaynağı: ürünler, hizmetler, iletişim, kampanya kuralları */
window.NUTO = {
  phone: '905380288202',
  phoneDisplay: '0538 028 82 02',
  address: 'Hatipoğulları Alanı, Merkez, D:1 No:6/B, Ormanlı / Kdz. Ereğli / Zonguldak',
  freeShipping: 750,
  havalePct: 5,
  gaziPct: 20,
  coupons: {
    HOSGELDIN10: { pct: 10, label: '%10 Hoş geldin indirimi' }
  },
  categories: [
    { id: 'ezme', name: 'Ezme & Krema' },
    { id: 'kavurma', name: 'Kavrulmuş & Krokan' },
    { id: 'ic', name: 'İç & Kabuklu' }
  ],
  products: [
    {
      id: 'sutlu', cat: 'ezme', name: 'Sütlü Fındık Kreması', tag: 'Krema serisi',
      img: '/images/urun-sutlu.png',
      desc: 'Fındığın yoğun lezzeti, yumuşak sütlü krema dokusuyla. Kahvaltı ve tatlıların favorisi.',
      variants: [{ label: '300 g kavanoz', price: 165 }, { label: '700 g kavanoz', price: 340 }],
      nutrition: { kcal: 542, protein: 9.4, fat: 34.2, carb: 52.1 },
      ingredients: 'Karadeniz fındığı (%45), süt tozu, pancar şekeri, doğal vanilya aroması.',
      allergen: 'Fındık ve süt ürünü (laktoz) içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.'
    },
    {
      id: 'kakaolu', cat: 'ezme', name: 'Kakaolu Fındık Kreması', tag: 'Krema serisi',
      img: '/images/urun-kakaolu.png',
      desc: 'Fındık ve kaliteli kakaonun buluştuğu ipeksi, akışkan, yoğun krema.',
      variants: [{ label: '300 g kavanoz', price: 165 }, { label: '700 g kavanoz', price: 340 }],
      nutrition: { kcal: 535, protein: 8.8, fat: 33.6, carb: 53.4 },
      ingredients: 'Karadeniz fındığı (%45), kakao tozu, pancar şekeri, süt tozu, doğal vanilya.',
      allergen: 'Fındık ve süt ürünü (laktoz) içerir. Eser miktarda diğer sert kabuklu meyveler içerebilir.'
    },
    {
      id: 'ezme', cat: 'ezme', name: '%100 Fındık Ezmesi', tag: 'Şekersiz',
      img: '/images/urun-ezme.png',
      desc: 'Yalnızca taş değirmende çekilmiş fındık. İlave şeker, palm yağı, koruyucu yok. Üstte biriken doğal yağı karıştırarak tüketin.',
      variants: [{ label: '320 g kavanoz', price: 195 }, { label: '650 g kavanoz', price: 380 }],
      nutrition: { kcal: 628, protein: 15.2, fat: 60.8, carb: 16.7 },
      ingredients: '%100 kavrulmuş Karadeniz fındığı.',
      allergen: 'Yalnızca fındık içerir.'
    },
    {
      id: 'krokan', cat: 'kavurma', name: 'Fındık Krokan', tag: 'Geleneksel',
      img: '/images/urun-krokan.png',
      desc: 'Kavrulmuş fındığın çıtırlığı, karamelize tatla. Kahve yanına ve tatlı süslemeye.',
      variants: [{ label: '250 g paket', price: 145 }, { label: '500 g paket', price: 275 }],
      nutrition: { kcal: 512, protein: 9.6, fat: 31.4, carb: 54.2 },
      ingredients: 'Kavrulmuş fındık (%60), pancar şekeri.',
      allergen: 'Fındık içerir.'
    },
    {
      id: 'kavrulmus', cat: 'kavurma', name: 'Kavrulmuş Fındık', tag: 'Vakumlu',
      img: '/images/urun-kavrulmus.png',
      desc: 'Hassas ısıda kavrulmuş, zarı soyulmuş, hava almaz vakumlu pakette çıtır fındık.',
      variants: [{ label: '500 g vakum', price: 275 }, { label: '1 kg vakum', price: 520 }],
      nutrition: { kcal: 646, protein: 15.0, fat: 62.4, carb: 17.6 },
      ingredients: '%100 kavrulmuş, zarı soyulmuş Karadeniz fındığı.',
      allergen: 'Fındık içerir.'
    },
    {
      id: 'cig', cat: 'ic', name: 'Çiğ İç Fındık', tag: 'Doğal',
      img: '/images/findik-kase-doga.png',
      desc: 'Kavurma veya başka işlem görmemiş, seçilmiş iç fındık.',
      variants: [{ label: '500 g vakum', price: 260 }, { label: '1 kg vakum', price: 490 }],
      nutrition: { kcal: 628, protein: 15.0, fat: 60.8, carb: 16.7 },
      ingredients: '%100 çiğ iç Karadeniz fındığı.',
      allergen: 'Fındık içerir.'
    },
    {
      id: 'kabuklu', cat: 'ic', name: 'Kabuklu Fındık', tag: 'Geleneksel hasat',
      img: '/images/nutopia-onluk.png',
      desc: 'Kabuğu içinde, kurutulmuş ve elenmiş Karadeniz fındığı.',
      variants: [{ label: '1 kg', price: 220 }, { label: '5 kg', price: 980 }],
      nutrition: { kcal: 628, protein: 15.0, fat: 60.8, carb: 16.7 },
      ingredients: 'Kabuklu Karadeniz fındığı.',
      allergen: 'Fındık içerir.'
    }
  ],
  /* Değirmen hizmetleri: fiyat = kabuklu fındık kg başına */
  services: [
    { id: 'kirma', name: 'Yalnızca kırma', desc: 'Kabuklu fındığı iç fındığa ayırır', price: 40 },
    { id: 'kirma-kavurma', name: 'Kırma + kavurma', desc: 'Kırma ve homojen kavurma', price: 65 },
    { id: 'kk-1kg', name: 'Kırma + kavurma + 1 kg vakum', desc: 'En çok tercih edilen', price: 70 },
    { id: 'kk-500', name: 'Kırma + kavurma + 500 g vakum', desc: '500 g vakumlu paketler', price: 80 },
    { id: 'kk-250', name: 'Kırma + kavurma + 250 g vakum', desc: '250 g vakumlu paketler', price: 90 },
    { id: 'ezme', name: 'Kavurma + taş değirmende ezme', desc: 'Katkısız saf fındık ezmesi', price: 130 }
  ],
  priceList: [
    ['Kırma', '40 ₺/kg'], ['Kavurma', '70 ₺/kg'], ['Fındık ezmesi', '130 ₺/kg'],
    ['Paketleme (1 kg vakum)', '20 ₺/kg'], ['Kırma + kavurma', '65 ₺/kg'],
    ['Kırma + kavurma + 1 kg vakum', '70 ₺/kg'], ['Kırma + kavurma + 500 g vakum', '80 ₺/kg'],
    ['Kırma + kavurma + 250 g vakum', '90 ₺/kg']
  ],
  yieldPct: 50
};

