# 20 — Kodlama Öncesi Hazırlık ve İdari/Hukuki İşler Matrisi

> Bu belge, tek bir satır kod yazılmadan veya sunucu açılmadan önce tamamlanması, başvurulması, onaylatılması ve toplanması gereken tüm idari, mali, operasyonel ve hukuki işleri doğrudan aksiyon maddeleri olarak tanımlar.
> **Kritik Yol (Critical Path):** Sanal POS (iyzico/PayTR), SMS Başlığı ve Vergi/Mevzuat onayları 1 ila 3 hafta sürebileceğinden hemen başlatılmalıdır.

---

## 1. FİNANSAL & ÖDEME SİSTEMLERİ BAŞVURU PAKETİ

### 1.1 iyzico (Birincil Sanal POS) Başvuru Listesi
- [ ] **Gerekli Evrakların Hazırlanması:**
  - Güncel Vergi Levhası fotokopisi.
  - İmza Sirküleri / İmza Beyannamesi (Şahıs firması ise beyanname, limited/A.Ş. ise sirküler).
  - Kimlik Fotokopisi (Firma sahibi/yetkilisi).
  - Banka Hesap Bilgileri (İşletme adına açılmış vadesiz TL IBAN cüzdanı/yazısı).
  - Ticaret Sicil Gazetesi (Tüzel kişiler için).
- [ ] **Web Sitesi Uyumluluk Kontrolü (iyzico denetçileri siteye bakar):**
  - Alan adında SSL aktif olmalı (Test ortamında bile geçici sayfa).
  - Sitede açıkça görünen `Hakkımızda`, `İletişim` (Adres, Sabit/Mobil Tel, E-posta) bulunmalı.
  - Sepet ve ödeme adımında `Mesafeli Satış Sözleşmesi`, `Ön Bilgilendirme Formu`, `İptal ve İade Koşulları`, `Gizlilik Politikası` linkleri aktif olmalı.
  - Para birimi (TL) ve ürün fiyatları açıkça yer almalı.
  - Visa / Mastercard / Troy logoları alt bilgiye eklenmeli.
- [ ] **Başvuru Aşaması:**
  - `iyzico.com/isin-icin/kurumsal-hesap` üzerinden başvuru formunun doldurulması.
  - API Anahtarları: Test ortamı (`Sandbox API Key` ve `Secret Key`) derhal alınmalı, canlı anahtarlar evrak onayına bırakılmalı.

### 1.2 PayTR (Yedek Sanal POS & Alternatif)
- [ ] PayTR Başvurusu (iFrame API entegrasyonu için yedek hesap açılışı):
  - iyzico ile paralel başvuru yapılması önerilir (Komisyon oranı ve bloke gün süresi karşılaştırması için).

### 1.3 Banka Hesapları ve Havale/EFT Yönetimi
- [ ] Havale/EFT siparişleri için kurumsal banka hesabı:
  - Banka Adı: (Örn: Ziraat Bankası / İş Bankası)
  - Şube ve Hesap No
  - IBAN: `TRXX ....`
  - Alıcı Unvanı: `Nutopia Fındık Değirmeni - Mehmet Güven`
- [ ] Havale takip prosedürü: Her sabah 09:00 ve akşam 17:00'de mobil bankacılıktan gelen ödemelerin sipariş numaraları (`NT-XXXXXX`) ile eşleştirilip onaylanması kuralı.

---

## 2. HABERLEŞME & BİLDİRİM (SMS BAŞLIĞI)

### 2.1 Alfanümerik Başlıklı SMS Paketi (Netgsm / İleti Merkezi / Mutlucell)
- [ ] **Sağlayıcı Seçimi:** Netgsm veya İleti Merkezi kurumsal abonelik başvurusu.
- [ ] **SMS Başlık (Originator) Onayı:**
  - İstenen Başlık: `NUTOPIA` (Maksimum 11 karakter).
  - Gerekli Evraklar:
    - Marka Tescil Belgesi (Varsa) VEYA Vergi Levhası (Firma unvanı veya tescilli işletme adı ile başlık ilişkisini kanıtlayan belge).
    - Başlık Talep Dilekçesi (Operatörün matbu kaşeli/imzalı formu).
    - Yetkili Kimlik Fotokopisi.
- [ ] **OTP / İşlemsel SMS Yetkisi:**
  - Şifre/Doğrulama SMS'lerinin İYS (İleti Yönetim Sistemi) onayından muaf olması için "Doğrulama/İşlemsel SMS" yetkisinin tanımlatılması.
- [ ] **Kredi / Kontör Satın Alımı:**
  - İlk etapta test ve lansman için 5.000 veya 10.000 SMS paketi alımı.
- [ ] **API Erişim Bilgileri:**
  - `UserCode`, `Password`, `Header (NUTOPIA)` bilgilerinin güvenli kasaya (Bitwarden/1Password) işlenmesi.

### 2.2 İşlemsel E-Posta Gönderim Altyapısı
- [ ] Gönderici Alan Adı: `mail.nutopiano.com` veya `nutopiano.com`
- [ ] Kurumsal E-Posta Kutuları (Google Workspace / Zoho / Yandex 360):
  - `destek@nutopiano.com` (Müşteri hizmetleri ve iletişim formu)
  - `siparis@nutopiano.com` (Sipariş bildirimleri)
  - `muhasebe@nutopiano.com` (Fatura ve resmi yazışmalar)
  - `kvkk@nutopiano.com` (Veri koruma başvuruları)
- [ ] Gönderim Servisi (SMTP / API): Brevo (Sendinblue) veya Mailgun / AWS SES hesabı:
  - DNS Kayıtları (DNS geçişi öncesi hazır edilecek):
    - `SPF`: `v=spf1 include:... ~all`
    - `DKIM`: TXT kaydı
    - `DMARC`: `v=DMARC1; p=quarantine; pct=100; rua=mailto:destek@nutopiano.com`

---

## 3. LOJİSTİK & KARGO ANLAŞMALARI

### 3.1 Ürün Gönderimi İçin Kargo Anlaşması
- [ ] **Firma Seçimi & Şube Görüşmesi:**
  - Kdz. Ereğli'deki yerel Yurtiçi Kargo, Aras Kargo veya MNG Kargo şubesi ile kurumsal e-ticaret sözleşmesi görüşmesi.
- [ ] **Fiyat ve Desi Matrisi:**
  - 1-2 Desi (Tekli/ikili kavanoz): Anlaşma fiyatı.
  - 3-5 Desi (Çoklu paketler): Anlaşma fiyatı.
  - 5+ Desi (Kabuklu çuvallar): Anlaşma fiyatı.
- [ ] **Kapıda Ödeme Servisi Eki:**
  - Kapıda Nakit Tahsilat ve Kapıda Kredi Kartı Tahsilat anlaşması.
  - Tahsil edilen paranın işletme hesabına aktarım günü (Haftalık Cuma vb.) ve kargo komisyonu (%1-2 + hizmet bedeli) netleştirilmesi.
- [ ] **Kargo Entegrasyon Şifreleri:**
  - API Kullanıcı Adı, Şifre, Müşteri Numarası.
  - İlk etapta manuel takip kodu girilecek olsa bile kurumsal cari kod tanımlanmalı.

### 3.2 Ambalaj & Paketleme Malzemeleri Temini
- [ ] 300g ve 700g kavanozlar için özel **şişme hava kanallı (airbag) koruyucu ambalaj** temini (Cam kavanoz kırılmasını sıfıra indirir).
- [ ] Özel baskılı veya kraft kargo kutuları.
- [ ] "Kırılabilir / Dikkat Gıda Ürünü" uyarı etiketleri.
- [ ] Güvenlik emniyet bandı (Kavanoz kapağının ilk kez alıcı tarafından açıldığını gösteren güvenlik hologramı/etiketi).

---

## 4. MALİ & MEVZUAT HAZIRLIKLARI (MALİ MÜŞAVİR İLE)

### 4.1 Vergi ve KDV Oranlarının Netleştirilmesi
- [ ] **Gıda Satışı KDV Oranı:**
  - Paketli fındık, fındık ezmesi ve kakaolu kremalarda toptan/perakende KDV oranı (Mevcut mevzuatta temel gıda ürünlerinde %1 mi, şeker ilaveli mamullerde %10 mu? Mali müşavir yazılı teyidi alınmalı).
- [ ] **Değirmen Hizmeti KDV Oranı:**
  - Fındık kırma, kavurma ve ezme hizmetinde uygulanacak KDV oranı (%10 veya %20).
- [ ] **Çiftçiden Alınan Fındık İçin Belge Düzeni:**
  - Çiftçi vergi mükellefi değilse, değirmen hizmeti bedeli karşılığı hizmet faturası kesilmesi süreci.
  - Ayni ödeme (fındık karşılığı işleme) yapılırsa gider pusulası / stopaj doğup doğmadığı.

### 4.2 e-Arşiv / e-Fatura Altyapısı
- [ ] GİB e-Arşiv Portal üzerinden mi manuel kesilecek, yoksa bir entegratör (Paraşüt, BizimHesap vb.) mi kullanılacak kararı.
- [ ] E-ticaret siparişlerinde e-Arşiv faturanın müşterinin e-postasına gönderim şablonu.

### 4.3 Yasal Kayıtlar ve Bildirimler
- [ ] **ETBİS (Elektronik Ticaret Bilgi Sistemi) Kaydı:**
  - `etbis.eticaret.gov.tr` üzerinden e-Devlet ile giriş yapılarak `nutopiano.com` alan adının bildirilmesi (Zorunludur, harçsızdır).
  - Anlaşmalı kargo firması ve sanal POS firmasının sisteme beyan edilmesi.
- [ ] **İl Tarım ve Orman Müdürlüğü İşletme Kayıt Belgesi:**
  - Ormanlı'daki fındık işleme değirmeninin gıda işletme kayıt numarasının (`TR-67-K-XXXXXX`) güncel olduğunun doğrulanması.
  - Bu kayıt numarasının internet sitesinin künyesine eklenmesi.
- [ ] **İYS (İleti Yönetim Sistemi):**
  - Ticari elektronik ileti (pazarlama/kampanya SMS/e-posta) gönderilecekse İYS kaydı; yalnızca sipariş ve kargo SMS'i gönderilecekse muafiyet kuralları.

---

## 5. İÇERİK & GÖRSEL STÜDYO ÇEKİM LİSTESİ

### 5.1 Profesyonel Fotoğraf Çekim Listesi (Beyaz Fon + Konsept)
- [ ] **Beyaz Fon E-Ticaret Ürün Çekimleri (1:1 Kare, Dekupeye Uygun):**
  - Sütlü Fındık Kreması (300g ve 700g cam kavanoz - önden etiketli, arkadan besin tablosu).
  - Kakaolu Fındık Kreması (300g ve 700g cam kavanoz).
  - %100 Fındık Ezmesi (320g ve 650g cam kavanoz - kapağı açık, doğal yağ tabakası ve kaşık dokusu görünür).
  - Fındık Krokan (Özel ambalajında ve bir tabağa dökülmüş çıtır parçalar).
  - Çifte Kavrulmuş Fındık (Vakumlu paket ve ahşap kasede fırınlanmış taneler).
  - Çiğ İç Fındık (Vakumlu paket).
  - Doğal Kabuklu Fındık (Geleneksel jüt kese/çuval içinde).
- [ ] **Tesis & Zanaat Çekimleri (Değirmen Güven Sayfaları İçin):**
  - Fındık kırma makinesinin çalışırken çekilmiş yüksek çözünürlüklü fotoğrafı.
  - Fırın kavurma tamburu ve altın sarısı kavrulmuş tanelerin dökülüş anı.
  - Zar soyma makinesinden çıkan bembeyaz iç fındıklar.
  - Taş değirmenin akışkan fındık ezmesini öğütme anı (Doğallık ve ipeksi doku kanıtı).
  - Ormanlı tesisinin dış cephesi, araç yanaşma ve çuval indirme sahası.
  - Usta Mehmet Güven'in fındık seçerken/kontrol ederken çekilmiş fotoğrafları.

---

## 6. SAHA OPERASYON & KURYE EKİPMANLARI

### 6.1 Kurye / Şoför Donanım Kontrolü
- [ ] **Kantar / Terazi Donanımı:**
  - Araçta taşınabilir, şarjlı, dijital asma kantar veya katlanabilir yer kantarı (Maksimum 300 kg kapasiteli, 50-100g hassasiyetli).
  - Terazinin Sanayi ve Teknoloji Bakanlığı / Belediye Ölçüler ve Ayar birimi mühür/damga kontrolü.
- [ ] **Mobil Cihaz & PWA Kurulumu:**
  - Şoförün kullanacağı Android/iOS akıllı telefon (İnternet paketi + GPS aktif).
  - Chrome / Safari üzerinden `admin.nutopiano.com/driver` adresinin ana ekrana simge olarak eklenmesi (PWA kurulumu).
- [ ] **Araç Donanımı:**
  - Çuvalların kaymasını ve yağmurdan ıslanmasını önleyici temiz branda.
  - Taşıma arabası / el arabası (Çuvalları bahçeden araca taşımak için).

