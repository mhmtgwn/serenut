# 19 — Ürün ve İçerik Ana Kataloğu

> Bu belge, mevcut `nutopiano_website/_eski` ve `data.js` kaynaklarındaki doğrulanmış ham verileri derler, Türk Gıda Kodeksi zorunluluklarına göre eksik/doğrulanması gereken noktaları işaretler ve veritabanı tohumlama (seed) ve canlı veri aktarımı için temel referansı oluşturur.

---

## 1. ÜRÜN VE VARYANT MASTER TABLOSU

| Ürün Adı | Slug | Kategori | Varyant (SKU) | Net Gram | Kargo Ağırlığı | Liste Fiyatı | Vergi Sınıfı | Durum |
|---|---|---|---|---|---|---|---|---|
| **Sütlü Fındık Kreması** | `sutlu-findik-kremasi` | `ezme` | `NUT-SUT-300` | 300 g | 520 g (Cam) | **165,00 ₺** | `food_default` | Aktif |
| | | | `NUT-SUT-700` | 700 g | 1.050 g (Cam) | **340,00 ₺** | `food_default` | Aktif |
| **Kakaolu Fındık Kreması**| `kakaolu-findik-kremasi`| `ezme` | `NUT-KAK-300` | 300 g | 520 g (Cam) | **165,00 ₺** | `food_default` | Aktif |
| | | | `NUT-KAK-700` | 700 g | 1.050 g (Cam) | **340,00 ₺** | `food_default` | Aktif |
| **%100 Fındık Ezmesi** | `100-findik-ezmesi` | `ezme` | `NUT-EZM-320` | 320 g | 540 g (Cam) | **195,00 ₺** | `food_default` | Aktif |
| | | | `NUT-EZM-650` | 650 g | 980 g (Cam) | **380,00 ₺** | `food_default` | Aktif |
| **Fındık Krokan** | `findik-krokan` | `kavurma` | `NUT-KRK-250` | 250 g | 270 g (Doypack)| **145,00 ₺** | `food_default` | Aktif |
| | | | `NUT-KRK-500` | 500 g | 530 g (Doypack)| **275,00 ₺** | `food_default` | Aktif |
| **Kavrulmuş Fındık** | `kavrulmus-findik` | `kavurma` | `NUT-KAV-500` | 500 g | 520 g (Vakum) | **275,00 ₺** | `food_default` | Aktif |
| | | | `NUT-KAV-1KG` | 1.000 g | 1.030 g (Vakum)| **520,00 ₺** | `food_default` | Aktif |
| **Çiğ İç Fındık** | `cig-ic-findik` | `ic` | `NUT-CIG-500` | 500 g | 520 g (Vakum) | **260,00 ₺** | `food_default` | Aktif |
| | | | `NUT-CIG-1KG` | 1.000 g | 1.030 g (Vakum)| **490,00 ₺** | `food_default` | Aktif |
| **Kabuklu Fındık** | `kabuklu-findik` | `ic` | `NUT-KBK-1KG` | 1.000 g | 1.050 g (Kese) | **220,00 ₺** | `food_default` | Aktif |
| | | | `NUT-KBK-5KG` | 5.000 g | 5.150 g (Çuval)| **980,00 ₺** | `food_default` | Aktif |

---

## 2. ETİKET BİLGİLERİ, BESİN DEĞERLERİ VE ALERJEN BEYANLARI

### 2.1 Sütlü Fındık Kreması
- **Tanım:** Doğal Karadeniz fındığının yoğun aroması ile yumuşacık sütlü kremanın buluşması.
- **İçindekiler:** Karadeniz Fındığı (%45), Süt Tozu, Şeker Pancarı Şekeri, Doğal Vanilya Aroması.
- **Alerjen Bilgisi:** **Fındık ve süt ürünü (laktoz) içerir.** Eser miktarda diğer sert kabuklu meyveleri içerebilir.
- **Besin Değerleri (100 g için yaklaşık):**
  - Enerji: `542 kcal`
  - Protein: `9,4 g`
  - Yağ: `34,2 g` (Doymuş Yağ: `6,1 g`)
  - Karbonhidrat: `52,1 g` (Şekerler: `48,0 g`)
  - Lif: `3,8 g`
  - Tuz: `0,15 g`
- **Raf Ömrü:** 12 Ay. Güneş görmeyen, kuru ve serin ortamda saklayınız.

### 2.2 Kakaolu Fındık Kreması
- **Tanım:** Hakiki kakao ve taze çekilmiş Karadeniz fındığı ile hazırlanan akışkan, yoğun gurme lezzet.
- **İçindekiler:** Karadeniz Fındığı (%45), Doğal Kakao Tozu, Şeker Pancarı Şekeri, Süt Tozu, Doğal Vanilya.
- **Alerjen Bilgisi:** **Fındık ve süt ürünü (laktoz) içerir.** Eser miktarda diğer sert kabuklu meyveleri içerebilir.
- **Besin Değerleri (100 g için yaklaşık):**
  - Enerji: `535 kcal`
  - Protein: `8,8 g`
  - Yağ: `33,6 g` (Doymuş Yağ: `6,5 g`)
  - Karbonhidrat: `53,4 g` (Şekerler: `46,2 g`)
  - Lif: `4,2 g`
  - Tuz: `0,12 g`
- **Raf Ömrü:** 12 Ay.

### 2.3 %100 Fındık Ezmesi (Şekersiz & Saf)
- **Tanım:** Yalnızca taş değirmenimizde çekilmiş seçme Karadeniz fındığı. İlave şeker, palm yağı, tuz veya koruyucu içermez.
- **İçindekiler:** %100 Kavrulmuş Karadeniz Fındığı.
- **Alerjen Bilgisi:** **Yalnızca fındık içerir.** Gluten ve süt ürünü içermez. Vegan beslenmeye %100 uygundur.
- **Besin Değerleri (100 g için yaklaşık):**
  - Enerji: `628 kcal`
  - Protein: `15,2 g`
  - Yağ: `60,8 g` (Doymuş Yağ: `4,5 g`)
  - Karbonhidrat: `16,7 g` (Doğal Şeker: `4,3 g`)
  - Lif: `9,7 g`
  - Tuz: `0,0 g`
- **Kullanım Notu:** Fındığın doğal yağı kavanoz yüzeyinde toplanabilir. Bu ürünün %100 katkısız olduğunun kanıtıdır; karıştırarak tüketiniz.
- **Raf Ömrü:** 12 Ay.

### 2.4 Fındık Krokan
- **İçindekiler:** Kavrulmuş Fındık (%60), Şeker Pancarı Şekeri.
- **Alerjen Bilgisi:** **Fındık içerir.**
- **Besin Değerleri (100 g):** Enerji: `512 kcal`, Protein: `9,6 g`, Yağ: `31,4 g`, Karbonhidrat: `54,2 g`.

### 2.5 Çifte Kavrulmuş Fındık (Vakumlu)
- **İçindekiler:** %100 Kavrulmuş ve Zarı Soyulmuş Karadeniz Fındığı.
- **Alerjen Bilgisi:** **Fındık içerir.**
- **Besin Değerleri (100 g):** Enerji: `646 kcal`, Protein: `15,0 g`, Yağ: `62,4 g`, Karbonhidrat: `17,6 g`.

---

## 3. DEĞİRMEN HİZMETLERİ VE BİRİM TARİFE LİSTESİ

| Hizmet Kodu | Hizmet Tanımı | Fiyat Esası | Birim Fiyat | Açıklama |
|---|---|---|---|---|
| `kirma` | Yalnızca Kırma | Girdi Kabuklu kg | **40,00 ₺/kg** | Kabuklu fındığı kırma makinesinde sağlam iç fındığa ayırır. |
| `kavurma` | Yalnızca Kavurma | Girdi İç/Kabuklu kg | **70,00 ₺/kg** | Homojen fırın kavurma ve zar soyma işlemi. |
| `kirma-kavurma` | Kırma + Kavurma | Girdi Kabuklu kg | **65,00 ₺/kg** | Kırma ve fırın kavurma birleşik avantaj paketi. |
| `kk-1kg` | Kırma + Kavurma + 1 kg Vakum | Girdi Kabuklu kg | **70,00 ₺/kg** | En çok tercih edilen; hava almaz 1 kg'lık vakum paketleme. |
| `kk-500` | Kırma + Kavurma + 500 g Vakum | Girdi Kabuklu kg | **80,00 ₺/kg** | 500 gramlık porsiyonluk taze vakumlu paketler. |
| `kk-250` | Kırma + Kavurma + 250 g Vakum | Girdi Kabuklu kg | **90,00 ₺/kg** | 250 gramlık küçük hediyelik ve pratik paketler. |
| `ezme` | Kavurma + Taş Değirmende Ezme | Girdi Kabuklu/İç kg | **130,00 ₺/kg** | Soğuk taş değirmende saf, ipeksi kavanozluk fındık ezmesi. |

---

## 4. GIDA MEVZUATI DOĞRULAMA KONTROL LİSTESİ (AŞAMA 0 İÇİN)
- [ ] Besin değerleri tablosundaki kalori, protein ve yağ oranlarının akredite gıda laboratuvarı analiz raporu ile doğrulanması.
- [ ] Türk Gıda Kodeksi Kakaolu ve Fındıklı Ezmeler Tebliği uyarınca ürün etiketlerindeki fındık oranı beyanının (%45 ve %100) teyidi.
- [ ] İl Tarım ve Orman Müdürlüğü İşletme Kayıt Numarası'nın (`TR-67-K-XXXXXX`) etiket ve web künyesine işlenmesi.
- [ ] Ambalaj partilerinde parti/lot numarası (`L26-XXXX`) ve tavsiye edilen tüketim tarihi (TETT) formatı.

