# 15 — API Taslağı ve Uç Nokta Sözleşmeleri

> Bu belge, Nutopia Platformu (`apps/api` - NestJS Fastify) REST API sözleşmesini, istek/yanıt şemalarını, idempotensi mekanizmalarını, hız sınırlama politikalarını ve hata formatlarını eksiksiz belgeler.
> Bağlayıcı mimari: `12-mimari-kilit-kararlar.md` (K5, K12, K17, K18). Veri modeli: `14-sql-sema.md`.

---

## 1. GENEL STANDARTLAR VE PROTOKOLLER

### 1.1 Temel URL ve Ortamlar
- **Üretim (Production):** `https://api.nutopiano.com/v1`
- **Staging / Test:** `https://staging-api.nutopiano.com/v1`
- **Yerel Geliştirme:** `http://127.0.0.1:3001/v1`

### 1.2 Ortak İstek Başlıkları (Request Headers)
| Başlık | Tip | Zorunlu? | Açıklama |
|---|---|---|---|
| `Content-Type` | `application/json` | Evet (POST/PUT/PATCH) | İstek gövdesi formatı |
| `Accept` | `application/json` | Evet | Beklenen yanıt formatı |
| `Idempotency-Key` | `string (UUID)` | Evet (Finansal/Sipariş) | Tekrarlı istekleri önleme anahtarı (24 saat geçerli) |
| `X-Request-Id` | `string (UUID)` | İsteğe bağlı | İstemci trace ID'si (yoksa sunucu üretir) |
| `X-Client-Version`| `string (SemVer)` | Evet | İstemci sürümü (minimum sürüm kontrolü için) |
| `X-Forwarded-For` | `string (IP)` | Proxy | İstemci IP tespiti (Cloudflare: `CF-Connecting-IP`) |

### 1.3 Standart Hata Formatı (RFC 7807 - Problem Details)
Tüm `4xx` ve `5xx` yanıtları `application/problem+json` formatında döner:
```json
{
  "type": "https://nutopiano.com/errors/insufficient-stock",
  "title": "Yetersiz Stok",
  "status": 409,
  "detail": "İstenen varyant (SKU: NUT-SUT-300) için yeterli stok bulunmuyor. Mevcut: 2, İstenen: 5.",
  "code": "INSUFFICIENT_STOCK",
  "requestId": "0192d4f8-3e4b-7123-810a-000000000001",
  "invalidParams": [
    {
      "name": "items[0].qty",
      "reason": "Maksimum satın alınabilir miktar aşıldı."
    }
  ]
}
```

---

## 2. KİMLİK DOĞRULAMA & OTURUM UÇLARI (`/v1/auth`)

### 2.1 Müşteri Telefon OTP İsteği
- **Uç Nokta:** `POST /v1/auth/otp/request`
- **Hız Sınırı:** IP başına dakikada 5 istek; telefon numarası başına saatte 5 istek.
- **İstek Gövdesi:**
```json
{
  "phone": "05321234567",
  "purpose": "login" // 'login' | 'order_confirm' | 'pickup_ack'
}
```
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "challengeId": "0192d4f8-1111-7000-8000-000000000001",
  "expiresInSeconds": 300,
  "destinationMasked": "+90 532 *** ** 67"
}
```

### 2.2 OTP Doğrulama ve Oturum Açma
- **Uç Nokta:** `POST /v1/auth/otp/verify`
- **İstek Gövdesi:**
```json
{
  "challengeId": "0192d4f8-1111-7000-8000-000000000001",
  "code": "481920"
}
```
- **Başarılı Yanıt (`200 OK`):**
  - Başlık: `Set-Cookie: nuto_session=...; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=2592000`
```json
{
  "customer": {
    "id": "0192d4f8-2222-7000-8000-000000000002",
    "fullName": "Ahmet Yılmaz",
    "phone": "+905321234567",
    "status": "active"
  }
}
```

### 2.3 Personel / Yönetici Girişi
- **Uç Nokta:** `POST /v1/auth/staff/login`
- **İstek Gövdesi:**
```json
{
  "email": "yonetim@nutopiano.com",
  "password": "GucluSifre!2026",
  "totpCode": "123456"
}
```
- **Başarılı Yanıt (`200 OK`):**
  - Başlık: `Set-Cookie: nuto_admin_session=...; HttpOnly; Secure; SameSite=Strict; Path=/admin`
```json
{
  "staff": {
    "id": "0192d4f8-3333-7000-8000-000000000003",
    "email": "yonetim@nutopiano.com",
    "fullName": "Mehmet Güven",
    "roles": ["owner"],
    "permissions": ["*"]
  }
}
```

---

## 3. MAĞAZA & KATALOG UÇLARI (`/v1/catalog`, `/v1/cart`, `/v1/checkout`)

### 3.1 Ürün Listesi ve Arama
- **Uç Nokta:** `GET /v1/products`
- **Sorgu Parametreleri:** `category`, `q` (arama metni), `sort` (`price_asc`, `price_desc`, `newest`), `limit`, `cursor`.
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "items": [
    {
      "id": "0192d4f8-4444-7000-8000-000000000004",
      "slug": "100-findik-ezmesi",
      "name": "%100 Fındık Ezmesi",
      "shortDesc": "Katkısız, ilave şekersiz saf taş değirmen çekimi fındık ezmesi.",
      "category": { "slug": "ezme", "name": "Ezme & Krema" },
      "minPriceKurus": 19500,
      "primaryMedia": {
        "url": "https://nutopiano.com/images/urun-ezme.png",
        "altText": "%100 Fındık Ezmesi Kavanozu"
      },
      "variants": [
        {
          "id": "0192d4f8-5555-7000-8000-000000000005",
          "sku": "NUT-EZM-320",
          "label": "320 g kavanoz",
          "priceKurus": 19500,
          "availableStock": 42
        },
        {
          "id": "0192d4f8-6666-7000-8000-000000000006",
          "sku": "NUT-EZM-650",
          "label": "650 g kavanoz",
          "priceKurus": 38000,
          "availableStock": 18
        }
      ]
    }
  ],
  "nextCursor": "0192d4f8-6666-7000-8000-000000000006"
}
```

### 3.2 Sepet İşlemleri
- **Uç Nokta:** `GET /v1/cart` (Çerezdeki `nuto_cart_token` ile eşleşir).
- **Sepete Ürün Ekleme:** `POST /v1/cart/items`
```json
{
  "variantId": "0192d4f8-5555-7000-8000-000000000005",
  "qty": 2
}
```
- **Kupon Uygulama:** `POST /v1/cart/coupon`
```json
{
  "code": "HOSGELDIN10"
}
```

### 3.3 Fiyat ve Sipariş Teklifi (Checkout Quote)
- **Uç Nokta:** `POST /v1/checkout/quote`
- **İşlev:** Sunucuda atomik kargo, vergi, kupon, havale indirimi hesaplar ve bir `quoteId` üretir.
- **İstek Gövdesi:**
```json
{
  "cartId": "0192d4f8-7777-7000-8000-000000000007",
  "shippingCityCode": "34",
  "paymentMethod": "bank_transfer",
  "claimGaziDiscount": false
}
```
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "quoteId": "0192d4f8-8888-7000-8000-000000000008",
  "expiresAt": "2026-10-30T22:15:00Z",
  "currency": "TRY",
  "itemsGrossKurus": 39000,
  "couponDiscountKurus": 3900,
  "bankTransferDiscountKurus": 1755,
  "shippingFeeKurus": 0,
  "codFeeKurus": 0,
  "grandTotalKurus": 33345,
  "taxTotalKurus": 3031,
  "isFreeShipping": true
}
```

### 3.4 Siparişi Oluşturma (Place Order)
- **Uç Nokta:** `POST /v1/checkout/orders`
- **Zorunlu Başlık:** `Idempotency-Key: 8a5f3e9b-0000-4000-a000-111122223333`
- **İstek Gövdesi:**
```json
{
  "quoteId": "0192d4f8-8888-7000-8000-000000000008",
  "customer": {
    "fullName": "Ayşe Kaya",
    "email": "ayse@example.com",
    "phone": "05339876543"
  },
  "shippingAddress": {
    "recipientName": "Ayşe Kaya",
    "phone": "05339876543",
    "cityCode": "34",
    "districtCode": "KADIKOY",
    "line1": "Bağdat Cad. No: 120 D: 4",
    "postalCode": "34728"
  },
  "paymentMethod": "card", // 'card' | 'bank_transfer' | 'cod'
  "legalConsents": {
    "distanceSaleContractVersion": "2026-v1",
    "preliminaryInfoVersion": "2026-v1",
    "acceptedAt": "2026-10-30T22:00:00Z"
  }
}
```
- **Başarılı Yanıt (`201 Created`):**
```json
{
  "orderId": "0192d4f8-9999-7000-8000-000000000009",
  "orderNumber": "NT-2026-000184",
  "trackToken": "trk_9f8e7d6c5b4a",
  "status": "pending_payment",
  "grandTotalKurus": 33345,
  "paymentInit": {
    "provider": "iyzico",
    "checkoutFormHtml": "<script>...</script><div id='iyzipay-checkout-form'></div>"
  }
}
```

---

## 4. DEĞİRMEN & KURYE UÇLARI (`/v1/mill`)

### 4.1 Fiyat Hesaplama Teklifi
- **Uç Nokta:** `POST /v1/mill/quote`
- **İstek Gövdesi:**
```json
{
  "servicePackage": "kk_1kg", // Kırma + Kavurma + 1kg Vakum
  "estKg": 200,
  "cityCode": "67",
  "districtCode": "KDZ_EREGLI",
  "neighborhoodCode": "ORMANLI",
  "claimGaziDiscount": true
}
```
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "rateId": "0192d4f8-aaaa-7000-8000-00000000000a",
  "unitPricePerKgKurus": 7000,
  "estGrossServiceKurus": 1400000,
  "gaziDiscountKurus": 280000,
  "pickupFeeKurus": 0,
  "deliveryFeeKurus": 0,
  "estTotalKurus": 1120000,
  "estOutputKg": 100,
  "currency": "TRY"
}
```

### 4.2 Değirmen Alım Talebi Oluşturma
- **Uç Nokta:** `POST /v1/mill/requests`
- **Zorunlu Başlık:** `Idempotency-Key: ...`
- **İstek Gövdesi:**
```json
{
  "servicePackage": "kk_1kg",
  "estInputKg": 200,
  "estBagCount": 4,
  "pickupSite": {
    "recipientName": "Hasan Demir",
    "phone": "05381112233",
    "cityCode": "67",
    "districtCode": "KDZ_EREGLI",
    "neighborhoodCode": "ORMANLI",
    "line1": "Merkez Mah. No: 12",
    "directionsText": "Ormanlı mezarlığının üstündeki fındık bahçesi",
    "geoLat": 41.285400,
    "geoLng": 31.428900
  },
  "returnMode": "courier_back",
  "preferredDate": "2026-11-03",
  "preferredSlot": "morning",
  "customerNote": "Traktör yolundan giriniz."
}
```
- **Başarılı Yanıt (`201 Created`):**
```json
{
  "requestId": "0192d4f8-bbbb-7000-8000-00000000000b",
  "requestNumber": "DG-2026-000072",
  "trackToken": "mill_tr_12345678",
  "status": "requested",
  "estTotalKurus": 1120000
}
```

---

## 5. ŞOFÖR MOBİL UYGULAMA UÇLARI (`/v1/driver`)
*Yetkilendirme: `staff` oturumu ve `driver:self` izni gerektirir.*

### 5.1 Günlük Rota ve Alım Listesi
- **Uç Nokta:** `GET /v1/driver/today`
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "planDate": "2026-11-03",
  "driverName": "Ahmet Şoför",
  "vehiclePlate": "67 AB 123",
  "stops": [
    {
      "pickupId": "0192d4f8-cccc-7000-8000-00000000000c",
      "requestId": "0192d4f8-bbbb-7000-8000-00000000000b",
      "requestNumber": "DG-2026-000072",
      "sequence": 1,
      "status": "planned",
      "customerName": "Hasan Demir",
      "phone": "05381112233",
      "addressText": "Ormanlı Merkez Mah. No: 12 (Mezarlık üstü)",
      "geoLat": 41.285400,
      "geoLng": 31.428900,
      "estKg": 200,
      "servicePackage": "Kırma + Kavurma + 1kg Vakum"
    }
  ]
}
```

### 5.2 Alım Kodu Doğrulama
- **Uç Nokta:** `POST /v1/driver/pickups/:id/verify-code`
- **İstek Gövdesi:**
```json
{
  "code": "7412"
}
```
- **Başarılı Yanıt:** `{"valid": true}`

### 5.3 Sahada Tartı Kaydetme ve Alımı Tamamlama
- **Uç Nokta:** `POST /v1/driver/pickups/:id/weigh-and-complete`
- **İstek Gövdesi:**
```json
{
  "grossGrams": 204500,
  "tareGrams": 800,
  "bagCount": 4,
  "scaleReceiptDocumentId": "0192d4f8-dddd-7000-8000-00000000000d",
  "customerAckCode": "9021",
  "note": "Kantar fişi çekildi, mahsul kuru."
}
```
- **Başarılı Yanıt (`200 OK`):**
```json
{
  "weighingId": "0192d4f8-eeee-7000-8000-00000000000e",
  "netGrams": 203700,
  "netKg": 203.7,
  "finalChargesKurus": 1140720,
  "status": "picked_up"
}
```

---

## 6. SAĞLAYICI WEBHOOK UÇLARI (`/v1/webhooks`)

### 6.1 iyzico Ödeme Sonuç Bildirimi
- **Uç Nokta:** `POST /v1/webhooks/iyzico`
- **İmza Doğrulama:** `X-IYZICO-SIGNATURE` başlığı ile gövde hash'i karşılaştırılır.
- **İşlem Mantığı:**
  1. İmza geçersiz ise anında `400 Bad Request`.
  2. Webhook payload'ı içindeki `conversationId` (`payments.payments.conversation_id`) bulunur.
  3. Sağlayıcı API'si çağrılarak ödeme durumu sorgulanır (`iyzico.payment.retrieve`).
  4. Ödeme durumu `SUCCESS` ise atomik transaction içinde:
     - `payments.payments.status = 'captured'`
     - `shop.orders.status = 'paid'`
     - `shop.stock_reservations` kalıcı stoka dönüştürülür (`committed`).
     - `core.outbox` tablosuna `OrderPaid` olayı yazılır.
  5. Yanıt: `200 OK` `{"received": true}`.

---

## 7. YÖNETİM (ADMIN) UÇLARI (`/v1/admin`)
*Tüm uçlar `nuto_admin_session` çerezi ve ilgili yetki (`permission`) gerektirir.*

| Metot | Uç Nokta | Gerekli İzin | Açıklama |
|---|---|---|---|
| `GET` | `/v1/admin/orders` | `orders:read` | Sipariş listesi (filtre, arama, sayfalama) |
| `PATCH` | `/v1/admin/orders/:id/status` | `orders:process` | Sipariş durumunu güncelleme |
| `POST` | `/v1/admin/orders/:id/refund` | `orders:refund` | Kısmi/tam iade başlatma |
| `POST` | `/v1/admin/orders/:id/confirm-transfer` | `payments:confirm_transfer` | Havale ödemesini onaylama |
| `POST` | `/v1/admin/products` | `catalog:write` | Yeni ürün oluşturma |
| `PUT` | `/v1/admin/products/:id` | `catalog:write` | Ürün ve varyant güncelleme |
| `GET` | `/v1/admin/mill/requests` | `mill:read` | Değirmen talep listesi |
| `POST` | `/v1/admin/mill/requests/:id/approve` | `mill:approve` | Talebi onaylama ve planlama |
| `POST` | `/v1/admin/mill/dispatch-plans` | `mill:plan` | Günlük şoför rota planı oluşturma |
| `GET` | `/v1/admin/reports/daily-sales` | `reports:read` | Günlük satış ve ciro raporu |

