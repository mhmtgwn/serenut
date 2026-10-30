# 28 — Yıllık İşletme, Bakım, Kapasite ve Finansal Projeksiyon Modeli (TCO & Capacity)

> Bu belge; Nutopia Platformu'nun 1., 2. ve 3. yıllardaki sunucu altyapı maliyetlerini, SMS/e-posta harcamalarını, ödeme komisyonlarını, tahmini işlem hacmini ve ölçeklenme sınırlarını gösteren toplam sahip olma maliyeti (TCO) ve finansal projeksiyon modelidir.

---

## 1. TRAFİK VE İŞLEM HACMİ PROJEKSİYONU (3 YILLIK)

| Parametre | Yıl 1 (Lansman & Oturma) | Yıl 2 (Bölgesel Büyüme) | Yıl 3 (Karadeniz Geneli & E-Ticaret) |
|---|---|---|---|
| **Yıllık Mağaza Sipariş Adedi** | 2.400 sipariş (~7 sipariş/gün) | 7.500 sipariş (~20 sipariş/gün) | 22.000 sipariş (~60 sipariş/gün) |
| **Ortalama Sipariş Tutarı (AOV)** | 450,00 ₺ | 600,00 ₺ (Enflasyon/Sepet büyümesi) | 750,00 ₺ |
| **Yıllık Mağaza Cirosu** | **1.080.000 ₺** | **4.500.000 ₺** | **16.500.000 ₺** |
| **Yıllık Değirmen Mahsul Talebi** | 180 talep | 450 talep | 1.100 talep |
| **İşlenen Toplam Mahsul (kg)** | 45.000 kg (~250 kg/talep) | 135.000 kg (~300 kg/talep) | 385.000 kg (~350 kg/talep) |
| **Ortalama İşleme Bedeli** | 70 ₺/kg (Ağırlıklı ortalama) | 85 ₺/kg | 100 ₺/kg |
| **Yıllık Değirmen Hizmet Cirosu** | **3.150.000 ₺** | **11.475.000 ₺** | **38.500.000 ₺** |
| **TOPLAM BRÜT PLATFORM HACMİ** | **4.230.000 ₺** | **15.975.000 ₺** | **55.000.000 ₺** |

---

## 2. DİJİTAL ALTYAPI VE SABİT MALİYETLER (YILLIK TAHMİN)

| Kalem | Açıklama | Yıl 1 (Aylık / Yıllık) | Yıl 2 (Yıllık) | Yıl 3 (Yıllık) |
|---|---|---|---|---|
| **VPS Sunucusu (Nutopiano)** | 4 GB RAM, 2 vCPU, 80 GB NVMe (Hetzner / Yerel TR) | 12 €/ay (~450 ₺) -> **5.400 ₺/yıl** | 8.500 ₺/yıl (8GB RAM) | 14.000 ₺/yıl (16GB RAM) |
| **Dış Yedekleme (B2 / S3)** | Günlük pgBackRest WAL + Görseller (100 GB) | 1 $ /ay (~35 ₺) -> **420 ₺/yıl** | 900 ₺/yıl | 2.400 ₺/yıl |
| **Alan Adı (nutopiano.com)** | Yıllık tescil ve yenileme bedeli | **500 ₺/yıl** | 600 ₺/yıl | 700 ₺/yıl |
| **Cloudflare WAF / CDN** | Standart koruma ve DNS | **0 ₺ (Ücretsiz Plan)** | 0 ₺ | 20 $/ay (~8.000 ₺ Pro) |
| **Kurumsal E-Posta Kutusu** | Google Workspace / Zoho (2 Kullanıcı) | 12 $ /ay (~450 ₺) -> **5.400 ₺/yıl** | 7.000 ₺/yıl | 12.000 ₺/yıl |
| **İzleme & Hata (Sentry / Uptime)** | Ücretsiz katman limitleri dahilinde | **0 ₺** | 0 ₺ | 3.500 ₺/yıl |
| **TOPLAM SABİT BİLİŞİM MALİYETİ** | | **~11.720 ₺ / Yıl** | **~17.000 ₺ / Yıl** | **~40.600 ₺ / Yıl** |

*Yorum: Platformun sabit bilişim maliyeti ciroya oranla binde 3'ün altındadır; son derece yüksek kârlılık marjı sağlar.*

---

## 3. İŞLEM BAZLI DEĞİŞKEN MALİYETLER

### 3.1 SMS Bildirim Giderleri (OTP, Kargo, Tartı Tutanakları)
- Sipariş ve talep başına ortalama: **4 SMS** (Doğrulama, Bilgilendirme, Kargo/Tartı, Tamamlama).
- Yıl 1 Tahmini SMS Hacmi: `(2.400 sipariş + 180 talep) * 4 = ~10.500 SMS`.
- Birim SMS Maliyeti: ~0,35 ₺ (Başlıklı SMS).
- **Yıl 1 SMS Bütçesi:** `10.500 * 0,35 ₺ = ~3.675 ₺ / Yıl`.

### 3.2 Sanal POS Komisyon Giderleri (iyzico / PayTR)
- Ortalama Komisyon Oranı: **%2,79 + 0,25 ₺** (Sektörel tahmini oran).
- Yıl 1 Kredi Kartı ile Geçen Tutar (Tahmini %60 pay): `1.080.000 ₺ * %60 = 648.000 ₺`.
- **Yıl 1 Tahmini POS Komisyonu:** `648.000 * 0,0279 = ~18.000 ₺ / Yıl`.

### 3.3 Ambalaj & Paketleme Giderleri (E-Ticaret)
- Cam kavanoz airbag koruyucu poşet: ~3,50 ₺ / adet.
- Kraft koli + emniyet bandı: ~5,00 ₺ / sipariş.
- **Yıl 1 Ambalaj Maliyeti:** `2.400 sipariş * 8,50 ₺ = ~20.400 ₺ / Yıl`.

---

## 4. PERİYODİK BAKIM VE SİSTEM SAĞLIK TAKVİMİ

```
Haftalık Rutinler (Her Pazartesi 08:30)
  ├── 1. Failed Jobs kuyruğu kontrolü (ops.jobs_failed_archive boş mu?)
  ├── 2. Disk doluluk oranı kontrolü (df -h / < %70 olmalı)
  └── 3. Eşleşmeyen havaleler listesi temizliği

Aylık Rutinler (Her Ayın 1'i Gece 02:00)
  ├── 1. Otomatik Kurtarma Tatbikatı (B2'deki yedeğin test DB'sine açılması)
  ├── 2. Güvenlik ve OS yamaları (apt update && apt upgrade)
  ├── 3. SSL sertifika geçerlilik süresi kontrolü
  └── 4. Kargo firması kapıda ödeme cari mutabakatı

Yıllık Rutinler (Her Yılbaşında)
  ├── 1. Alan adı ve kurumsal lisans yenilemeleri
  ├── 2. PostgreSQL VACUUM FULL ve indeks optimizasyonu (reindexdb)
  └── 3. Şoför kantar ve terazilerinin Sanayi Bakanlığı periyodik muayenesi
```

