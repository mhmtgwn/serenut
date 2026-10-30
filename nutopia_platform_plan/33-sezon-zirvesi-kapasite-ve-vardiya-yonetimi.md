# 33 — Fındık Sezon Zirvesi (Ağustos-Ekim) Kapasite, Vardiya ve Kriz Yönetim Planı (Peak Season Operations)

> Bu belge; Batı Karadeniz'de fındık hasadının başladığı Ağustos-Ekim ayları arasındaki 90 günlük "Zirve Sezon" (Peak Season) döneminde değirmenin fiziksel kapasitesini, şoför/araç rotasyonunu, elektrik/makine bakım yedekliliğini ve kriz protokollerini belirler.
> Amaç: Yıllık cironun %70'inin toplandığı hasat döneminde değirmenin tıkanmasını, üreticinin kapıda beklemesini ve makine arızası nedeniyle müşteri kaybını sıfıra indirmek.

---

## 1. SEZONLUK HACİM VE KAPASİTE MODELİ

| Parametre | Standart Dönem (Kasım - Temmuz) | Zirve Sezon (Ağustos - Ekim / 90 Gün) |
|---|---|---|
| **Günlük Alım Talebi** | 1 - 3 talep / gün | **15 - 35 talep / gün** |
| **İşlenen Günlük Mahsul** | 500 - 1.500 kg / gün | **6.000 - 12.000 kg / gün** |
| **Çalışma Düzeni** | Tek Vardiya (09:00 - 18:00) | **Çift Vardiya (07:00 - 23:00 / 16 Saat)** |
| **Aktif Kurye Aracı** | 1 Araç (Transit / Kamyonet) | **2 Araç (1 Ana Araç + 1 Sezonluk Kiralık/Destek)** |
| **Kırma Makinesi Çalışma** | Günde 2 - 3 saat | Günde 10 - 12 saat kesintisiz |
| **Kavurma Tamburu** | Günde 2 parti | Günde 8 - 10 parti |

---

## 2. SAHA VE DEĞİRMEN ÇİFT VARDİYA ÇALIŞMA PLANI

```mermaid
gantt
    title Zirve Sezon Günlük Operasyon Çizelgesi (16 Saat)
    dateFormat  HH:mm
    axisFormat %H:%M

    section Kurye & Saha
    1. Saha Alım Turu (Köyler)       :07:30, 12:30
    Araç Boşaltma & İkinci Tartı     :12:30, 13:30
    2. Saha Alım & Teslimat Turu     :14:00, 19:30
    Kasa Kapanış & Günlük Sayım      :19:30, 20:30

    section Değirmen İçi İşleme
    1. Vardiya: Kırma & Eleme        :07:00, 15:00
    Kavurma Tamburları & Soğutma     :08:30, 15:30
    2. Vardiya: Taş Değirmen Ezme    :15:00, 23:00
    Vakumlama & Paketleme            :15:30, 22:30
    Tesis Temizliği & Makine Bakımı  :22:30, 23:30
```

---

## 3. SEZONLUK TALEP VE RANDEVU KONTROLÜ (RATE LIMITING)

Hasat zamanında herkes aynı anda fındığını getirmek veya aldırmak ister. Sistemin fiziksel kapasiteyi aşmaması için yazılım seviyesinde şu bariyerler çalışır:

1. **Günlük Kapasite Kotası (`daily_quota_kg`):**
   - Tesisin günlük maksimum işleme kapasitesi `10.000 kg` olarak sisteme kilitlenir.
   - Web veya telefondan talep açılırken o günün toplam tahmini kg'ı `9.000 kg`'a ulaştığında sistem o tarihi otomatik olarak randevuya kapatır ("Dolu") ve çiftçiyi bir sonraki uygun güne yönlendirir.
2. **Köy / Havza Bazlı Rota Birleştirme (Cluster Dispatching):**
   - Şoförün aynı gün içinde hem Alaplı'ya hem de Ormanlı'nın uzak köylerine gitmesi engellenir.
   - Sistem talepleri coğrafi olarak kümeler:
     - *Pazartesi - Çarşamba - Cuma:* Ormanlı ve Merkez Köyleri.
     - *Salı - Perşembe - Cumartesi:* Alaplı ve Çaycuma Havzası.
   - Böylece araç yakıt ve zaman verimliliği %40 artırılır.

---

## 4. MAKİNE YEDEKLİLİĞİ VE KRİTİK YEDEK PARÇA STOK LİSTESİ

Sezon ortasında kırma veya kavurma makinesinin arızalanması kabul edilemez bir ciro kaybıdır. Ormanlı tesisinde sezondan önce hazır bulundurulacak **Kritik Yedek Parça Kiti**:

| Makine | Kritik Aşınma Parçası | Yedek Adedi | Temin Yeri / Raf No |
|---|---|---|---|
| **Kırma Makinesi** | Kırıcı Çelik Bıçaklar & Elek Telleri | 2 Takım | Tesis Yedek Dolabı A-1 |
| **Kırma Makinesi** | Ana Tahrik Kayışları (V-Kayış) | 4 Adet | Tesis Yedek Dolabı A-2 |
| **Fırın Kavurma** | Rezistans / Brülör Ateşleme Bujisi | 2 Adet | Tesis Yedek Dolabı B-1 |
| **Fırın Kavurma** | Sıcaklık Sensörü (Termokupl PT100) | 2 Adet | Tesis Yedek Dolabı B-2 |
| **Zar Soyma** | Silikon Aşındırma Merdaneleri | 1 Takım | Tesis Yedek Dolabı C-1 |
| **Taş Değirmen** | Granit Taş Tahrik Rulmanı & Keçesi | 2 Takım | Tesis Yedek Dolabı C-2 |
| **Vakum Makinesi** | Isıtıcı Çene Teli ve Teflon Bant | 5 Metre | Paketleme Masası Altı |
| **Saha Kantarı** | Şarjlı Dijital Kantar (Yedek Terazi) | 1 Adet Tam Yedek | Şoför Araç Kabini |

---

## 5. ELEKTRİK KESİNTİSİ VE ENERJİ GÜVENCESİ

- Kırsal bölgelerde hasat aylarında aşırı yüklenme veya fırtına kaynaklı elektrik kesintileri sıkça yaşanabilir.
- **Jeneratör Kapasitesi:** Tesisin tüm kırma, kavurma ve ezme motorlarını aynı anda kaldırabilecek güçte **en az 35 kVA Otomatik Transfer Panolu (ATS) Dizel Jeneratör** sezondan önce bakımdan geçirilir.
- **Yakıt Rezervi:** Tesis deposunda kesintisiz 48 saat çalışmaya yetecek **200 Litre mazot** yedek bidonlarda hazır bulundurulur.
- **Sunucu & İnternet Güvencesi:** Tesis içi kantar ve bilgisayarlar için **3 kVA Online UPS (Kesintisiz Güç Kaynağı)** hattı çekilir (Elektrik gitse bile kantar tartısı ve fiş yazımı sıfır kesintiyle sürer).

---

## 6. GEÇİCİ SEZONLUK PERSONEL YÖNETİMİ VE EĞİTİMİ

Hasat döneminde işletmeye dahil edilecek geçici mevsimlik personelin sisteme uyumu:
1. **Rol Kısıtlaması:** Geçici personele asla `owner` veya `manager` yetkisi verilmez; yalnızca sınırlı `packer` (Paketleme) ve `mill:process` (Makine iş emri ilerletme) yetkisi tanımlanır.
2. **1 Günlük Zorunlu Saha Eğitimi:**
   - Hijyen ve koruyucu kıyafet (Bone, önlük, gıda eldiveni) zorunluluğu.
   - Çuval Lot Etiketlerinin asla sökülmemesi kuralı.
   - Vakum poşetlerinde kaçak kontrolü (Vakum dikiş testi).
   - Dijital terazide dara alma mantığı.

