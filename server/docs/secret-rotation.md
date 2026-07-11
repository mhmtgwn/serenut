# Secret Rotation Prosedürü

**Serenut OS — Versiyon 1.0 | Son Güncelleme: 2026-07**

---

## 1. JWT_SECRET Rotasyonu

`JWT_SECRET` güvenliğini korumak amacıyla her **90 günde bir** rotasyona tabi tutulmalıdır.

### Rotasyon Adımları:
1. **Yeni Secret Üretilmesi:**
   ```bash
   openssl rand -hex 64
   ```
2. **Çift Anahtar Desteği (Grace Period):**
   Uygulamanın kesintisiz hizmet vermesi için `.env` dosyasına geçici olarak `JWT_SECRET_NEW` eklenir. `auth.service.ts` her iki anahtarla da doğrulama yapar.
3. **Yeni Anahtara Geçiş:**
   1 saatlik geçiş süresinin ardından `.env` dosyası güncellenir:
   ```env
   JWT_SECRET=<yeni_secret>
   ```
   `JWT_SECRET_NEW` değişkeni silinir.
4. **Aktif Oturumları Sonlandırma:**
   Güvenlik nedeniyle tüm eski oturumlar iptal edilir:
   ```sql
   UPDATE sessions SET is_revoked = true WHERE expires_at > NOW();
   ```

---

## 2. RSA_PRIVATE_KEY Rotasyonu

Lisansların imzalanmasında kullanılan RSA anahtar çifti her **12 ayda bir** değiştirilmelidir.

### Rotasyon Adımları:
1. **Yeni RSA Anahtar Çiftinin Üretilmesi:**
   ```bash
   openssl genrsa -out private.pem 2048
   openssl rsa -in private.pem -outform PEM -pubout -out public.pem
   ```
2. **Bakım Penceresi Planlanması:**
   Gece saat 03:00 - 03:30 aralığında 30 dakikalık bir bakım penceresi ilan edilir.
3. **Anahtarların Güncellenmesi:**
   Yeni RSA anahtarı `.env` veya secret manager üzerinden sisteme yüklenir.
4. **Cihazların Yeniden Aktivasyonu:**
   Bakım penceresi sonrası tüm POS cihazları ilk heartbeat isteklerinde imza uyuşmazlığı tespitiyle otomatik olarak yeniden aktivasyon (re-activation) sürecini tetikler.
