# 24 — Hata Kılavuzu, Teşhis ve Acil Durum Müdahale Rehberi (Troubleshooting & Runbook)

> Bu belge; canlı sistemde karşılaşılması muhtemel tüm operasyonel, sistemsel, donanımsal ve entegrasyon arızalarında (Webhook kayıpları, tartı itirazları, stok kilitlenmeleri, kargo aksamaları vb.) personelin ve sistem yöneticisinin atması gereken kesin adımları (Runbook) içerir.

---

## 1. ACİL DURUM VE MÜDAHALE SEVİYELERİ (SEVERITY MATRIX)

| Seviye | Tanım | Örnek Olay | Müdahale Süresi (SLA) | Bildirim Kanalı |
|---|---|---|---|---|
| **SEV-1 (Kritik)** | Sistemin tamamen durması, ödeme alınamaması veya veri kaybı riski | Web sitesi/API 500 veriyor, Veritabanı yanıt vermiyor, Kart ödemeleri kitlendi | **< 15 Dakika** | SMS + Telefon Araması |
| **SEV-2 (Yüksek)** | Temel bir operasyonel sürecin aksaması, iş kaybı | SMS OTP gitmiyor, Şoför PWA tartı kaydedemiyor, Kargo API yanıt vermiyor | **< 1 Saat** | SMS + Telegram/Slack |
| **SEV-3 (Orta)** | Tekil kullanıcı hatası, küçük tutarsızlık | Müşteri tartıya itiraz ediyor, Havale açıklaması yanlış girilmiş, Kupon çalışmıyor | **< 4 Saat** | Admin Bildirim Paneli |
| **SEV-4 (Düşük)** | Kozmetik veya raporlama hatası | Raporlama ekranında tarih filtresi kayması, Yazım hatası | **< 24 Saat** | E-Posta / Görev Listesi |

---

## 2. ÖDEME VE FİNANS KAYNAKLI SORUNLAR

### 2.1 Müşteriden Para Çekildi Ama Sipariş "pending_payment" Kaldı
- **Kök Neden:** Müşteri 3D Secure onayını yaptıktan sonra tarayıcıyı erken kapattı veya iyzico webhook çağrısı ağ kesintisi nedeniyle gecikti.
- **Teşhis Adımları:**
  1. Admin Panelinde sipariş no (`NT-XXXXXX`) ile arama yapın.
  2. `payments.payments` tablosundaki `conversation_id`'yi kopyalayın.
  3. iyzico Kurumsal Panelinde "İşlemler / Transaction" menüsünden bu `conversation_id` ile ödemeyi aratın.
- **Çözüm / Müdahale:**
  - *Durum A (iyzico'da ödeme BAŞARILI görünüyorsa):* Admin panelinde sipariş detayındaki `[Ödemeyi Sağlayıcıdan Yeniden Sorgula (Reconcile)]` butonuna tıklayın. Sistem iyzico API'sini çağırarak ödemeyi anında `captured`, siparişi `paid` yapar, stoğu kalıcı düşer ve müşteriye onay SMS'i iletir.
  - *Durum B (iyzico'da işlem yok veya BAŞARISIZ ise):* Müşterinin ekstresindeki provizyon otomatik düşecektir. Müşteriye SMS/telefon ile ödemenin bankasınca reddedildiği ve yeniden denemesi gerektiği bildirilir.

### 2.2 Müşteri Havale Gönderdi Ama Açıklama Kodunu Yazmadı
- **Kök Neden:** Müşteri banka transferinde `NT-XXXXXX` sipariş kodunu açıklama yerine boş bıraktı veya sadece kendi adını yazdı.
- **Çözüm / Müdahale:**
  1. Admin Paneli -> `Ödemeler / Eşleşmeyen Havaleler` sekmesine gidin.
  2. Banka ekstresindeki gönderici ad-soyadı ve tutarı (`₺...`) ile sistemde `awaiting_transfer` durumunda bekleyen siparişleri filtreleyin.
  3. Eşleşen siparişi açıp `[Manuel Havale Eşleştir]` butonuna tıklayın; banka dekont numarasını girip onaylayın.

---

## 3. DEĞİRMEN VE TARTI ANLAŞMAZLIKLARI

### 3.1 Çiftçi Saha Tartısına İtiraz Ediyor ("Benim Fındığım Daha Fazlaydı")
- **Kök Neden:** Çiftçinin evdeki eski yaylı el kantarı ile şoförün kalibreli dijital kantarı arasındaki ölçüm farkı veya çuval darasının yanlış algılanması.
- **Protokol Adımları:**
  1. Şoför asla müşteriyle tartışmaya girmez.
  2. PWA üzerinden kantar ekranında görünen brüt ağırlığın ve daranın fotoğrafını çeker.
  3. Çiftçiye şu teklif sunulur: *"İsterseniz çuvallarınızı birlikte değirmenimize getirelim; oradaki onaylı sabit sanayi kantarında birlikte tekrar tartalım."*
  4. Çiftçi kabul etmezse talep şoför tarafından `cancelled_by_customer` olarak işaretlenir ve araç bahçeden ayrılır (Alım yapılmaz).
  5. Çiftçi onay kodunu verip tartıyı imzaladıktan sonra sonradan itiraz ederse: Sistemdeki imzalı/kodlu dijital tutanak (`weighings` kaydı ve kantar fotoğrafı) referans gösterilir; resmi tutanak bağlayıcıdır.

### 3.2 İkinci Tartıda Fazla Kayıp Çıktı (Tesis Giriş Tartısı Anomalisı)
- **Kök Neden:** Taşıma sırasında çuvalın patlaması, aşırı nem buharlaşması veya tartı kalibrasyon kayması.
- **Protokol:**
  1. Fark %1'i aştığında sistem partiyi durdurur.
  2. Tesis kabul sorumlusu derhal aracı ve çuvalları fiziksel incelemeye alır (Dökülme/yırtık var mı?).
  3. Çuvallar tek tek tekrar tartılır.
  4. Hata şoförün sahadaki tartısından kaynaklanmışsa: Müşteri telefonla aranarak kamera/kantar kaydı eşliğinde durum nazikçe izah edilir ve tutanak düzeltme onayı (SMS ile) alınır.

---

## 4. LOJİSTİK VE KARGO SORUNLARI

### 4.1 Kargo Yolda Kırıldı / Hasar Gördü (Cam Kavanoz Patlaması)
- **Kök Neden:** Kargo transfer merkezinde kolinin darbe alması.
- **Protokol:**
  1. Müşteriden kargo ambalajının ve kırık kavanozun 2 adet fotoğrafı WhatsApp veya web üzerinden talep edilir.
  2. Müşteriye anında şu yanıt verilir: *"Afiyetinizin bölünmesine çok üzüldük. Hiçbir formalite beklemeden yeni paketiniz bugün kargoya veriliyor."*
  3. Admin panelinden `Yeni Gönderim (Telafi Paketi)` oluşturulur (Müşteriden ek ücret alınmaz).
  4. Hasar fotoğrafları ile ilgili kargo firması şubesine **Tazmin Dilekçesi** açılarak ürün bedeli kargo firmasından tahsil edilir.

### 4.2 Kargo Takip Numarası Sistemde Güncellenmiyor
- **Çözüm:** Kargo API servisi geçici olarak yanıt vermiyorsa, admin panelinde ilgili sipariş detayına girilerek kargo şubesinden alınan 12 haneli barkod numarası `shop.shipments.tracking_no` alanına elle yapıştırılır ve `[Kaydet ve Müşteriye SMS At]` butonuna basılır.

---

## 5. TEKNİK SİSTEM VE SUNUCU ARIZALARI

### 5.1 Web Sitesi ve API 502 / 500 Hatası Veriyor
```bash
# 1. Sunucuya SSH ile bağlanın
ssh deploy@<VPS_IP>

# 2. Konteyner durumlarını kontrol edin
docker ps -a

# 3. Hangi konteynerin çöktüğünü görün (nuto-api veya nuto-web)
docker logs --tail 100 nuto-api
docker logs --tail 100 nuto-web

# 4. Bellek (RAM) durumunu inceleyin (OOM Kill kontrolü)
free -m
dmesg -T | grep -i oom

# 5. Hızlı Kurtarma (Konteynerleri yeniden başlatın)
cd /srv/nuto
docker compose restart api web
```

### 5.2 Veritabanı Kilitlenmesi (Deadlock / High Load)
```bash
# Veritabanı konteynerine girin
docker exec -it nuto-db psql -U nuto_user -d nutopia_prod

# Kilitli ve uzun süren sorguları listeleyin
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle' AND (now() - pg_stat_activity.query_start) > interval '10 seconds';

# Sorunlu sorguyu sonlandırın
SELECT pg_terminate_backend(<PID>);
```

