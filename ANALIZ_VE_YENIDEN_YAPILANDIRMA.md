# SHAMAN POS - KAPSAMLI ANALİZ VE YENİDEN YAPILANDIRMA PLANI

**Tarih:** 15 Kasım 2024  
**Versiyon:** 0.1.0 → 2.0.0  
**Durum:** Analiz ve Planlama Aşaması

---

## 📊 MEVCUT DURUM ANALİZİ

### 1. DOSYA YAPISI (46 Dart Dosyası)

#### ✅ İYİ TARAFLAR:
- Clean Architecture yapısı mevcut (data, domain, presentation)
- Servisler ayrılmış (20 servis dosyası)
- Model sınıfları tanımlı (6 model)
- Widget'lar modüler

#### ❌ SORUNLAR:
- `core/` ve `domain/` klasörleri boş
- Çok fazla servis dosyası (20 servis - karmaşık)
- Duplikasyon var (örn: printer servisleri 5 farklı dosyada)
- Test dosyaları yok
- Dokümantasyon eksik

---

## 🎯 MEVCUT ÖZELLİKLER

### ✅ ÇALIŞAN ÖZELLİKLER:
1. **Sipariş Yönetimi**
   - Sipariş oluşturma
   - Sipariş listeleme
   - Ödeme takibi

2. **Müşteri Yönetimi**
   - Müşteri ekleme/düzenleme
   - Müşteri listeleme
   - İletişim bilgileri

3. **Ürün Yönetimi**
   - Ürün ekleme/düzenleme
   - Ürün listeleme
   - Stok takibi (kısmi)

4. **Yazıcı Yönetimi**
   - Sunmi dahili yazıcı (ESC/POS, TSPL)
   - Bluetooth yazıcılar (ESC/POS, TSC, CPCL, ZPL)
   - Test yazdırma
   - Fiş yazdırma

5. **Finans**
   - Gelir/gider takibi
   - Ödeme kayıtları
   - Temel raporlama

6. **Ayarlar**
   - Profil ayarları
   - Güvenlik ayarları
   - Dil/para birimi
   - Yedekleme
   - SMS ayarları

### ⚠️ EKSIK/SORUNLU ÖZELLİKLER:

#### 1. SMS GÖNDERİMİ
- **Durum:** Ayarlar var ama entegrasyon yok
- **Sorun:** SMS API entegrasyonu eksik
- **Gerekli:** SMS gateway (Twilio, Netgsm, İleti Merkezi)

#### 2. SİPARİŞ TAKİBİ
- **Durum:** Temel sipariş var ama durum takibi zayıf
- **Sorun:** 
  - Sipariş durumları net değil (Hazırlanıyor, Yolda, Teslim Edildi)
  - Bildirim sistemi yok
  - Zaman takibi yok
- **Gerekli:** Durum makinesi, bildirimler, timeline

#### 3. STOK YÖNETİMİ
- **Durum:** Ürün var ama stok takibi eksik
- **Sorun:**
  - Stok miktarı güncellenmesi otomatik değil
  - Kritik stok uyarısı yok
  - Stok geçmişi yok

#### 4. RAPORLAMA
- **Durum:** Temel finans var ama detaylı raporlar yok
- **Sorun:**
  - Günlük/haftalık/aylık raporlar yok
  - Grafik ve görselleştirme zayıf
  - Export özelliği yok (PDF, Excel)

#### 5. KULLANICI YÖNETİMİ
- **Durum:** Tek kullanıcı
- **Sorun:**
  - Multi-user desteği yok
  - Yetki sistemi yok
  - Personel takibi yok

#### 6. PERFORMANS
- **Sorun:**
  - Database sorguları optimize değil
  - Pagination eksik bazı sayfalarda
  - Gereksiz rebuild'ler
  - Memory leak riski

---

## 🔴 KRİTİK HATALAR VE SORUNLAR

### 1. MİMARİ SORUNLAR
```
❌ domain/ klasörü boş - İş mantığı presentation'da
❌ core/ klasörü boş - Ortak sınıflar dağınık
❌ Servis çoğalması - 20 servis dosyası
❌ Singleton abuse - Her servis singleton
❌ Tight coupling - Servisler birbirine bağımlı
```

### 2. DATABASE SORUNLARI
```
❌ Migration sistemi yok
❌ Index'ler eksik - Yavaş sorgular
❌ Transaction yönetimi zayıf
❌ Backup/restore test edilmemiş
❌ Veri bütünlüğü kontrolleri eksik
```

### 3. YAZICI SORUNLARI
```
⚠️ 5 farklı printer servisi (karmaşık)
⚠️ Logo ölçeklendirme bazen bozuk
⚠️ Hata yönetimi yetersiz
⚠️ Timeout yönetimi yok
⚠️ Queue sistemi yok (çoklu yazdırma)
```

### 4. UI/UX SORUNLARI
```
⚠️ Tutarsız tasarım
⚠️ Loading state'leri eksik
⚠️ Error handling kullanıcı dostu değil
⚠️ Form validasyonları zayıf
⚠️ Responsive design eksik
⚠️ Accessibility (a11y) yok
```

### 5. GÜVENLİK SORUNLARI
```
❌ Şifreleme var ama key management zayıf
❌ SQL injection riski (raw queries)
❌ Input validation eksik
❌ Session yönetimi yok
❌ Audit log yok
```

### 6. TEST VE KALITE
```
❌ Unit test yok
❌ Widget test yok
❌ Integration test yok
❌ CI/CD yok
❌ Code coverage 0%
```

---

## 🎨 YENİ UYGULAMA TASARIMI

### TEMEL PRENSİPLER:
1. **Basitlik** - Karmaşıklığı azalt
2. **Hız** - Performans odaklı
3. **Güvenilirlik** - Hata toleransı
4. **Ölçeklenebilirlik** - Büyümeye hazır
5. **Kullanıcı Deneyimi** - Sezgisel arayüz

### MİMARİ: Clean Architecture + BLoC

```
lib/
├── core/
│   ├── constants/
│   ├── errors/
│   ├── usecases/
│   └── utils/
├── features/                    # Feature-based organization
│   ├── auth/
│   ├── orders/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── pages/
│   │       └── widgets/
│   ├── customers/
│   ├── products/
│   ├── finance/
│   ├── printer/
│   └── settings/
└── main.dart
```

---

## 📋 YENİ UYGULAMA ÖZELLİKLERİ

### PHASE 1: CORE (2 hafta)
**Öncelik: YÜKSEK**

#### 1.1 Temel Altyapı
- [ ] Clean Architecture kurulumu
- [ ] BLoC state management
- [ ] Database migration sistemi
- [ ] Error handling framework
- [ ] Logging sistemi
- [ ] Dependency injection (get_it)

#### 1.2 Sunmi Yazıcı Entegrasyonu
- [ ] ESC/POS fiş yazdırma
- [ ] TSPL etiket yazdırma
- [ ] Logo yazdırma (optimize)
- [ ] Barkod/QR kod
- [ ] Test sayfası
- [ ] Hata yönetimi

#### 1.3 Database
- [ ] SQLite optimizasyonu
- [ ] Index'ler
- [ ] Migration sistemi
- [ ] Backup/restore
- [ ] Data validation

### PHASE 2: CORE FEATURES (3 hafta)
**Öncelik: YÜKSEK**

#### 2.1 Sipariş Yönetimi
- [ ] Sipariş oluşturma (hızlı UI)
- [ ] Sipariş durumları
  - Beklemede
  - Hazırlanıyor
  - Hazır
  - Yolda
  - Teslim Edildi
  - İptal
- [ ] Sipariş timeline
- [ ] Sipariş arama/filtreleme
- [ ] Sipariş düzenleme
- [ ] Toplu işlemler

#### 2.2 Müşteri Yönetimi
- [ ] Müşteri CRUD
- [ ] Telefon numarası validasyonu
- [ ] Adres yönetimi
- [ ] Müşteri geçmişi
- [ ] Favori müşteriler
- [ ] Müşteri notları

#### 2.3 Ürün Yönetimi
- [ ] Ürün CRUD
- [ ] Kategori yönetimi
- [ ] Stok takibi
- [ ] Kritik stok uyarıları
- [ ] Fiyat geçmişi
- [ ] Ürün resimleri

### PHASE 3: SMS & BİLDİRİMLER (1 hafta)
**Öncelik: ORTA**

#### 3.1 SMS Entegrasyonu
- [ ] SMS gateway seçimi (Netgsm/İleti Merkezi)
- [ ] Sipariş onay SMS'i
- [ ] Sipariş hazır SMS'i
- [ ] Kurye yola çıktı SMS'i
- [ ] SMS şablonları
- [ ] SMS geçmişi
- [ ] Toplu SMS

#### 3.2 Bildirimler
- [ ] Push notification (local)
- [ ] Sipariş bildirimleri
- [ ] Stok uyarıları
- [ ] Ödeme hatırlatmaları

### PHASE 4: FİNANS & RAPORLAMA (2 hafta)
**Öncelik: ORTA**

#### 4.1 Gelir/Gider Takibi
- [ ] Gelir kayıtları (otomatik)
- [ ] Gider kayıtları (manuel)
- [ ] Kategori bazlı takip
- [ ] Ödeme yöntemleri
- [ ] Nakit/Kart/Online

#### 4.2 Raporlama
- [ ] Günlük rapor
- [ ] Haftalık rapor
- [ ] Aylık rapor
- [ ] Grafik ve görselleştirme
- [ ] PDF export
- [ ] Excel export
- [ ] Karşılaştırmalı raporlar

### PHASE 5: GELİŞMİŞ ÖZELLİKLER (2 hafta)
**Öncelik: DÜŞÜK**

#### 5.1 Kullanıcı Yönetimi
- [ ] Multi-user desteği
- [ ] Rol ve yetkiler
- [ ] Personel takibi
- [ ] Vardiya yönetimi

#### 5.2 Entegrasyonlar
- [ ] QR kod ile sipariş takibi
- [ ] Online sipariş entegrasyonu
- [ ] Muhasebe yazılımı entegrasyonu

---

## 🎨 TASARIM PRENSİPLERİ

### RENK PALETİ
```dart
Primary: #2E7D32 (Yeşil - Güven, Başarı)
Secondary: #1976D2 (Mavi - Profesyonellik)
Accent: #F57C00 (Turuncu - Dikkat)
Error: #D32F2F (Kırmızı)
Success: #388E3C (Yeşil)
Warning: #F57F17 (Sarı)
Background Light: #FAFAFA
Background Dark: #121212
```

### TİPOGRAFİ
```
Başlıklar: Roboto Bold
Gövde: Roboto Regular
Sayılar: Roboto Mono (fiyatlar için)
```

### COMPONENT LIBRARY
- Material Design 3
- Custom button styles
- Consistent spacing (8px grid)
- Elevation system
- Animation guidelines

---

## 🔧 TEKNOLOJİ STACK

### MEVCUT:
```yaml
flutter: SDK
provider: ^6.1.1 (State Management)
sqflite: ^2.4.2 (Database)
sunmi_printer_plus: ^4.1.0 (Printer)
bluetooth_print_plus: ^2.4.6 (Bluetooth)
```

### YENİ EKLENECEK:
```yaml
# State Management
flutter_bloc: ^8.1.3
equatable: ^2.0.5

# Dependency Injection
get_it: ^7.6.4
injectable: ^2.3.2

# Network (SMS için)
dio: ^5.4.0
retrofit: ^4.0.3

# Storage
hive: ^2.2.3 (Cache için)

# Utilities
freezed: ^2.4.5 (Immutable models)
json_serializable: ^6.7.1
dartz: ^0.10.1 (Functional programming)

# Testing
mocktail: ^1.0.1
bloc_test: ^9.1.5

# Code Quality
very_good_analysis: ^5.1.0
```

---

## 📦 YEDEKLEME STRATEJİSİ

### 1. GIT YEDEKLEME
```bash
# Mevcut durumu tag'le
git tag -a v0.1.0-legacy -m "Legacy version before refactor"
git push origin v0.1.0-legacy

# Yeni branch oluştur
git checkout -b refactor/v2.0.0
```

### 2. DOSYA YEDEKLEMESİ
```
shaman_new_backup_2024_11_15/
├── lib/
├── android/
├── ios/
├── assets/
├── pubspec.yaml
└── README.md
```

### 3. DATABASE YEDEKLEMESİ
- Tüm tabloları export et
- Test verileri kaydet
- Migration script'leri sakla

---

## 📊 PERFORMANS HEDEFLERİ

### MEVCUT:
- Uygulama başlatma: ~3-4 saniye
- Sipariş oluşturma: ~2 saniye
- Liste yükleme: ~1-2 saniye
- Yazdırma: ~3-5 saniye

### HEDEF:
- Uygulama başlatma: <2 saniye ⚡
- Sipariş oluşturma: <1 saniye ⚡
- Liste yükleme: <500ms ⚡
- Yazdırma: <2 saniye ⚡

---

## 🎯 BAŞARI KRİTERLERİ

### PHASE 1 (Core)
- [ ] Uygulama hatasız açılıyor
- [ ] Database migration çalışıyor
- [ ] Sunmi yazıcı test başarılı
- [ ] Error handling çalışıyor

### PHASE 2 (Features)
- [ ] Sipariş oluşturma <1 saniye
- [ ] Tüm CRUD işlemleri çalışıyor
- [ ] Stok otomatik güncelleniyor
- [ ] UI responsive

### PHASE 3 (SMS)
- [ ] SMS başarıyla gönderiliyor
- [ ] Bildirimler çalışıyor
- [ ] Şablonlar özelleştirilebilir

### PHASE 4 (Finance)
- [ ] Raporlar doğru
- [ ] PDF export çalışıyor
- [ ] Grafikler görüntüleniyor

### PHASE 5 (Advanced)
- [ ] Multi-user çalışıyor
- [ ] Entegrasyonlar aktif

---

## ⏱️ ZAMAN ÇİZELGESİ

| Phase | Süre | Başlangıç | Bitiş |
|-------|------|-----------|-------|
| Analiz & Planlama | 1 gün | 15 Kas | 15 Kas |
| Phase 1: Core | 2 hafta | 16 Kas | 29 Kas |
| Phase 2: Features | 3 hafta | 30 Kas | 20 Ara |
| Phase 3: SMS | 1 hafta | 21 Ara | 27 Ara |
| Phase 4: Finance | 2 hafta | 28 Ara | 10 Oca |
| Phase 5: Advanced | 2 hafta | 11 Oca | 24 Oca |
| Test & Polish | 1 hafta | 25 Oca | 31 Oca |

**TOPLAM: ~10 hafta (2.5 ay)**

---

## 📝 SONRAKİ ADIMLAR

1. **BU DOSYAYI İNCELE** - Eklemelerini yap
2. **YEDEKLEME YAP** - Git + Dosya
3. **YENİ BRANCH OLUŞTUR** - refactor/v2.0.0
4. **PHASE 1'E BAŞLA** - Core altyapı

---

## 💡 NOTLAR

- Bu bir **sıfırdan yazma** değil, **akıllı refactoring**
- Çalışan kodları koruyacağız, sadece iyileştireceğiz
- Her phase sonunda test edilebilir durum
- Geri dönüş her zaman mümkün (git)

---

**Hazırlayan:** AI Assistant  
**Onaylayan:** [Senin Adın]  
**Tarih:** 15 Kasım 2024
