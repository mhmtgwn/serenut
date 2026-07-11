# Caching & Invalidation Strategy

**Serenut OS — Versiyon 1.0 | Son Güncelleme: 2026-07**

---

## 1. Önbellek Yapısı ve Anahtar Tasarımları (Key Patterns)

Performansı artırmak ve veri tabanı yükünü azaltmak amacıyla Redis caching yapısı aşağıdaki kalıplarla tasarlanmıştır:

| Veri Tipi | Redis Key | TTL (Ömür) | Açıklama |
|-----------|-----------|------------|----------|
| Plan Listesi | `plans:list` | 300s (5 dk) | Tüm standard abonelik planları listesi |
| Finansal KPI | `admin:dashboard:revenue` | 30s | MRR, ARR, Churn, Revenue MTD dashboard verileri |
| Lisans Durumu | `license:status:{licenseId}` | 60s (1 dk) | Lisansın geçerli olup olmadığı bilgisi |
| Kullanıcı Yetkileri | `user:permissions:{userId}` | 300s (5 dk) | RLS ve API yetki kontrolü için izin listesi |

---

## 2. Cache Warmup (Isınma) Stratejisi

Uygulama sunucusu başlatıldığında (bootstrap aşamasında), çok sık okunan durağan listeler otomatik olarak veritabanından çekilip Redis önbelleğine doldurulur.

- **Plans Cache Warmup:** Sunucu başlarken standard `plans` tablosu okunur ve `plans:list` anahtarına JSON formatında kaydedilir.

---

## 3. Cache Invalidation (Geçersiz Kılma) Kuralları

Önbellekteki verinin güncelliğini korumak amacıyla ilgili veri güncellendiğinde veya silindiğinde önbellek anahtarları anında temizlenir (Active Invalidation):

### Senaryolar:
1. **Lisans Askıya Alındığında (Suspend) / İptal Edildiğinde:**
   Lisans durumu güncellendiği an ilgili önbellek silinir:
   ```typescript
   await redisClient.del(`license:status:${licenseId}`);
   ```
2. **Abonelik Planları Güncellendiğinde:**
   Admin panelinden bir fiyat planı güncellenirse önbellek listesi silinir:
   ```typescript
   await redisClient.del('plans:list');
   ```
3. **Kullanıcı Yetki Grubu veya Rol Değiştiğinde:**
   Kullanıcının izinleri güncellendiğinde ilgili yetki önbelleği sıfırlanır:
   ```typescript
   await redisClient.del(`user:permissions:${userId}`);
   ```
