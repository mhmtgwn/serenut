# SHAMAN POS v2.0 - FAZ FAZ UYGULAMA PLANI

**Başlangıç:** 16 Kasım 2024  
**SMS Yöntemi:** SIM Kart (Dahili - Android SMS Manager)  
**Toplam Süre:** 10 hafta

---

## 🎯 FAZ 1: TEMEL ALTYAPI (2 Hafta)

### Hedef: Sağlam temeller üzerine inşa et

### ✅ Yapılacaklar:

#### 1. Proje Hazırlığı (1 gün)
```bash
# Yedekleme
git add .
git commit -m "v0.1.0 - Legacy version before refactor"
git tag v0.1.0-legacy
git push origin v0.1.0-legacy

# Yeni branch
git checkout -b refactor/v2.0.0

# Klasör yedekleme
cp -r shaman_new shaman_new_backup_2024_11_15
```

**Checklist:**
- [ ] Git yedekleme yapıldı
- [ ] Klasör kopyası alındı
- [ ] Database export alındı
- [ ] Yeni branch oluşturuldu

#### 2. Paket Güncellemeleri (1 gün)
```yaml
# pubspec.yaml - Eklenecekler
dependencies:
  # State Management
  flutter_bloc: ^8.1.3
  equatable: ^2.0.5
  
  # Dependency Injection
  get_it: ^7.6.4
  injectable: ^2.3.2
  
  # SMS (SIM Kart)
  telephony: ^0.2.0  # Android SMS Manager
  
  # Utilities
  freezed_annotation: ^2.4.1
  json_annotation: ^4.8.1
  dartz: ^0.10.1
  
dev_dependencies:
  # Code Generation
  build_runner: ^2.4.6
  freezed: ^2.4.5
  json_serializable: ^6.7.1
  injectable_generator: ^2.4.1
  
  # Testing
  mocktail: ^1.0.1
  bloc_test: ^9.1.5
  
  # Code Quality
  very_good_analysis: ^5.1.0
```

**Checklist:**
- [ ] `pubspec.yaml` güncellendi
- [ ] `flutter pub get` çalıştırıldı
- [ ] Paket çakışmaları çözüldü

#### 3. Klasör Yapısı (1 gün)
```
lib/
├── core/
│   ├── constants/
│   │   ├── app_constants.dart
│   │   ├── database_constants.dart
│   │   └── sms_templates.dart
│   ├── errors/
│   │   ├── failures.dart
│   │   └── exceptions.dart
│   ├── usecases/
│   │   └── usecase.dart
│   └── utils/
│       ├── logger.dart
│       ├── validators.dart
│       └── formatters.dart
├── features/
│   ├── printer/
│   ├── orders/
│   ├── customers/
│   ├── products/
│   ├── finance/
│   └── sms/
└── injection_container.dart
```

**Checklist:**
- [ ] Klasörler oluşturuldu
- [ ] Core sınıflar yazıldı
- [ ] Base usecase hazır
- [ ] Logger sistemi çalışıyor

#### 4. Dependency Injection (2 gün)
```dart
// injection_container.dart
final sl = GetIt.instance;

Future<void> init() async {
  // Features
  _initPrinter();
  _initOrders();
  _initCustomers();
  _initProducts();
  _initFinance();
  _initSms();
  
  // Core
  _initCore();
  
  // External
  _initExternal();
}
```

**Checklist:**
- [ ] get_it kuruldu
- [ ] injectable setup
- [ ] Tüm servisler DI'a kayıtlı
- [ ] Singleton'lardan kurtulundu

#### 5. Database Migration (3 gün)
```sql
-- Migration v1 -> v2
ALTER TABLE orders ADD COLUMN status TEXT DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN timeline TEXT;
ALTER TABLE products ADD COLUMN stock_quantity INTEGER DEFAULT 0;
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_date ON orders(created_at);
CREATE INDEX idx_products_stock ON products(stock_quantity);
```

**Checklist:**
- [ ] Migration sistemi kuruldu
- [ ] Index'ler eklendi
- [ ] Foreign key'ler tanımlandı
- [ ] Test data seeder hazır
- [ ] Backup/restore test edildi

#### 6. Sunmi Printer Feature (3 gün)
```
features/printer/
├── data/
│   ├── datasources/
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
        └── print_button.dart
```

**Checklist:**
- [ ] Clean Architecture yapısı kuruldu
- [ ] ESC/POS optimize edildi
- [ ] TSPL optimize edildi
- [ ] Logo ölçeklendirme düzeltildi
- [ ] BLoC state management
- [ ] Unit testler yazıldı
- [ ] Test sayfası çalışıyor

### 📊 FAZ 1 Çıktıları:
- ✅ Sağlam altyapı
- ✅ Clean Architecture
- ✅ Dependency Injection
- ✅ Database migration
- ✅ Sunmi yazıcı hazır
- ✅ Test coverage >50%

---

## 🎯 FAZ 2: SİPARİŞ YÖNETİMİ (2 Hafta)

### Hedef: Hızlı ve güvenilir sipariş sistemi

### ✅ Yapılacaklar:

#### 1. Order Domain Layer (2 gün)
```dart
// entities/order.dart
@freezed
class Order with _$Order {
  const factory Order({
    required String id,
    required String orderNumber,
    required String customerId,
    required List<OrderItem> items,
    required double totalAmount,
    required OrderStatus status,
    required PaymentMethod paymentMethod,
    required DateTime createdAt,
    String? notes,
    List<StatusChange>? timeline,
  }) = _Order;
}

// entities/order_status.dart
enum OrderStatus {
  pending,      // Beklemede
  preparing,    // Hazırlanıyor
  ready,        // Hazır
  onTheWay,     // Yolda
  delivered,    // Teslim Edildi
  cancelled,    // İptal
}
```

**Checklist:**
- [ ] Order entity (freezed)
- [ ] OrderItem entity
- [ ] OrderStatus enum
- [ ] StatusChange entity (timeline için)
- [ ] Repository interface
- [ ] Use case'ler (7 adet)

#### 2. Order Data Layer (2 gün)
```dart
// models/order_model.dart
@JsonSerializable()
class OrderModel extends Order {
  // JSON serialization
}

// datasources/order_local_datasource.dart
abstract class OrderLocalDataSource {
  Future<List<OrderModel>> getOrders({OrderStatus? status});
  Future<OrderModel> getOrderById(String id);
  Future<String> createOrder(OrderModel order);
  Future<void> updateOrderStatus(String id, OrderStatus status);
  Future<void> cancelOrder(String id);
  Future<List<OrderModel>> searchOrders(String query);
}
```

**Checklist:**
- [ ] Order model + JSON
- [ ] Local datasource
- [ ] Repository implementation
- [ ] Database queries optimize
- [ ] Pagination eklendi
- [ ] Search functionality

#### 3. Order BLoC (2 gün)
```dart
// bloc/order_bloc.dart
class OrderBloc extends Bloc<OrderEvent, OrderState> {
  // Events:
  // - LoadOrders
  // - CreateOrder
  // - UpdateOrderStatus
  // - CancelOrder
  // - SearchOrders
  // - FilterByStatus
  
  // States:
  // - OrderInitial
  // - OrderLoading
  // - OrdersLoaded
  // - OrderCreated
  // - OrderError
}
```

**Checklist:**
- [ ] OrderBloc oluşturuldu
- [ ] Tüm event'ler tanımlandı
- [ ] Tüm state'ler tanımlandı
- [ ] Error handling
- [ ] Loading states
- [ ] BLoC testleri

#### 4. Order UI - Oluşturma (2 gün)
```dart
// pages/create_order_page.dart
// Hızlı sipariş oluşturma ekranı
```

**Özellikler:**
- Müşteri seçimi (arama ile)
- Ürün ekleme (hızlı butonlar)
- Miktar ayarlama
- Toplam hesaplama (otomatik)
- Ödeme yöntemi seçimi
- Not ekleme
- Kaydet ve yazdır

**Checklist:**
- [ ] UI tasarımı
- [ ] Form validasyonu
- [ ] Müşteri seçici widget
- [ ] Ürün seçici widget
- [ ] Toplam hesaplama
- [ ] Kaydet butonu
- [ ] Yazdır entegrasyonu
- [ ] Loading/error states

#### 5. Order UI - Liste & Detay (2 gün)
```dart
// pages/orders_list_page.dart
// Sipariş listesi + filtreleme

// pages/order_detail_page.dart
// Detay + timeline + durum güncelleme
```

**Checklist:**
- [ ] Liste sayfası
- [ ] Durum filtreleri (chip'ler)
- [ ] Arama özelliği
- [ ] Pagination
- [ ] Pull to refresh
- [ ] Detay sayfası
- [ ] Timeline widget
- [ ] Durum güncelleme butonları
- [ ] Yazdır butonu
- [ ] İptal butonu

#### 6. Stok Entegrasyonu (2 gün)
```dart
// Sipariş oluşturulunca stok düş
// Sipariş iptal edilince stok iade
```

**Checklist:**
- [ ] Sipariş → Stok düşme
- [ ] İptal → Stok iade
- [ ] Stok kontrolü (yetersiz stok uyarısı)
- [ ] Transaction yönetimi
- [ ] Stok geçmişi kaydı

### 📊 FAZ 2 Çıktıları:
- ✅ Sipariş CRUD tam
- ✅ 6 durum yönetimi
- ✅ Timeline takibi
- ✅ Stok entegrasyonu
- ✅ Hızlı sipariş oluşturma (<1 saniye)
- ✅ Test coverage >60%

---

## 🎯 FAZ 3: MÜŞTERİ & ÜRÜN (2 Hafta)

### Hedef: Eksiksiz müşteri ve ürün yönetimi

### ✅ Yapılacaklar:

#### 1. Customer Feature (1 hafta)
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
├── data/
│   ├── models/
│   ├── datasources/
│   └── repositories/
└── presentation/
    ├── bloc/
    ├── pages/
    └── widgets/
```

**Checklist:**
- [ ] Customer entity (freezed)
- [ ] Address entity (embedded)
- [ ] Phone validation (Türkiye formatı)
- [ ] Repository & use cases
- [ ] Data layer
- [ ] CustomerBloc
- [ ] Liste sayfası
- [ ] Detay sayfası
- [ ] Ekleme/düzenleme formu
- [ ] Arama özelliği
- [ ] Favori müşteriler
- [ ] Müşteri geçmişi (siparişler)
- [ ] Testler

#### 2. Product Feature (1 hafta)
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
├── data/
├── presentation/
```

**Checklist:**
- [ ] Product entity
- [ ] Category entity
- [ ] StockMovement entity
- [ ] Repository & use cases
- [ ] Data layer
- [ ] ProductBloc
- [ ] Liste sayfası (grid/list)
- [ ] Detay sayfası
- [ ] Ekleme/düzenleme formu
- [ ] Kategori yönetimi
- [ ] Stok takibi
- [ ] Kritik stok uyarıları
- [ ] Stok geçmişi
- [ ] Ürün resimleri (optional)
- [ ] Testler

### 📊 FAZ 3 Çıktıları:
- ✅ Müşteri yönetimi tam
- ✅ Ürün yönetimi tam
- ✅ Stok takibi otomatik
- ✅ Kritik stok uyarıları
- ✅ Test coverage >70%

---

## 🎯 FAZ 4: SMS SİSTEMİ (1 Hafta)

### Hedef: SIM kart üzerinden SMS gönderimi

### ✅ Yapılacaklar:

#### 1. SMS Domain Layer (1 gün)
```dart
// entities/sms.dart
@freezed
class Sms with _$Sms {
  const factory Sms({
    required String id,
    required String phoneNumber,
    required String message,
    required SmsStatus status,
    required DateTime createdAt,
    String? orderId,
    String? errorMessage,
  }) = _Sms;
}

// entities/sms_template.dart
enum SmsTemplate {
  orderConfirmation,  // Sipariş onayı
  orderReady,         // Sipariş hazır
  orderOnTheWay,      // Yolda
  orderDelivered,     // Teslim edildi
}
```

**Checklist:**
- [ ] Sms entity
- [ ] SmsTemplate enum
- [ ] SmsStatus enum
- [ ] Repository interface
- [ ] Use case'ler

#### 2. SMS Data Layer - SIM Kart (2 gün)
```dart
// datasources/sms_datasource.dart
import 'package:telephony/telephony.dart';

class SmsDataSourceImpl implements SmsDataSource {
  final Telephony telephony;
  
  @override
  Future<bool> sendSms(String phone, String message) async {
    try {
      await telephony.sendSms(
        to: phone,
        message: message,
      );
      return true;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Future<List<SmsModel>> getSmsHistory() async {
    // SQLite'dan geçmiş SMS'leri çek
  }
}
```

**Checklist:**
- [ ] telephony paketi entegrasyonu
- [ ] SMS izni (AndroidManifest.xml)
- [ ] SMS gönderme fonksiyonu
- [ ] SMS durumu takibi
- [ ] SMS geçmişi (SQLite)
- [ ] Hata yönetimi
- [ ] Repository implementation

#### 3. SMS Şablonları (1 gün)
```dart
// constants/sms_templates.dart
class SmsTemplates {
  static String orderConfirmation(String customerName, String orderNo) {
    return '''
Sayın $customerName,
Siparişiniz alındı.
Sipariş No: $orderNo
Teşekkür ederiz.
''';
  }
  
  static String orderReady(String customerName, String orderNo) {
    return '''
Sayın $customerName,
Siparişiniz hazır!
Sipariş No: $orderNo
''';
  }
  
  static String orderOnTheWay(String customerName, String orderNo) {
    return '''
Sayın $customerName,
Siparişiniz yola çıktı!
Sipariş No: $orderNo
''';
  }
  
  static String orderDelivered(String customerName, String orderNo) {
    return '''
Sayın $customerName,
Siparişiniz teslim edildi.
Sipariş No: $orderNo
Afiyet olsun!
''';
  }
}
```

**Checklist:**
- [ ] 4 SMS şablonu
- [ ] Değişken sistemi ({name}, {order_no})
- [ ] Özelleştirilebilir şablonlar
- [ ] Şablon önizleme

#### 4. SMS BLoC & UI (2 gün)
```dart
// bloc/sms_bloc.dart
class SmsBloc extends Bloc<SmsEvent, SmsState> {
  // Events:
  // - SendSms
  // - SendBulkSms
  // - GetSmsHistory
  
  // States:
  // - SmsInitial
  // - SmsSending
  // - SmsSent
  // - SmsError
  // - SmsHistoryLoaded
}
```

**Checklist:**
- [ ] SmsBloc
- [ ] SMS ayarları sayfası
  - Şablon düzenleme
  - Test SMS
  - İzin kontrolü
- [ ] SMS geçmişi sayfası
- [ ] Toplu SMS (optional)
- [ ] SMS önizleme widget

#### 5. Sipariş Entegrasyonu (1 gün)
```dart
// Sipariş durumu değişince otomatik SMS
// - Sipariş oluşturuldu → SMS
// - Hazır → SMS
// - Yolda → SMS
// - Teslim edildi → SMS
```

**Checklist:**
- [ ] Order status change → SMS trigger
- [ ] Otomatik SMS gönderimi
- [ ] SMS gönderim ayarları (açık/kapalı)
- [ ] SMS onay dialogu (optional)
- [ ] SMS başarı/hata bildirimi

### 📊 FAZ 4 Çıktıları:
- ✅ SIM kart SMS entegrasyonu
- ✅ 4 SMS şablonu
- ✅ Otomatik SMS gönderimi
- ✅ SMS geçmişi
- ✅ Test coverage >75%

---

## 🎯 FAZ 5: FİNANS & RAPORLAMA (2 Hafta)

### Hedef: Detaylı finans takibi ve raporlama

### ✅ Yapılacaklar:

#### 1. Finance Domain Layer (2 gün)
```dart
// entities/transaction.dart (base)
// entities/income.dart
// entities/expense.dart
// entities/payment_method.dart (enum)
```

**Checklist:**
- [ ] Transaction entity (base)
- [ ] Income entity
- [ ] Expense entity
- [ ] PaymentMethod enum
- [ ] Category entity
- [ ] Repository & use cases

#### 2. Finance Data Layer (2 gün)
**Checklist:**
- [ ] Models + JSON
- [ ] Datasource
- [ ] Repository implementation
- [ ] Otomatik gelir kaydı (sipariş → gelir)
- [ ] Manuel gider kaydı

#### 3. Finance UI (2 gün)
**Checklist:**
- [ ] Dashboard
  - Günlük özet
  - Haftalık trend
  - Aylık karşılaştırma
- [ ] Gelir/gider listesi
- [ ] Gider ekleme formu
- [ ] Kategori yönetimi

#### 4. Raporlama (4 gün)
**Checklist:**
- [ ] Report generator service
- [ ] Günlük rapor
- [ ] Haftalık rapor
- [ ] Aylık rapor
- [ ] Özel tarih aralığı
- [ ] Grafikler (fl_chart)
  - Line chart (gelir trendi)
  - Bar chart (günlük satışlar)
  - Pie chart (ödeme yöntemleri)
- [ ] PDF export
- [ ] Rapor yazdırma (Sunmi)

### 📊 FAZ 5 Çıktıları:
- ✅ Gelir/gider takibi
- ✅ Detaylı raporlar
- ✅ Grafikler
- ✅ PDF export
- ✅ Test coverage >80%

---

## 🎯 FAZ 6: POLISH & TEST (1 Hafta)

### Hedef: Mükemmel kullanıcı deneyimi

### ✅ Yapılacaklar:

#### 1. UI/UX Polish (2 gün)
**Checklist:**
- [ ] Tüm sayfaları gözden geçir
- [ ] Loading states
- [ ] Empty states
- [ ] Error states
- [ ] Success animations
- [ ] Tutarlı renk paleti
- [ ] Tutarlı spacing
- [ ] Responsive design
- [ ] Dark mode polish

#### 2. Performance (2 gün)
**Checklist:**
- [ ] Database query optimization
- [ ] Index'leri kontrol et
- [ ] Memory profiling
- [ ] Image optimization
- [ ] Lazy loading
- [ ] Cache stratejisi

#### 3. Testing (2 gün)
**Checklist:**
- [ ] Unit testler (>80% coverage)
- [ ] Widget testler
- [ ] Integration testler
- [ ] Manual testing
- [ ] Bug fixing

#### 4. Documentation (1 gün)
**Checklist:**
- [ ] README güncelle
- [ ] Kullanıcı kılavuzu
- [ ] API documentation
- [ ] Changelog
- [ ] Version bump (2.0.0)

### 📊 FAZ 6 Çıktıları:
- ✅ Production ready
- ✅ Test coverage >80%
- ✅ Performance hedefleri karşılandı
- ✅ Dokümantasyon tam

---

## 📅 ZAMAN ÇİZELGESİ ÖZET

| Faz | Süre | Başlangıç | Bitiş | Çıktı |
|-----|------|-----------|-------|-------|
| **FAZ 1** | 2 hafta | 16 Kas | 29 Kas | Altyapı + Yazıcı |
| **FAZ 2** | 2 hafta | 30 Kas | 13 Ara | Sipariş Yönetimi |
| **FAZ 3** | 2 hafta | 14 Ara | 27 Ara | Müşteri + Ürün |
| **FAZ 4** | 1 hafta | 28 Ara | 3 Oca | SMS Sistemi |
| **FAZ 5** | 2 hafta | 4 Oca | 17 Oca | Finans + Rapor |
| **FAZ 6** | 1 hafta | 18 Oca | 24 Oca | Polish + Test |

**TOPLAM: 10 hafta (2.5 ay)**

---

## ✅ HER FAZ SONUNDA:

1. **Commit & Push**
   ```bash
   git add .
   git commit -m "Completed Phase X"
   git push origin refactor/v2.0.0
   ```

2. **Test Et**
   - Tüm özellikler çalışıyor mu?
   - Hata var mı?
   - Performance nasıl?

3. **Demo**
   - Kullanıcıya göster
   - Feedback al
   - Gerekirse düzelt

4. **Dokümante Et**
   - Ne yapıldı?
   - Ne değişti?
   - Bilinen sorunlar?

---

## 🚀 BAŞLAMAYA HAZIR MISIN?

**Şimdi yapılacak:**
1. ✅ Bu planı onayla
2. ⏳ Yedekleme yap
3. ⏳ FAZ 1'e başla!

**İlk adım:** `git tag v0.1.0-legacy`
