# SHAMAN POS v2.0 - DETAYLI YAPILACAKLAR LİSTESİ

## 🎯 PHASE 1: CORE ALTYAPI (2 Hafta)

### GÜN 1-2: Proje Kurulumu
- [ ] Yedekleme yap (git tag + dosya kopyası)
- [ ] Yeni branch oluştur: `refactor/v2.0.0`
- [ ] `pubspec.yaml` güncelle - yeni paketler ekle
- [ ] Klasör yapısını oluştur (`features/` bazlı)
- [ ] `analysis_options.yaml` - very_good_analysis ekle
- [ ] `.gitignore` güncelle

### GÜN 3-4: Core Sınıflar
- [ ] `core/errors/failures.dart` - Hata sınıfları
- [ ] `core/errors/exceptions.dart` - Exception'lar
- [ ] `core/usecases/usecase.dart` - Base usecase
- [ ] `core/utils/logger.dart` - Logging sistemi
- [ ] `core/utils/validators.dart` - Input validation
- [ ] `core/constants/app_constants.dart`
- [ ] `core/constants/database_constants.dart`

### GÜN 5-6: Dependency Injection
- [ ] `injection_container.dart` - get_it setup
- [ ] Tüm servisleri DI'a kaydet
- [ ] Singleton pattern'den kurtul
- [ ] Factory pattern'lere geç

### GÜN 7-8: Database Refactoring
- [ ] `database_helper.dart` - Migration sistemi ekle
- [ ] Index'leri tanımla
- [ ] Foreign key'leri ekle
- [ ] Transaction helper'ları
- [ ] Database versiyonlama (v1 → v2)
- [ ] Test data seeder

### GÜN 9-10: Sunmi Printer Feature
```
features/printer/
├── data/
│   ├── datasources/
│   │   ├── sunmi_printer_datasource.dart
│   │   └── sunmi_printer_datasource_impl.dart
│   ├── models/
│   │   ├── print_job_model.dart
│   │   └── printer_config_model.dart
│   └── repositories/
│       └── printer_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── print_job.dart
│   │   └── printer_config.dart
│   ├── repositories/
│   │   └── printer_repository.dart
│   └── usecases/
│       ├── print_receipt.dart
│       ├── print_label.dart
│       └── test_printer.dart
└── presentation/
    ├── bloc/
    │   ├── printer_bloc.dart
    │   ├── printer_event.dart
    │   └── printer_state.dart
    └── widgets/
        └── print_preview_widget.dart
```

**Yapılacaklar:**
- [ ] Entity'leri oluştur
- [ ] Repository interface tanımla
- [ ] Use case'leri yaz
- [ ] Datasource implementation
- [ ] BLoC setup
- [ ] ESC/POS komutları optimize et
- [ ] TSPL komutları optimize et
- [ ] Logo ölçeklendirme düzelt
- [ ] Hata yönetimi ekle
- [ ] Test yaz (unit + widget)

### GÜN 11-12: Error Handling & Logging
- [ ] Global error handler
- [ ] Error dialog widget
- [ ] Toast notification sistem
- [ ] Debug/Release log seviyeleri
- [ ] Crash reporting (optional: Sentry)

### GÜN 13-14: Testing & Documentation
- [ ] Unit testler (core)
- [ ] Widget testler (printer)
- [ ] Integration test (database)
- [ ] README güncelle
- [ ] API documentation

---

## 🎯 PHASE 2: CORE FEATURES (3 Hafta)

### HAFTA 1: Sipariş Yönetimi

#### GÜN 1-2: Order Entity & Repository
```
features/orders/
├── domain/
│   ├── entities/
│   │   ├── order.dart
│   │   ├── order_item.dart
│   │   └── order_status.dart (enum)
│   ├── repositories/
│   │   └── order_repository.dart
│   └── usecases/
│       ├── create_order.dart
│       ├── get_orders.dart
│       ├── update_order_status.dart
│       ├── cancel_order.dart
│       └── search_orders.dart
```

**Yapılacaklar:**
- [ ] Order entity (freezed ile immutable)
- [ ] OrderStatus enum (6 durum)
- [ ] Repository interface
- [ ] Use case'ler
- [ ] Validation rules

#### GÜN 3-4: Order Data Layer
- [ ] Order model (JSON serialization)
- [ ] Order datasource (SQLite)
- [ ] Repository implementation
- [ ] Database queries optimize et
- [ ] Index'ler ekle
- [ ] Test data

#### GÜN 5-7: Order UI
- [ ] OrderBloc (state management)
- [ ] Sipariş oluşturma sayfası
  - Müşteri seçimi
  - Ürün ekleme (hızlı)
  - Toplam hesaplama
  - Ödeme yöntemi
  - Not ekleme
- [ ] Sipariş listesi sayfası
  - Durum filtreleme
  - Arama
  - Sıralama
  - Pagination
- [ ] Sipariş detay sayfası
  - Timeline gösterimi
  - Durum güncelleme
  - Yazdırma
  - SMS gönderme
- [ ] Sipariş düzenleme
- [ ] Sipariş iptal

### HAFTA 2: Müşteri & Ürün Yönetimi

#### GÜN 1-3: Customer Feature
```
features/customers/
├── domain/
│   ├── entities/
│   │   ├── customer.dart
│   │   └── address.dart
│   ├── repositories/
│   │   └── customer_repository.dart
│   └── usecases/
│       ├── create_customer.dart
│       ├── get_customers.dart
│       ├── update_customer.dart
│       ├── delete_customer.dart
│       └── search_customers.dart
```

**Yapılacaklar:**
- [ ] Customer entity
- [ ] Address entity (embedded)
- [ ] Phone validation
- [ ] Repository & use cases
- [ ] Data layer
- [ ] CustomerBloc
- [ ] UI sayfaları
  - Liste
  - Detay
  - Ekleme/Düzenleme
  - Arama
- [ ] Favori müşteriler

#### GÜN 4-7: Product Feature
```
features/products/
├── domain/
│   ├── entities/
│   │   ├── product.dart
│   │   ├── category.dart
│   │   └── stock_movement.dart
│   ├── repositories/
│   │   └── product_repository.dart
│   └── usecases/
│       ├── create_product.dart
│       ├── get_products.dart
│       ├── update_stock.dart
│       ├── get_low_stock_products.dart
│       └── get_stock_history.dart
```

**Yapılacaklar:**
- [ ] Product entity
- [ ] Category entity
- [ ] StockMovement entity
- [ ] Repository & use cases
- [ ] Data layer
- [ ] ProductBloc
- [ ] UI sayfaları
  - Liste (grid/list view)
  - Detay
  - Ekleme/Düzenleme
  - Kategori yönetimi
  - Stok takibi
- [ ] Kritik stok uyarıları
- [ ] Stok geçmişi

### HAFTA 3: Entegrasyon & Polish

#### GÜN 1-3: Feature Entegrasyonu
- [ ] Order → Customer ilişkisi
- [ ] Order → Product ilişkisi
- [ ] Stok otomatik güncelleme (sipariş oluşturulunca)
- [ ] Sipariş iptalinde stok iadesi
- [ ] Cascade delete'ler
- [ ] Data consistency checks

#### GÜN 4-5: Performance Optimization
- [ ] Database query optimization
- [ ] Index'leri gözden geçir
- [ ] Lazy loading
- [ ] Pagination her yerde
- [ ] Image caching (ürün resimleri)
- [ ] Memory profiling

#### GÜN 6-7: UI/UX Polish
- [ ] Loading states her yerde
- [ ] Empty states
- [ ] Error states
- [ ] Success animations
- [ ] Form validations
- [ ] Keyboard handling
- [ ] Focus management

---

## 🎯 PHASE 3: SMS & BİLDİRİMLER (1 Hafta)

### GÜN 1-2: SMS Gateway Entegrasyonu
```
features/sms/
├── data/
│   ├── datasources/
│   │   ├── sms_remote_datasource.dart (API)
│   │   └── sms_local_datasource.dart (Cache)
│   ├── models/
│   │   ├── sms_model.dart
│   │   └── sms_template_model.dart
│   └── repositories/
│       └── sms_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── sms.dart
│   │   └── sms_template.dart
│   ├── repositories/
│   │   └── sms_repository.dart
│   └── usecases/
│       ├── send_sms.dart
│       ├── send_bulk_sms.dart
│       └── get_sms_history.dart
```

**Yapılacaklar:**
- [ ] SMS gateway seçimi (Netgsm/İleti Merkezi)
- [ ] API entegrasyonu (Dio + Retrofit)
- [ ] SMS entity & models
- [ ] Repository & use cases
- [ ] SMS şablonları
  - Sipariş onay
  - Sipariş hazır
  - Kurye yola çıktı
  - Teslim edildi
- [ ] Şablon değişkenleri ({name}, {order_no}, vb.)
- [ ] SMS geçmişi
- [ ] Hata yönetimi (API down, kredi yok, vb.)

### GÜN 3-4: Bildirim Sistemi
- [ ] Local notification setup
- [ ] Notification channels
- [ ] Sipariş bildirimleri
- [ ] Stok uyarı bildirimleri
- [ ] Bildirim ayarları
- [ ] Bildirim geçmişi

### GÜN 5: SMS UI
- [ ] SMS ayarları sayfası
  - API credentials
  - Şablon yönetimi
  - Test SMS
- [ ] SMS geçmişi sayfası
- [ ] Toplu SMS gönderimi
- [ ] SMS preview

### GÜN 6-7: Testing & Integration
- [ ] SMS mock service (test için)
- [ ] Unit testler
- [ ] Integration testler
- [ ] Sipariş flow'una SMS ekle
- [ ] Error handling testleri

---

## 🎯 PHASE 4: FİNANS & RAPORLAMA (2 Hafta)

### HAFTA 1: Finans Yönetimi

#### GÜN 1-3: Finance Feature
```
features/finance/
├── domain/
│   ├── entities/
│   │   ├── transaction.dart
│   │   ├── expense.dart
│   │   ├── income.dart
│   │   └── payment_method.dart (enum)
│   ├── repositories/
│   │   └── finance_repository.dart
│   └── usecases/
│       ├── add_expense.dart
│       ├── get_transactions.dart
│       ├── get_daily_summary.dart
│       ├── get_period_summary.dart
│       └── export_report.dart
```

**Yapılacaklar:**
- [ ] Transaction entity (base class)
- [ ] Income/Expense entities
- [ ] PaymentMethod enum
- [ ] Repository & use cases
- [ ] Data layer
- [ ] Otomatik gelir kaydı (sipariş → gelir)
- [ ] Manuel gider kaydı

#### GÜN 4-5: Finance UI
- [ ] Finans dashboard
  - Günlük özet
  - Haftalık trend
  - Aylık karşılaştırma
- [ ] Gelir/Gider listesi
- [ ] Gider ekleme formu
- [ ] Kategori yönetimi
- [ ] Ödeme yöntemi istatistikleri

### HAFTA 2: Raporlama

#### GÜN 1-3: Report Engine
- [ ] Report generator service
- [ ] Günlük rapor
  - Toplam sipariş
  - Toplam gelir
  - Toplam gider
  - Net kar
  - En çok satan ürünler
- [ ] Haftalık rapor
- [ ] Aylık rapor
- [ ] Özel tarih aralığı raporu
- [ ] Karşılaştırmalı raporlar

#### GÜN 4-5: Görselleştirme
- [ ] fl_chart entegrasyonu
- [ ] Line chart (gelir trendi)
- [ ] Bar chart (günlük satışlar)
- [ ] Pie chart (ödeme yöntemleri)
- [ ] Donut chart (ürün kategorileri)
- [ ] Interactive charts

#### GÜN 6-7: Export & Print
- [ ] PDF export (pdf paketi)
  - Rapor şablonu
  - Logo ekleme
  - Tablo formatı
  - Grafik ekleme
- [ ] Excel export (excel paketi)
- [ ] Rapor yazdırma (Sunmi)
- [ ] Email rapor (optional)

---

## 🎯 PHASE 5: GELİŞMİŞ ÖZELLİKLER (2 Hafta)

### HAFTA 1: Kullanıcı Yönetimi

#### GÜN 1-4: Multi-User System
```
features/auth/
├── domain/
│   ├── entities/
│   │   ├── user.dart
│   │   ├── role.dart
│   │   └── permission.dart
│   ├── repositories/
│   │   └── auth_repository.dart
│   └── usecases/
│       ├── login.dart
│       ├── logout.dart
│       ├── create_user.dart
│       └── change_password.dart
```

**Yapılacaklar:**
- [ ] User entity
- [ ] Role enum (Admin, Manager, Cashier)
- [ ] Permission system
- [ ] Auth repository
- [ ] Login/logout
- [ ] Session management
- [ ] Password hashing (bcrypt)
- [ ] User CRUD
- [ ] Role assignment

#### GÜN 5-7: Personel Takibi
- [ ] Vardiya yönetimi
- [ ] Personel performans raporu
- [ ] Sipariş bazlı tracking
- [ ] Audit log
- [ ] Activity timeline

### HAFTA 2: Entegrasyonlar & Polish

#### GÜN 1-3: QR Kod Sistemi
- [ ] QR kod generator
- [ ] Sipariş QR kodu
- [ ] QR kod scanner
- [ ] Sipariş takip sayfası (QR ile)
- [ ] Müşteri self-service (optional)

#### GÜN 4-5: Final Polish
- [ ] Tüm sayfaları gözden geçir
- [ ] Tutarlılık kontrolü
- [ ] Performance optimization
- [ ] Memory leak kontrolü
- [ ] Accessibility (a11y)
- [ ] Dark mode polish
- [ ] Responsive design

#### GÜN 6-7: Documentation & Training
- [ ] Kullanıcı kılavuzu
- [ ] Video tutorials
- [ ] FAQ
- [ ] Troubleshooting guide
- [ ] API documentation
- [ ] Code documentation

---

## 🧪 TEST & KALITE (1 Hafta)

### GÜN 1-2: Unit Tests
- [ ] Core tests
- [ ] Use case tests
- [ ] Repository tests
- [ ] BLoC tests
- [ ] Utility tests
- [ ] Code coverage >80%

### GÜN 3-4: Integration Tests
- [ ] Database tests
- [ ] API tests (SMS)
- [ ] Printer tests
- [ ] End-to-end flows

### GÜN 5: Widget Tests
- [ ] Critical widget'lar
- [ ] Form validations
- [ ] Navigation tests
- [ ] State management tests

### GÜN 6-7: Manual Testing & Bug Fixing
- [ ] Tüm feature'ları test et
- [ ] Edge case'leri test et
- [ ] Performance test
- [ ] Bug fixing
- [ ] Regression testing

---

## 📦 DEPLOYMENT

### Pre-Release Checklist
- [ ] Tüm testler geçiyor
- [ ] Code coverage >80%
- [ ] Performance hedefleri karşılanıyor
- [ ] Documentation tamamlandı
- [ ] Changelog hazırlandı
- [ ] Version bump (2.0.0)

### Release Steps
- [ ] Production build
- [ ] APK imzalama
- [ ] Google Play Console upload
- [ ] Beta test (internal)
- [ ] Beta test (external)
- [ ] Production release

### Post-Release
- [ ] Monitoring setup
- [ ] Crash reporting
- [ ] User feedback toplama
- [ ] Bug tracking
- [ ] Hotfix planı

---

## 📊 METRIKLER & KPI'lar

### Performans
- [ ] App startup time <2s
- [ ] Order creation <1s
- [ ] List loading <500ms
- [ ] Print time <2s
- [ ] Database query <100ms

### Kalite
- [ ] Code coverage >80%
- [ ] Zero critical bugs
- [ ] <5 minor bugs
- [ ] Lint score 100/100

### Kullanıcı Deneyimi
- [ ] Crash rate <0.1%
- [ ] ANR rate <0.01%
- [ ] User rating >4.5/5

---

## 🎯 PRİORİTE MATRİSİ

### YÜKSEK ÖNCELİK (Must Have)
1. Sunmi yazıcı entegrasyonu
2. Sipariş yönetimi
3. Müşteri yönetimi
4. Ürün yönetimi
5. Temel finans
6. Database migration

### ORTA ÖNCELİK (Should Have)
1. SMS entegrasyonu
2. Bildirimler
3. Detaylı raporlama
4. PDF export
5. Stok takibi

### DÜŞÜK ÖNCELİK (Nice to Have)
1. Multi-user
2. QR kod sistemi
3. Online entegrasyon
4. Excel export
5. Email rapor

---

## 💰 MALIYET TAHMİNİ

### Geliştirme Süresi
- **Toplam:** 10 hafta (2.5 ay)
- **Günlük çalışma:** 6-8 saat
- **Toplam saat:** ~400 saat

### Üçüncü Parti Servisler
- **SMS Gateway:** ~100-500 TL/ay (kullanıma göre)
- **Crash Reporting:** Ücretsiz (Sentry free tier)
- **Cloud Backup:** Ücretsiz (Google Drive API)

### Toplam Maliyet
- **Geliştirme:** [Senin değerlendirmen]
- **Servisler:** ~100-500 TL/ay
- **Maintenance:** [Aylık destek maliyeti]

---

## 📞 DESTEK & İLETİŞİM

### Teknik Destek
- **Email:** [email]
- **Telefon:** [telefon]
- **WhatsApp:** [whatsapp]

### Dokümantasyon
- **GitHub:** [repo link]
- **Wiki:** [wiki link]
- **API Docs:** [docs link]

---

**Son Güncelleme:** 15 Kasım 2024  
**Versiyon:** 1.0  
**Durum:** Onay Bekliyor
