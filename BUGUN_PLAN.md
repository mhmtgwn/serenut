# SHAMAN POS v2.0 - BUGÜN YAPILACAKLAR (15 KASIM 2024)

## 🚀 HEDEF: TEK GÜNDE ÇALIŞAN UYGULAMA

**Başlangıç:** Şimdi  
**Bitiş:** Bu gece  
**Yaklaşım:** MVP (Minimum Viable Product) - Hızlı ve işlevsel

---

## ⚡ SAAT 14:00 - 15:00: HAZIRLIK (1 saat)

### 1. Yedekleme (10 dakika)
```bash
# Hızlı yedekleme
git add .
git commit -m "Backup before v2.0 sprint"
git tag v0.1.0-backup
git push origin v0.1.0-backup

# Yeni branch
git checkout -b v2.0-sprint
```

### 2. Temizlik (20 dakika)
```bash
# Gereksiz dosyaları sil
rm -rf lib/core/*
rm -rf lib/domain/*

# Sadece bunları tut:
lib/
├── data/
│   ├── models/
│   └── services/
├── pages/
├── widgets/
└── main.dart
```

### 3. Paketleri Güncelle (30 dakika)
```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.1.1
  sqflite: ^2.4.2
  sunmi_printer_plus: ^4.1.0
  telephony: ^0.2.0  # SMS için
  intl: ^0.19.0
  fl_chart: ^1.0.0
  image: ^4.5.4
  path_provider: ^2.1.5
```

**Checklist:**
- [ ] Yedekleme yapıldı
- [ ] Gereksiz dosyalar silindi
- [ ] Paketler güncellendi
- [ ] `flutter pub get`

---

## ⚡ SAAT 15:00 - 16:00: DATABASE (1 saat)

### Basit ve Hızlı Database
```dart
// lib/data/database.dart
class AppDatabase {
  static Database? _database;
  
  // Tablolar:
  // 1. customers (id, name, phone, address)
  // 2. products (id, name, price, stock, category)
  // 3. orders (id, customer_id, total, status, date, payment_method)
  // 4. order_items (id, order_id, product_id, quantity, price)
  // 5. expenses (id, amount, category, date, note)
  // 6. sms_log (id, phone, message, status, date)
  
  Future<void> createTables(Database db) async {
    // Basit CREATE TABLE komutları
  }
}
```

**Checklist:**
- [ ] Database helper oluşturuldu
- [ ] 6 tablo tanımlandı
- [ ] CRUD metodları yazıldı
- [ ] Test edildi

---

## ⚡ SAAT 16:00 - 17:00: MODELLER (1 saat)

### Basit Model Sınıfları
```dart
// lib/data/models/

// customer.dart
class Customer {
  final int? id;
  final String name;
  final String phone;
  final String? address;
}

// product.dart
class Product {
  final int? id;
  final String name;
  final double price;
  final int stock;
  final String category;
}

// order.dart
class Order {
  final int? id;
  final int customerId;
  final double total;
  final String status; // pending, ready, delivered
  final DateTime date;
  final String paymentMethod; // cash, card
}

// order_item.dart
class OrderItem {
  final int? id;
  final int orderId;
  final int productId;
  final int quantity;
  final double price;
}

// expense.dart
class Expense {
  final int? id;
  final double amount;
  final String category;
  final DateTime date;
  final String? note;
}
```

**Checklist:**
- [ ] 5 model sınıfı
- [ ] toMap() metodları
- [ ] fromMap() metodları

---

## ⚡ SAAT 17:00 - 18:00: SERVİSLER (1 saat)

### Basit Servisler
```dart
// lib/data/services/

// customer_service.dart
class CustomerService {
  Future<List<Customer>> getAll();
  Future<int> add(Customer customer);
  Future<void> update(Customer customer);
  Future<void> delete(int id);
}

// product_service.dart
class ProductService {
  Future<List<Product>> getAll();
  Future<int> add(Product product);
  Future<void> update(Product product);
  Future<void> updateStock(int id, int quantity);
}

// order_service.dart
class OrderService {
  Future<List<Order>> getAll({String? status});
  Future<int> create(Order order, List<OrderItem> items);
  Future<void> updateStatus(int id, String status);
}

// expense_service.dart
class ExpenseService {
  Future<List<Expense>> getAll();
  Future<int> add(Expense expense);
}

// sms_service.dart
class SmsService {
  Future<bool> sendSms(String phone, String message);
  Future<void> sendOrderSms(Order order, Customer customer);
}

// printer_service.dart (mevcut kodu kullan)
class PrinterService {
  Future<bool> printReceipt(Order order, Customer customer, List<OrderItem> items);
}
```

**Checklist:**
- [ ] 6 servis sınıfı
- [ ] Temel CRUD metodları
- [ ] SMS entegrasyonu
- [ ] Yazıcı entegrasyonu

---

## ⚡ SAAT 18:00 - 20:00: UI TASARIMI (2 saat)

### Modern ve Basit UI

#### 1. Ana Sayfa (30 dakika)
```dart
// lib/pages/home_page.dart
// Dashboard:
// - Bugünkü satışlar (card)
// - Bekleyen siparişler (card)
// - Kritik stok (card)
// - Hızlı işlemler (buttons)
```

#### 2. Sipariş Sayfaları (30 dakika)
```dart
// lib/pages/orders_page.dart
// Liste + Durum filtreleri

// lib/pages/create_order_page.dart
// Hızlı sipariş oluşturma
// - Müşteri seç (dropdown)
// - Ürün ekle (grid)
// - Toplam (otomatik)
// - Kaydet + Yazdır
```

#### 3. Müşteri & Ürün (30 dakika)
```dart
// lib/pages/customers_page.dart
// Liste + Ekle/Düzenle

// lib/pages/products_page.dart
// Grid/Liste + Ekle/Düzenle
```

#### 4. Finans (30 dakika)
```dart
// lib/pages/finance_page.dart
// - Günlük özet
// - Gelir/Gider listesi
// - Basit grafik
```

**Checklist:**
- [ ] Ana sayfa
- [ ] Sipariş sayfaları (2)
- [ ] Müşteri sayfası
- [ ] Ürün sayfası
- [ ] Finans sayfası

---

## ⚡ SAAT 20:00 - 21:00: ENTEGRASYONLAR (1 saat)

### 1. SMS Entegrasyonu (20 dakika)
```dart
// Sipariş oluşturulunca SMS gönder
// Sipariş hazır olunca SMS gönder
```

### 2. Yazıcı Entegrasyonu (20 dakika)
```dart
// Sipariş oluşturulunca fiş yazdır
// Mevcut printer_service kullan
```

### 3. Stok Entegrasyonu (20 dakika)
```dart
// Sipariş oluşturulunca stok düş
// Sipariş iptal edilince stok iade
```

**Checklist:**
- [ ] SMS otomasyonu
- [ ] Yazıcı otomasyonu
- [ ] Stok otomasyonu

---

## ⚡ SAAT 21:00 - 22:00: TEST & POLISH (1 saat)

### 1. Test (30 dakika)
- [ ] Müşteri ekle/düzenle/sil
- [ ] Ürün ekle/düzenle/stok güncelle
- [ ] Sipariş oluştur
- [ ] SMS gönder
- [ ] Fiş yazdır
- [ ] Finans raporları

### 2. UI Polish (30 dakika)
- [ ] Renkler tutarlı
- [ ] Loading states
- [ ] Error messages
- [ ] Success messages
- [ ] Icon'lar

---

## 🎨 TASARIM PRENSİPLERİ

### Renk Paleti
```dart
// lib/constants/colors.dart
class AppColors {
  static const primary = Color(0xFF2E7D32);      // Yeşil
  static const secondary = Color(0xFF1976D2);    // Mavi
  static const accent = Color(0xFFF57C00);       // Turuncu
  static const error = Color(0xFFD32F2F);        // Kırmızı
  static const success = Color(0xFF388E3C);      // Yeşil
  static const background = Color(0xFFFAFAFA);   // Açık gri
}
```

### Widget'lar
```dart
// lib/widgets/
// - custom_button.dart
// - custom_card.dart
// - custom_text_field.dart
// - loading_indicator.dart
// - empty_state.dart
```

---

## 📱 EKRAN YAPISI

```
HomePage (Dashboard)
├── OrdersPage
│   ├── CreateOrderPage
│   └── OrderDetailPage
├── CustomersPage
│   └── CustomerFormPage
├── ProductsPage
│   └── ProductFormPage
├── FinancePage
│   └── ExpenseFormPage
└── SettingsPage
    ├── PrinterSettingsPage
    └── SmsSettingsPage
```

---

## ✅ BUGÜN SONU CHECKLIST

### Temel Özellikler
- [ ] Müşteri CRUD çalışıyor
- [ ] Ürün CRUD çalışıyor
- [ ] Sipariş oluşturma çalışıyor
- [ ] Stok otomatik düşüyor
- [ ] SMS gönderimi çalışıyor
- [ ] Fiş yazdırma çalışıyor
- [ ] Finans takibi çalışıyor

### UI/UX
- [ ] Tüm sayfalar tasarlandı
- [ ] Navigation çalışıyor
- [ ] Loading states var
- [ ] Error handling var
- [ ] Responsive

### Test
- [ ] Manuel test yapıldı
- [ ] Tüm flow'lar çalışıyor
- [ ] Hata yok

---

## 🚀 HIZLI BAŞLANGIÇ KOMUTU

```bash
# 1. Yedekle
git add . && git commit -m "Backup" && git tag v0.1.0-backup

# 2. Yeni branch
git checkout -b v2.0-sprint

# 3. Başla!
code .
```

---

## 💡 HIZLI İPUÇLARI

1. **Kopyala-Yapıştır:** Mevcut çalışan kodları kullan
2. **Basit Tut:** Karmaşık mimari yok, direkt kod
3. **Provider Kullan:** State management basit
4. **Stateless Widgets:** Mümkün olduğunca
5. **Hot Reload:** Sürekli test et
6. **Commit Sık:** Her özellik sonrası commit

---

## 🎯 BAŞARI KRİTERİ

**Bugün sonu:**
- ✅ Sipariş oluşturabiliyorum
- ✅ SMS gönderebiliyorum
- ✅ Fiş yazdırabiliyorum
- ✅ Stok takip edebiliyorum
- ✅ Finans görebiliyorum

**Yarın:**
- Polish
- Detaylar
- Optimizasyon

---

## ⏰ ZAMAN TABLOSU ÖZET

| Saat | Görev | Süre |
|------|-------|------|
| 14:00-15:00 | Hazırlık | 1h |
| 15:00-16:00 | Database | 1h |
| 16:00-17:00 | Modeller | 1h |
| 17:00-18:00 | Servisler | 1h |
| 18:00-20:00 | UI | 2h |
| 20:00-21:00 | Entegrasyon | 1h |
| 21:00-22:00 | Test | 1h |

**TOPLAM: 8 saat**

---

## 🔥 HADI BAŞLAYALIM!

**İlk komut:**
```bash
git add . && git commit -m "Starting v2.0 sprint" && git checkout -b v2.0-sprint
```

**Sonra:**
1. Database yaz
2. Modelleri yaz
3. Servisleri yaz
4. UI'ı yap
5. Entegre et
6. Test et

**BAŞLA! 🚀**
